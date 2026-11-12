# Aural

A lightweight native Spotify mini player for macOS, built with Swift, SwiftUI and Liquid Glass.

> **Disclaimer:** Aural is an unofficial interface for [Spotify Soloist](https://developer.spotify.com/documentation/soloist). It requires a Spotify Premium account. Aural is not affiliated with, endorsed or sponsored by Spotify.

> **Status:** early development. Not ready for everyday use yet. See [Roadmap](#roadmap).

---

## Why

The official Spotify desktop app is built on the Chromium Embedded Framework — essentially a full web browser — and regularly uses 1 GB of RAM or more. For something that mostly plays music in the background, that is a lot.

Aural is a small native window that does the core things — play, pause, skip, seek, shuffle, repeat, your playlists, search — and nothing else. The heavy lifting is done by Spotify Soloist, Spotify's official headless player, which Aural controls through its local WebSocket API.

### Memory

| | Memory while playing |
|---|---|
| Official Spotify desktop app | 1 GB+ (to be measured under the same conditions) |
| Spotify Soloist (playback engine) | ~34–37 MB *(measured)* |
| Aural (interface) | to be measured |
| **Aural + Soloist** | **target: under 150 MB** |

Measured with `footprint` on an Apple Silicon MacBook Pro, macOS 26. Numbers will be updated as development progresses.

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

Planned for the first release:

- Play / pause / next / previous / seek / volume
- Shuffle and repeat
- Autoplay of similar tracks when an album or playlist ends
- Your playlists, Liked Songs and saved albums
- Search
- Like / unlike the current track
- macOS Now Playing (Control Center, lock screen) and media keys, including AirPods
- Demo mode with local audio files — try the app without a Spotify account

Intentionally **not** included: lyrics, podcasts, home feed, social features, offline downloads.

## Requirements

- macOS 26 or later, Apple Silicon
- Spotify Premium
- [Spotify Soloist](https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates) and your own Soloist API key from the [Spotify for Developers dashboard](https://developer.spotify.com/dashboard/soloist)
- The official Spotify app on your phone or another device, once, to pair Soloist

Aural will guide you through installing Soloist, entering your API key and pairing on first launch *(planned)*.

## Building from source

Requires Xcode (for the macOS SDK and command-line tools) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
make test      # run AuralCore's tests
make run       # build and launch the app (available from Stage 2)
```

During early development, `make probe URI=spotify:track:<id>` runs a command-line prototype that starts Soloist and plays a track.

## Limitations

- **Soloist builds expire every 90 days.** Aural will warn you in advance and update Soloist with one click *(planned)*.
- **Soloist is visible on your local network** as a Spotify Connect device, and Soloist has no option to turn this off. Others on the same Wi-Fi can see it and could start playback on it.
- **The Soloist API key is passed as a command-line argument**, so it is visible in the process list to other processes of your user account. Soloist offers no other way to pass it.
- **Library and search use the Spotify Web API in Development Mode**, which Spotify limits to five users per registered app. To use Aural, you may need to register your own app in the Spotify for Developers dashboard.
- Playing an **artist** directly isn't supported by Soloist; artists open their albums instead.

## Roadmap

- [x] Soloist research and measurements
- [ ] Soloist control prototype
- [ ] Minimal app with Now Playing and media keys
- [ ] Library and search
- [ ] Full interface with Liquid Glass
- [ ] Queue, shuffle, repeat, autoplay, likes
- [ ] Demo mode
- [ ] Polish: guided setup, one-click Soloist updates, image cache

## Built with

Swift 6, SwiftUI, AVFoundation, MediaPlayer, Spotify Soloist and the Spotify Web API — no third-party dependencies. Developed with [Claude Code](https://claude.com/claude-code); see [`CLAUDE.md`](CLAUDE.md) for the project brief the agent works from.

## License

*To be decided.*
