# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.3.1] - 2026-11-17

### Fixed
- **Windows: the app could close without warning a few seconds after opening the Scene in the middle of a song** (first line change). The cause was the karaoke-style fill drawing, rewritten with two plain text layers (as on the Mac); the leaving line no longer uses an animated blur and an off-screen mask: it still rises, shrinks a little and fades from left to right. The Scene now writes a short trace of each step to `lyra.log` (never titles or lyrics).
- **Windows: karaoke-style fill** now starts at the first letter of the line (it started late on centred lines).
- **Windows: the white colour swatch** in the settings has a thin outline and stays visible on a light background.

### Changed
- **Global shortcut** (⌃⌥⌘L on the Mac, Ctrl+Alt+Shift+L on Windows): it now **turns click-through on and off**; if the window is hidden, it also shows it. Showing or hiding the window is done from the menu bar menu (Mac) or the notification-area menu (Windows), which both have "Montrer / Cacher la fenêtre" and a "Clic-à-travers" item with a check mark.

## [1.3.0] - 2026-11-16

### Added
- **Scene on Windows (beta).** The full-screen mode of the Mac, with the same settings and rules: screen choice (window's screen, main screen, or by name), smooth zoom from the small window, blurred drifting cover with a breathing gradient, large lines sized to about 70 % of the screen width, "Avec la pochette" and "Paroles seules" layouts, title card with reflection (lyrics-only layout), breathing note and particles during gaps, grain and vignette, control bar (previous, play/pause, next, progress, exit) with Space, arrows and Esc, word-by-word exit of the leaving line; pauses when hidden, on another virtual desktop or when the display sleeps; falls back to another screen when one is unplugged.
- **Windows small window**: optional animated cover background and karaoke-style fill (off by default); "Scène plein écran" group in the settings.
- Shared test files for the Scene calculations (screen choice, fill timing, gaps, text size, layout geometry), read by both apps.

### Notes
- Mac: no functional change; version number shared with Windows.
- The Windows Scene had never been seen on a real screen before this release.

## [1.2.0] - 2026-11-16

### Added
- **Windows version (beta).** First Windows release, shared with the Mac release (same version number, one GitHub release, two files). Windows 10 version 1809 or later and Windows 11, 64-bit; **Spotify only** (read through the Windows media controls, SMTC: no permission to give); **no Scene yet** (full-screen mode is planned for 1.3.0); never run on a real PC before this release, hence "beta". Features:
  - A small always-on-top window with the synchronised lyrics, one, three or five lines, current line highlighted, neighbours dimmed, soft scrolling (opacity and scale) and text that adapts to the window size; resizable with the mouse.
  - Three backgrounds (solid, glass, transparent) and font themes (Classic, Elegant, Neon, Minimal), font, weight, maximum size, colour of the current line, background opacity; colours taken from the album cover (the cover is read locally from Windows, never downloaded); optional experimental "system blur" on Windows 11 (off by default).
  - Plain-text lyrics as a scrolling block, ghost-line waiting animation, manual offset of -5 s to +5 s for the current song, clear messages for each state (nothing playing, searching, no lyrics, instrumental, service busy with a countdown and "Réessayer", offline).
  - "Mauvaises paroles ?": search LRCLIB by title and artist and pick another version, remembered for that song (identifier only, no text), with a way back to the automatic choice.
  - Playback buttons (previous, play/pause, next) in the hover bar; click-through mode; global shortcut Ctrl+Alt+Shift+L (changeable); notification-area icon with a menu; welcome screen at the first launch; auto-hide (never / when paused / when nothing plays, default); launch at Windows start (a value in the user's `Run` registry key, written only when you tick the box); "Copier le diagnostic" in the icon menu; link "Signaler un problème" (opens the issues page of this repository in your browser, nothing is sent).
  - Update notice: at most one request a day, 8 seconds after launch, to `api.github.com` (latest release of this repository), nothing sent about you, setting "Vérifier les mises à jour" (on by default).
  - Accessibility: UI Automation names on the interactive controls; "Reduce animations" and transparency settings of Windows are respected.
  - **Installer** `Lyra-Lyrics-1.2.0-windows-x64-setup.exe` (Inno Setup, built by GitHub Actions on Windows, never on the Mac): per user, no administrator rights, Start menu shortcut, entry in Settings > Apps, uninstaller that asks (default: no) whether to delete your settings, lookup index and log. The installer and the app are **not code-signed**: Windows SmartScreen may warn.
  - Disk: `%APPDATA%\LyraLyrics\` (settings, lookup index with hashed keys and no text, a log without titles or lyrics); network: `lrclib.net` and the daily update check only.
- Windows application icon (derived from the Mac icon) for the exe, the windows and the notification area.
- GitHub Actions workflow `windows-release.yml` (on a `v*` tag: tests, single-file self-contained build, installer, SHA-256, draft release with the installer attached; it never publishes).
- Shared test fixtures: both apps (Swift and C#) now read the same JSON files in `Fixtures/` for text normalisation, `Retry-After`, LRC parsing, request spacing, lookup runner, playback model, settings defaults, palette, auto-hide, update check and manual choices, with `scripts/test-parite.sh` to run both suites.

### Changed
- Version 1.2.0 on both platforms (the Mac `CFBundleVersion` goes to 4). The Windows update check and the Mac one use the same comparison.
- The README (English and French) now covers Windows, and the privacy text no longer pins the `User-Agent` version.

### Fixed
Core fixes made while aligning the Mac and Windows cores (they apply to the Mac app and to Windows):
- Title and artist normalisation: "feat.", "ft." and "vs." are now split off the artist in the same way on both sides, including when the dot touches the next name ("feat.Guest"); on Windows, "ß", "ẞ", "ς" and "İ" are now folded like on the Mac.
- `Retry-After` is capped at 300 seconds (a server asking for a day no longer freezes the app for hours; after 5 minutes one request tries again); negative values count as 0; "inf", "nan" and hexadecimal values are rejected instead of opening an infinite wait.
- LRC lines that are indented (spaces, tabs or no-break spaces before the timestamp) are now accepted instead of being dropped.
- Mac: the wait for the network to come back is now cancellable (a cancelled lookup no longer stays suspended until the next network change).
- Windows: concurrent saves of the lookup index no longer fail (writes are serialised).

### Known limitations
- Windows: beta, never run on a real PC before this release; the installer and the CI workflow had never been run before the first tag; unsigned (SmartScreen, and on Windows 11 the "Smart App Control" may refuse it); Spotify only; no Scene, animated background or karaoke fill yet (stored in the settings file but no control is shown); Windows on Arm not verified; interface in French only.

## [1.1.0] - 2026-11-16

### Added
- **Richer Scene.** A new setting "Mise en page" (Paroles seules / Avec la pochette, default "Avec la pochette"): the cover, sharp with rounded corners, a soft shadow and a faint reflection, sits on the left (about a third of the width) with the title and artist below, the lyrics on the right; the living background stays behind. A control bar at the bottom centre appears when the mouse moves and fades after 3 seconds: previous, play/pause, next (same commands and permission flow as the hover bar), a thin progress bar with elapsed and total time, and an exit button. Keyboard: Space = play/pause, left/right arrows = previous/next, Esc = exit. A line that leaves now rises gently, shrinks a little and fades word by word (about 40 ms apart, about 0.6 s in all; a plain cross-fade with "Reduce motion"). The background drifts a bit more and the colour gradient breathes slowly (it waits while lines move).
- **Scene (full-screen mode).** Double-click the floating window (or menu bar > "Scène plein écran", or the settings button): it zooms smoothly to full screen on the screen you choose (setting "Écran": window's screen, main screen, or one by name). Esc, double-click or your shortcut leave it. The cover, strongly blurred, drifts slowly behind large lyrics whose size adapts to 70 % of the screen width; the current line fills from left to right over its estimated duration in the accent colour taken from the cover; the next lines wait below, the past one lifts and fades. Intros, gaps over 6 s and instrumentals get a calm animation (a breathing note and at most 30 slow particles) that leaves 1 s before the next line. A title card (cover, title, artist, with a soft reflection under the cover) shows for about 3 s at each new song and dissolves into the background. Light grain and vignette (one setting). Text contrast stays at 4.5:1 or more; "Reduce motion" and "Reduce transparency" are respected; the animations pause when the window is hidden or the display sleeps.
- **Wrong lyrics?** Search LRCLIB by title and artist (results show title, artist, album, duration and a "synced" badge) and pick another version; it is used at once and remembered for that song (LRCLIB identifier only, no text), with "Revenir au choix automatique".
- Welcome screen at first launch (3 cards, "Allow Spotify" asks for the permission only on click, reopen from the menu).
- "Launch at login" setting (SMAppService, with a LaunchAgent in `~/Library/LaunchAgents` as fallback, written only when you tick the box and removed when you untick it).
- Re-opening the app (Dock, Spotlight, Finder) shows the window and opens the settings.
- Auto-hide: never / when paused / when nothing plays (default), with a soft fade; never overrides a manual hide or show.
- "New version available" notice: at most one request a day at launch to `api.github.com` (latest release of this repository), nothing sent about you, setting "Vérifier les mises à jour" (on by default).
- Elegant waiting animation (ghost lines that shimmer) while lyrics are searched.
- Both off by default: "Fond animé" (small window: the blurred cover drifts behind the lyrics) and "Remplissage karaoké" (small window and Scene).
- A full-screen button (arrows icon, tooltip "Plein écran (Scène)", VoiceOver label) in the hover bar next to the style and settings buttons; in the Scene, a discreet exit button appears when the mouse moves and fades after 3 seconds (Esc and double-click still work).
- Animated demo in the README (invented lyrics and artwork).

### Changed
- The GitHub account was renamed: all links now point to `MalikChopa/lyra-lyrics` and the app identifier is now `io.github.malikchopa.lyra-lyrics`. Consequence for people who already ran an earlier version: your settings start from their defaults once, the Automation permission for Spotify is asked again once, and the old folder `~/Library/Application Support/io.github.*.lyra-lyrics` can be deleted by hand.
- The plain-text ("not synchronised") block scrolls with one Core Animation animation instead of a 10 Hz timer: measured about 0.01 % CPU on average (about 2 % before).
- The settings panel is longer and scrolls on small screens.

### Fixed
- A vertical line in the small window after making it wider (animated cover background on): the drifting cover was centred on a width of zero at start and no longer covered the right part of the window. It now follows the window width. Checked on the real composed window for the three styles at 460, 900 and 300 pt wide (largest luminance jump between neighbouring columns: about 11 levels before, 0.6 to 1.2 after).
- The text colour you pick always colours the lyrics: the cover colours used to replace it for the current line. They now only tint the background and the filled part of the optional karaoke fill. The Scene also redraws its lines when you change the colour.
- The Neon glow and the karaoke fill drew a rectangle of light around the letters: the glow (two blurs of 16 and 5 pt) was cut off by the edge of the text bitmap (22 pt margin) and by the rectangular karaoke mask. The glow is now a tight outline-following glow (blurs of 3 and 1.5 pt, nothing visible beyond 6 pt from the letters), and the masked layer is drawn without glow or shadow (the unmasked layer below keeps them). Measured with pixels (debug `--glow-proof`): biggest step between neighbouring pixels outside the letters 31 to 32 levels before, 0 to 3 after.
- The karaoke fill was always on in the Scene; it now follows the "Remplissage karaoké" setting (off by default). Settings saved by 1.1.0 test builds (settings version 1) get the karaoke setting switched off once.
- Flaky `clic-travers` self-test (a real Esc typed during the test closed the panel).

Measured (release build with debug flags, fake player, `ps` every second for 60 s, the app process only): Scene 0.85 % CPU on average (p95 4.6 %); small window 0.23 % (0.40 % with the two optional effects) on 2026-10-27. Re-measured on 2026-10-28 on a busier machine, same method, both builds back to back: Scene 2.12 % before the glow/karaoke/button changes and 2.08 % / 1.80 % after (two runs); small window 0.25 % before and 0.30 % after (noise level).
Re-measured on 2026-10-28 for the richer Scene, same method, builds back to back on the same machine: Scene (default "Avec la pochette" layout) 2.06 % and 1.68 % on average (p95 11.8 / 10.7 %) against 1.88 % and 2.06 % (p95 10.8 / 10.6 %) before; small window 0.19 % against 0.25 %. No measurable change. The machine was busier than on 2026-10-27, so absolute figures are not comparable with the first line.

[1.1.0]: https://github.com/MalikChopa/lyra-lyrics/releases/tag/v1.1.0

## [1.0.1] - 2026-10-23

Fixes for three problems reported with 1.0.0.

### Fixed
- The Neon glow and the karaoke fill drew a rectangle of light around the letters: the glow (two blurs of 16 and 5 pt) was cut off by the edge of the text bitmap (22 pt margin) and by the rectangular karaoke mask. The glow is now a tight outline-following glow (blurs of 3 and 1.5 pt, nothing visible beyond 6 pt from the letters), and the masked layer is drawn without glow or shadow (the unmasked layer below keeps them). Measured with pixels (debug `--glow-proof`): biggest step between neighbouring pixels outside the letters 31 to 32 levels before, 0 to 3 after.
- The karaoke fill was always on in the Scene; it now follows the "Remplissage karaoké" setting (off by default). Settings saved by 1.1.0 test builds (settings version 1) get the karaoke setting switched off once.
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

[1.0.1]: https://github.com/MalikChopa/lyra-lyrics/releases/tag/v1.0.1

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

[1.0.0]: https://github.com/MalikChopa/lyra-lyrics/releases/tag/v1.0.0
