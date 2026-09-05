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
    @NSApplicationDelegateAdaptor(CodexStatusBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CodexStatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private let codexManager = CodexManager()
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var launchAtLoginErrorMessage: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: 30)
        self.statusItem = statusItem

        refreshStatusItem()

        codexManager.$data
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        codexManager.$lastErrorMessage
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItem() {
        guard let statusItem,
              let button = statusItem.button else {
            return
        }

        button.attributedTitle = statusTitle(for: codexManager.data)
        button.toolTip = "Codex Status Bar"
        statusItem.menu = makeMenu()
    }

    private func statusTitle(for data: CodexData) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.minimumLineHeight = 8
        paragraphStyle.maximumLineHeight = 8

        return NSAttributedString(
            string: data.menuBarTitle,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                .paragraphStyle: paragraphStyle,
                .baselineOffset: -1
            ]
        )
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let data = codexManager.data

        menu.addItem(disabledTitle: "5-hour remaining: \(formattedPercentage(data.remainingPercentage5h))")
        menu.addItem(disabledTitle: "Renews in \(data.timeUntil5hRenewal)")
        menu.addItem(disabledTitle: "Local renewal: \(data.local5hRenewalTime)")
        menu.addItem(.separator())
        menu.addItem(disabledTitle: "Weekly remaining: \(formattedPercentage(data.remainingPercentageWeekly))")
        menu.addItem(disabledTitle: "Renews in \(data.timeUntilWeeklyRenewal)")
        menu.addItem(disabledTitle: "Local renewal: \(data.localWeeklyRenewalTime)")
        menu.addItem(.separator())
        menu.addItem(disabledTitle: "Source: \(data.sourceDescription)")

        if let updatedAt = data.updatedAt {
            menu.addItem(disabledTitle: "Updated at \(Self.formattedUpdateDate(updatedAt))")
        }

        if let staleSeconds = data.staleSeconds {
            menu.addItem(disabledTitle: "Local snapshot: \(Self.formattedStaleTime(staleSeconds)) old")
        }

        if let lastErrorMessage = codexManager.lastErrorMessage {
            menu.addItem(.separator())
            menu.addItem(disabledTitle: lastErrorMessage)
        }

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        if let launchAtLoginErrorMessage {
            menu.addItem(disabledTitle: launchAtLoginErrorMessage)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit App",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func formattedPercentage(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private static func formattedStaleTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        return "\(minutes / 60)h"
    }

    private static func formattedUpdateDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }

            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = "Unable to update launch at login"
        }

        refreshStatusItem()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

private extension NSMenu {
    func addItem(disabledTitle title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}

struct CodexData: Decodable {
    let remainingPercentage5h: Double
    let timeUntil5hRenewal: String
    let local5hRenewalTime: String
    let remainingPercentageWeekly: Double
    let timeUntilWeeklyRenewal: String
    let localWeeklyRenewalTime: String
    let staleSeconds: Int?
    let updatedAt: Date?
    let sourceDescription: String

    static let placeholder = CodexData(
        remainingPercentage5h: 0,
        timeUntil5hRenewal: "--:--",
        local5hRenewalTime: "--:--",
        remainingPercentageWeekly: 0,
        timeUntilWeeklyRenewal: "--",
        localWeeklyRenewalTime: "--/-- --:--",
        staleSeconds: nil,
        updatedAt: nil,
        sourceDescription: "Waiting for data"
    )

    var fiveHourMenuBarTitle: String {
        formattedPercentage(remainingPercentage5h)
    }

    var weeklyMenuBarTitle: String {
        formattedPercentage(remainingPercentageWeekly)
    }

