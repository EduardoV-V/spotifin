; Instalador do Spotifin (Inno Setup). Parâmetros vindos do workflow:
;   /DAppVersion=1.0.0 /DSourceDir=<pasta Release> /DOutputDir=<saída> /DOutputName=<nome do exe>
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6E0C5C2D-3B7B-4C55-9F0E-5A1C7D2B9A11}
AppName=Spotifin
AppVersion={#AppVersion}
AppPublisher=Eduardo Valente
DefaultDirName={autopf}\Spotifin
DefaultGroupName=Spotifin
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\spotifin.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Spotifin"; Filename: "{app}\spotifin.exe"
Name: "{autodesktop}\Spotifin"; Filename: "{app}\spotifin.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\spotifin.exe"; Description: "{cm:LaunchProgram,Spotifin}"; Flags: nowait postinstall skipifsilent
