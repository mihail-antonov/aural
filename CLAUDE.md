# CLAUDE.md

## Project

**Aural** — a lightweight native Spotify mini player for macOS, written entirely in **Swift / SwiftUI** with Apple's Liquid Glass design. Playback is done by **Spotify Soloist**, Spotify's official headless player; Aural is its native interface and controls it through Soloist's local WebSocket API.
(Never rename the app to anything starting with "Spot" or resembling "Spotify".)

**The single most important goal: low memory usage.** The official Spotify desktop app is a Chromium (CEF) web app that uses 1 GB+ of RAM. **Aural + Soloist together** must stay well below that — target **under ~150 MB combined**, with Aural itself under ~60 MB. Soloist's own baseline (measured in Stage 0): ~19 MB logged in and idle, ~34–37 MB while playing. Every design decision should be judged against this.

**Second goal: feel native to macOS 26.** Liquid Glass, system controls, Now Playing, media keys — it should look and behave like an app Apple could have shipped.

**Third goal: portfolio piece.** Code quality, README and documentation matter. See "Portfolio".

The owner is primarily a JavaScript developer, new to Swift, and uses Zed as the main editor. Keep code readable, idiomatic and well-structured; prefer clarity over cleverness. Briefly explain non-obvious Swift patterns in comments.

