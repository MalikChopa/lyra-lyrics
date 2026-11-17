# Lyra Lyrics 1.3.0

## English

The full-screen **Scene** comes to the **Windows version (beta)**.

- **Scene on Windows.** Double-click the small window, use the full-screen button of the hover bar, or the notification-icon menu: the window zooms to full screen on the screen you choose (window's screen, main screen, or one by name). The album cover, strongly blurred, drifts slowly behind large lyrics (about 70 % of the screen width); layout "Avec la pochette" (sharp cover with title and artist on the left, lyrics on the right, default) or "Paroles seules" (centred lyrics, with a title card and a soft reflection for about 3 s at each new song); a breathing note and a few slow particles during intros, gaps and instrumentals; light grain and vignette (one setting); a control bar when the mouse moves (previous, play/pause, next, progress, exit), Space, Left/Right arrows and Esc; the leaving line fades word by word. Windows "show animations" and "transparency effects" settings are respected, and animations pause when the Scene is hidden, on another virtual desktop or when the display sleeps.
- **Also on Windows**: optional animated cover background and karaoke-style fill for the small window and the Scene (both off by default), and a "Scène plein écran" group in the settings.
- **Mac**: no new feature; the version number follows Windows (one shared version). The shared Scene calculations are now checked by test files read by both apps.

**Download:** `Lyra-Lyrics-1.3.0-macOS.zip` (2,134,224 bytes)

**SHA-256:** `e32d230d79b85c5b6a267ae3b9d16e4e9f818f19bb402662b4c1da6ff91266e2`

**Download:** `Lyra-Lyrics-1.3.0-windows-x64-setup.exe` (71,881,434 bytes, built by GitHub Actions from the `v1.3.0` tag)

**SHA-256:** `ee02e81d7466207e39df05ddf0126c40508bda00d4b99229b33ec54c77a2d6b9`

**First launch on the Mac (important).** The app is **not notarised**: move **Lyra Lyrics.app** to Applications, open it, then **System Settings > Privacy & Security > Open Anyway**. The exact wording may differ on your version of macOS.

**First launch on Windows (important).** The installer and the app are **not signed**. Run `Lyra-Lyrics-1.3.0-windows-x64-setup.exe`; if Windows SmartScreen shows "Windows protected your PC" (French: "Windows a protégé votre ordinateur"), click **More info** ("Informations complémentaires"), then **Run anyway** ("Exécuter quand même"). On Windows 11 with Smart App Control turned on, that button may not exist and Windows may refuse the file: this has not been checked on a real PC. To check your download, compare its SHA-256 with the line above (`Get-FileHash <file>` in PowerShell, or `shasum -a 256 <file>` on a Mac). To uninstall: Settings > Apps > Lyra Lyrics (the uninstaller asks whether to delete your settings; the default answer keeps them).

Known limitations: **the Windows Scene had never been seen on a real screen before this release**: its rendering is only checked by compiling it on the developer's Mac, by the shared test files and, if GitHub's Windows runner can draw without a desktop, by screenshots made with invented lyrics. Windows stays a beta, Spotify only, with an unsigned installer.

## Français

La **Scène** plein écran arrive sur la **version Windows (bêta)**.

- **Scène sous Windows.** Double-clic sur la petite fenêtre, bouton plein écran de la barre au survol, ou menu de l'icône de notification : la fenêtre grandit jusqu'au plein écran sur l'écran de ton choix (celui de la fenêtre, l'écran principal, ou un écran par son nom). La pochette, très floue, dérive lentement derrière de grandes paroles (environ 70 % de la largeur de l'écran) ; mise en page « Avec la pochette » (pochette nette avec titre et artiste à gauche, paroles à droite, par défaut) ou « Paroles seules » (paroles centrées, avec une carte du titre et un reflet discret pendant environ 3 s à chaque nouveau morceau) ; une note qui respire et quelques particules lentes pendant les introductions, les trous et les instrumentaux ; un grain et une vignette légers (un seul réglage) ; une barre de commandes quand la souris bouge (précédent, lecture/pause, suivant, progression, sortie), Espace, flèches gauche/droite et Échap ; la ligne qui part s'efface mot à mot. Les réglages Windows « Afficher les animations » et « Effets de transparence » sont respectés, et les animations se mettent en pause quand la Scène est masquée, sur un autre bureau virtuel ou quand l'écran se met en veille.
- **Aussi sous Windows** : fond de pochette animé et remplissage façon karaoké en option pour la petite fenêtre et la Scène (désactivés par défaut), et un groupe « Scène plein écran » dans les réglages.
- **Mac** : aucune fonction nouvelle ; le numéro suit celui de Windows (une version commune). Les calculs de la Scène communs aux deux apps sont maintenant vérifiés par des fichiers d'essai lus par les deux.

**Téléchargement :** `Lyra-Lyrics-1.3.0-macOS.zip` (2 134 224 octets)

**SHA-256 :** `e32d230d79b85c5b6a267ae3b9d16e4e9f818f19bb402662b4c1da6ff91266e2`

**Téléchargement :** `Lyra-Lyrics-1.3.0-windows-x64-setup.exe` (71 881 434 octets, construit par GitHub Actions à partir de l'étiquette `v1.3.0`)

**SHA-256 :** `ee02e81d7466207e39df05ddf0126c40508bda00d4b99229b33ec54c77a2d6b9`

**Premier lancement sur Mac (important).** L'app n'est **pas notariée** : glisse **Lyra Lyrics.app** dans Applications, ouvre-la, puis **Réglages Système > Confidentialité et sécurité > Ouvrir quand même**. Le texte exact peut différer selon ta version de macOS.

**Premier lancement sur Windows (important).** L'installateur et l'app ne sont **pas signés**. Lance `Lyra-Lyrics-1.3.0-windows-x64-setup.exe` ; si Windows SmartScreen affiche « Windows a protégé votre ordinateur », clique sur **Informations complémentaires**, puis sur **Exécuter quand même**. Sous Windows 11 avec le Contrôle intelligent des applications activé, ce bouton peut ne pas exister et Windows peut refuser le fichier : non vérifié sur un vrai PC. Pour vérifier ton téléchargement, compare son SHA-256 avec la ligne ci-dessus (`Get-FileHash <fichier>` dans PowerShell, ou `shasum -a 256 <fichier>` sur Mac). Pour désinstaller : Paramètres > Applications > Lyra Lyrics (le désinstallateur demande s'il faut supprimer tes réglages ; la réponse par défaut les conserve).

Limites connues : **la Scène Windows n'avait jamais été vue sur un vrai écran avant cette release** : son rendu n'est vérifié que par la compilation sur le Mac du développeur, par les fichiers d'essai communs et, si l'exécuteur Windows de GitHub sait dessiner sans bureau, par des captures faites avec des paroles inventées. Windows reste une bêta, Spotify seulement, avec un installateur non signé.