    var menuBarTitle: String {
        "\(fiveHourMenuBarTitle)\n\(weeklyMenuBarTitle)"
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
    nonisolated init(
        fiveHour: CodexLimitWindow,
        weekly: CodexLimitWindow,
        staleSeconds: Int?,
        updatedAt: Date,
        sourceDescription: String
    ) {
        self.init(
            remainingPercentage5h: Self.remainingPercentage(fromUsedPercentage: fiveHour.usedPercent),
            timeUntil5hRenewal: fiveHour.resetsIn,
            local5hRenewalTime: fiveHour.localRenewalTime,
            remainingPercentageWeekly: Self.remainingPercentage(fromUsedPercentage: weekly.usedPercent),
            timeUntilWeeklyRenewal: weekly.resetsIn,
            localWeeklyRenewalTime: weekly.localRenewalTime,
            staleSeconds: staleSeconds,
            updatedAt: updatedAt,
            sourceDescription: sourceDescription
        )
    }

    private nonisolated static func remainingPercentage(fromUsedPercentage usedPercentage: Double) -> Double {
        min(max(100 - usedPercentage, 0), 100)
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
        Text("5-hour remaining: \(data.remainingPercentage5h.formatted(.number.precision(.fractionLength(0))))%")
        Text("Renews in \(data.timeUntil5hRenewal)")
        Text("Local renewal: \(data.local5hRenewalTime)")

        Divider()

        Text("Weekly remaining: \(data.remainingPercentageWeekly.formatted(.number.precision(.fractionLength(0))))%")
        Text("Renews in \(data.timeUntilWeeklyRenewal)")
        Text("Local renewal: \(data.localWeeklyRenewalTime)")

        Divider()

        Text("Source: \(data.sourceDescription)")

        if let updatedAt = data.updatedAt {
            Text("Updated at \(Self.formattedUpdateDate(updatedAt))")
        }

        if let staleSeconds = data.staleSeconds {
            Text("Local snapshot: \(Self.formattedStaleTime(staleSeconds)) old")
        }

        if let lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
        }

        Divider()

        Toggle("Open at Login", isOn: Binding(
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

        Button("Quit App") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private static func formattedStaleTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        return "\(minutes / 60)h"
    }

    private static func formattedUpdateDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
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
            launchAtLoginErrorMessage = "Unable to update launch at login"
        }
    }
}

@MainActor
final class CodexManager: ObservableObject {
    @Published private(set) var data: CodexData = .placeholder
    @Published private(set) var lastErrorMessage: String?

    private let usageProvider = CodexUsageProvider()
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
            self.data = try await usageProvider.readLatestUsage()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Unable to refresh data"
        }
    }
}

struct CodexUsageProvider {
    private let appServerProvider = CodexAppServerProvider()
    private let rolloutProvider = CodexRolloutProvider()

    nonisolated func readLatestUsage() async throws -> CodexData {
        do {
            return try await appServerProvider.readLatestUsage()
        } catch {
            return try await rolloutProvider.readLatestUsage()
        }
    }
}

struct CodexAppServerProvider {
    private let timeout: TimeInterval = 20

    nonisolated func readLatestUsage() async throws -> CodexData {
        try await Task.detached(priority: .utility) {
            try readLatestUsageSynchronously()
        }
        .value
    }

    private nonisolated func readLatestUsageSynchronously() throws -> CodexData {
        let executableURL = try codexExecutableURL()
        let response = try appServerResponse(from: executableURL)

        if let error = response["error"] {
            throw CodexAppServerError.requestRejected(String(describing: error))
        }

        guard let result = response["result"] as? [String: Any] else {
            throw CodexAppServerError.missingResult
        }

        let rateLimits = CodexJSON.pickDictionary(from: result, keys: ["rateLimits", "rate_limits"]) ?? result
        let snapshotDate = Date()

        guard let fiveHour = CodexJSON.window(from: rateLimits["primary"], snapshotDate: snapshotDate),
              let weekly = CodexJSON.window(from: rateLimits["secondary"], snapshotDate: snapshotDate) else {
            throw CodexAppServerError.missingRateLimits
        }

        return CodexData(
            fiveHour: fiveHour,
            weekly: weekly,
            staleSeconds: nil,
            updatedAt: snapshotDate,
            sourceDescription: "Codex app-server"
        )
    }

