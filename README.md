# OpenCode Usage

<img src="docs/icon.png" width="96" align="right" alt="">

A macOS menu bar app that shows what your OpenCode **Go** plan is using, right
now. Port of the Noctalia plugin from my dotfiles.

The menu bar shows the gauge and three figures — `H 2% W 13% M 10%` — where
**H** is the rolling 5-hour window, **W** the current week (Monday start) and
**M** the calendar month. Any combination can be turned off in settings. Click
for per-model spend, requests, tokens and the reset times.

## Install

```shell
brew install --cask ./Casks/opencode-usage.rb
```

Or download `OpenCodeUsage.zip` from the latest release and drag the app out.
The build is ad-hoc signed, so the first launch needs right-click → **Open**.

## Build

```shell
./build.sh                      # this machine's arch
ARCHS="arm64 x86_64" ./build.sh # universal
open build/OpenCodeUsage.app
```

No Xcode project, no packages: `build.sh` runs one `swiftc` call and assembles
the bundle. The icon lives in `Resources/AppIcon.icns`; `./icon.sh` redraws it
from `Resources/icon.swift`.

Self-checks:

```shell
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --selftest   # offline asserts
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --dump       # live fetch, prints numbers
./build/OpenCodeUsage.app/Contents/MacOS/OpenCodeUsage --loginitem on|off  # same as the settings toggle
```

## Settings

Open the panel, click the gear.

| Setting | Default | Notes |
| --- | --- | --- |
| Refresh | 10 min | Timer keeps running while the panel is closed. |
| Org ID | empty | Only for keys that can reach several workspaces: the header is sent only when set. |
| Warn / critical | 80% / 95% | Panel color and warning triangle. |
| Menu bar | H + W + M | Which figures to show. |
| Launch at login | off | Writes and registers `~/Library/LaunchAgents/dev.myleshen.opencode-usage.plist`. |

### One scope only

The console attributes each request to a principal, and API-key traffic is
billed to a *service account*, not to your member id. On my workspace the
member account had $0.85 this month while the account total was $10 — same Go
quota, so filtering to the member id would have under-reported it by an order of
magnitude. The app therefore always shows every principal the key can see.

Only the `go` plan table is included. `go_plus` / `go_teams` limits would need
adding to `Sources/Usage.swift`.

## How it works

1. Reads the Go key from `~/.local/share/opencode/opencode.db` (table
   `credential`, `integration_id = 'opencode-go'`, `active = 1`), falling back to
   the legacy `~/.local/share/opencode/auth.json`. opencode v2 moved credentials
   into sqlite; the JSON file can hold an expired key. The key never leaves the
   machine except as the `Authorization` header to `opencode.ai`.
2. `GET /console/api/usage/models?since=…` for the 5h / week / month / today
   windows, in parallel, following pagination.
3. Filters `provider == "opencode-go"`, converts `totalCostMicroCents / 1e8` to
   USD, and compares against the plan limits (5h cap = 20% of the limit, week
   50%, month 100%).

Window boundaries use the local calendar (Monday start), converted to UTC ISO
for the `since` parameter.

## Notes

- The launch-at-login plist records the absolute path of the bundle, so
  re-run the toggle after moving the app.
- Launching the app twice is safe: the newer copy exits and the older one keeps
  the menu bar item, so the login item cannot produce a duplicate.
- No Quit menu item — `pkill -f OpenCodeUsage` or delete the app.
- Uninstall: turn off launch at login, quit, delete the app.

## Releasing

`.github/workflows/release.yml` builds a universal app, runs the self-test, zips
it and publishes `OpenCodeUsage.zip` on a `v*` tag. The cask installs from
`releases/latest/download/OpenCodeUsage.zip`, so a new tag is enough for
`brew upgrade`.
