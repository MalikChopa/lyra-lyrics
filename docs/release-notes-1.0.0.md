# Lyra Lyrics 1.0.0

## English

First public release: a small always-on-top window showing the synchronised lyrics (from [LRCLIB](https://lrclib.net)) of the song playing in Spotify or Apple Music. Smooth Apple Music-style scrolling, colours taken from the album cover, one / three / five lines, four font themes, a window you can resize with the mouse (the text adapts to it), previous / play-pause / next buttons, three backgrounds (solid, frosted glass, transparent), font / size / colour / opacity, per-song offset, click-through mode (the global shortcut Control-Option-Command-L leaves it, useful when the menu bar icon is hidden behind the MacBook notch), no account, no telemetry. For Spotify, the cover is downloaded once per song from Spotify's image server (`i.scdn.co`), kept in memory only, and nothing is requested if you switch the setting off. macOS 26+, Apple silicon. Interface in French only.

**Download:** `Lyra-Lyrics-1.0.0-macOS.zip` (1,759,322 bytes)
**SHA-256:** `f9ce20f205282f01f586f0a91bd59a658a81610d0ac1babfa42c2a75bd911679`

**First launch (important).** The app is **not notarised** by Apple, so macOS blocks it the first time. Move **Lyra Lyrics.app** to Applications, open it, then go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**, and confirm. The exact wording may differ on your version of macOS.

Known limitations: Apple Music streaming tracks are not verified; reading Spotify's position needs the Automation permission; cover colours, playback buttons and mouse resizing were tested with a simulated player and invented covers, not yet on real players with real covers; plain-text lyrics use about 2 % CPU while scrolling; LRCLIB is community-run and sometimes busy. See the [README](../README.md) and the [changelog](../CHANGELOG.md).

## Français

Première version publique : une petite fenêtre toujours au-dessus qui affiche les paroles synchronisées (de [LRCLIB](https://lrclib.net)) du morceau en cours dans Spotify ou Apple Music. Défilement doux façon Apple Music, couleurs tirées de la pochette, une / trois / cinq lignes, quatre thèmes de police, fenêtre redimensionnable à la souris (le texte s'y adapte), boutons précédent / lecture-pause / suivant, trois fonds (uni, verre dépoli, transparent), police / taille / couleur / opacité, décalage par titre, mode clic-à-travers (le raccourci global ⌃⌥⌘L en sort, utile quand l'icône de la barre de menus est cachée derrière l'encoche du MacBook), sans compte, sans télémétrie. Pour Spotify, la pochette est téléchargée une fois par morceau depuis le serveur d'images de Spotify (`i.scdn.co`), gardée en mémoire seulement, et rien n'est demandé si tu désactives le réglage. macOS 26+, Apple silicon. Interface en français seulement.

**Téléchargement :** `Lyra-Lyrics-1.0.0-macOS.zip` (1 759 322 octets)
**SHA-256 :** `f9ce20f205282f01f586f0a91bd59a658a81610d0ac1babfa42c2a75bd911679`

**Premier lancement (important).** L'app n'est **pas notariée** par Apple : macOS la bloque la première fois. Glisse **Lyra Lyrics.app** dans Applications, ouvre-la, puis va dans **Réglages Système > Confidentialité et sécurité**, descends et clique sur **Ouvrir quand même**, puis confirme. Le texte exact peut différer selon ta version de macOS.

Limites connues : morceaux en streaming d'Apple Music non vérifiés ; lire la position de Spotify demande l'autorisation Automatisation ; couleurs de pochette, boutons de lecture et redimensionnement testés avec un lecteur simulé et des pochettes inventées, pas encore avec de vrais lecteurs et de vraies pochettes ; le texte brut coûte environ 2 % de processeur pendant le défilement ; LRCLIB est communautaire et parfois occupé. Voir le [README](../README.fr.md) et le [journal des versions](../CHANGELOG.md).