### History (why Soloist)
The first prototype used `librespot` (unofficial Rust implementation). Login worked, but playback failed with `error audio key 0 1` (librespot issue #1649): Spotify no longer hands out decryption keys to librespot for many accounts, including the owner's, and there is no legitimate fix. The librespot code and Rust have been removed. Soloist is official, so it works with any Premium account and carries no account or legal risk.

## Scope

### In scope (core features only)
- Playback: play / pause / next / previous / seek / volume
- Queue
- Shuffle and repeat
- Like / unlike the current track (Liked Songs) — only if confirmed available
- User's playlists, Liked Songs, saved albums
- Search (tracks, albums, artists, playlists)
- "Similar songs": continue playing related tracks when a context ends — Soloist's built-in autoplay (confirmed in Stage 0; no command to turn it on or off)
- macOS Now Playing integration (Control Center, lock screen) and media keys (keyboard, AirPods)
- **Demo mode with local audio files** (see "Demo mode")

### Out of scope — do not implement
- Lyrics, podcasts, audiobooks
- Recommendations UI, home feed, editorial content
- Spotify Connect device switching / output device picker
- Offline downloads of Spotify content, recording audio
- Social features, friend activity
- Any web view, embedded browser, Electron, Tauri, or Dioxus desktop
- Any unofficial Spotify protocol implementation (librespot and ports)

## Design

Reference image: `docs/design.png`. Read it before working on any UI.

A single **compact window** (roughly 320 × 360 pt, not resizable or only slightly), rounded corners, Liquid Glass background. Top to bottom:

1. **Header row:** album art (square, rounded corners, ~110 pt) on the left; on the right a small monospaced uppercase label `NOW PLAYING`, the track title (large, bold), the artist (secondary gray), and a heart button (filled with the accent color when liked).
2. **Progress bar:** thin track, accent-colored fill, round draggable knob. Below it, elapsed time on the left (`1:25`) and remaining time on the right (`-2:10`), in a small monospaced font.
3. **Controls row:** shuffle, previous, a **large circular play/pause button filled with the accent color**, next, repeat. Shuffle/repeat show the accent color when active.
4. **Bottom row:** a small icon + label button that opens the **user's playlists**. The exact presentation (popover, sheet, or the window expanding) is decided during development — propose 2 options with a quick prototype before committing.

Visual rules:
- **Accent color:** lime green, approximately `#C8F04B` (tune to match the reference). Used sparingly: play button, progress fill, active states, heart.
- **Fonts:** SF Pro for text, SF Mono for the `NOW PLAYING` label and the time stamps. System fonts only.
- **Liquid Glass:** the window background and floating controls use Liquid Glass (`.glassEffect()` and system glass button styles on macOS 26). Glass belongs to the controls/chrome layer, not to content like album art. Keep enough contrast for text and the accent color on light wallpapers.
- Respect **Reduce Transparency** and **Increase Contrast** (verify how SwiftUI glass behaves with them; fall back to an opaque dark background like the reference).
- Prefer **system SwiftUI controls and SF Symbols** over custom-drawn ones, so they adopt Liquid Glass automatically.
- Supports dark and light appearance.

**Minimum macOS version: 26.** Apple Silicon only.

## Tech stack

| Concern | Choice |
|---|---|
| Language / UI | Swift 6 (strict concurrency), SwiftUI, `@Observable` |
| Playback engine | Spotify Soloist (separate process, installed by the user) |
| Soloist control | `URLSessionWebSocketTask` to Soloist's local WebSocket API |
| Soloist process | `Process` (Foundation) to launch / stop it |
| Spotify Web API (library, search) | `URLSession` + `Codable` — only for what still works, see "Web API availability" |
| Demo mode playback | `AVFoundation` (`AVPlayer` / `AVAudioPlayer`) |
| Now Playing + media keys | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| Secrets (Soloist API key, tokens) | Keychain (Security framework) |
| Project | **XcodeGen** (`project.yml`) for the app; logic in a local **Swift package** |

Prefer Apple frameworks over third-party packages. Add a dependency only with a clear reason, pin its exact version, and note it here.

When unsure about any API (Soloist, Spotify Web API, SwiftUI Liquid Glass), check the current official documentation instead of guessing.

## Architecture

```
AuralCore/                  # local Swift package: all logic, no UI
  Package.swift
  Sources/AuralCore/
    Player/                 # player abstraction, PlaybackState, events
    Sources/
      Soloist/              # process management, WebSocket client, message types
      Local/                # demo mode (AVFoundation)
    Library/                # playlists, liked songs, albums, search (Web API)
    Cache/                  # on-disk image cache
    Support/                # Keychain, track-ID / URI parsing, logging
  Tests/AuralCoreTests/
App/                        # SwiftUI app target
  project.yml               # XcodeGen definition
  Sources/
    App/                    # app entry, window setup
    Views/                  # mini player, playlists panel, components
    Models/                 # @Observable view models mirroring core state
    System/                 # Now Playing, media keys
docs/
  design.png
```

Principles:
- **AuralCore owns all logic and state** (like a backend); the app target is a thin UI layer (like a frontend) that sends commands and renders state. AuralCore must not import SwiftUI.
- AuralCore is tested with `swift test` from the command line.
- **Sources are behind a common protocol** (`PlaybackSource`: Soloist, Local). The rest of the app does not know which one is active. All Soloist-specific code stays in `Sources/Soloist`.
- Queue, shuffle and repeat are owned by the playback source (Soloist owns them for Spotify; the Local source implements its own simple version). There is no separate queue module.
- Use Swift concurrency (`async`/`await`, actors) for the WebSocket client and process management. UI state is updated on the main actor.
- Nothing in the UI blocks on Soloist, the network, or disk.

### Soloist integration
Confirmed in Stage 0 (Soloist 1.3.10, docs + hands-on test):

**Setup and launch**
- The user generates their own Soloist API key in the Spotify for Developers dashboard (`/dashboard/soloist`, requires Premium). Aural installs Soloist itself from Spotify's official download URL (see "Soloist management in the app"). **Aural never bundles, hosts, mirrors or redistributes Soloist.**
- The API key is stored in the Keychain and passed **only as the `-k` / `--api-key` argument** — Soloist has no environment variable or config file for it. It is never logged or written to files. Known limitation: while Soloist runs, the key is visible in the process list (`ps`) to processes of the same user.
- Aural launches Soloist as a child process with `-n <device name> -k <key> --ws 127.0.0.1:0 -z 100`, or connects to an already running instance. Always bind the WebSocket to loopback (the API has no auth/TLS). Port `0` = OS-assigned; read the real port from `~/Library/Application Support/soloist/ws.port` (and `ws.addr`). `-z 100` caps Soloist's playback cache (default is unlimited; minimum 100 MB). Aural stops the child process when it quits.
- Daemon exit codes: `0` OK, `1` general failure, `10` build expired.

**Pairing and network**
- First use **requires pairing from an official Spotify app**: the user picks the device in the Spotify Connect device picker on the same local network. There is no in-app login. Aural shows a first-run screen ("Open Spotify and choose <device name>"). After pairing, Soloist stores the session in its data directory and restores it automatically on every restart (~0.3 s).
- After a restart the device is logged in but not active; `play <uri>` makes it active automatically (this takes playback away from other devices).
- Discovery uses multicast (mDNS). macOS **Local Network privacy** applies to the app that launched Soloist — without permission, multicast fails (`No route to host`) and the device is invisible. Aural's `Info.plist` needs `NSLocalNetworkUsageDescription`, and Aural shows a clear message when access is denied.
- Soloist is visible as a Connect device to everyone on the local network (Free accounts can connect too). There is no option to disable network discovery. Mention this under limitations in the README.

**Expiry**
- **Builds expire 90 days after their build date.** `soloist --version` prints e.g. `soloist 1.3.10.65 build 1794463304 (20261112) …`; expiry = the date in parentheses + 90 days. How Aural handles it: see "Soloist management in the app".
- **The API key has no documented expiry.** The docs only say: if the key is revoked or replaced in the dashboard, restart Soloist with the new key; the key is separate from the stored session and is required at every startup. Treat it as valid until revoked, and let the user replace it from the app if Soloist rejects it (exact rejection behaviour still to be verified).

**Soloist management in the app** (no terminal commands for the user, ever)
- Aural manages its own Soloist install in `~/Library/Application Support/Aural/soloist/`. The executable path comes from **one place in AuralCore** and is never hard-coded elsewhere. It defaults to that path and allows an override (used by the probe and for a manual install).
- Soloist's data directory (device identity, pairing session) stays separate from the executable (default `~/Library/Application Support/soloist/`), so the API key (Keychain) and the pairing session survive updates.
- **Install and update from the app:** download the official macOS archive directly from Spotify's official download URL (`https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz`) into a fresh temporary directory, extract it, **verify the code signature is `Developer ID Application: Spotify (2FNC3A47ZF)`** (Security framework, before the executable is ever run), then replace the old executable and restart Soloist. Spotify publishes no checksums, so the signature check is the integrity check. If the download or verification fails, fall back to opening the official downloads page.
- **Expiry:** read the build date from `soloist --version` at startup. From 7 days before expiry, show a non-blocking notice with an "Update" button. On exit code `10`, show a clear screen with the same button.
- **First run is a guided setup screen:** install Soloist → enter the API key (stored in Keychain) → pair from the Spotify app ("Open Spotify and choose <device name>"), including the Local Network permission step.

**WebSocket API**
- JSON text frames. Commands: `{"type":"command","command":"<name>", …}`. Queries: `get_auth_state`, `get_state`, `get_queue {limit}`. Controls: `play {uri?}`, `pause`, `skip_next`, `skip_prev`, `seek {position_ms}`, `set_volume {volume}`, `set_shuffle {enabled}`, `set_repeat_context {enabled}`, `set_repeat_track {enabled}`, `add_to_queue {uri}`, `activate`, `deactivate`.
- `play` accepts track, album, playlist (and episode) URIs — **not artist URIs**. `add_to_queue` accepts track URIs only.
- Repeat is two flags; map Aural's off / context / track to them inside `Sources/Soloist`.
- Events: `auth_state`, `playback_state` (full snapshot), `track_changed`, `playback_changed`, `position_sync`, `volume_changed`, `options_changed`, `context_changed`, `queue_changed`, `device_changed`, `command_result`, `error`.
- Metadata (entity `decorations`): title, artists (`creators`), album (`parent`), cover URLs in 4 sizes, `duration_ms`. Position is an anchor (`position_ms`, `timestamp_ms`, `speed`); compute the current position locally — no per-tick events.
- `command_result` only means "accepted", not "state changed" — wait for the state event. Enable/disable controls from `playback_state.available_actions`: e.g. a single track URI has no `shuffle` / `set_repeat`, and those commands are then silently ignored.
- Broadcast `queue_changed` carries at most 10 entries; use `get_queue {limit}` for more. Autoplay entries have `source: "autoplay"`.

- Soloist's memory counts toward the combined budget — always measure Aural and Soloist together.

### Web API availability
Spotify has heavily restricted the public Web API for apps in Development Mode:
- November 2024: Recommendations, Related Artists, Audio Features / Analysis and Spotify-owned algorithmic/editorial playlists were removed for new apps.
- February 2026: ~15 more endpoints were removed (including browse categories, artist top tracks, new releases, album metadata and bulk "get several tracks/albums/artists"), popularity fields were stripped, and Development Mode now requires the app owner to have Premium and is limited to 5 users.

Rules:
- **Do not assume any Web API endpoint works.** Verify each one against the current docs and a real request before building on it.
- Prefer what Soloist's WebSocket API provides (metadata, playback state). Use the Web API only for what Soloist cannot do (e.g. the user's playlists, Liked Songs, search) — confirm each one.
- Web API login uses OAuth Authorization Code with PKCE; the redirect URI must use the loopback address `http://127.0.0.1:<port>/...`, not `localhost`. Tokens go in the Keychain.
- Keep a list in "Progress" of which Soloist messages and Web API endpoints are actually used and confirmed working.

