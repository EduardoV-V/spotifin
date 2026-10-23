<p align="center">
  <img src="assets/brand/logo.png" alt="Spotifin logo" width="160">
</p>

<h1 align="center">Spotifin</h1>

<p align="center"><strong>Your Jellyfin music library, with the interface you already know how to use.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/built%20with-Flutter-02569B" alt="Flutter">
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20Windows%20%7C%20Linux-lightgrey" alt="Platforms">
  <img src="https://img.shields.io/badge/status-early%20release-orange" alt="Early release">
</p>

Spotifin is a music player for people who host their own music. It connects to your [Jellyfin](https://jellyfin.org) server and plays **only** what is on it, wrapped in a Spotify-style interface: a home screen that learns what you play, playlists you can actually organize, a proper queue, lyrics, artist pages with photos, and downloads that make your library work even when offline.

No other service, no subscription, no ads, no telemetry. Your files, your server, a nicer way to listen.

> [!WARNING]
> **Spotifin is in an early stage.** It is built and maintained by a single developer (me :D), as a personal project that grew into something worth sharing. Version 1.0.0 is the first public release: **expect bugs, rough edges and missing features.** It is tested only on my own library and devices, so your setup may reveal problems that have not been seen yet.
>
> **Please [open an issue](../../issues)** when something breaks, looks wrong or feels off, and also when you wish the app did something it does not do yet.

[Features](#features) · [A closer look](#a-closer-look) · [Download](#download) · [Getting started](#getting-started) · [Offline mode](#offline-mode) · [Settings](#settings) · [FAQ](#faq) · [Feedback](#feedback-and-issues) · [For developers](#for-developers) · [License](#license)

## Features

### Listening
- **Original quality or transcoded.** Play the original file straight from Jellyfin, including Hi-Res FLAC, or pick a transcoded stream (320k, 192k, 96k) to save data.
- **A queue that behaves like you expect.** "Play next", "add to queue", a separate manual queue that survives skipping, shuffle, repeat one/all, and drag-and-drop reordering. The current track stays pinned on top.
- **Synced lyrics** when your server has them, highlighted line by line while the song plays.
- **Resume anywhere.** The playing queue and position are synced through Jellyfin, and other Jellyfin sessions can be controlled remotely.
- **Your plays count.** Spotifin reports playback to Jellyfin, so play counts, "recently played" and "most played" stay correct in every Jellyfin app.

### Discovering your own library
- **"Algorythimic" homepage:** shortcuts to what you played recently, your playlists, recently played artists, recently added tracks and your most played songs.
- **Search your media:** tracks, albums, artists and playlists in a single field, accent-insensitive.
- **Artist pages** with photo, biography and the artist's tracks. Photos and details come from Deezer, TheAudioDB and Wikipedia, are cached on your device and never block the app from working.
- **Album pages**, genres and a library view with filters for playlists, albums, artists and downloaded content.

### Playlists and favorites
- Create, rename, delete and reorder playlists.
- Custom playlist covers, or an automatic 2×2 mosaic from the first tracks.
- Favorite songs with a single click and stay in sync with Jellyfin.
- Mark a playlist to **download automatically**, so new tracks arrive on your device by themselves.

### Offline
- Download tracks, albums or entire playlists, in original quality or as MP3 (320k / 192k / 96k).
- When the server disappears, Spotifin switches to **offline mode** by itself: your downloads play, the rest is dimmed, search keeps working over what you have.
- Playlist changes made without a connection go to an **outbox** and are sent when the server is back. [More details below.](#offline-mode)

### Made for phone and desktop
- **Phone:** mini player, full-screen player with swipeable cover art, bottom navigation, the keyboard overlaying the screen instead of squeezing it.
- **Desktop:** resizable side panels, a "now playing" panel, right-click context menus, smooth scrolling and keyboard media keys.
- Multiple Jellyfin accounts, switchable without logging out.

## A closer look

**The home screen** is built around your usage. Your last played playlists, artists and albums sit at the top as quick shortcuts, followed by horizontal shelves for your playlists, recently played artists, recently added music and your most played tracks.

**The player** shows large cover art you can swipe to change tracks, a seek bar, queue, lyrics and track details. The accent color follows the cover art. From the track menu you can add to a playlist, go to the artist or album, download or remove the download.

**The queue** shows what plays now, what you added manually and what comes next. Reorder by dragging, remove with a tap, and the manual queue is never lost when you skip.

**Downloads** live on their own screen, with progress, per-track quality and storage used. Pausing, cancelling and removing everything is one tap away.

**Artist pages** with a wide photo, a short biography, popular tracks and the full discography available in your library.

## Download

Get the latest version from the [Releases](../../releases) page.

| Platform | Architectures | Files |
| --- | --- | --- |
| Windows | x64 | `Spotifin_Windows_x64_vX.Y.Z_Setup.exe` (installer) or `Spotifin_Windows_x64_vX.Y.Z.zip` (portable) |
| Linux | x64 (amd64) and ARM64 | `.deb` and `.tar.gz` for each architecture |
| Android | – | Not published yet; you can [build it yourself](#for-developers) |

Every file comes with a `.sha256` checksum, and `build-manifest.json` lists all assets of a release.

<details>
<summary><strong>Windows installation notes</strong></summary>

Run the installer, or unzip the portable version and start `spotifin.exe`. If the app does not open, install the [Microsoft Visual C++ Redistributable (x64)](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist).
</details>

<details>
<summary><strong>Linux installation notes</strong></summary>

Debian, Ubuntu and derivatives:

```bash
sudo apt install ./Spotifin_LinuxX64_vX.Y.Z.deb      # or Spotifin_LinuxARM64_...
```

Other distributions, from the `.tar.gz`:

```bash
mkdir spotifin && tar -xzf Spotifin_LinuxX64_vX.Y.Z.tar.gz -C spotifin
./spotifin/spotifin
```

Spotifin needs GTK 3, `libmpv` (the audio engine), `libsecret` and `jsoncpp`. The `.deb` pulls them in for you. For the tarball on Debian/Ubuntu:

```bash
sudo apt install libgtk-3-0 libmpv2 libsecret-1-0 libjsoncpp25 zenity
```

A Secret Service provider (GNOME Keyring or KWallet) is recommended to store your login token safely. Without one, Spotifin stores it in a local file instead.
</details>

> 32-bit (x86) builds are not available, because Flutter does not support them.

## Getting started

1. Open Spotifin and type your server address. You can leave out `http://` or `https://`. DNS adresses are also supported.
2. Sign in with your Jellyfin username and password.
3. Your library, playlists and favorites load right away, and your home screen fills up as you listen.

## Offline mode

Offline support is a core part of Spotifin, not an afterthought:

- **Downloads** are stored on the device and play without a connection. Choose the quality for new downloads in *Settings* or on the *Downloads* screen.
- **Offline mode** turns on automatically when the server cannot be reached, and you can force it in *Settings → Offline mode*. Tracks that are not downloaded are dimmed.
- **Everything you looked at is remembered:** playlists, favorites, home shelves, artist details and images are cached, so the app stays pleasant to use.
- **Outbox:** creating, renaming, deleting, reordering, adding and removing playlist items works offline. Changes are queued and sent automatically when the server is back. Favorites have their own queue.
- **Search** keeps working offline over downloaded and favorite tracks.

## Settings

| Setting | What it does |
| --- | --- |
| Streaming quality | Original, 320k, 192k or 96k stream. |
| Download quality | Quality of new downloads: Original or MP3 320k / 192k / 96k. |
| Offline mode | Forces offline mode and shows how many changes are waiting to be sent. |
| Server address | Change the server without logging out. |
| Accounts | Add, switch and remove Jellyfin accounts. |
| Jellyfin API key | Optional. Only needed to upload playlist covers to the server when your Jellyfin user is not an administrator (create one in the Jellyfin dashboard, under *API Keys*). Without it, covers are saved on the device only. |
| TheAudioDB key | Optional. Your own key for artist data; a free public key is used by default. |
| Last.fm key / ListenBrainz token | Optional. Enables global play counts per track. |

## FAQ

**Does Spotifin work without Jellyfin?** No. Jellyfin is the only source of music, by design.

**Does it send my data anywhere?** No telemetry or analytics. The only outside requests are optional artist photos and details (Deezer, TheAudioDB, Wikipedia) and the optional Last.fm / ListenBrainz features you enable yourself. Your login and music go only to your own server.

**Is there an iOS or macOS version?** Not at the moment.

**A feature I use in Spotify is missing.** That is probably true! Tell me about it in an [issue](../../issues).

## Feedback and issues

Spotifin is a one-person project, and your reports are the best way to make it better.

- **Found a bug?** [Open an issue](../../issues/new) with what you did, what you expected and what happened. Your platform (Android, Windows or Linux), the app version (shown in *Settings*) and your Jellyfin version help a lot. Screenshots and screen recordings are welcome.
- **Have an idea?** Open an issue describing what you would like to do and why. Small details count too.
- **Something confusing?** That is a problem in the design, so please report it as well.

## For developers

<details>
<summary><strong>Building from source</strong></summary>

Requirements: the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable) and the toolchain of your target platform.

```bash
git clone <repository-url> spotifin
cd spotifin
flutter pub get
flutter run -d windows        # or: -d linux, or the Android device id
```

Release builds:

```bash
flutter build windows --release
flutter build linux --release
flutter build apk --release
```

Platform notes:

- **Windows:** Visual Studio with the "Desktop development with C++" workload.
- **Linux:** `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev mpv libsecret-1-dev libjsoncpp-dev`
- **Android:** Android SDK, `minSdk` 23. If your Jellyfin server uses plain HTTP on your LAN, allow cleartext traffic in `AndroidManifest.xml` (`android:usesCleartextTraffic="true"`).
- Do not build the same folder from Windows and from WSL, because the generated files differ. Use a separate clone for each.
</details>

<details>
<summary><strong>Publishing a release</strong></summary>

Releases are produced by the *Release* GitHub Actions workflow:

1. Update `version:` in `pubspec.yaml` and `appVersion` in `lib/app/version.dart` (they must match).
2. Commit, then push a tag: `git tag v1.0.1 && git push origin v1.0.1`.
3. The workflow builds Windows (x64) and Linux (x64 and ARM64) and creates a **draft** release with installers, packages, checksums and `build-manifest.json`. Review the notes and publish.
</details>

<details>
<summary><strong>Credits</strong></summary>

Spotifin is built with [Flutter](https://flutter.dev), [just_audio](https://pub.dev/packages/just_audio), [audio_service](https://pub.dev/packages/audio_service) and [media_kit](https://github.com/media-kit/media-kit) (libmpv) for desktop audio. Artist data comes from [Deezer](https://developers.deezer.com), [TheAudioDB](https://www.theaudiodb.com) and [Wikipedia](https://www.wikipedia.org). The Inter typeface is licensed under the SIL Open Font License (see `assets/fonts/Inter-LICENSE.txt`).

</details>

## License

Spotifin is released under the [MIT License](LICENSE).

## Disclaimer

Spotifin is an independent project. It is not affiliated with, endorsed by or sponsored by Spotify or the Jellyfin project. It only plays media from a server you control, and you are responsible for the content you store there.