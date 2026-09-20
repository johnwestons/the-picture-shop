#ifndef StageDir
  #error StageDir must be supplied by the build script.
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by the build script.
#endif
#ifndef AppVersion
  #error AppVersion must be supplied by the build script.
#endif
#ifndef NumericVersion
  #error NumericVersion must be supplied by the build script.
#endif
#ifndef OutputName
  #error OutputName must be supplied by the build script.
#endif
#ifndef AppIcon
  #error AppIcon must be supplied by the build script.
#endif

[Setup]
AppId={{D2FE5B9E-971E-49C7-BDC4-A6772B413417}
AppName=The Picture Shop
AppVersion={#AppVersion}
AppVerName=The Picture Shop {#AppVersion}
VersionInfoVersion={#NumericVersion}
VersionInfoProductName=The Picture Shop
VersionInfoDescription=The Picture Shop tester installer
VersionInfoCompany=The Picture Shop
DefaultDirName={localappdata}\Programs\The Picture Shop
DefaultGroupName=The Picture Shop
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\ThePictureShop.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\The Picture Shop"; Filename: "{app}\ThePictureShop.exe"; IconFilename: "{app}\ThePictureShop.ico"
Name: "{autodesktop}\The Picture Shop"; Filename: "{app}\ThePictureShop.exe"; IconFilename: "{app}\ThePictureShop.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\ThePictureShop.exe"; Description: "Launch The Picture Shop"; Flags: nowait postinstall skipifsilent
