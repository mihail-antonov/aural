<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png" width="160" height="160" alt="Aural app icon">
</p>

<h1 align="center">Aural</h1>

<p align="center">
  A lightweight native Spotify mini player for macOS, built with Swift, SwiftUI and Liquid Glass.
</p>

> **Disclaimer:** Aural is an unofficial interface for [Spotify Soloist](https://developer.spotify.com/documentation/soloist). It requires a Spotify Premium account. Aural is not affiliated with, endorsed or sponsored by Spotify.

> **Status:** works day to day; final polish in progress. There is no ready-made download: you build your own copy in a few minutes (see [Install](#install)).

---

## Why

The official Spotify desktop app is built on the Chromium Embedded Framework — essentially a full web browser — and regularly uses 1 GB of RAM or more. For something that mostly plays music in the background, that is a lot.

Aural is a small native window that does the core things — play, pause, skip, seek, shuffle, repeat, your playlists, search — and nothing else. The heavy lifting is done by Spotify Soloist, Spotify's official headless player, which Aural controls through its local WebSocket API.

### Memory

| | Memory |
|---|---|
| Official Spotify desktop app | 1 GB+ (to be measured under the same conditions) |
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

Aural is not on the App Store and there is no ready-made download: you build your own copy from this repository with Xcode. It takes a few minutes, needs no paid Apple account, and you end up with a normal app in your Applications folder.

### 1. What you need

- A Mac with Apple Silicon and **macOS 26** or later
- **Spotify Premium**
- The official Spotify app on your phone or another computer (used once, to connect Aural)
- **Xcode 26** from the Mac App Store (free), opened once so it can finish installing its components
- [Homebrew](https://brew.sh), to install XcodeGen

### 2. Build and install

1. Install XcodeGen, which generates the Xcode project:

   ```bash
   brew install xcodegen
   ```

2. Get the code:

   ```bash
   git clone https://github.com/mihail-antonov/aural.git
   cd aural
   ```

3. Set up free code signing. macOS only runs apps that are signed, and a stable signature lets Aural keep your keys in the Keychain without asking again after every update.
   1. In Xcode, open **Settings → Accounts**, click **+** and sign in with your Apple ID. This creates a free "Personal Team".
   2. Select the team, click **Manage Certificates…**, then **+ → Apple Development**.
   3. Find your team ID (a 10-character code) in the new certificate:

      ```bash
      security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
      ```

      It is the value after `OU=`.
   4. Create your local settings file and put the team ID in it:

      ```bash
      cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig
      ```

      Then edit `App/Config/Local.xcconfig` and replace `YOURTEAMID` with your team ID. This file stays on your Mac (it is in `.gitignore`).

4. Build Aural and copy it to your Applications folder:

   ```bash
   make install
   ```

If `make install` says that xcodebuild requires Xcode, point the command-line tools at Xcode once: `sudo xcode-select -s /Applications/Xcode.app`.

Aural is now in `/Applications`. Open it from Launchpad, Spotlight or Finder, and keep it in the Dock if you like (right-click its Dock icon → **Options → Keep in Dock**).

### 3. First launch

Aural guides you through four short steps in its window:

1. **Install Soloist.** One click: Aural downloads Soloist directly from Spotify, checks that it is signed by Spotify, and installs it in its own folder. Aural never ships Soloist itself.
2. **Add your Soloist API key.** Open the [Soloist page in the Spotify for Developers dashboard](https://developer.spotify.com/dashboard/soloist), sign in with your Premium account, generate a key and paste it into Aural. The key is stored in your Keychain.
3. **Pair with Spotify.** Open the Spotify app on your phone (or another computer) on the same Wi-Fi, open the device picker and choose **Aural**. macOS asks whether Aural may find devices on your local network: click **Allow**, otherwise Spotify cannot see Aural. You only pair once.
4. **Connect your library** *(optional, for playlists, Liked Songs, albums, search and the like button)*. Spotify asks every user of the Web API to register their own app:
   1. In the [Spotify for Developers dashboard](https://developer.spotify.com/dashboard), click **Create app**.
   2. Give it any name and description, select **Web API**, and add this redirect URI exactly: `http://127.0.0.1:43821/callback`.
   3. Save, copy the app's **Client ID** into Aural, and sign in when the browser opens.

   You can skip this step and connect later from the `…` menu. Playback works without it.

After that, Aural opens straight to the player.

### Updating

- **Aural:** in the `aural` folder, run `git pull && make install`. Your keys, pairing and library login are kept.
- **Soloist:** Spotify's Soloist builds stop working 90 days after release. A week before that, Aural shows an **Update Soloist** button; if a build has already expired, Aural asks you to update when it starts. Either way it is one click.

## Building for development

```bash
make test      # run AuralCore's unit tests
make run       # build a debug version and launch it
make install   # build the release version and copy it to /Applications
```

The logic lives in the `AuralCore` Swift package and is tested with `swift test`; the app target is generated from `App/project.yml` with XcodeGen. Xcode is only needed for SwiftUI previews and debugging.

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

*To be decided.*