    private nonisolated func codexExecutableURL() throws -> URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let pathValues = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let candidatePaths = pathValues.map { "\($0)/codex" } + [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            homeDirectory.appending(path: ".local/bin/codex").path(),
            homeDirectory.appending(path: ".codex/bin/codex").path()
        ]

        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        throw CodexAppServerError.codexExecutableNotFound
    }

    private nonisolated func appServerResponse(from executableURL: URL) throws -> [String: Any] {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let responseBuffer = AppServerResponseBuffer(responseID: 2)
        let responseSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                responseSemaphore.signal()
                return
            }

            if responseBuffer.append(data) {
                responseSemaphore.signal()
            }
        }

        try process.run()

        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-status-bar","title":"Codex Status Bar","version":"0.1.0"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#
        ].joined(separator: "\n") + "\n"

        standardInput.fileHandleForWriting.write(Data(requests.utf8))

        let result = responseSemaphore.wait(timeout: .now() + timeout)
        standardOutput.fileHandleForReading.readabilityHandler = nil

        try? standardInput.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        guard result == .success else {
            throw CodexAppServerError.timeout
        }

        if let response = responseBuffer.response() {
            return response
        }

        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
        throw CodexAppServerError.noResponse(errorMessage)
    }
}

final class AppServerResponseBuffer: @unchecked Sendable {
    private let responseID: Int
    private let lock = NSLock()
    nonisolated(unsafe) private var textBuffer = ""
    nonisolated(unsafe) private var matchedResponse: [String: Any]?

    nonisolated init(responseID: Int) {
        self.responseID = responseID
    }

    nonisolated func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        textBuffer += String(data: data, encoding: .utf8) ?? ""

        while let newlineIndex = textBuffer.firstIndex(of: "\n") {
            let line = String(textBuffer[..<newlineIndex])
            textBuffer.removeSubrange(...newlineIndex)

            guard let lineData = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  message["id"] as? Int == responseID else {
                continue
            }

            matchedResponse = message
            return true
        }

        return false
    }

    nonisolated func response() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }

        return matchedResponse
    }
}

enum CodexAppServerError: LocalizedError {
    case codexExecutableNotFound
    case requestRejected(String)
    case missingResult
    case missingRateLimits
    case timeout
    case noResponse(String)

    var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return "codex executable not found"
        case .requestRejected(let message):
            return "codex app-server rejected the request: \(message)"
        case .missingResult:
            return "codex app-server did not return result"
        case .missingRateLimits:
            return "codex app-server did not return rate_limits"
        case .timeout:
            return "codex app-server timed out"
        case .noResponse(let message):
            return "codex app-server did not return a response: \(message)"
        }
    }
}

enum CodexJSON {
    nonisolated static func window(from value: Any?, snapshotDate: Date) -> CodexLimitWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = pickDouble(from: object, keys: ["usedPercent", "used_percent", "percent"]) else {
            return nil
        }