### Demo mode
A **Local** source: the user picks a folder of audio files (MP3, FLAC, AAC/M4A, WAV), shown as a "playlist". Purpose: anyone can run the app without Spotify (portfolio), and screenshots / videos use royalty-free music instead of copyrighted album art. Read metadata and embedded artwork with AVFoundation. Keep it simple — no library database.

## Memory rules

- **Album art is cached on disk**, not in memory. Keep only the images currently visible in memory, at the size they are displayed (downscale on load). Cap the disk cache (e.g. 200 MB, LRU eviction).
- In SwiftUI, load thumbnails lazily (`LazyVStack` / `List`) and release them when off-screen.
- Load long lists lazily / paginated; do not hold full JSON responses — decode into small structs.
- No unbounded caches, buffers or message queues.
- After each stage, measure **Aural and Soloist separately and combined** (Activity Monitor, `footprint`, or `vmmap`) and record it in "Progress". If memory regresses noticeably, investigate before moving on.

## Development stages

Work **one stage at a time**. Each stage must end with something that runs. Do not start the next stage until the current one works and the owner has confirmed.

0. **Soloist research (no app code).** Read Soloist's docs (overview, authentication, features, WebSocket API, `soloist ctl`, terms). Answer: can it load a track / album / playlist URI? Queue, shuffle, repeat, seek, volume, autoplay? What events and metadata does it send? Does first use need pairing from the official Spotify app, or can it start with a stored session? Install it on the owner's Mac (the owner generates the API key), run it, play a track, measure its memory. Check how library and search would work. **Report findings and propose updates to this file before writing code.**
1. **Soloist control prototype.** AuralCore with the Soloist source: launch Soloist, connect over WebSocket, play a URI, receive and log events. Driven from a tiny test executable or unit/integration test.
2. **Minimal app.** XcodeGen project, a plain SwiftUI window showing the current track with play/pause/next. Now Playing and media keys working.
3. **Library and search.** Playlists, Liked Songs, saved albums, search, and the like button's save/remove — all through the Web API (OAuth PKCE), since Soloist provides no library, search or like. Confirm each endpoint with a real request first. Remember `play` cannot take artist URIs.
4. **Full UI per design.** The mini player as in `docs/design.png`, with Liquid Glass; the playlists button and panel (prototype 2 options first).
5. **Queue, shuffle, repeat, autoplay, like button.**
6. **Demo mode** with the Local source.
7. **Polish and portfolio.** Image cache with a cap, restore last state on launch, **Soloist management in the app** (guided first-run setup, install/update with signature check, expiry notice and exit-code-10 screen, replacing the API key — see "Soloist management in the app"), app icon, README, screenshots and a short video recorded in demo mode.

