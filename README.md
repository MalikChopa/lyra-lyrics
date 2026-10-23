# Lyra Lyrics

**A small always-on-top window that shows the synchronised lyrics of the song playing in Spotify or Apple Music, on your Mac.**

*English · [Français](README.fr.md)*

![Lyra Lyrics: a frosted-glass window tinted with the colours of the album cover, floating over other apps, showing three lines of lyrics with playback buttons](docs/images/hero.jpg)

> The screenshots in this README are renderings made by the app itself (`--snapshot`) on a drawn desktop, with **invented** lyrics, titles, artists and cover images. In the real app the frosted glass blurs what is behind the window; these renderings do not show that blur.
> The app's interface is in **French** in this version (menus, settings, messages).

## What it does

Play a song in Spotify or Apple Music (the Music app). Lyra Lyrics notices it, looks the lyrics up on [LRCLIB](https://lrclib.net), and shows one, three or five lines in a small window that stays above every other window, wherever you put it on screen. The line being sung is highlighted and glides smoothly into place as the song goes on.

No account, no sign-in, no server of ours: the app talks to your music player and to lrclib.net, nothing else.

## Features

- **Always on top**, draggable anywhere, also over other apps' windows (but see the [Dock icon trade-off](#the-dock-icon-and-full-screen-apps)). **Resizable with the mouse**: drag any edge or corner (6 pt grab zone, 280 x 110 pt minimum, 90 % of the visible screen at most); the text **adapts automatically**: the font size is the largest at which the visible lines fit the window in width and height (the "Max size" setting is the upper limit), so a bigger window means bigger text. A line wraps only if it does not fit even at 14 pt. The size is remembered; "Default size" in the settings resets it. Disabled in click-through mode.
- **Smooth scrolling** like Apple Music: on each line change the lines glide up, the new current line scales up and brightens, the neighbours fade and get a light blur. Done with Core Animation layer animations (no per-frame redraw), smooth at 60 and 120 Hz; with "Reduce motion" on, a simple cross-fade replaces the glide.
- **Colours from the album cover** (on by default, can be switched off): the background tint and the current-line colour come from the cover of the song playing, with a contrast of at least 4.5:1 for the current line against the tint. Apple Music: the cover is read from the Music app. Spotify: the cover is downloaded once per song (see [Privacy](#privacy)). Off, or no cover: the plain styles.
- **Playback buttons** in the bar that appears when the pointer is over the window: previous, play/pause, next, for the player that is playing. The first time, if macOS has not been asked yet, the first click asks for the Automation permission (a one-line explanation appears in the window, then the system prompt) and then sends the command; if you refused it, the buttons stay greyed and a click offers "Open Settings" (nothing is ever asked twice).
- **One, three or five lines** (setting "Lines"); the window height adapts, long lines still wrap and shrink the font as needed.
- **Font themes**: Classic, Elegant (New York serif), Neon (rounded bold with a glow), Minimal (light), each setting font, weight, colour, glow and neighbour size in one click. Changing any single control afterwards shows "Custom".
- **Synchronised lyrics**: current line highlighted, neighbours dimmed. When LRCLIB only has plain text, it is shown as a slowly scrolling block, with a notice that it is not synchronised.
- **Three backgrounds**: solid, frosted glass, transparent (text with a soft shadow).
- **Settings**: font, weight, max size, text colour, glow, background opacity.
- **Manual offset** from -5 s to +5 s, for the current song only, when a lyrics file is slightly early or late.
- **Click-through mode**: clicks go through the window to the app below. Turning it on closes the settings panel and a 3-second notice in the window reminds you how to come back. To leave it, press the shortcut (see [Keyboard shortcut](#keyboard-shortcut)): it turns click-through off and shows the window. The menu bar icon also works, but on a MacBook with a notch it can be hidden behind the notch when the menu bar is full; the shortcut is the way back.
- **Global shortcut**: Control-Option-Command-L by default, can be changed in the settings.
- **Menu bar icon**, optional Dock icon (off by default).
- **"Clear cache"** button, and a clear message for every situation: nothing playing, searching, no lyrics, instrumental, service busy, offline, permission needed, unreadable title.
- **Accessibility**: VoiceOver labels (also on the playback buttons); "Reduce motion" and "Reduce transparency" from macOS are respected.
- **Light on energy**: measured (3 runs of 60 s, `ps`) at 0.2 to 0.3 % CPU on average with one or three lines of synchronised lyrics and 0.4 to 0.5 % with five lines (95th percentile at most 2.3 %), and about 0 % when the window is hidden or when no player is running (one Mac, simulated player, debug build, app process only, see [Known limitations](#known-limitations)).

| Colours from the cover (two covers) | |
|---|---|
| ![Window tinted red from the first cover](docs/images/artwork-red.jpg) | ![Window tinted blue from the second cover](docs/images/artwork-blue.jpg) |

| One line | Five lines |
|---|---|
| ![One visible line](docs/images/lines-1.jpg) | ![Five visible lines](docs/images/lines-5.jpg) |

| Elegant | Neon | Minimal |
|---|---|---|
| ![Elegant theme](docs/images/theme-elegant.jpg) | ![Neon theme](docs/images/theme-neon.jpg) | ![Minimal theme](docs/images/theme-minimal.jpg) |

| Resized window: the text follows | |
|---|---|
| ![Small window, small text](docs/images/resized-small.jpg) | ![Large window, large text](docs/images/resized-large.jpg) |

| Solid | Transparent (on a light desktop) |
|---|---|
| ![Solid background](docs/images/style-solid.jpg) | ![Transparent background](docs/images/style-transparent.jpg) |

| Settings panel | Lyrics without synchronisation |
|---|---|
| ![Settings panel next to the window](docs/images/settings.jpg) | ![Plain lyrics shown as a scrolling block](docs/images/unsynced.jpg) |

## Requirements

- A Mac with **Apple silicon** and **macOS 26 or later**. The released app is an `arm64` binary only (checked with `lipo -info`: "Non-fat file ... architecture: arm64"). Intel Macs are not supported by the download; building from source on Intel has not been tried.
- Spotify (desktop app) and/or Apple Music (the Music app).
- Developed and tested on macOS 27; macOS 26 itself has not been tested.

## Install

1. Download `Lyra-Lyrics-1.0.1-macOS.zip` from the [Releases page](https://github.com/MalikMoussaoui/lyra-lyrics/releases) and unzip it.
2. Move **Lyra Lyrics.app** to your **Applications** folder.
3. Open it. The first time, macOS **blocks** it ("Apple could not verify..."). This is expected: the app is **not notarised** by Apple (notarisation needs a paid developer account, and this project is free and spare-time). To allow it:
   - open **System Settings > Privacy & Security**,
   - scroll down to the message about "Lyra Lyrics" and click **Open Anyway**,
   - confirm with your password or Touch ID, then open the app again.

   The exact wording of these screens may differ on your version of macOS. A right-click > Open is no longer enough on recent versions of macOS.
4. A music-note icon appears in the menu bar, and a window "Nothing playing" appears. Start a song.

The SHA-256 of each zip is in the release notes: compare it with `shasum -a 256 Lyra-Lyrics-1.0.1-macOS.zip` if you want to check your download.

If you would rather not trust a binary, [build it yourself](#build-from-source).

## Permissions

Lyra Lyrics never asks for Accessibility, Input Monitoring or Screen Recording. It uses only **Automation** (macOS asks the first time you click the button; you can change it later in System Settings > Privacy & Security > Automation):

- **Apple Music: required.** The only way to read the playback position is to ask the Music app. The window shows "Authorisation needed" with a button; the system then shows its prompt. If you refuse, the same button opens the settings.
- **Spotify: optional.** Song changes reach the app through a notification Spotify broadcasts, with no permission. A line in the settings panel ("improve precision") lets you allow reading Spotify's position, which keeps the highlighted line accurate after pauses and seeks. Without it, the lyrics still show but the synchronisation is less precise.

The app reads the title, artist, album, duration and position of the current song, and (for the cover colours) its cover image. It only controls playback when **you click** one of the three playback buttons (previous, play/pause, next); it needs the same Automation permission for that, and never asks for it by itself.

## Privacy

- **What leaves your Mac.** To find the lyrics, the title, artist, album and duration of the current song are sent to lrclib.net (with your IP address, like any web request). The request also carries the app's name, version and project address in the `User-Agent` header (`LyraLyrics/1.0.0 (+https://github.com/MalikMoussaoui/lyra-lyrics)`). **One more request, only for Spotify and only if "Colours from the album cover" is on:** the cover image of the song is downloaded once from Spotify's image server (`i.scdn.co`), kept in memory only and never written to disk, and cancelled if the song changes first. Apple Music covers are read from the Music app and are not downloaded. Switch the setting off and no cover request is made at all. Nothing else leaves your Mac: no statistics, no telemetry, no crash report, no update check.
- **Lyrics are never stored.** They are kept in memory for the song being shown (and the previous one), and are gone when you quit. There is no HTTP cache and no copy/export function.
- **What is on disk.** Your settings, and a small lookup index in `~/Library/Application Support/io.github.malikmoussaoui.lyra-lyrics/`: a salted hash of (title, artist, duration) mapped to the LRCLIB identifier, for 24 hours and at most 500 entries. It contains no text. "Clear cache" empties it. This hash is a light obfuscation, not a protection.
- **Only the current song** is looked up, when it starts playing: no preloading, no history.
- This describes what the code is designed and tested to do (the release binary contains no URL other than lrclib.net, this repository and Spotify's image host `i.scdn.co`). It is not legal advice.

## The Dock icon and full-screen apps

macOS lets a window float above a full-screen app only if the app has **no Dock icon**. That is why the Dock icon is **off by default** ("Icon in the Dock" in the settings). If you turn it on, the lyrics window no longer appears above an app in full screen (it stays above normal windows). Choose what matters more to you.

## Keyboard shortcut

**Control-Option-Command-L** hides or shows the window. **In click-through mode it works differently:** it turns click-through **off** and shows the window (it never hides it), because in that mode the window no longer receives any click, so you could not open the settings; and on a MacBook with a notch the menu bar icon can be hidden behind the notch when the menu bar is full. With click-through off, it hides or shows as usual. Launching the app a second time (Spotlight, Finder) also leaves click-through. The shortcut can be changed in the settings panel (gear button on the window, visible when the pointer is over it). If the system cannot register the combination, the panel shows "raccourci indisponible" and the previous one stays active.

## Build from source

You only need the **Command Line Tools** for Xcode (no full Xcode) with Swift 6, on macOS 26 or later. No dependency is downloaded.

```sh
git clone https://github.com/MalikMoussaoui/lyra-lyrics.git
cd lyra-lyrics
swift build                 # debug build of all targets
scripts/test.sh             # unit tests (Swift Testing); last line tells which path was used
scripts/bundle.sh           # release build -> .build/bundle/LyraLyrics.app
scripts/package.sh          # zip -> .build/dist/Lyra-Lyrics-<version>-macOS.zip, with its SHA-256
```

- **Signing**: `scripts/bundle.sh` signs with the first local code-signing certificate it finds in your keychain, looking for `PF_SIGN_IDENTITY` (if you set it) and then "Lyra Lyrics Code", and prints which one it used; it **falls back to an ad hoc signature** if none exists. That is fine to run on your own Mac, but with an ad hoc signature macOS may ask for the Automation permission again after each rebuild.
- **Rename the app**: edit the one line `displayName` in `Sources/LyricsCore/AppIdentity.swift`; the bundle identifier is in `Resources/Info.plist` and `scripts/bundle.sh`.
- The debug build has extra command-line flags for tests (a fake player, a fake LRCLIB server, `--snapshot`); the release build does not contain them. See `scripts/run-app-test.sh` and `Fixtures/selftests/`. Code comments are in French.
- `scripts/ear-check.sh` helps you check the synchronisation by ear on Spotify.

## Known limitations

- **Apple Music streaming tracks: not verified.** It was not established whether Music reports a usable position for tracks streamed from the catalogue (as opposed to your library); synchronisation may be missing or off for them.
- **Spotify: reading its position needs the Automation permission** (see above); without it the app follows song changes only.
- **Cover colours: not verified with a real cover.** They were tested with invented images (Apple Music path, and the Spotify path against a local test server). The Spotify image host (`i.scdn.co`) and the Apple events used to read the cover and to control playback were taken from the apps' scripting dictionaries and have not been tried on a real player. The 4.5:1 contrast is computed against the tint as an opaque colour; on the glass and transparent styles the real background behind the window is unknown.
- **Playback buttons and the permission prompt from the buttons: not verified on a real player** (tested with a simulated permission and a simulated sender; the real prompt and the real Apple events are to be checked by hand).
- **Resizing**: the cursor shape on the grab zones and a real mouse drag were not checked on screen (the automated test sends synthetic mouse events).
- **Plain-text lyrics** (not synchronised) scroll in a block that costs about 2 % CPU while it moves.
- **LRCLIB availability.** The service is community-run and free: it sometimes answers "busy" (HTTP 503, measured on 7 of 22 well-known songs on a first request) or has no lyrics for a song. Since 1.0.1 a failed request moves on to the search endpoint straight away and the app retries by itself ("Lyrics service busy", with a countdown and a **Retry** button); "Lyrics unavailable" now only means that LRCLIB really has nothing.
- **Interface in French only**; **Apple silicon only**; **macOS 26+ only**; no Windows version yet.
- **How well it is tested**: the logic is covered by unit tests and by automated runs with a simulated player and a simulated server. Real players were tested on one Mac (macOS 27). The synchronisation was checked **by ear** on Spotify by the author, without a numeric measurement. The CPU figures come from a simulated player on one Mac.
- Not notarised: macOS asks you to confirm the first launch.

## Credits and rights

- Lyrics come from **[LRCLIB](https://lrclib.net)**, a community database. Lyra Lyrics is an independent app, **not affiliated** with LRCLIB, Spotify or Apple.
- **Lyrics belong to their authors and publishers.** They are shown here for **personal use**, only for the song you are playing; the app never stores them on disk, never uploads them and never redistributes them. If you find a problem with some lyrics, report it to LRCLIB.
- The app icon is drawn in code (see `scripts/make-icon-proposals.swift`); no artwork was copied.

## Licence

[MIT](LICENSE), Copyright (c) 2026 Chopa. See also the [changelog](CHANGELOG.md).