        let resetsAt = pickResetDate(from: object, snapshotDate: snapshotDate)
        return CodexLimitWindow(usedPercent: usedPercent, resetsAt: resetsAt)
    }

    nonisolated static func pickDictionary(from object: [String: Any], keys: [String]) -> [String: Any]? {
        keys.compactMap { object[$0] as? [String: Any] }.first
    }

    private nonisolated static func pickResetDate(from object: [String: Any], snapshotDate: Date) -> String? {
        if let resetsAt = pickString(from: object, keys: ["resetsAt", "resets_at"]) {
            return resetsAt
        }

        if let resetEpoch = pickDouble(from: object, keys: ["resetsAt", "resets_at"]) {
            let seconds = resetEpoch > 1_000_000_000_000 ? resetEpoch / 1_000 : resetEpoch
            return Date(timeIntervalSince1970: seconds).ISO8601Format()
        }

        if let resetsInSeconds = pickDouble(from: object, keys: ["resetsInSeconds", "resets_in_seconds"]) {
            return snapshotDate.addingTimeInterval(resetsInSeconds).ISO8601Format()
        }

        return nil
    }

    private nonisolated static func pickString(from object: [String: Any], keys: [String]) -> String? {
        keys.compactMap { object[$0] as? String }.first
    }

    private nonisolated static func pickDouble(from object: [String: Any], keys: [String]) -> Double? {
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
        var latestSnapshot: (eventDate: Date, rateLimits: [String: Any])?

        for file in try recentRolloutFiles() {
            guard let snapshot = try latestRateLimitsSnapshot(in: file.url, fileModificationDate: file.modificationDate) else {
                continue
            }

            if latestSnapshot == nil || snapshot.eventDate > latestSnapshot!.eventDate {
                latestSnapshot = snapshot
            }
        }

        guard let latestSnapshot,
              let fiveHour = window(from: latestSnapshot.rateLimits["primary"], snapshotDate: latestSnapshot.eventDate),
              let weekly = window(from: latestSnapshot.rateLimits["secondary"], snapshotDate: latestSnapshot.eventDate) else {
            throw CodexRolloutError.noRateLimitsSnapshot
        }

        let staleSeconds = max(0, Int(Date().timeIntervalSince(latestSnapshot.eventDate)))
        return CodexData(
            fiveHour: fiveHour,
            weekly: weekly,
            staleSeconds: staleSeconds,
            updatedAt: latestSnapshot.eventDate,
            sourceDescription: "Local snapshot"
        )
    }

    private nonisolated func recentRolloutFiles() throws -> [(url: URL, modificationDate: Date)] {
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
            .map { $0 }
    }

    private nonisolated func latestRateLimitsSnapshot(
        in fileURL: URL,
        fileModificationDate: Date
    ) throws -> (eventDate: Date, rateLimits: [String: Any])? {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("rate_limits") || line.contains("rateLimits"),
                  let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rateLimits = findRateLimits(in: object) else {
                continue
            }

            return (eventDate(from: object, fallback: fileModificationDate), rateLimits)
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

    private nonisolated func window(from value: Any?, snapshotDate: Date) -> CodexLimitWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = pickDouble(from: object, keys: ["usedPercent", "used_percent", "percent"]) else {
            return nil
        }

        let resetsAt = pickResetDate(from: object, snapshotDate: snapshotDate)
        return CodexLimitWindow(usedPercent: usedPercent, resetsAt: resetsAt)
    }

    private nonisolated func pickResetDate(from object: [String: Any], snapshotDate: Date) -> String? {
        if let resetsAt = pickString(from: object, keys: ["resetsAt", "resets_at"]) {
            return resetsAt
        }

        if let resetEpoch = pickDouble(from: object, keys: ["resetsAt", "resets_at"]) {
            let seconds = resetEpoch > 1_000_000_000_000 ? resetEpoch / 1_000 : resetEpoch
            return Date(timeIntervalSince1970: seconds).ISO8601Format()
        }

        if let resetsInSeconds = pickDouble(from: object, keys: ["resetsInSeconds", "resets_in_seconds"]) {
            return snapshotDate.addingTimeInterval(resetsInSeconds).ISO8601Format()
        }

        return nil
    }

    private nonisolated func eventDate(from object: [String: Any], fallback: Date) -> Date {
        let payload = object["payload"] as? [String: Any]
        let timestamp = object["timestamp"] ?? payload?["timestamp"]

        if let timestamp = timestamp as? String,
           let date = ISO8601DateFormatter.codexDate(from: timestamp) {
            return date
        }

        if let timestamp = timestamp as? Double {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1_000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }

        if let timestamp = timestamp as? Int {
            let value = Double(timestamp)
            let seconds = value > 1_000_000_000_000 ? value / 1_000 : value
            return Date(timeIntervalSince1970: seconds)
        }

        return fallback
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
            return "~/.codex/sessions directory is unavailable"
        case .noRateLimitsSnapshot:
            return "No rate_limits snapshot found"
        }
    }
}

#if DEBUG
#Preview {
    CodexStatusMenu(
        data: CodexData(remainingPercentage5h: 25, timeUntil5hRenewal: "02:15:00", local5hRenewalTime: "23:15",
                        remainingPercentageWeekly: 48, timeUntilWeeklyRenewal: "2 dias",
                        localWeeklyRenewalTime: "28/10 14:00", staleSeconds: 120, updatedAt: Date(),
                        sourceDescription: "Local snapshot"),
        lastErrorMessage: nil
    )
}
#endif
