[Setup]
AppId=com.example.ai_tools
AppName=AI Tools
AppVersion={#ReleaseVersion}
DefaultDirName={autopf}\AI Tools
DefaultGroupName=AI Tools
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\ai_tools.exe
SetupIconFile=..\runner\resources\app_icon.ico
OutputBaseFilename=AI-Tools-Windows-x64-Setup
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AI Tools"; Filename: "{app}\ai_tools.exe"
Name: "{autodesktop}\AI Tools"; Filename: "{app}\ai_tools.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ai_tools.exe"; Description: "Abrir AI Tools"; Flags: nowait postinstall skipifsilent