Optional later stages (only if the owner asks): menu bar mode; global keyboard shortcuts.

## Building

- The owner works in Zed. Everything must build and run from the command line: `swift test` for AuralCore; `xcodegen` + `xcodebuild` for the app. Provide a single `make run` that builds and launches the app, and `make test`.
- Xcode is only needed for SwiftUI Previews and debugging.
- Sign with the owner's free Apple "Personal Team" so the signature is stable and Keychain doesn't prompt after every build.

## Conventions

- Swift 6 language mode with strict concurrency; no warnings.
- Small, composable views; no business logic in views.
- Errors: typed errors per module; no `try!` / force unwraps outside tests and truly impossible cases (comment why).
- Logging with `os.Logger`; no `print` debugging left in committed code. Never log API keys or tokens.
- Secrets never in the repository.
- Commit after each working step with a clear message.

## Portfolio

- **README headline: measured memory.** "Official Spotify client: ~X GB. Aural + Soloist: Y MB." Measure honestly under the same conditions; include Activity Monitor screenshots.
- README sections: what it is, why (memory), architecture diagram (SwiftUI ↔ AuralCore ↔ WebSocket ↔ Soloist ↔ Spotify), the librespot → Soloist story, setup (download Soloist from the official page, generate your own API key), how to build, demo mode, limitations.
- **Disclaimer:** unofficial interface for Spotify Soloist; requires Spotify Premium; not affiliated with, endorsed or sponsored by Spotify.
- No Spotify logo or brand colors in the app or README.
- Screenshots and videos are recorded in **demo mode** with royalty-free music.

