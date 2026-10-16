; Artha for Windows: Inno Setup script. The release workflow builds the app
; (flutter build windows) and compiles this with
;   iscc /DAppVersion=0.1.0 windows\installer\artha.iss
; Installs for the current user by default (no admin prompt). Uninstalling
; leaves the encrypted data in %APPDATA%\Artha alone.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define Release "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{E08F3DAF-D71C-41CD-8B56-B177B7B4C216}
AppName=Artha
AppVersion={#AppVersion}
AppVerName=Artha {#AppVersion}
AppPublisher=Rajeev Sudharamachandran
DefaultDirName={autopf}\Artha
DefaultGroupName=Artha
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=Artha-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\artha.exe
UninstallDisplayName=Artha
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
; Windows 10 1809 or later (and Windows 11)
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Artha"; Filename: "{app}\artha.exe"; Comment: "Personal finance"
Name: "{autodesktop}\Artha"; Filename: "{app}\artha.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\artha.exe"; Description: "{cm:LaunchProgram,Artha}"; Flags: nowait postinstall skipifsilent
