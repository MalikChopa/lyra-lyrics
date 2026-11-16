# Lyra Lyrics

**Une petite fenêtre toujours au-dessus qui affiche les paroles synchronisées du morceau en cours : sur Mac dans Spotify ou Apple Music, sur Windows (bêta) dans Spotify.**

*[English](README.md) · Français*

![Lyra Lyrics : une fenêtre en verre dépoli teintée aux couleurs de la pochette flotte au-dessus d'autres apps et affiche trois lignes de paroles avec les boutons de lecture](docs/images/hero.jpg)

![Démo (paroles et pochettes inventées)](docs/images/demo.gif)

> **L'interface de l'app est en français seulement** dans cette version (menus, réglages, messages), sur Mac comme sur Windows.
> Les captures de ce README sont des rendus faits par l'app Mac elle-même (`--snapshot`) sur un faux bureau dessiné, avec des paroles, titres, artistes et pochettes **inventés**. Dans la vraie app, le verre dépoli floute ce qui se trouve derrière la fenêtre ; ces rendus ne montrent pas ce flou. Il n'y a pas encore de capture de la version Windows.

## Ce que ça fait

Lance un morceau dans Spotify ou Apple Music (l'app Musique, Mac seulement). Lyra Lyrics le repère, cherche les paroles sur [LRCLIB](https://lrclib.net) et en affiche une, trois ou cinq lignes dans une petite fenêtre qui reste au-dessus de toutes les autres, où tu veux sur l'écran. La ligne chantée est mise en avant et glisse en douceur à sa place au fil du morceau.

Pas de compte, pas de connexion, pas de serveur à nous : l'app parle à ton lecteur de musique et à lrclib.net, plus (une fois par jour au plus, désactivable) à GitHub pour savoir si une nouvelle version existe. Voir [Vie privée](#vie-privée).

**Mac et Windows.** La version Mac est complète (Spotify et Apple Music, Scène plein écran). La version **Windows est une bêta** : Spotify seulement ; la Scène plein écran y arrive en 1.3.0 ; elle n'avait **jamais tourné sur un vrai PC** avant sa publication. Voir [Windows (bêta)](#windows-bêta).

## Fonctions

### Nouveautés de la 1.3.0

- **La Scène plein écran arrive sur Windows (bêta)** : mêmes réglages et mêmes règles que sur Mac (écran au choix, mise en page « Avec la pochette » ou « Paroles seules », carte du titre, passages sans paroles animés, grain et vignette, barre de commandes avec Espace, flèches et Échap, sortie des lignes mot à mot) ; double-clic sur la petite fenêtre, bouton plein écran de la barre ou menu de l'icône. Aussi sur Windows : fond de pochette animé et remplissage karaoké en option (désactivés par défaut). Rendu jamais vu sur un vrai PC avant la publication.
- Mac : aucune fonction nouvelle ; le numéro suit celui de Windows (une version commune).

### Nouveautés de la 1.2.0

- **Version Windows (bêta).** Windows 10 1809 ou plus récent, ou Windows 11, 64 bits ; Spotify seulement ; sans la Scène ; avec un installateur (par utilisateur, sans droits d'administrateur) non signé. Tout est dans [Windows (bêta)](#windows-bêta).
- **Corrections communes aux deux apps** : « feat. », « ft. » et « vs. » reconnus de la même façon des deux côtés ; `Retry-After` plafonné à 300 s ; lignes LRC indentées acceptées ; sur Mac, l'attente du retour du réseau est annulable. Détail dans le [journal des versions](CHANGELOG.md) (en anglais), qui contient aussi toutes les versions précédentes.

### Fonctions du Mac (dont la Scène, nouveauté de la 1.1.0)

- **Scène (mode plein écran).** Clic sur le bouton plein écran de la barre au survol de la fenêtre flottante (ou double-clic) : elle grandit en douceur jusqu'au plein écran, sur l'écran de ton choix (Échap, double-clic, le bouton de sortie qui apparaît quand la souris bouge, ou ton raccourci pour en sortir). La pochette, très floue, dérive lentement derrière de grandes paroles (la ligne courante est mise en valeur dans la couleur d'accent, les suivantes attendent dessous ; le réglage en option « Remplissage karaoké » la remplit de gauche à droite pendant qu'elle est chantée) ; en mise en page « Paroles seules », une carte avec la pochette et son reflet discret s'affiche environ 3 secondes à chaque nouveau morceau (avec la mise en page par défaut, « Avec la pochette », le titre et l'artiste restent affichés à gauche et il n'y a pas de carte) ; pendant les introductions, les trous et les instrumentaux, une note qui respire et quelques particules lentes prennent le relais ; un grain et une vignette légers (un seul réglage). Règles de sobriété : une seule couleur d'accent tirée de la pochette, au plus deux effets en mouvement à la fois, courbes douces, contraste du texte d'au moins 4,5 : 1, « Réduire les animations » et « Réduire la transparence » respectés. Mesuré : environ 1,7 à 2,1 % de CPU en moyenne dans la Scène et environ 0,2 % dans la petite fenêtre (build release avec drapeaux de diagnostic, faux lecteur, 2026-10-28 ; voir le journal des versions).
  ![Scène : carte du titre](docs/images/scene-01-carte.jpg)
  ![Scène : paroles, ligne courante mise en valeur](docs/images/scene-02-lignes.jpg)
  ![Scène : passage instrumental](docs/images/scene-05-passage.jpg)
  ![Scène : pochette à gauche, paroles à droite, barre de commandes](docs/images/scene-03-barre-commandes.jpg)
  ![Scène : paroles seules](docs/images/scene-04-paroles-seules.jpg)
- **Mises en page et commandes de la Scène.** Réglage « Mise en page » : « Avec la pochette » (défaut : pochette nette avec titre et artiste à gauche, paroles à droite) ou « Paroles seules » (paroles centrées et carte du titre). Bouge la souris pour montrer une barre en bas (précédent, lecture/pause, suivant, progression avec temps écoulé et total, sortie) ; elle se masque après 3 secondes. Clavier : Espace = lecture/pause, flèches gauche/droite = précédent/suivant, Échap = sortie. La ligne qui part monte, rétrécit un peu et s'efface mot à mot.
- **Mauvaises paroles ?** Un panneau de recherche (réglages, barre de menus, ou bouton de l'état « indisponibles ») liste les versions de LRCLIB (titre, artiste, album, durée, pastille « synchro ») ; celle que tu choisis sert tout de suite et est retenue pour ce morceau (son identifiant LRCLIB seulement, jamais de texte), avec un retour au choix automatique.
- **Écran d'accueil** au premier lancement (3 cartes, un bouton « Autoriser Spotify » qui ne demande l'autorisation qu'à ton clic) ; rouvrable depuis le menu.
- **Lancement à l'ouverture de session** (réglages), **masquage automatique** (jamais / en pause / quand rien ne joue, en fondu, sans jamais défaire ton propre masquage ou affichage), **relancer l'app** montre la fenêtre et les réglages, **avis de nouvelle version** (une requête par jour au plus vers GitHub, désactivable).
- **Attente élégante** (lignes fantômes qui scintillent) pendant la recherche des paroles, **fond animé** de pochette et **remplissage façon karaoké** en option (petite fenêtre et Scène) (désactivés par défaut), et un bloc de texte non synchronisé qui défile par une seule animation Core Animation (environ 0 % de CPU au lieu de 2 %).
  ![Petite fenêtre avec fond animé et remplissage](docs/images/small-s24.jpg)

- **Toujours au-dessus**, déplaçable n'importe où, y compris au-dessus des fenêtres d'autres apps (voir [l'icône du Dock et le plein écran](#licône-du-dock-et-le-plein-écran)). **Redimensionnable à la souris** : tire un bord ou un coin (zone de prise de 6 pt, 280 × 110 pt au minimum, 90 % de l'écran visible au maximum) ; le texte **s'adapte automatiquement** : la taille de police est la plus grande pour laquelle les lignes visibles tiennent dans la fenêtre en largeur et en hauteur (le réglage « Taille max » est la limite haute) : fenêtre plus grande, texte plus grand. Une ligne ne passe à la ligne que si elle ne tient pas, même à 14 pt. La taille est retenue ; « Taille par défaut » dans les réglages la réinitialise. Désactivé en mode clic-à-travers.
- **Défilement doux** façon Apple Music : à chaque changement de ligne, les lignes glissent vers le haut, la nouvelle ligne courante grossit un peu et s'éclaircit, les voisines s'estompent et prennent un léger flou. Fait avec des animations de couches Core Animation (aucun redessin à chaque image), fluide à 60 et 120 Hz ; avec « Réduire les animations », un simple fondu remplace le glissement.
- **Couleurs de la pochette** (activé par défaut, désactivable) : la teinte du fond et la couleur de la ligne courante viennent de la pochette du morceau en cours, avec un contraste d'au moins 4,5 : 1 pour la ligne courante contre la teinte. Apple Music : la pochette est lue dans l'app Musique. Spotify : la pochette est téléchargée une fois par morceau (voir [Vie privée](#vie-privée)). Désactivé, ou sans pochette : les styles unis.
- **Boutons de lecture** dans la barre qui apparaît au survol : précédent, lecture/pause, suivant, pour le lecteur en cours. Si macOS n'a pas encore été interrogé, le premier clic demande l'autorisation Automatisation (une phrase d'explication apparaît dans la fenêtre, puis l'invite du système) et envoie ensuite la commande ; si tu l'as refusée, les boutons restent grisés et un clic propose « Ouvrir les Réglages » (rien n'est jamais demandé deux fois).
- **Une, trois ou cinq lignes** (réglage « Lignes ») ; la hauteur de la fenêtre s'adapte, les lignes longues passent toujours à la ligne et réduisent la police au besoin.
- **Thèmes de police** : Classique, Élégant (serif New York), Néon (arrondie grasse avec une lueur serrée qui suit les lettres), Minimal (fine), chacun règle police, graisse, couleur, halo et taille des voisines d'un clic. Modifier ensuite un seul réglage affiche « Personnalisé ».
- **Paroles synchronisées** : ligne courante mise en avant, voisines atténuées. Quand LRCLIB n'a que du texte brut, il s'affiche en bloc qui défile lentement, avec la mention « non synchronisées ».
- **Trois fonds** : uni, verre dépoli, transparent (texte avec une ombre douce).
- **Réglages** : police, graisse, taille max, couleur du texte, halo, opacité du fond.
- **Décalage manuel** de −5 s à +5 s, pour le titre en cours seulement, quand des paroles sont un peu en avance ou en retard.
- **Mode clic-à-travers** : les clics traversent la fenêtre vers l'app dessous. L'activer ferme le volet de réglages et un avis de 3 secondes dans la fenêtre rappelle comment revenir. Pour en sortir, appuie sur le raccourci (voir [Raccourci clavier](#raccourci-clavier)) : il désactive le clic-à-travers et montre la fenêtre. L'icône de la barre de menus marche aussi, mais sur un MacBook à encoche elle peut être cachée derrière l'encoche quand la barre est pleine ; le raccourci est le chemin de retour.
- **Raccourci global** : ⌃⌥⌘L par défaut, modifiable dans les réglages.
- **Icône dans la barre de menus**, icône du Dock facultative (décochée par défaut).
- Bouton **« Vider le cache »**, et un message clair pour chaque situation : rien en lecture, recherche, pas de paroles, instrumental, service occupé, hors connexion, autorisation nécessaire, titre illisible.
- **Accessibilité** : libellés VoiceOver (boutons de lecture compris) ; « Réduire les animations » et « Réduire la transparence » de macOS sont respectés.
- **Sobre en énergie** : mesuré (3 passages de 60 s, `ps`) à 0,2 à 0,3 % de processeur en moyenne avec une ou trois lignes de paroles synchronisées et 0,4 à 0,5 % avec cinq lignes (95e centile : 2,3 % au plus), et environ 0 % quand la fenêtre est cachée ou qu'aucun lecteur ne tourne (un Mac, lecteur simulé, build debug, processus de l'app seulement, voir [Limites connues](#limites-connues)).

| Couleurs de la pochette (deux pochettes) | |
|---|---|
| ![Fenêtre teintée de rouge par la première pochette](docs/images/artwork-red.jpg) | ![Fenêtre teintée de bleu par la seconde pochette](docs/images/artwork-blue.jpg) |

| Une ligne | Cinq lignes |
|---|---|
| ![Une ligne visible](docs/images/lines-1.jpg) | ![Cinq lignes visibles](docs/images/lines-5.jpg) |

| Élégant | Néon | Minimal |
|---|---|---|
| ![Thème Élégant](docs/images/theme-elegant.jpg) | ![Thème Néon](docs/images/theme-neon.jpg) | ![Thème Minimal](docs/images/theme-minimal.jpg) |

| Fenêtre redimensionnée : le texte suit | |
|---|---|
| ![Petite fenêtre, petit texte](docs/images/resized-small.jpg) | ![Grande fenêtre, grand texte](docs/images/resized-large.jpg) |

| Uni | Transparent (sur un bureau clair) |
|---|---|
| ![Fond uni](docs/images/style-solid.jpg) | ![Fond transparent](docs/images/style-transparent.jpg) |

| Volet de réglages | Paroles sans synchronisation |
|---|---|
| ![Volet de réglages à côté de la fenêtre](docs/images/settings.jpg) | ![Texte brut en bloc qui défile](docs/images/unsynced.jpg) |

## Prérequis

### Mac

- Un Mac **Apple silicon** sous **macOS 26 ou plus récent**. L'app publiée est un binaire `arm64` seulement (vérifié avec `lipo -info` : « Non-fat file ... architecture: arm64 »). Les Mac Intel ne sont pas pris en charge par le téléchargement ; compiler depuis les sources sur Intel n'a pas été essayé.
- Spotify (app de bureau) et/ou Apple Music (l'app Musique).
- Développée et testée sous macOS 27 ; macOS 26 lui-même n'a pas été testé.

### Windows

- **Windows 10 version 1809 ou plus récent, ou Windows 11, en 64 bits** (x64). Windows sur Arm : non vérifié.
- L'**app Spotify de bureau**, ouverte (l'app lit Spotify par le contrôle multimédia de Windows). Aucun autre lecteur n'est pris en compte (ni Apple Music, ni un navigateur). Rien à installer d'autre : l'app est livrée avec son environnement .NET.

## Installation

### Mac

1. Télécharge `Lyra-Lyrics-1.2.0-macOS.zip` sur la [page des Releases](https://github.com/MalikChopa/lyra-lyrics/releases) et décompresse-le.
2. Glisse **Lyra Lyrics.app** dans ton dossier **Applications**.
3. Ouvre-la. La première fois, macOS la **bloque** (« Apple n'a pas pu vérifier... »). C'est normal : l'app n'est **pas notariée** par Apple (la notarisation demande un compte développeur payant, et ce projet est gratuit et fait sur le temps libre). Pour l'autoriser :
   - ouvre **Réglages Système > Confidentialité et sécurité**,
   - descends jusqu'au message qui parle de « Lyra Lyrics » et clique sur **Ouvrir quand même**,
   - confirme avec ton mot de passe ou Touch ID, puis rouvre l'app.

   Le texte exact de ces écrans peut différer selon ta version de macOS. Le clic droit > Ouvrir ne suffit plus sur les versions récentes de macOS.
4. Une icône en forme de note de musique apparaît dans la barre de menus, et une fenêtre « Rien en lecture » s'affiche. Lance un morceau.

Le SHA-256 de chaque fichier est dans les notes de version : compare-le avec `shasum -a 256 Lyra-Lyrics-1.2.0-macOS.zip` si tu veux vérifier ton téléchargement.

### Windows

1. Télécharge `Lyra-Lyrics-1.2.0-windows-x64-setup.exe` sur la [page des Releases](https://github.com/MalikChopa/lyra-lyrics/releases).
2. Lance-le. L'installateur **n'est pas signé** : Windows SmartScreen peut afficher « Windows a protégé votre ordinateur ». Clique sur **Informations complémentaires**, puis sur **Exécuter quand même**. Sous Windows 11 avec le Contrôle intelligent des applications activé, ce bouton peut ne pas exister et Windows peut refuser le fichier : **non vérifié sur un vrai PC**. Le code n'est pas signé (budget zéro ; une signature gratuite est envisagée, rien n'est établi).
3. L'installateur installe pour **ton compte seulement** (aucun droit d'administrateur ni fenêtre de contrôle de compte attendus : non vérifié sur un vrai PC) dans `%LOCALAPPDATA%\Programs\Lyra Lyrics`, ajoute un raccourci dans le menu Démarrer et propose de lancer l'app à la fin. Il existe en français et en anglais.
4. Une icône apparaît dans la zone de notification (souvent derrière la flèche « ^ » de la barre des tâches sous Windows 11), un écran d'accueil s'ouvre au premier lancement et une fenêtre « Rien en lecture » s'affiche. Lance un morceau dans Spotify.
5. **Désinstaller** : Paramètres > Applications > Lyra Lyrics. Le désinstallateur ferme l'app, retire le raccourci et l'entrée de lancement au démarrage s'il y en a une, puis demande s'il faut supprimer aussi tes réglages, l'index de recherche et le journal (réponse par défaut : non, tout est conservé).

Pour vérifier ton téléchargement : `Get-FileHash Lyra-Lyrics-1.2.0-windows-x64-setup.exe` dans PowerShell, à comparer avec le SHA-256 des notes de version.

Si tu préfères ne pas faire confiance à un binaire, [compile-la toi-même](#compiler-depuis-les-sources).

## Windows (bêta)

La version Windows est une **bêta** : elle est complète pour l'essentiel, mais elle n'avait **jamais tourné sur un vrai PC** avant sa publication (tout a été écrit, compilé et testé sur un Mac : tests unitaires et fichiers d'essai communs avec la version Mac). Attends-toi à des défauts d'affichage ou de détection, et signale-les via « À propos et droits » > « Signaler un problème » (ouvre la page des signalements du dépôt dans ton navigateur ; l'app n'envoie rien).

**Ce qu'elle fait** : la même petite fenêtre toujours au-dessus (déplaçable, redimensionnable à la souris, texte qui s'adapte) ; Spotify seulement, lu par le contrôle multimédia de Windows (**rien à autoriser**) ; paroles synchronisées sur une, trois ou cinq lignes avec défilement doux, ou bloc non synchronisé qui défile ; trois fonds (uni, verre, transparent), thèmes de police, couleurs tirées de la pochette (lue localement, jamais téléchargée), décalage manuel de −5 s à +5 s ; boutons précédent, lecture/pause, suivant ; mode clic-à-travers ; raccourci global **Ctrl+Alt+Maj+L** (modifiable) ; icône dans la zone de notification ; écran d'accueil ; masquage automatique (quand rien ne joue par défaut) ; lancement au démarrage de Windows (case à cocher) ; « Mauvaises paroles ? » (recherche LRCLIB et choix d'une autre version, retenu pour ce morceau) ; avis de nouvelle version (une requête par jour au plus, désactivable) ; « Copier le diagnostic » dans le menu de l'icône.

**Depuis la 1.3.0** : la **Scène** plein écran, le fond de pochette animé et le remplissage façon karaoké (ces deux derniers désactivés par défaut), comme sur Mac.

**Ce qu'elle n'a pas (encore)** : Apple Music et les autres lecteurs, une interface dans une autre langue. Le style « Verre » n'est qu'un dégradé teinté sans flou ; une option expérimentale « Flou du système » (Windows 11, désactivée par défaut) existe mais n'a jamais été essayée sur un vrai écran.

**Ce qu'elle écrit sur ton disque**
- `%APPDATA%\LyraLyrics\` : `settings.json` (tes réglages), `lookup-index.json` (index de recherche sans aucun texte : clés brouillées, identifiants LRCLIB), `lyra.log` (journal sans titres, sans paroles ni identifiants LRCLIB, 256 Ko puis rotation).
- Si tu coches « Lancer au démarrage de Windows » : une valeur `LyraLyrics` dans la clé `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (retirée quand tu la décoches et à la désinstallation).
- L'installateur : l'app dans `%LOCALAPPDATA%\Programs\Lyra Lyrics\`, un raccourci du menu Démarrer, une entrée dans Paramètres > Applications (clé `HKCU`). Rien sous `HKLM` ni dans `Program Files`, aucun service, aucune tâche planifiée.
- .NET extrait les bibliothèques natives de l'app dans `%TEMP%\.net\LyraLyrics\` au premier lancement ; ce dossier reste après la désinstallation et peut être effacé à la main.

**Ce qui sort de ton PC** : seulement deux adresses. `lrclib.net` (titre, artiste, album et durée du morceau en cours, avec ton adresse IP, pour chercher les paroles ; une requête de plus quand tu cliques sur « Chercher » dans « Mauvaises paroles ? ») et, une fois par jour au plus, `api.github.com` (dernière version de ce dépôt, rien de toi n'est envoyé hormis le `User-Agent` de l'app ; désactivable dans les réglages). Aucune pochette n'est téléchargée sous Windows, ni statistique, ni télémétrie.

**Limites** : voir [Limites connues](#limites-connues). Les paroles ne sont jamais écrites sur le disque non plus sous Windows.

## Autorisations (Mac)

Sous Windows il n'y a rien à autoriser (voir [Windows (bêta)](#windows-bêta)). Sur Mac, Lyra Lyrics ne demande jamais Accessibilité, Surveillance de l'entrée ni Enregistrement de l'écran. Elle utilise seulement **Automatisation** (macOS la demande quand tu cliques sur le bouton ; tu peux la changer ensuite dans Réglages Système > Confidentialité et sécurité > Automatisation) :

- **Apple Music : obligatoire.** La seule façon de lire la position de lecture est d'interroger l'app Musique. La fenêtre affiche « Autorisation nécessaire » avec un bouton ; le système montre alors son invite. Si tu refuses, le même bouton ouvre les réglages.
- **Spotify : facultative.** Les changements de morceau arrivent par une notification que Spotify diffuse, sans permission. Une ligne du volet de réglages (« Améliorer la précision ») permet d'autoriser la lecture de la position dans Spotify, ce qui garde la ligne mise en avant juste après une pause ou un saut. Sans elle, les paroles s'affichent quand même, mais la synchro est moins précise.

L'app lit le titre, l'artiste, l'album, la durée et la position du morceau en cours, et (pour les couleurs) sa pochette. Elle ne pilote la lecture que quand **tu cliques** sur l'un des trois boutons de lecture (précédent, lecture/pause, suivant) ; elle a besoin pour cela de la même autorisation Automatisation, et ne la demande jamais d'elle-même.

## Vie privée

Ce qui suit décrit le Mac ; pour Windows (mêmes principes, une requête de pochette en moins), voir [Windows (bêta)](#windows-bêta).

- **Ce qui sort de ton Mac.** Pour trouver les paroles, le titre, l'artiste, l'album et la durée du morceau en cours sont envoyés à lrclib.net (avec ton adresse IP, comme toute requête web). La requête porte aussi le nom de l'app, sa version et l'adresse du projet dans l'en-tête `User-Agent` (`LyraLyrics/<version> (+https://github.com/MalikChopa/lyra-lyrics)`). **Une requête de plus, seulement pour Spotify et seulement si « Couleurs de la pochette » est activé :** la pochette du morceau est téléchargée une fois depuis le serveur d'images de Spotify (`i.scdn.co`), gardée en mémoire seulement, jamais écrite sur le disque, et annulée si le morceau change avant la fin. Les pochettes d'Apple Music sont lues dans l'app Musique, sans téléchargement. Désactive le réglage et plus aucune requête de pochette n'est faite. **Une requête de plus, une fois par jour au plus, au lancement, si « Vérifier les mises à jour » est activé (défaut) :** un GET vers `api.github.com` (dernière version de ce dépôt) pour te dire quand une nouvelle version existe. Rien de toi n'est envoyé (seulement le `User-Agent` de l'app), la session est éphémère et le réglage se désactive. Rien d'autre ne quitte ton Mac : ni statistiques, ni télémétrie, ni rapport de plantage.
- **Les paroles ne sont jamais stockées.** Elles restent en mémoire pour le morceau affiché (et le précédent) et disparaissent quand tu quittes. Pas de cache HTTP, pas de fonction copier ou exporter.
- **Ce qui est sur le disque.** Tes réglages, et un petit index de recherche dans `~/Library/Application Support/io.github.malikchopa.lyra-lyrics/` : une empreinte salée de (titre, artiste, durée) associée à l'identifiant LRCLIB, pendant 24 h et 500 entrées au plus ; seuls les choix faits à la main dans « Mauvaises paroles ? » (200 au plus) n'expirent pas. Il ne contient aucun texte. « Vider le cache » le vide. Cette empreinte est un simple brouillage, pas une protection.
- **Seul le morceau en cours** est cherché, quand il démarre : pas de préchargement, pas d'historique.
- Cela décrit ce que le code est conçu et testé pour faire (le binaire Mac publié ne contient aucune adresse autre que lrclib.net, `api.github.com`, ce dépôt et l'hôte d'images de Spotify `i.scdn.co` ; l'exe Windows, seulement `lrclib.net`, `api.github.com` et `github.com`). Ce n'est pas un avis juridique.

## L'icône du Dock et le plein écran

macOS ne laisse une fenêtre flotter au-dessus d'une app en plein écran que si l'app n'a **pas d'icône dans le Dock**. C'est pourquoi l'icône du Dock est **décochée par défaut** (« Icône dans le Dock » dans les réglages). Si tu l'actives, la fenêtre de paroles ne s'affiche plus au-dessus d'une app en plein écran (elle reste au-dessus des fenêtres normales). À toi de choisir ce qui compte le plus.

## Raccourci clavier

Sur Windows, le raccourci par défaut est **Ctrl+Alt+Maj+L** (modifiable dans les réglages) ; il cache ou montre la fenêtre et sort aussi du clic-à-travers. Sur Mac, **⌃⌥⌘L** (Contrôle, Option, Commande, L) cache ou montre la fenêtre. **En mode clic-à-travers, il fait autre chose :** il désactive le clic-à-travers et montre la fenêtre (il ne la cache jamais), parce que dans ce mode la fenêtre ne reçoit plus aucun clic et que tu ne pourrais pas ouvrir les réglages ; et sur un MacBook à encoche, l'icône de la barre de menus peut être cachée derrière l'encoche quand la barre est pleine. Clic-à-travers désactivé, il cache ou montre comme d'habitude. Relancer l'app (Spotlight, Finder) sort aussi du clic-à-travers. Il se change dans le volet de réglages (bouton ⚙ de la fenêtre, visible quand le pointeur la survole). Si le système ne peut pas enregistrer la combinaison, le volet affiche « raccourci indisponible » et l'ancienne reste active.

## Compiler depuis les sources

Il te faut seulement les **Command Line Tools** de Xcode (pas Xcode complet) avec Swift 6, sous macOS 26 ou plus récent. Aucune dépendance n'est téléchargée.

```sh
git clone https://github.com/MalikChopa/lyra-lyrics.git
cd lyra-lyrics
swift build                 # build debug de toutes les cibles
scripts/test.sh             # tests unitaires (Swift Testing) ; la dernière ligne dit quel chemin a servi
scripts/bundle.sh           # build release -> .build/bundle/LyraLyrics.app
scripts/package.sh          # zip -> .build/dist/Lyra-Lyrics-<version>-macOS.zip, avec son SHA-256
```

- **Signature** : `scripts/bundle.sh` signe avec le premier certificat local de signature de code qu'il trouve dans ton trousseau, en cherchant `PF_SIGN_IDENTITY` (si tu la définis) puis « Lyra Lyrics Code », et affiche lequel il a utilisé ; il **retombe sur une signature ad hoc** s'il n'en existe aucun. C'est suffisant pour l'utiliser chez toi, mais avec une signature ad hoc macOS peut redemander l'autorisation Automatisation après chaque recompilation.
- **Renommer l'app** : modifie la seule ligne `displayName` de `Sources/LyricsCore/AppIdentity.swift` ; l'identifiant de bundle est dans `Resources/Info.plist` et `scripts/bundle.sh`.
- Le build debug a des drapeaux de ligne de commande pour les tests (faux lecteur, faux serveur LRCLIB, `--snapshot`) ; le build release ne les contient pas. Voir `scripts/run-app-test.sh` et `Fixtures/selftests/`. Les commentaires du code sont en français.
- `scripts/ear-check.sh` aide à vérifier la synchro à l'oreille sur Spotify.

### Windows

Il te faut le **SDK .NET 10**. Aucun autre paquet n'est téléchargé que ceux de .NET lui-même.

```sh
dotnet test windows/LyraLyrics.Core.Tests     # tests du cœur (portable, tourne aussi sur Mac et Linux)
dotnet build windows/LyraLyrics.App -c Release
dotnet publish windows/LyraLyrics.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
```

L'app WPF ne s'exécute que sous Windows. L'installateur est un script Inno Setup 6 (`windows/installer/LyraLyrics.iss`) construit par la CI GitHub (`.github/workflows/windows-release.yml`), jamais sur un Mac. Le détail est dans `docs/windows/`.

## Limites connues

- **Morceaux en streaming dans Apple Music : non vérifié.** On n'a pas établi si Musique donne une position utilisable pour les titres lus depuis le catalogue (et non depuis ta bibliothèque) ; la synchro peut manquer ou être décalée pour eux.
- **Spotify : lire sa position demande l'autorisation Automatisation** (voir plus haut) ; sans elle, l'app suit seulement les changements de morceau.
- **Couleurs de la pochette : non vérifiées avec une vraie pochette.** Elles ont été testées avec des images inventées (chemin Apple Music, et chemin Spotify contre un serveur de test local). L'hôte d'images de Spotify (`i.scdn.co`) et les Apple events qui lisent la pochette et pilotent la lecture viennent des dictionnaires de script des apps et n'ont pas été essayés sur un vrai lecteur. Le contraste de 4,5 : 1 est calculé contre la teinte comme une couleur opaque ; sur les styles verre et transparent, le vrai fond derrière la fenêtre est inconnu.
- **Boutons de lecture et invite d'autorisation depuis les boutons : non vérifiés sur un vrai lecteur** (testés avec une autorisation et un envoi simulés ; la vraie invite et les vrais Apple events restent à vérifier à la main).
- **Redimensionnement** : la forme du curseur sur les zones de prise et un vrai glissement à la souris n'ont pas été vérifiés à l'écran (l'essai automatique envoie des événements souris synthétiques).
- **Texte brut** (non synchronisé) : il défile en bloc, ce qui coûte environ 2 % de processeur pendant le défilement.
- **Disponibilité de LRCLIB.** Le service est communautaire et gratuit : il répond parfois « occupé » (HTTP 503, mesuré sur 7 titres connus sur 22 à la première demande) ou n'a pas de paroles pour un titre. Depuis la 1.0.1, une requête en échec passe tout de suite à la recherche et l'app réessaie seule (« Service de paroles occupé », avec compte à rebours et bouton **Réessayer**) ; « Paroles indisponibles » veut maintenant dire que LRCLIB n'a vraiment rien.
- **Interface en français seulement** ; sur Mac : **Apple silicon seulement** et **macOS 26 ou plus seulement**.
- **Niveau de test** : la logique est couverte par des tests unitaires et par des essais automatiques avec un lecteur et un serveur simulés. Les vrais lecteurs ont été essayés sur un seul Mac (macOS 27). La synchro a été vérifiée **à l'oreille** sur Spotify par l'auteur, sans mesure chiffrée. Les chiffres de processeur viennent d'un lecteur simulé sur un Mac.
- Non notariée : macOS te demande de confirmer le premier lancement.
- **Windows (bêta) : jamais essayée sur un vrai PC avant sa publication.** L'installateur, le raccourci, la désinstallation, l'affichage de la fenêtre (fond, clic-à-travers, redimensionnement, plusieurs écrans, mise à l'échelle), la détection de Spotify par le contrôle multimédia (y compris la version du Microsoft Store), le raccourci global, l'icône de notification, le lancement au démarrage et la vérification de mise à jour ne sont vérifiés que par des tests sur Mac et par la lecture du code ; le workflow CI qui construit l'installateur n'avait jamais tourné avant la première release.
- **Windows : Scène jamais vue sur un vrai écran** avant la 1.3.0 (rendu vérifié seulement par compilation et, si l'exécuteur de GitHub sait dessiner, par des captures faites avec des paroles inventées) ; **Spotify seulement**, installateur **non signé** (SmartScreen, voir [Installation](#installation)), publicités Spotify traitées comme « Rien en lecture » par une heuristique non vérifiée, Windows sur Arm non vérifié.

## Crédits et droits

- Les paroles viennent de **[LRCLIB](https://lrclib.net)**, base communautaire. Lyra Lyrics est une app indépendante, **non affiliée** à LRCLIB, Spotify, Apple ou Microsoft ; les noms Spotify, Apple Music et Windows ne servent qu'à décrire la compatibilité.
- **Les paroles appartiennent à leurs auteurs et éditeurs.** Elles sont affichées ici pour un **usage personnel**, seulement pour le morceau que tu écoutes ; l'app (Mac comme Windows) ne les stocke jamais sur le disque, ne les envoie nulle part et ne les redistribue pas. Les captures de ce README n'en contiennent que d'inventées. Si tu trouves un problème avec des paroles, signale-le à LRCLIB.
- L'icône de l'app est dessinée par du code (voir `scripts/make-icon-proposals.swift`) ; aucun visuel n'a été copié.

## Licence

[MIT](LICENSE), Copyright (c) 2026 Chopa. Voir aussi le [journal des versions](CHANGELOG.md) (en anglais).
