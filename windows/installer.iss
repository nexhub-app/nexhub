; NexHub Windows 安装包脚本（Inno Setup 6）
; AppVersion 由 CI 通过 `iscc installer.iss /DMyAppVersion=<tag>` 注入。
; 产物：NexHub-windows-setup.exe

[Setup]
AppName=NexHub
AppVersion={#MyAppVersion}
AppPublisher=NexHub
DefaultDirName={autopf}\NexHub
DefaultGroupName=NexHub
OutputDir=.
OutputBaseFilename=NexHub-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64
UninstallDisplayIcon={app}\NexHub.exe
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NexHub"; Filename: "{app}\NexHub.exe"
Name: "{autodesktop}\NexHub"; Filename: "{app}\NexHub.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"

[Run]
Filename: "{app}\NexHub.exe"; Description: "运行 NexHub"; Flags: nowait postinstall skipifdoesntexist
