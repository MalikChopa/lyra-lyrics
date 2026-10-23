# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-10-23

Fixes for three problems reported with 1.0.0.

### Fixed
- **Lyrics not found for well-known songs.** LRCLIB's `/api/get` often answers `503 Retry-After: 1` the first time it is asked for a song (measured: 7 of 22 titles in one session). 1.0.0 asked the same request again three times and then showed "Lyrics unavailable" without ever trying the search endpoint, which answers in under 0.1 s. Now a failed `/api/get` (503, other 5xx, time-out, network error) moves straight to `/api/search` (300 ms later), then the failed requests are retried after `Retry-After`. Measured against the real LRCLIB on 22 well-known songs: 17 found with synchronised lyrics before, all 20 replayed ones after (the 2 others follow an unchanged code path).
- A temporary error is never shown as "Lyrics unavailable" any more: the window shows "Lyrics service busy" with a countdown, retries by itself (after 5, 10, 20, 40, 60 and 60 s), and finally keeps "busy" with a **Retry** button. "Lyrics unavailable" (also with a **Retry** button) now means that LRCLIB really has nothing for the song.
- Broader search when the exact request finds nothing: title without "(feat. …)", "- Remastered 2011", "- Radio Edit"… (case, accents and apostrophes kept), first artist of a multi-artist string, a combined `q=` query without a leading "The", and a short title without a trailing "(…)". Titles and artists are compared without accents, punctuation or a leading "The". At most 6 requests per song in the first attempt (3 in each later retry), one at a time, at least 300 ms apart.
- **Duration gap**: lyrics whose duration differs from the song's by 5 to 15 s are now shown synchronised when title and artist match (the per-song offset in the settings corrects a small drift); beyond 15 s they are still shown as plain text.
- The "circuit breaker" pauses are shorter (10, 20, 40, 60, 120 s instead of 30 to 300 s) and a new song shortens a running pause to 5 s at most, so one bad minute no longer blocks the whole session. A `429` still waits for the server's `Retry-After`.
- The "not found" memory (24 h, hashes only) is ignored for entries written by 1.0.0, which could hide a song for a day after a 503.
- **Click-through and the settings panel.** Turning click-through on now closes the settings panel and the "About" window, and a 3-second notice tells how to come back ("Click-through on · <your shortcut> to come back"). The settings panel has a visible **×** button and closes with **Esc** as soon as it is open.
- **Playback buttons with Spotify.** The Automation permission is tied to the app's identifier, which changed with the rename, so the buttons stayed greyed. Now, while the permission has not been asked yet, the buttons look active and the first click asks for it, with a one-line explanation in the window, then sends the command. If the permission was refused, the buttons stay greyed and a click offers "Open Settings" (nothing is ever asked twice). The Spotify line in the settings panel states the real situation (allowed / not asked / refused / Spotify closed) and is re-read when the panel opens and when a Spotify song starts.

### Changed
- Text of the "Lyrics unavailable" state: "(Remix, rare title or not listed yet.)" instead of mentioning a busy service (a busy service now has its own state).

[1.0.1]: https://github.com/MalikMoussaoui/lyra-lyrics/releases/tag/v1.0.1

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