## Legal note

Aural uses Spotify Soloist, Spotify's official headless player, as intended: controlled by a local interface through its WebSocket API. Follow Soloist's terms: each user uses their own API key, the key is never shared, and Soloist is never bundled or redistributed. Also follow the Spotify Developer Policy for any Web API use. Do not add features for downloading or recording audio, or anything that works around Spotify's protections.

## Progress

_Update this section at the end of each stage: what works, measured memory (Aural / Soloist / combined), confirmed Soloist messages and Web API endpoints, known issues._

- [x] librespot prototype — abandoned: audio key error 1 (librespot #1649). Rust removed.
- [x] Stage 0 — Soloist research (2026-11-12)
  - Soloist 1.3.10.65, build 20261112 (expires ~2027-02-10), Apple Silicon build, signed Developer ID Spotify (2FNC3A47ZF). Installed outside the repo.
  - Memory (`footprint` / `vmmap`): idle not paired 5.5 MB; logged in idle 19 MB; playing 34–37 MB (peak 37.6 MB); crash-reporter helper process ~3.8 MB.
  - Confirmed working: pairing from the Spotify app, session restore on restart, `play` with track and album URIs, `pause`, `seek`, `set_volume`, `set_shuffle` + repeat (album context), autoplay after a single track, `trace` events listed in "Soloist integration".
  - Known issues: Local Network permission required for discovery; shuffle/repeat silently ignored for a single-track context; API key visible in `ps`; device visible to everyone on the LAN.
- [x] Stage 1 — Soloist control prototype (2026-11-12)
  - AuralCore Swift package (no dependencies): `PlaybackSource` protocol and models, `SoloistSource` (actor) built from `SoloistProcess` (launch / attach / stop), `SoloistConnection` (`URLSessionWebSocketTask`), wire types + pure mapping, Keychain read. `aural-probe` CLI; `make test`, `make probe URI=… [SOLOIST=…]`.
  - Verified live: launch with stored session (logs in by itself), attach to an already running Soloist (left running on exit), `play` track URI, events → state, Ctrl-C stops Soloist and its helper process, missing executable error, Soloist killed → error event. 14 unit tests (decoding from real message shapes, command encoding, repeat mapping, position, state merging).
  - Memory during playback: aural-probe (debug build) 5.8 MB; Soloist 24–25 MB + helper 3.8 MB; combined ~34 MB.
  - Known issues: the ad-hoc-signed probe triggers a Keychain access prompt after rebuilds (fixed by stable signing in Stage 2); the first `playback_state` after a track change can briefly show the previous position until `position_sync` arrives.
- [ ] Stage 2 — Minimal app, Now Playing, media keys
- [ ] Stage 3 — Library and search
- [ ] Stage 4 — Full UI with Liquid Glass
- [ ] Stage 5 — Queue, shuffle, repeat, autoplay, like
- [ ] Stage 6 — Demo mode (local files)
- [ ] Stage 7 — Polish and portfolio
