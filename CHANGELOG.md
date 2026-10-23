# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-23

First public release. Native macOS app (Swift / SwiftUI, macOS 26 or later).

### Added
- **Smooth scrolling** like Apple Music: lines glide up on each change, the current line scales up and brightens, neighbours fade and get a light blur; Core Animation layer animations (no per-frame redraw); "Reduce motion" gives a cross-fade.
- **Colours from the album cover** (setting, on by default): background tint and current-line colour from the cover, current line at least 4.5:1 against the tint. Apple Music: cover read from the Music app; Spotify: one HTTPS download per song from Spotify's image server, in memory only, cancelled on song change; nothing is requested when the setting is off.
- **Playback buttons** (previous, play/pause, next) in the hover bar, greyed out with an explanation when the Automation permission is missing.
- **One, three or five lines** setting, **font themes** (Classic, Elegant, Neon, Minimal; "Custom" when a single control is changed), font weight and glow settings.
- **Resizable window**: drag edges and corners (280 x 110 pt minimum, 90 % of the visible screen maximum); the font size adapts automatically to the window (the "Max size" setting is the upper limit, 14 pt floor, a line wraps only if it does not fit at the floor); size remembered, "Default size" button, disabled in click-through mode.
- Click-through exit: the global shortcut now turns click-through off and shows the window (instead of hiding it), also relaunching the app does; documented that the menu bar icon can be hidden behind the MacBook notch.
- Always-on-top floating window showing the lyrics of the song playing in Spotify or Apple Music (Music), without any account.
- Time-synchronised lyrics (current line highlighted, neighbouring lines dimmed); plain-text lyrics are shown as a slowly scrolling block, with a notice that they are not synchronised.
- Lyrics from [LRCLIB](https://lrclib.net), fetched on demand for the song being played only. Lyrics are kept in memory only; only a hashed lookup index (no text) is written to disk, for 24 hours.
- Three background styles: solid, frosted glass, transparent. Settings for font, size, colour and background opacity.
- Manual lyrics offset (-5 to +5 s) per song, "Clear cache" button, click-through mode, global show/hide shortcut (default Control-Option-Command-L, can be changed).
- Optional Dock icon (off by default), menu bar icon, "About and rights" window with attribution and a network-transparency statement.
- Clear on-screen states: nothing playing, searching, lyrics unavailable, instrumental, service busy, offline, permission needed, unreadable title.
- Accessibility: VoiceOver labels, "Reduce motion" and "Reduce transparency" are respected.
- Low energy use: about 0.2 % CPU while showing synchronised lyrics, near 0 % when hidden or idle (measured once, on one Mac, with a simulated player; see the README).
- No telemetry, no crash reporting, no update check.

### Notes
- The app is not notarised by Apple (no paid developer account). On first launch macOS blocks it; see "Install" in the README.
- The interface is in French only in this version.
- `scripts/bundle.sh` looks for the signing identity "Lyra Lyrics Code" (or `PF_SIGN_IDENTITY`) and falls back to ad hoc, printing which one was used.
- Settings of pre-release builds (which used another bundle identifier) are not migrated.

[1.0.0]: https://github.com/MalikMoussaoui/lyra-lyrics/releases/tag/v1.0.0
