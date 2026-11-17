<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png" width="160" height="160" alt="Aural app icon">
</p>

<h1 align="center">Aural</h1>

<p align="center">
  A lightweight native Spotify mini player for macOS, built with Swift, SwiftUI and Liquid Glass.
</p>

> **Disclaimer:** Aural is an unofficial interface for [Spotify Soloist](https://developer.spotify.com/documentation/soloist). It requires a Spotify Premium account. Aural is not affiliated with, endorsed or sponsored by Spotify.

> **Getting Aural:** install Xcode, then one command builds and installs it (see [Install](#install)).

---

## Why

The official Spotify desktop app is built on the Chromium Embedded Framework — essentially a full web browser — and uses close to 1 GB of RAM. For something that mostly plays music in the background, that is a lot.

Aural is a small native window that does the core things — play, pause, skip, seek, shuffle, repeat, your playlists, search — and nothing else. The heavy lifting is done by Spotify Soloist, Spotify's official headless player, which Aural controls through its local WebSocket API.

### Memory

| | Memory |
|---|---|
| Official Spotify desktop app (1.3.9) | ~900 MB |
| Aural (interface) | ~37 MB |
| Spotify Soloist (playback engine) | ~24 MB |
| **Aural + Soloist** | **~60 MB** |

Measured with `footprint` on an Apple Silicon MacBook Pro, macOS 26, Release build of Aural.

## How it works

```
┌──────────────┐  commands / state   ┌──────────────┐   WebSocket    ┌──────────────┐           ┌─────────┐
│   SwiftUI    │ ◄─────────────────► │  AuralCore   │ ◄────────────► │   Soloist    │ ◄───────► │ Spotify │
│ (interface)  │                     │ (Swift pkg)  │   127.0.0.1    │  (official)  │           │         │
└──────────────┘                     └──────┬───────┘                └──────────────┘           └─────────┘
                                            │ HTTPS (OAuth PKCE)
                                            ▼
                                    Spotify Web API
                                 (playlists, search, likes)
```

- **SwiftUI app** — a thin interface layer: the mini player window, Liquid Glass, Now Playing and media keys.
- **AuralCore** — a Swift package that owns all logic and state. It launches and supervises Soloist as a child process, talks to it over WebSocket, and calls the Web API for library and search.
- **Spotify Soloist** — Spotify's official headless client. It handles authentication, streaming and audio output.

You only ever launch Aural. It starts Soloist in the background and stops it when you quit.

### Why Soloist (and not librespot)

The first prototype used [librespot](https://github.com/librespot-org/librespot), the popular open-source implementation of Spotify's protocol. Login worked, but playback failed: Spotify stopped handing out audio decryption keys to librespot for many accounts ([librespot#1649](https://github.com/librespot-org/librespot/issues/1649)), and there is no legitimate workaround.

Spotify Soloist, released in August 2026, is the official answer for headless and DIY setups. It works with any Premium account, is maintained by Spotify, and is designed to be controlled by local interfaces like this one.

## Features

- Play / pause / next / previous / seek (drag the ring around the cover) / volume
- Shuffle and repeat
- Autoplay of similar songs when an album, playlist or song ends
- Your playlists, Liked Songs and saved albums; save albums and playlists to your library
- Search for songs, albums, artists and playlists
- Queue page: what plays next, jump to a song, clear the queue
- Like / unlike the current song
- Take playback over from your phone or another device ("Playing in Aural")
- Remembers the last song and position when you quit
- macOS Now Playing (Control Center, lock screen) and media keys, including AirPods
- Keyboard: Space plays / pauses, ⌘→ next, ⌘← previous, Esc goes back to the player
- Installs and updates Soloist by itself, no terminal needed

Intentionally **not** included: lyrics, podcasts, home feed, social features, offline downloads.

## Install

There is no ready-made download: you build your own copy, which takes one command. You need a Mac with Apple Silicon and **macOS 27**, **Spotify Premium**, and the Spotify app on your phone.

1. **Install [Xcode](https://apps.apple.com/app/xcode/id497799835)** from the App Store (free) and open it once, so it can finish setting up.
2. **Build and install Aural.** In Terminal:

   ```bash
   git clone https://github.com/mihail-antonov/aural.git
   cd aural
   make install
   ```

3. **Open Aural** from Launchpad or Spotlight and follow its setup.

That's it. To keep Aural in the Dock, right-click its icon while it runs → **Options → Keep in Dock**.

### What the setup asks for

Aural walks you through four steps in its window. Each one explains itself; open the notes below only if you get stuck.

<details>
<summary><b>1. Install Soloist</b>: one click</summary>

Aural downloads Soloist, Spotify's official player, directly from Spotify, checks that it is signed by Spotify, and installs it in its own folder. Aural never ships Soloist itself.
</details>

<details>
<summary><b>2. Your Soloist API key</b>: from the Spotify for Developers dashboard</summary>

Open the [Soloist page in the dashboard](https://developer.spotify.com/dashboard/soloist), sign in with your Premium account, click to generate a key and paste it into Aural. It is stored in your Keychain.
</details>

<details>
<summary><b>3. Pair with Spotify</b>: choose "Aural" on your phone, once</summary>

Open the Spotify app on your phone (or another computer) on the same Wi-Fi, open the device picker and choose **Aural**. When macOS asks whether Aural may find devices on your local network, click **Allow**; otherwise Spotify cannot see it.
</details>

<details>
<summary><b>4. Connect your library</b>: optional, for playlists, Liked Songs, albums and search</summary>

Spotify asks every Web API user to register their own app:

1. In the [Spotify for Developers dashboard](https://developer.spotify.com/dashboard), click **Create app**.
2. Enter any name and description, select **Web API**, and add this redirect URI exactly: `http://127.0.0.1:43821/callback`.
3. Save, copy the app's **Client ID** into Aural, and sign in when the browser opens.

You can skip this and connect later from the `…` menu; playback works without it.
</details>

### Updating

- **Aural:** in the `aural` folder, run `git pull && make install`. After an update macOS may ask once whether Aural can use its saved keys; click **Always Allow**.
- **Soloist:** Spotify's builds stop working 90 days after release. A week before, Aural shows an **Update Soloist** button; if a build has expired, Aural asks you to update when it starts. One click either way.

<details>
<summary>Troubleshooting</summary>

- **"Aural needs Xcode to build"**: install Xcode, open it once, then run `sudo xcode-select -s /Applications/Xcode.app` and try again.
- **Spotify doesn't show Aural in its device list**: check System Settings → Privacy & Security → Local Network and turn Aural on; phone and Mac must be on the same network.
- **No Keychain question after every update** *(optional)*: sign Aural with a free Apple "Personal Team" instead of the default local signature; see `App/Config/Local.xcconfig.example`.
</details>

## Building for development

```bash
make test      # run AuralCore's unit tests
make run       # build a debug version and launch it
make install   # build the release version and copy it to /Applications
```

The logic lives in the `AuralCore` Swift package and is tested with `swift test`. The app's Xcode project is generated from `App/project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), which the first build downloads (pinned version, checksum-verified). Xcode itself is only needed for SwiftUI previews and debugging.

## Limitations

- **Soloist builds expire every 90 days.** Aural offers the update a week in advance; updating takes one click.
- **Soloist is visible on your local network** as a Spotify Connect device, and Soloist has no option to turn this off. Others on the same Wi-Fi can see it and could start playback on it.
- **The Soloist API key is passed as a command-line argument**, so it is visible in the process list to other processes of your user account. Soloist offers no other way to pass it.
- **Library and search use the Spotify Web API in Development Mode**, which needs your own registered app (step 4 above) and allows at most five users per app.
- **Playlists you follow but do not own** can be played, but Spotify does not let Aural list their songs.
- **Artists** cannot be played as a whole (Soloist does not support it); opening an artist shows their songs instead.
- **Soloist reports at most 10 upcoming songs** for a playlist or album, so the queue page shows only those.

## Roadmap

- [x] Soloist research and measurements
- [x] Soloist control prototype
- [x] Minimal app with guided setup, Now Playing and media keys
- [x] Library and search
- [x] Full interface with Liquid Glass
- [x] Queue, shuffle, repeat, autoplay, likes
- [x] Image cache, restore last song, in-app Soloist updates
- [ ] Screenshots and a short video

## Built with

Swift 6, SwiftUI, MediaPlayer, Spotify Soloist and the Spotify Web API, with no third-party dependencies. Developed with [Claude Code](https://claude.com/claude-code); see [`CLAUDE.md`](CLAUDE.md) for the project brief the agent works from.

## License

Aural's source code is available under the [MIT License](LICENSE). Spotify Soloist is Spotify's software, is not part of this repository, and is covered by Spotify's own terms.
