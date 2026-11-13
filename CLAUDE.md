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

### Out of scope — do not implement
- Lyrics, podcasts, audiobooks
- Playing local audio files or any music without Spotify (a "demo mode" was planned and dropped by the owner: Aural is bound to Spotify)
- Recommendations UI, home feed, editorial content
- Spotify Connect device switching / output device picker (exception: the player's device menu can take playback over to Aural — "Playing in Aural")
- Offline downloads of Spotify content, recording audio
- Social features, friend activity
- Any web view, embedded browser, Electron, Tauri, or Dioxus desktop
- Any unofficial Spotify protocol implementation (librespot and ports)

## Design

Reference image: `docs/design-2.png` — **kept locally only, not committed** (third-party mockup with real album covers; listed in `.gitignore`). Follow its layout and style; read it before working on any UI. It shows a phone-sized screen; Aural adapts it to a small Mac window.

A single **portrait window, 320 × 638 pt, fixed size** (586 pt of content plus the 52 pt hidden title bar; `Metrics.windowSize`. Was 628 pt until 2026-11-13, +10 pt for more room between the artist and the time), rounded corners, no visible toolbar strip. The list button switches to the library (playlists, Liked, albums, search) in the same window; its back chevron or Esc returns to the player. (A bottom navigation bar was tried in Stage 4 and dropped by the owner.) The player page, top to bottom:

1. **Toolbar and header row:** the `…` menu is a system toolbar item at the top right (settings: change Soloist API key, change Spotify Client ID; Aural and Soloist versions), drawn like the other icons (no toolbar button background). Under it, the design's header row is back (owner, 2026-11-13) with new content: left (the design's chevron) **where the music plays** — a speaker icon with a dropdown, accent color when Soloist is the active device, dimmed white when another device plays; the menu offers "Playing in Spotify" / "Playing in Aural" (choosing Aural: Soloist `activate` + `play`) — the only device switching in scope, no picker of other devices (Soloist does not name them); middle the playlist / album name (`contextName`); right (the design's `…`) the **heart** (adds the song to Liked Songs; filled accent heart when liked, clicking again removes it).
2. **Track info:** title (bold) and artist (secondary), centered.
3. **Time:** `01:23 | 02:35` (elapsed | total), small, with monospaced digits, above the cover.
4. **Cover with progress ring:** the album art **cropped to a circle**, surrounded by a **circular progress ring** (accent-colored arc on a faint track) with a round **draggable knob**. Custom-drawn (no system control exists): must support VoiceOver (adjustable value) and keyboard seeking.
5. **Controls row:** shuffle, previous, a **large round play/pause button** (system Liquid Glass `.glass` button), next, repeat. Shuffle/repeat use the accent color when active. The design's `⊖` ("hide song") is dropped — no API for it.
6. **Bottom row:** search, **library** (`square.stack`, opens the library in the same window), **queue** (`list.bullet`, opens the queue page), **volume** (opens a small glass popover with a slider). No adding to playlists — Aural stays a lightweight player.

Player layout rule: the header and track info are placed from the window top, the two control rows from the bottom (33 pt between them, 40 pt to the bottom edge), and the time + cover/ring fill the middle, shrinking if space gets tight (`Metrics.ringSize`). Adding or resizing a row must never change the controls' spacing; ask the owner before touching gaps that were not part of the request.

Visual rules:
- **Background:** a vertical gradient **tinted from the current cover's dominant color** (computed from the small, already downscaled cover image), dark enough for white text. It changes smoothly with the track. Opaque, as in the design: it is the content layer and keeps text readable on any wallpaper.
- **Accent color:** warm peach, approximately `#F0B878` (tune to match the reference). Fixed, not derived from the cover. Used sparingly: progress ring and knob, time highlight, heart, active shuffle/repeat.
- **Liquid Glass (Apple's design language, macOS 26):** glass belongs to the **controls layer**, not to content. Use Apple's own button styles, not custom ones: `.glass` for play/pause and the Play / Shuffle / Save buttons (Play's icon in the accent color), no glass in setup: `.borderedProminent` in the accent color for the main button, `.borderless` and `Link` for minor actions, plain filled text fields (`.glassProminent` has no hover or press feedback on macOS); `.glassEffect()`, grouping nearby controls in a `GlassEffectContainer`. Header buttons, the `…` menu, control rows and popovers are glass; the cover and background are not. Check Apple's current documentation for exact APIs.
- **Fonts:** system fonts only (SF Pro); monospaced digits for times.
- Respect **Reduce Transparency** and **Increase Contrast** (verify how glass behaves with them; the opaque background already works without transparency).
- Prefer **system SwiftUI controls and SF Symbols** over custom-drawn ones, so they adopt Liquid Glass automatically. Exceptions agreed with the owner: the progress ring, and Spotify-style icon tooltips (`.tooltip(…)`, `Tooltip.swift`: dark label above the icon after ~0.45 s, drawn in a window-level layer). The toolbar's `…` menu, list rows and links keep the native `.help` tooltip.
- Text and controls are designed for the dark tinted background in both system appearances.

**Minimum macOS version: 26.** Apple Silicon only.

## Tech stack

| Concern | Choice |
|---|---|
| Language / UI | Swift 6 (strict concurrency), SwiftUI, `@Observable` |
| Playback engine | Spotify Soloist (separate process, installed by the user) |
| Soloist control | `URLSessionWebSocketTask` to Soloist's local WebSocket API |
| Soloist process | `Process` (Foundation) to launch / stop it |
| Spotify Web API (library, search) | `URLSession` + `Codable` — only for what still works, see "Web API availability" |
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
  design-2.png             # design reference (local only, not committed)
```

Principles:
- **AuralCore owns all logic and state** (like a backend); the app target is a thin UI layer (like a frontend) that sends commands and renders state. AuralCore must not import SwiftUI.
- AuralCore is tested with `swift test` from the command line.
- **Playback goes through a protocol** (`PlaybackSource`, implemented by the Soloist source), so the UI never sees Soloist's message format. All Soloist-specific code stays in `Sources/Soloist`.
- Queue, shuffle and repeat are owned by the playback source (Soloist, plus Aural's list queue and history on top). There is no separate queue module.
- Use Swift concurrency (`async`/`await`, actors) for the WebSocket client and process management. UI state is updated on the main actor.
- Nothing in the UI blocks on Soloist, the network, or disk.

### Soloist integration
Confirmed in Stage 0 (Soloist 1.3.10, docs + hands-on test):

**Setup and launch**
- The user generates their own Soloist API key in the Spotify for Developers dashboard (`/dashboard/soloist`, requires Premium). Aural installs Soloist itself from Spotify's official download URL (see "Soloist management in the app"). **Aural never bundles, hosts, mirrors or redistributes Soloist.**
- The API key is stored in the Keychain and passed **only as the `-k` / `--api-key` argument** — Soloist has no environment variable or config file for it. It is never logged or written to files. Known limitation: while Soloist runs, the key is visible in the process list (`ps`) to processes of the same user.
- Aural launches Soloist as a child process with `-n <device name> -k <key> --ws 127.0.0.1:0 -z 100`, or connects to an already running instance. Always bind the WebSocket to loopback (the API has no auth/TLS). Port `0` = OS-assigned; read the real port from `ws.port` (and `ws.addr`) in Soloist's data directory. `-z 100` caps Soloist's playback cache (default is unlimited; minimum 100 MB). Aural stops the child process when it quits.
- Daemon exit codes: `0` OK, `1` general failure, `10` build expired.

**Pairing and network**
- First use **requires pairing from an official Spotify app**: the user picks the device in the Spotify Connect device picker on the same local network. There is no in-app login. Aural shows a first-run screen ("Open Spotify and choose <device name>"). After pairing, Soloist stores the session in its data directory and restores it automatically on every restart (~0.3 s).
- After a restart the device is logged in but not active; `play <uri>` makes it active automatically (this takes playback away from other devices).
- Discovery uses multicast (mDNS). macOS **Local Network privacy** applies to the app that launched Soloist — without permission, multicast fails (`No route to host`) and the device is invisible. Aural's `Info.plist` needs `NSLocalNetworkUsageDescription`, and Aural shows a clear message when access is denied.
- Soloist is visible as a Connect device to everyone on the local network (Free accounts can connect too). There is no option to disable network discovery. Mention this under limitations in the README.

**Expiry**
- **Builds expire 90 days after their build date.** `soloist --version` prints e.g. `soloist 1.3.10.65 build 1794463304 (20261112) …`; expiry = the date in parentheses + 90 days. How Aural handles it: see "Soloist management in the app".
- **The API key has no documented expiry.** The docs only say: if the key is revoked or replaced in the dashboard, restart Soloist with the new key; the key is separate from the stored session and is required at every startup. Treat it as valid until revoked, and let the user replace it from the app if Soloist rejects it.
- **An invalid key is only detected at pairing (tested in Stage 2).** Soloist starts normally with any key (WebSocket up, "waiting for login", no error). When a Spotify app then tries to connect, the backend refuses (`session_access_denied`), the phone stays on "connecting…" and fails, Soloist prints one line `login failed: make sure --api-key is valid` to stdout, and **no WebSocket event is sent** (`auth_state` stays `logged_in: false`). Aural detects this line from Soloist's output (log text is not a stable API: keep the pattern in one place in `Sources/Soloist`) and also shows a hint if pairing does not complete within a reasonable time. Keys seen so far are 37 characters of `[A-Za-z0-9_]`; the format is undocumented, so only do a loose sanity check.

**Soloist management in the app** (no terminal commands for the user, ever)
- Aural manages its own Soloist install in `~/Library/Application Support/Aural/soloist/`. The executable path comes from **one place in AuralCore** and is never hard-coded elsewhere. It defaults to that path and allows an override (used by the probe and for a manual install).
- Soloist's data directory (device identity, pairing session) is Aural's own `~/Library/Application Support/Aural/soloist-data/`: separate from the executable, so the API key (Keychain) and the pairing session survive updates, and separate from Soloist's default directory, so a Soloist started by hand never clashes with Aural's. Any Soloist running in that directory was started by Aural (e.g. left over after a crash); Aural takes it over and stops it on quit.
- The API key is saved to the Keychain by the signed app, **only after pairing succeeds** (an invalid key is never stored). Keychain entry: service `app.aural.soloist-api-key`. Developer tools (the probe) attach to Aural's running Soloist without the key, so they never trigger Keychain prompts.
- **Install and update from the app:** download the official macOS archive directly from Spotify's official download URL (`https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz`) into a fresh temporary directory, extract it, **verify the code signature is `Developer ID Application: Spotify (2FNC3A47ZF)`** (Security framework, before the executable is ever run; the requirement is Soloist's own designated requirement from `codesign -d -r-`: identifier `com.spotify.soloist`, Apple-issued Developer ID certificate, team OU `2FNC3A47ZF`), remove `com.apple.quarantine` if present (a quarantined, notarized binary still runs, but this avoids Gatekeeper prompts), then replace the old executable and restart Soloist. Spotify publishes no checksums, so the signature check is the integrity check. If the download or verification fails, fall back to opening the official downloads page.
- **Expiry:** read the build date from `soloist --version` at startup. From 7 days before expiry, show a non-blocking notice with an "Update" button. On exit code `10`, show a clear screen with the same button.
- **First run is a guided setup screen (Stage 2):**
  1. **Install Soloist** — one button: download from the official URL, verify the signature, install into Aural's folder. Skipped if a valid, unexpired install is already there.
  2. **Get your key** — a button opens the Soloist page in the Spotify for Developers dashboard; a field to paste the key; Aural starts Soloist with it and stores it in the Keychain.
  3. **Pair with Spotify** — "Open Spotify on your phone or another computer and choose Aural from the devices." Any official Spotify app with the Connect device picker works; needed only once. Includes the Local Network permission. Pairing is detected from `auth_state` and setup continues automatically. An invalid key is reported here (see above) with a way back to step 2.
  4. Web API login for the library is added in Stage 3.
- The user never needs a terminal command.

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
2. **Minimal app + guided setup.** XcodeGen project; the guided first-run setup (install Soloist, API key, pairing — see "Soloist management in the app"); a plain SwiftUI window showing the current track with play/pause/next. Now Playing and media keys working.
3. **Library and search.** Web API login as setup step 4. Playlists, Liked Songs, saved albums, search, and the like button's save/remove — all through the Web API (OAuth PKCE), since Soloist provides no library, search or like. Confirm each endpoint with a real request first. Remember `play` cannot take artist URIs.
4. **Full UI per design.** The player as in `docs/design-2.png` (see "Design"), with Liquid Glass: cover-tinted background, circular cover with progress ring, glass controls, volume popover, `…` menu; the list button's playlists / queue panel (prototype 2 options first).
5. **Queue, shuffle, repeat, autoplay, like button.**
6. ~~Demo mode~~ — dropped (see "Out of scope").
7. **Polish and portfolio.** Image cache with a cap, restore last state on launch, **Soloist management in the app** (update flow, expiry notice and exit-code-10 screen with "Update" button, a settings screen to replace the API key — see "Soloist management in the app"; first-run setup and install are done in Stage 2), app icon, README, screenshots and a short video (see "Portfolio" for the cover-art question).

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
- README sections: what it is, why (memory), architecture diagram (SwiftUI ↔ AuralCore ↔ WebSocket ↔ Soloist ↔ Spotify), the librespot → Soloist story, setup (download Soloist from the official page, generate your own API key), how to build, limitations.
- **Disclaimer:** unofficial interface for Spotify Soloist; requires Spotify Premium; not affiliated with, endorsed or sponsored by Spotify.
- No Spotify logo or brand colors in the app or README.
- Screenshots and videos must not show copyrighted album art prominently. Open question (decide in Stage 7): e.g. play royalty-free / Creative Commons music that is on Spotify, or blur the covers.

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
- [x] Stage 2 — Minimal app + guided setup, Now Playing, media keys (2026-11-12)
  - App target (XcodeGen, `make app` / `make run`), signed with the Personal Team (team ID in the uncommitted `App/Config/Local.xcconfig`), hardened runtime, no sandbox, `NSLocalNetworkUsageDescription`.
  - Guided setup verified by the owner from a clean state: install (download → tar → Spotify signature check → atomic install), API key (opens the dashboard, loose format check, starts Soloist), pairing as "Aural" (detected from `auth_state`, key saved afterwards). Relaunch goes straight to the player without Keychain prompts.
  - Plain player (cover, title, artist, time, previous / play-pause / next), Now Playing in Control Center, media keys — confirmed working by the owner. Quitting stops Soloist.
  - AuralCore: `SoloistInstaller`, `SoloistVersion` (expiry), `SoloistAPIKey`, login-rejection detection, `LocalNetworkAccess`, `ArtworkLoader` (downscaled to 300 px, no URL cache), Keychain save/delete, keyless `attach()` for the probe. 25 unit tests (incl. signature rejection with Apple's `/bin/ls`).
  - Memory during playback (debug build): Aural 30 MB (peak 32 MB), Soloist 26 MB + helper 3.8 MB; combined ~60 MB.
  - Fixed during testing: Swift 6 isolation trap when MediaPlayer called the artwork closure on a background queue (closures for system callbacks must be created `nonisolated`); Soloist orphaned after a crash (now taken over and stopped).
  - Known issues: invalid-key rejection path implemented but not yet tested in the app; the layout is not the final design (Stage 4).
- [x] Stage 3 — Library and search (2026-11-12)
  - Web API login (PKCE) as setup step 4 (optional, "Skip for now"): the user creates their own Development Mode app (Web API only) with redirect URI `http://127.0.0.1:43821/callback` (the dashboard requires a port; `https` would need a local TLS certificate), pastes the Client ID, signs in in the default browser; a one-shot loopback listener receives the code. Client ID + tokens are stored together in the Keychain (`app.aural.spotify-web-api`); refreshed tokens are saved again. Expired login (refresh token lives 6 months) → back to setup step 4.
  - Confirmed with real requests (`aural-probe webapi-check`, 2026-11-12): `GET /me`, `GET /me/playlists`, `GET /playlists/{id}/items` (200 own/collaborative, **403 followed**), `GET /me/tracks`, `GET /me/albums`, `GET /albums/{id}/tracks`, `GET /search` (limit 10 OK, **11 → 400**), `GET /me/library/contains`, `PUT /me/library`, `DELETE /me/library`. Scopes: `playlist-read-private playlist-read-collaborative user-library-read user-library-modify` (search needs none). Page size 50 (search 10).
  - Soloist cannot play Liked Songs as a context: `spotify:collection:tracks` is rejected, `spotify:user:<id>:collection` is accepted but ignored. Playing a track from any list plays it and queues the next 20 tracks of the list (`add_to_queue`); playlists and albums play as a whole via their URI. Artists (not playable) show their tracks via search `artist:"name"`.
  - App: plain library window (Playlists, Liked, Albums, Search; paged lazy lists; 60–64 px thumbnails), heart in the player (checks `contains` on track change, likes/unlikes, then reads back Spotify's state), followed playlists show "Tracks not available" but can be played. 35 unit tests.
  - Memory (Activity Monitor, owner): Aural ~35 MB playing with the library window closed, ~55 MB with it open after browsing all tabs; Soloist ~27 MB + helper ~4 MB. Fixed: thumbnails were loading 300 px images; the shared URL cache now keeps images on disk only. The library window is replaced by an in-player panel in Stage 4 — measure that again.
  - Known issues: closing the library window does not lower memory (`footprint`: 53 MB closed; a second open/browse/close cycle → 58 MB, i.e. mostly reused, +5 MB not explained). In Stage 4, check the in-player panel with several open/close cycles for growth. The leaked Soloist API key still needs rotating.
- [x] Stage 4 — Full UI with Liquid Glass (2026-11-13)
  - Player per `docs/design-2.png`, measured and scaled to a 320 × 576 pt window (`Metrics` in `PlayerView.swift`): cover-tinted gradient as the window's own background, 225 pt round cover with a 264 pt progress ring (thin track, accent fill, glowing knob; drag seeks live, click glides along the arc), time in the ring's open top, glass play/pause (custom style with smooth hover), icon buttons dimmed → white on hover, accent for active shuffle / repeat / heart.
  - Design changes agreed with the owner: no header row (only the `…` menu as a plain toolbar icon, top right: change Soloist API key, change Client ID, versions; "Go to album" dropped); the left slot of the controls row is **Search**; the list button opens the library in the same window (slide); Search is its own page. Bottom navigation (custom bar, system segmented control, `TabView`) was tried and dropped — macOS `TabView` can only show tabs in the top toolbar.
  - Library: glass segmented tabs (Playlists / Liked / Albums, custom from `glassEffect`; the system segmented `Picker` keeps the classic look in window content), iOS Music-style rows (no separators, hover highlight, playing song marked with an animated waveform, track numbers on album pages), playing anything returns to the player. Settings steps open from the `…` menu with Cancel.
  - Previous: Spotify-like (restart after 3 s; inside playlists / albums Soloist's `skip_prev`; otherwise Aural's own history of played tracks, re-queueing what followed) — `SoloistHistory`, tested. Not confirmed live: whether Soloist's `play` clears the user queue (undocumented); Aural re-queues only if the queue came back empty.
  - Web API: 502–504 are retried once after 1 s (a 503 appeared while switching tabs quickly); cancelled loads are not errors; failed lists offer "Try again".
  - Accessibility: Reduce Motion (cross-fades, no bounce), Increase Contrast (full-white icons and secondary text), ring is an adjustable VoiceOver element with arrow-key seeking; glass follows the macOS 27 Liquid Glass setting by itself.
  - Fixed: the window was 32 pt taller than its content (hidden title bar height added on top), which caused the blank strip at the bottom; the content now subtracts the measured title-bar height.
  - Memory (owner, Activity Monitor, debug build, after using every screen): Aural 59 MB (transient peak ~100 MB while clicking through lists), Soloist 28.5 MB + helper 4 MB; combined ~92 MB. Idle before playing (`footprint`): Aural 34 MB, Soloist 19 MB + 3.7 MB. Cover is now Spotify's 640 px image decoded at 450 px (~0.8 MB).
  - Known issues: the transient browsing peak (list thumbnails via `AsyncImage`) — revisit with the capped image cache in Stage 7; Home page postponed; list thumbnails are 64 px images at 44–52 pt (slightly soft).
- [x] Stage 5 — Queue, shuffle, repeat, autoplay, like (2026-11-13)
  - Player layout reworked with the owner: header row from the design (device menu left, playlist / album name middle, heart right), title scrolls when too long (`MarqueeText`, still with Reduce Motion), controls row shuffle · previous · play · next · repeat, bottom row search · library · queue · volume. Layout anchored top / bottom with the ring filling the middle (`Metrics`). Window 320 × 638 (fixed; the title-bar measurement had silently returned 0 and made the window 52 pt taller than specified).
  - Device menu: speaker icon (accent while Aural is the active device); "Playing in Spotify" (state only, disabled) / "Playing in Aural" (takes playback over: `activate` + `play`).
  - Queue page (works without the Web API): Now Playing, "Next in Queue" / "Up Next" / "Autoplay". While Aural plays one of its lists, Soloist's queue holds only the next track, so the page shows the rest of the list (up to 50) and rows jump there; otherwise Soloist's `queue_changed` entries (at most 10, display only). Confirmed live by the owner: queue entries carry titles, artists and covers. Clear Queue: Soloist cannot clear its queue, so Aural stops its list and skips queued songs when they start (`SoloistListQueue.skipWhenStarted`).
  - Like: heart in the header row (Liked Songs only; add-to-playlist was tried and dropped to stay lightweight — no `playlist-modify-*` scopes). No flicker on track changes (last state kept, Liked Songs known up front). Save to Library for albums and other people's playlists; song count and total time on album / playlist pages. Confirmed by the owner: `PUT` / `DELETE /me/library` and `GET /me/library/contains` with album and playlist URIs.
  - Shuffle / repeat in the controls row; autoplay is Soloist's own.
  - UI: library pages slide in and out (own page stack; macOS `NavigationStack` did not animate); Apple's button styles throughout (glass for the player and collection pages; filled accent, borderless and `Link` in setup); Spotify-style icon tooltips (`Tooltip.swift`, agreed exception); play/pause no longer flickers between tracks; progress ring glides back on a new track.
  - 50 unit tests.
  - Memory (`footprint`, debug build, logged in, idle after launch): Aural 33 MB (peak 42 MB), Soloist 22 MB + helper 3.8 MB; combined ~59 MB. Not yet measured while playing and after browsing every page — record in Stage 7 with the release build.
  - Known issues: Soloist reports at most 10 queue entries for whole playlists / albums; a cleared queued song may sound for a moment before it is skipped; the device menu cannot name the other device.
- [x] ~~Stage 6 — Demo mode (local files)~~ — dropped by the owner (2026-11-13): Aural is a lightweight player bound to Spotify, not a standalone media player.
- [ ] Stage 7 — Polish and portfolio
