//
//  Codex_Status_BarApp.swift
//  Codex Status Bar
//
//  Created by Gabriel Bandeira on 05/09/26.
//

import SwiftUI
import AppKit
import Combine
import Foundation
import ServiceManagement

@main
struct Codex_Status_BarApp: App {
    @StateObject private var codexManager = CodexManager()

    var body: some Scene {
        MenuBarExtra {
            CodexStatusMenu(data: codexManager.data, lastErrorMessage: codexManager.lastErrorMessage)
        } label: {
            Text(codexManager.data.menuBarTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct CodexData: Decodable {
    let percentage5h: Double
    let timeUntil5hRenewal: String
    let local5hRenewalTime: String
    let percentageWeekly: Double
    let timeUntilWeeklyRenewal: String
    let localWeeklyRenewalTime: String

    static let placeholder = CodexData(
        percentage5h: 0,
        timeUntil5hRenewal: "--:--",
        local5hRenewalTime: "--:--",
        percentageWeekly: 0,
        timeUntilWeeklyRenewal: "--",
        localWeeklyRenewalTime: "--/-- --:--"
    )

    var menuBarTitle: String {
        "\(formattedPercentage(percentage5h)) | \(formattedPercentage(percentageWeekly))"
    }

    private func formattedPercentage(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

struct CodexLimitWindow {
    let usedPercent: Double
    let resetsAt: String?
}

extension CodexData {
    nonisolated init(fiveHour: CodexLimitWindow, weekly: CodexLimitWindow) {
        self.init(
            percentage5h: fiveHour.usedPercent,
            timeUntil5hRenewal: fiveHour.resetsIn,
            local5hRenewalTime: fiveHour.localRenewalTime,
            percentageWeekly: weekly.usedPercent,
            timeUntilWeeklyRenewal: weekly.resetsIn,
            localWeeklyRenewalTime: weekly.localRenewalTime
        )
    }
}

extension CodexLimitWindow {
    nonisolated var resetsIn: String {
        guard let resetsAt,
              let date = ISO8601DateFormatter.codexDate(from: resetsAt) else {
            return "--"
        }

        let seconds = Int(date.timeIntervalSince(Date()))
        guard seconds > 0 else {
            return "now"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d\(hours)h"
        }

        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }

        return minutes > 0 ? "\(minutes)m" : "<1m"
    }

    nonisolated var localRenewalTime: String {
        guard let resetsAt,
              let date = ISO8601DateFormatter.codexDate(from: resetsAt) else {
            return "--"
        }

        return date.formatted(
            .dateTime
                .day(.twoDigits)
                .month(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}

extension ISO8601DateFormatter {
    nonisolated static func codexDate(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

struct CodexStatusMenu: View {
    let data: CodexData
    let lastErrorMessage: String?

    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginErrorMessage: String?

    var body: some View {
        Text("Consumo 5h: \(data.percentage5h.formatted(.number.precision(.fractionLength(0))))%")
        Text("Renova em \(data.timeUntil5hRenewal)")
        Text("Horario local: \(data.local5hRenewalTime)")

        Divider()

        Text("Consumo semanal: \(data.percentageWeekly.formatted(.number.precision(.fractionLength(0))))%")
        Text("Renova em \(data.timeUntilWeeklyRenewal)")
        Text("Horario local: \(data.localWeeklyRenewalTime)")

        if let lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
        }

        Divider()

        Toggle("Abrir ao iniciar", isOn: Binding(
            get: {
                launchAtLoginEnabled
            },
            set: { isEnabled in
                updateLaunchAtLogin(isEnabled)
            }
        ))

        if let launchAtLoginErrorMessage {
            Text(launchAtLoginErrorMessage)
        }

        Divider()

        Button("Fechar App") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginErrorMessage = "Nao foi possivel alterar inicio automatico"
        }
    }
}

@MainActor
final class CodexManager: ObservableObject {
    @Published private(set) var data: CodexData = .placeholder
    @Published private(set) var lastErrorMessage: String?

    private let rolloutProvider = CodexRolloutProvider()
    private var timer: Timer?

    init() {
        Task {
            await fetchCodexData()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchCodexData()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func fetchCodexData() async {
        do {
            self.data = try await rolloutProvider.readLatestUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Falha ao atualizar dados"
        }
    }
}

struct CodexRolloutProvider {
    private let sessionsDirectory: URL
    private let maxFiles = 20
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")) {
        self.sessionsDirectory = codexHome.appending(path: "sessions")
    }

    nonisolated func readLatestUsage() async throws -> CodexData {
        try await Task.detached(priority: .utility) {
            try readLatestUsageSynchronously()
        }
        .value
    }

    private nonisolated func readLatestUsageSynchronously() throws -> CodexData {
        for fileURL in try recentRolloutFiles() {
            guard let rateLimits = try latestRateLimitsSnapshot(in: fileURL) else {
                continue
            }

            guard let fiveHour = window(from: rateLimits["primary"]),
                  let weekly = window(from: rateLimits["secondary"]) else {
                continue
            }

            return CodexData(fiveHour: fiveHour, weekly: weekly)
        }

        throw CodexRolloutError.noRateLimitsSnapshot
    }

    private nonisolated func recentRolloutFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CodexRolloutError.sessionsDirectoryUnavailable
        }

        let cutoff = Date().addingTimeInterval(-maxAge)
        var files: [(url: URL, modificationDate: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl" else {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modificationDate = values.contentModificationDate,
                  modificationDate >= cutoff else {
                continue
            }

            files.append((fileURL, modificationDate))
        }

        return files
            .sorted { $0.modificationDate > $1.modificationDate }
            .prefix(maxFiles)
            .map(\.url)
    }

    private nonisolated func latestRateLimitsSnapshot(in fileURL: URL) throws -> [String: Any]? {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("rate_limits") || line.contains("rateLimits"),
                  let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rateLimits = findRateLimits(in: object) else {
                continue
            }

            return rateLimits
        }

        return nil
    }

    private nonisolated func findRateLimits(in object: [String: Any], depth: Int = 0) -> [String: Any]? {
        guard depth <= 4 else {
            return nil
        }

        if let rateLimits = pickDictionary(from: object, keys: ["rate_limits", "rateLimits"]),
           rateLimits["primary"] != nil || rateLimits["secondary"] != nil {
            return rateLimits
        }

        for value in object.values {
            if let child = value as? [String: Any],
               let found = findRateLimits(in: child, depth: depth + 1) {
                return found
            }
        }

        return nil
    }

    private nonisolated func window(from value: Any?) -> CodexLimitWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = pickDouble(from: object, keys: ["usedPercent", "used_percent", "percent"]) else {
            return nil
        }

        let resetsAt = pickResetDate(from: object)
        return CodexLimitWindow(usedPercent: usedPercent, resetsAt: resetsAt)
    }

    private nonisolated func pickResetDate(from object: [String: Any]) -> String? {
        if let resetsAt = pickString(from: object, keys: ["resetsAt", "resets_at"]) {
            return resetsAt
        }

        if let resetEpoch = pickDouble(from: object, keys: ["resetsAt", "resets_at"]) {
            let seconds = resetEpoch > 1_000_000_000_000 ? resetEpoch / 1_000 : resetEpoch
            return Date(timeIntervalSince1970: seconds).ISO8601Format()
        }

        if let resetsInSeconds = pickDouble(from: object, keys: ["resetsInSeconds", "resets_in_seconds"]) {
            return Date(timeIntervalSinceNow: resetsInSeconds).ISO8601Format()
        }

        return nil
    }

    private nonisolated func pickDictionary(from object: [String: Any], keys: [String]) -> [String: Any]? {
        keys.compactMap { object[$0] as? [String: Any] }.first
    }

    private nonisolated func pickString(from object: [String: Any], keys: [String]) -> String? {
        keys.compactMap { object[$0] as? String }.first
    }

    private nonisolated func pickDouble(from object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            switch object[key] {
            case let value as Double:
                return value
            case let value as Int:
                return Double(value)
            case let value as String:
                return Double(value)
            default:
                continue
            }
        }

        return nil
    }
}

enum CodexRolloutError: LocalizedError {
    case sessionsDirectoryUnavailable
    case noRateLimitsSnapshot

    var errorDescription: String? {
        switch self {
        case .sessionsDirectoryUnavailable:
            return "Diretorio ~/.codex/sessions indisponivel"
        case .noRateLimitsSnapshot:
            return "Nenhum snapshot rate_limits encontrado"
        }
    }
}

#Preview {
    CodexStatusMenu(
        data: CodexData(percentage5h: 45, timeUntil5hRenewal: "02:15:00", local5hRenewalTime: "23:15",
                        percentageWeekly: 80, timeUntilWeeklyRenewal: "2 dias", localWeeklyRenewalTime: "28/10 14:00"),
        lastErrorMessage: nil
    )
}
