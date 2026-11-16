; Installateur de Lyra Lyrics (Inno Setup 6) : par utilisateur, sans droits d'administrateur.
; Compilation (voir docs/windows/INSTALLER-WINDOWS.md) :
;   ISCC.exe /DAppVersion=1.2.0 /DPublishDir=<dossier contenant LyraLyrics.exe> /O<dossier de sortie> windows\installer\LyraLyrics.iss
; Ce fichier est enregistré en UTF-8 AVEC marque d'ordre des octets : sans elle, Inno Setup lit les accents en ANSI.

#ifndef AppVersion
  #error "AppVersion manquant : passer /DAppVersion=X.Y.Z (même numéro que windows/Directory.Build.props)"
#endif
#ifndef PublishDir
  #error "PublishDir manquant : passer /DPublishDir=<dossier de LyraLyrics.exe>"
#endif
#define AppName "Lyra Lyrics"
#define AppExe "LyraLyrics.exe"
#define RepoRoot AddBackslash(SourcePath) + "..\.."

[Setup]
; Identifiant stable de l'application (jamais modifié : c'est lui qui relie une mise à jour à l'installation précédente).
AppId={{318F5B4D-2FF1-4733-8750-0E7771DB70D6}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppName}
AppPublisherURL=https://github.com/MalikChopa/lyra-lyrics
AppSupportURL=https://github.com/MalikChopa/lyra-lyrics/issues
AppUpdatesURL=https://github.com/MalikChopa/lyra-lyrics/releases
; Par utilisateur : aucun droit d'administrateur, aucune fenêtre UAC, aucune écriture sous HKLM ni dans Program Files.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputBaseFilename=Lyra-Lyrics-{#AppVersion}-windows-x64-setup
LicenseFile={#RepoRoot}\LICENSE
SetupIconFile={#RepoRoot}\windows\LyraLyrics.App\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} (installation)
WizardStyle=modern
ShowLanguageDialog=auto
; L'arrêt de l'application est fait par le script (section [Code]) : le gestionnaire de redémarrage de Windows n'intervient pas.
CloseApplications=no
RestartApplications=no
Compression=lzma2/fast
SolidCompression=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
french.LaunchLyra=Lancer Lyra Lyrics
english.LaunchLyra=Launch Lyra Lyrics
french.AskDeleteData=Supprimer aussi les réglages, le cache d'index et le journal de Lyra Lyrics ?%n%nDossier : %1%n%nChoisir « Non » les conserve (utile si vous réinstallez plus tard).
english.AskDeleteData=Also delete the Lyra Lyrics settings, lookup cache and log?%n%nFolder: %1%n%nChoosing "No" keeps them (useful if you reinstall later).

[Files]
Source: "{#PublishDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci du menu Démarrer (par utilisateur : « {autoprograms} » = menu Démarrer de l'utilisateur quand les droits d'administrateur ne sont pas demandés).
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchLyra}"; Flags: nowait postinstall skipifsilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunValue = 'LyraLyrics';          // même nom que StartupRegistration.cs

// Demande d'abord la fermeture normale, puis force si l'application est encore là. Les paramètres sont des constantes : aucun texte venant de l'extérieur.
procedure StopLyra;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(1500);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(500);
end;

// Installation ou mise à jour : l'exécutable ne doit pas tourner pendant la copie.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopLyra;
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usUninstall then
    StopLyra                                   // avant la suppression des fichiers
  else if CurUninstallStep = usPostUninstall then
  begin
    // Lancement à la connexion (clé écrite par l'application, jamais par l'installateur) : supprimée si elle existe.
    RegDeleteValue(HKEY_CURRENT_USER, RunKey, RunValue);
    // Réglages, index, journal : conservés par défaut ; effacés seulement sur réponse « Oui » (jamais en désinstallation silencieuse).
    DataDir := ExpandConstant('{userappdata}\LyraLyrics');
    if (not UninstallSilent) and DirExists(DataDir) then
      if MsgBox(FmtMessage(CustomMessage('AskDeleteData'), [DataDir]), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
