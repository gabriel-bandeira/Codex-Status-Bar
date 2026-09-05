# Codex Status Bar

Native macOS menu bar utility that shows the remaining Codex usage limits at a glance.

The menu bar item shows two stacked percentages to keep the status item compact:

```text
25%
48%
```

The top value is the remaining 5-hour limit. The bottom value is the remaining weekly limit.

## How It Works

The app does not use an external HTTP API. Every 30 seconds, it first tries to read the latest limits directly from Codex with:

```text
codex app-server
```

The app sends this JSON-RPC method:

```text
account/rateLimits/read
```

If the `codex` executable is not installed or cannot be reached by the app, it falls back to local Codex session snapshots in:

```text
~/.codex/sessions
```

In fallback mode, the app:

1. Finds recent `rollout-*.jsonl` files.
2. Reads the newest snapshots.
3. Finds the `rate_limits` object.
4. Maps `primary` to the 5-hour limit.
5. Maps `secondary` to the weekly limit.
6. Converts `used_percent` into remaining percentage with `100 - used_percent`.
7. Updates the menu bar item.

The dropdown menu shows:

- 5-hour remaining percentage;
- time until the 5-hour window renews;
- local 5-hour renewal time;
- weekly remaining percentage;
- time until the weekly window renews;
- local weekly renewal time;
- exact local timestamp for the displayed data;
- data source: `Codex app-server` or `Local snapshot`;
- snapshot age when fallback mode is used;
- `Open at Login`;
- `Quit App`.

When the source is `Codex app-server`, the displayed data is from a live Codex limit read. When the source is `Local snapshot`, the data refers to the local snapshot timestamp shown as `Updated at ...` and may be older than the current `/status` output in Codex.

## Does It Use Codex Tokens?

The app does not send prompts, start conversations, or ask a model to generate text.

The live read uses `account/rateLimits/read` through `codex app-server`, which reads account limit metadata. The fallback only reads local `rollout-*.jsonl` files. The expected behavior is that the app does not consume Codex tokens; it only reads or reuses limit information.

## Install the Local Build

A local build is included at:

```text
dist/Codex-Status-Bar-local-arm64.zip
```

This build is for Apple Silicon Macs.

To install it:

1. Download `dist/Codex-Status-Bar-local-arm64.zip`.
2. Extract the archive.
3. Move `Codex Status Bar.app` to `/Applications`.
4. Right-click the app and choose `Open` the first time.
5. If macOS blocks the app, open `System Settings > Privacy & Security` and click `Open Anyway`.
6. After the app opens, use the menu bar dropdown and enable `Open at Login`.

## Launch at Login

The app menu includes:

```text
Open at Login
```

When enabled, the app uses `SMAppService.mainApp` to register itself as a macOS login item. It appears in:

```text
System Settings > General > Login Items
```

You can disable it from the app menu or from System Settings.

## Signing and Gatekeeper

This build is not notarized by Apple and does not use Developer ID, because Developer ID requires a paid Apple Developer Program membership.

It is a locally signed ad-hoc build. That means:

- it is suitable for personal and hobby use;
- macOS may block the first launch;
- another Mac needs to trust the app manually;
- there is no App Store review;
- there is no Apple notarization.

Without Developer ID, the expected flow is to manually approve the app on first launch with `Open Anyway` in `Privacy & Security`.

## Build Locally with Xcode

To create a local build with Xcode:

1. Open the project in Xcode.
2. Select the `Codex Status Bar` target.
3. Confirm that `Application is agent (UIElement)` / `LSUIElement` is set to `YES`.
4. For local usage with `codex app-server` and `~/.codex/sessions`, disable `App Sandbox` or implement a folder permission flow with security-scoped bookmarks.
5. Use `Product > Archive` or run the app directly from Xcode.

You can also create an ad-hoc command-line build:

```sh
xcodebuild \
  -project "Codex Status Bar.xcodeproj" \
  -scheme "Codex Status Bar" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  INFOPLIST_KEY_LSUIElement=YES \
  ENABLE_APP_SANDBOX=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  build
```

## Current Limitations

- The included build is arm64 only.
- Live reads require the `codex` executable to be installed in a path the app can find, such as `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `~/.local/bin/codex`, or `~/.codex/bin/codex`.
- With App Sandbox enabled, the app may not be able to execute `codex app-server` or read `~/.codex/sessions`.
- There is no UI yet to choose the `.codex` folder and store persistent permission.

## License

This project is licensed under the BSD Zero Clause License. You can use, copy, modify, and distribute it for personal or commercial purposes.

## Possible Next Steps

- Add a `.codex` folder picker with a security-scoped bookmark.
- Create a universal `arm64 + x86_64` build.
- Add manual configuration for the `codex` executable path.
- Create a GitHub Release and attach the zip there.
