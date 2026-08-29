param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [switch]$Install,
    [string]$DeviceSerial
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($DeviceSerial) {
    $DeviceSerial = $DeviceSerial.Trim()
    if (-not $Install) { throw '-DeviceSerial requires -Install.' }
    if (-not $DeviceSerial -or $DeviceSerial -match '\s|[\x00-\x1F\x7F]') {
        throw 'Android device serial contains invalid characters.'
    }
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot 'output\mobile'
$toolingRoot = Join-Path $outputRoot 'tooling'
$androidRoot = Join-Path $toolingRoot 'android-sdk'
$jdkRoot = Join-Path $toolingRoot 'jdk-17'
$loveAndroidRoot = Join-Path $outputRoot 'love-android'
$config = Get-Content -Raw (Join-Path $projectRoot 'mobile\config.json') | ConvertFrom-Json
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$sharedMobile = Join-Path (Split-Path $projectRoot -Parent) 'Mouse Frontier 8.10\output\mobile'

New-Item -ItemType Directory -Force -Path $outputRoot,$toolingRoot | Out-Null

function Get-VerifiedDownload {
    param([string]$Uri,[string]$Destination,[string]$Hash)
    if (-not (Test-Path -LiteralPath $Destination)) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
    }
    $algorithm = if ($Hash.Length -eq 40) { 'SHA1' } else { 'SHA256' }
    if ((Get-FileHash -Algorithm $algorithm -LiteralPath $Destination).Hash -ne $Hash) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Checksum verification failed for $Uri"
    }
}

if (-not (Test-Path -LiteralPath $jdkRoot)) {
    $sharedJdk = Join-Path $sharedMobile 'tooling\jdk-17'
    if (Test-Path -LiteralPath $sharedJdk) {
        New-Item -ItemType Junction -Path $jdkRoot -Target $sharedJdk | Out-Null
    }
    else {
        Write-Output 'Downloading verified JDK 17 build tooling...'
        $metadata = Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
        $package = $metadata[0].binary.package
        $archive = Join-Path $toolingRoot 'jdk-17.zip'
        Get-VerifiedDownload -Uri $package.link -Destination $archive -Hash $package.checksum
        New-Item -ItemType Directory -Force -Path $jdkRoot | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $jdkRoot -Force
    }
}

if (-not (Test-Path -LiteralPath $androidRoot)) {
    $sharedSdk = Join-Path $sharedMobile 'tooling\android-sdk'
    if (Test-Path -LiteralPath $sharedSdk) {
        New-Item -ItemType Junction -Path $androidRoot -Target $sharedSdk | Out-Null
    }
    else {
        Write-Output 'Downloading verified Android command-line tooling...'
        $archive = Join-Path $toolingRoot 'android-command-line-tools-12.zip'
        Get-VerifiedDownload -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -Destination $archive -Hash '3d2917302740f476999a091bc5558837c7a863c5'
        $extractRoot = Join-Path $toolingRoot 'android-command-line-tools-extract'
        New-Item -ItemType Directory -Force -Path $extractRoot,$androidRoot | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
        $versionedRoot = Join-Path $androidRoot 'cmdline-tools\12.0'
        New-Item -ItemType Directory -Force -Path $versionedRoot | Out-Null
        Copy-Item -Path (Join-Path $extractRoot 'cmdline-tools\*') -Destination $versionedRoot -Recurse -Force
    }
}

$javaExecutable = Get-ChildItem $jdkRoot -Recurse -Filter java.exe | Select-Object -First 1 -ExpandProperty FullName
if (-not $javaExecutable) { throw 'JDK 17 could not be located' }
$javaHome = Split-Path (Split-Path $javaExecutable -Parent) -Parent
$sdkManager = Join-Path $androidRoot 'cmdline-tools\12.0\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath (Join-Path $androidRoot 'platform-tools\adb.exe'))) {
    $previousJavaHome = $env:JAVA_HOME
    try {
        $env:JAVA_HOME = $javaHome
        1..100 | ForEach-Object { 'y' } | & $sdkManager --sdk_root=$androidRoot --licenses | Out-Null
        & $sdkManager --sdk_root=$androidRoot 'platform-tools' 'platforms;android-34' 'build-tools;35.0.0' 'ndk;25.2.9519653'
        if ($LASTEXITCODE -ne 0) { throw "Android SDK setup failed with exit code $LASTEXITCODE" }
    }
    finally { $env:JAVA_HOME = $previousJavaHome }
}

if (-not (Test-Path -LiteralPath (Join-Path $loveAndroidRoot 'gradlew.bat'))) {
    Write-Output 'Creating the local LÖVE Android wrapper...'
    & git clone --recurse-submodules --depth 1 --branch $config.loveVersion https://github.com/love2d/love-android.git $loveAndroidRoot
    if ($LASTEXITCODE -ne 0) { throw "LÖVE Android checkout failed with exit code $LASTEXITCODE" }
}

$gameActivityPath = Join-Path $loveAndroidRoot 'love\src\main\java\org\love2d\android\GameActivity.java'
$gameActivity = Get-Content -Raw -LiteralPath $gameActivityPath
if ($gameActivity -notmatch 'PICTURE_SHOP_LANDSCAPE_LOCK') {
    $replacement = @'
public class GameActivity extends SDLActivity {
    // PICTURE_SHOP_LANDSCAPE_LOCK
    @Override
    public void setOrientationBis(int width, int height, boolean resizable, String hint) {
        setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }
'@
    $gameActivity = $gameActivity.Replace('public class GameActivity extends SDLActivity {',$replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_EMBEDDED_GAME') {
    $replacement = @'
        embed = getResources().getBoolean(R.bool.embed);
        // PICTURE_SHOP_EMBEDDED_GAME
        if (embed) {
            needToCopyGameInArchive = true;
        }
'@
    $gameActivity = $gameActivity.Replace('        embed = getResources().getBoolean(R.bool.embed);',$replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_GAME_CACHE') {
    $replacement = @'
    private void copyGameInsideArchive() {
        // PICTURE_SHOP_GAME_CACHE
        File cachedGame = new File(this.getCacheDir(), "game.love");
        File installedApk = new File(this.getApplicationInfo().sourceDir);
        if (cachedGame.isFile() && cachedGame.length() > 0 && cachedGame.lastModified() >= installedApk.lastModified()) {
            gamePath = cachedGame.getPath();
            storagePermissionUnnecessary = true;
            Log.d("GameActivity", "Reusing cached embedded game: " + gamePath);
            return;
        }
'@
    $gameActivity = $gameActivity.Replace('    private void copyGameInsideArchive() {',$replacement.TrimEnd())
}
if ($gameActivity -notmatch 'PICTURE_SHOP_STATIC_LIBCPP') {
    $gameActivity = $gameActivity.Replace('            "c++_shared",',
        '            // PICTURE_SHOP_STATIC_LIBCPP: linked into each native library.')
}
foreach ($marker in @('PICTURE_SHOP_LANDSCAPE_LOCK','PICTURE_SHOP_EMBEDDED_GAME','PICTURE_SHOP_GAME_CACHE','PICTURE_SHOP_STATIC_LIBCPP')) {
    if ($gameActivity -notmatch $marker) { throw "Android wrapper patch failed: $marker" }
}
[System.IO.File]::WriteAllText($gameActivityPath,$gameActivity,[System.Text.UTF8Encoding]::new($false))

# LÖVE Android 11.5 predates Android's 16 KB page-size requirement. Rebuild
# every native library with Android's documented r27-and-earlier linker flags.
# Static libc++ avoids bundling NDK r25's own 4 KB-only libc++_shared.so.
$applicationMkPath = Join-Path $loveAndroidRoot 'love\src\jni\Application.mk'
$applicationMk = Get-Content -Raw -LiteralPath $applicationMkPath
$originalApplicationMk = $applicationMk
$applicationMk = $applicationMk -replace '(?m)^APP_STL := c\+\+_shared\r?$','APP_STL := c++_static'
$applicationMk = $applicationMk -replace '(?m)^APP_LDFLAGS :=.*\r?$',
    'APP_LDFLAGS := -llog -landroid -lz -fuse-ld=lld -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384'
if ($applicationMk -notmatch 'APP_STL := c\+\+_static' -or $applicationMk -notmatch 'max-page-size=16384') {
    throw 'Unable to apply Android 16 KB native-library compatibility settings'
}
if ($applicationMk -ne $originalApplicationMk) {
    [System.IO.File]::WriteAllText($applicationMkPath,$applicationMk,[System.Text.UTF8Encoding]::new($false))
}

$embedAssets = Join-Path $loveAndroidRoot 'app\src\embed\assets'
New-Item -ItemType Directory -Force -Path $embedAssets | Out-Null
Copy-Item -LiteralPath $resolvedPackage -Destination (Join-Path $embedAssets 'game.love') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'mobile\android\AndroidManifest.xml') -Destination (Join-Path $loveAndroidRoot 'app\src\embed\AndroidManifest.xml') -Force
$androidResources = Join-Path $outputRoot 'android-res'
if (Test-Path -LiteralPath $androidResources) {
    Copy-Item -Path (Join-Path $androidResources '*') -Destination (Join-Path $loveAndroidRoot 'app\src\main\res') -Recurse -Force
}

$propertiesPath = Join-Path $loveAndroidRoot 'gradle.properties'
$properties = Get-Content -Raw $propertiesPath
$properties = $properties -replace '(?m)^app\.name_byte_array=.*$','# app.name_byte_array disabled for Picture Shop'
$properties = $properties -replace '(?m)^#?app\.name=.*$',("app.name=" + $config.applicationName)
$properties = $properties -replace '(?m)^app\.application_id=.*$',("app.application_id=" + $config.applicationId)
$properties = $properties -replace '(?m)^app\.orientation=.*$','app.orientation=landscape'
$properties = $properties -replace '(?m)^app\.version_code=.*$',("app.version_code=" + $config.versionCode)
$properties = $properties -replace '(?m)^app\.version_name=.*$',("app.version_name=" + $config.versionName)
if ($properties -notmatch '(?m)^org\.gradle\.jvmargs=') { $properties += "`r`norg.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8`r`n" }
[System.IO.File]::WriteAllText($propertiesPath,$properties,[System.Text.UTF8Encoding]::new($false))

$appBuildPath = Join-Path $loveAndroidRoot 'app\build.gradle'
$appBuild = Get-Content -Raw $appBuildPath
if ($appBuild -notmatch "noCompress 'love'") {
    $appBuild = $appBuild -replace 'android \{',"android {`r`n    aaptOptions { noCompress 'love' }"
    [System.IO.File]::WriteAllText($appBuildPath,$appBuild,[System.Text.UTF8Encoding]::new($false))
}

$previousJavaHome = $env:JAVA_HOME
$previousAndroidHome = $env:ANDROID_HOME
$previousAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$substDrive = $null
$buildLoveRoot = $loveAndroidRoot
$buildAndroidRoot = $androidRoot
$buildJavaHome = $javaHome
try {
    foreach ($candidate in @('M:','N:','O:','P:')) {
        if (-not (Test-Path ($candidate + '\'))) {
            & subst.exe $candidate $outputRoot
            if ($LASTEXITCODE -eq 0) { $substDrive = $candidate; break }
        }
    }
    if ($substDrive) {
        $buildLoveRoot = $substDrive + '\love-android'
        $buildAndroidRoot = $substDrive + '\tooling\android-sdk'
        $buildJavaHome = (Get-ChildItem ($substDrive + '\tooling\jdk-17') -Recurse -Filter java.exe | Select-Object -First 1).Directory.Parent.FullName
    }
    $env:JAVA_HOME = $buildJavaHome
    $env:ANDROID_HOME = $buildAndroidRoot
    $env:ANDROID_SDK_ROOT = $buildAndroidRoot

    Write-Output 'Building the Picture Shop Android APK...'
    & (Join-Path $buildLoveRoot 'gradlew.bat') --project-dir $buildLoveRoot --no-daemon :app:clean assembleEmbedNoRecordDebug
    if ($LASTEXITCODE -ne 0) { throw "Android APK build failed with exit code $LASTEXITCODE" }
}
finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_SDK_ROOT = $previousAndroidSdkRoot
    if ($substDrive) { & subst.exe $substDrive /D | Out-Null }
}

$builtApk = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\outputs\apk') -Recurse -Filter '*embed-noRecord-debug*.apk' | Select-Object -First 1
if (-not $builtApk) { $builtApk = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\outputs\apk') -Recurse -Filter '*.apk' | Select-Object -First 1 }
if (-not $builtApk) { throw 'Gradle completed without producing an APK' }
$apkPath = Join-Path $outputRoot ("ThePictureShop-" + $config.versionName + "-debug.apk")
Copy-Item -LiteralPath $builtApk.FullName -Destination $apkPath -Force

$archive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
try {
    $embeddedGame = $archive.GetEntry('assets/game.love')
    if (-not $embeddedGame) { throw 'APK is missing assets/game.love' }
    if ($embeddedGame.Length -ne (Get-Item -LiteralPath $resolvedPackage).Length) { throw 'Embedded game size does not match the package' }
}
finally { $archive.Dispose() }

$buildToolsRoot = Join-Path $androidRoot 'build-tools\35.0.0'
$apksigner = Join-Path $buildToolsRoot 'apksigner.bat'
$signatureJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $javaHome
    & $apksigner verify --verbose $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
}
finally { $env:JAVA_HOME = $signatureJavaHome }
$aapt = Join-Path $buildToolsRoot 'aapt.exe'
$badging = & $aapt dump badging $apkPath | Out-String
if ($badging -notmatch [regex]::Escape("package: name='$($config.applicationId)'")) { throw 'APK application ID verification failed' }
$permissionDump = & $aapt dump permissions $apkPath | Out-String
if ($LASTEXITCODE -ne 0) { throw 'APK permission inspection failed' }
$internetPermission = [regex]::IsMatch(
    $permissionDump,
    "(?m)^uses-permission(?:-sdk-\d+)?: name='android\.permission\.INTERNET'\s*$"
)
if (-not $internetPermission) { throw 'APK is missing required android.permission.INTERNET permission' }
$zipalign = Join-Path $buildToolsRoot 'zipalign.exe'
& $zipalign -c -P 16 -v 4 $apkPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'APK ZIP alignment is not compatible with 16 KB page-size devices' }
$readelf = Join-Path $androidRoot 'ndk\25.2.9519653\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
$arm64Libraries = Get-ChildItem (Join-Path $loveAndroidRoot 'app\build\intermediates\merged_native_libs') -Recurse -Filter '*.so' |
    Where-Object { $_.FullName -match 'embedNoRecordDebug' -and $_.FullName -match 'arm64-v8a' }
if (-not $arm64Libraries) { throw 'No ARM64 libraries were available for the 16 KB ELF audit' }
foreach ($library in $arm64Libraries) {
    if ($library.Name -eq 'libc++_shared.so') { throw 'APK still contains NDK r25 libc++_shared.so' }
    $loadSegments = @(& $readelf -l $library.FullName | Where-Object { $_ -match '^  LOAD' })
    $badSegments = @($loadSegments | Where-Object { $_ -notmatch '0x(?:4000|8000|10000)$' })
    if (-not $loadSegments -or $badSegments.Count -gt 0) {
        throw "$($library.Name) is not 16 KB ELF-aligned"
    }
}

$adb = Join-Path $androidRoot 'platform-tools\adb.exe'
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" })
$authorizedDeviceSerials = @($devices | ForEach-Object { ($_ -split '\s+')[0] })
$deviceLaunchVerified = $false
$installedDeviceSerial = $null
if ($Install) {
    if ($DeviceSerial) {
        if ($authorizedDeviceSerials -notcontains $DeviceSerial) {
            throw "Requested Android device '$DeviceSerial' is not authorized or connected."
        }
        $installedDeviceSerial = $DeviceSerial
    }
    else {
        if ($authorizedDeviceSerials.Count -ne 1) {
            throw "Expected one authorized Android device or -DeviceSerial, found $($authorizedDeviceSerials.Count)"
        }
        $installedDeviceSerial = $authorizedDeviceSerials[0]
    }
    $adbTarget = @('-s', $installedDeviceSerial)
    & $adb @adbTarget install -r $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'APK installation failed' }
    & $adb @adbTarget shell am force-stop $config.applicationId
    & $adb @adbTarget logcat -c
    & $adb @adbTarget shell am start -W -n "$($config.applicationId)/org.love2d.android.GameActivity"
    if ($LASTEXITCODE -ne 0) { throw 'Installed APK did not launch' }
    for ($attempt = 1; $attempt -le 45; $attempt++) {
        $deviceProcessId = (& $adb @adbTarget shell pidof $config.applicationId | Out-String).Trim()
        $log = (& $adb @adbTarget logcat -d -v brief | Out-String)
        if ($log -match '\[PICTURE SHOP\] Startup complete') { $deviceLaunchVerified = $true; break }
        if ($log -match 'FATAL EXCEPTION|stack traceback|Lua error') { throw 'Installed APK reported a startup error' }
        if (-not $deviceProcessId) { throw 'The Picture Shop process stopped during startup' }
        Start-Sleep -Seconds 1
    }
    if (-not $deviceLaunchVerified) { throw 'The installed app did not reach its startup marker' }
}

$report = [ordered]@{
    applicationId = $config.applicationId
    versionName = $config.versionName
    versionCode = $config.versionCode
    apk = $apkPath
    apkBytes = (Get-Item -LiteralPath $apkPath).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash.ToLowerInvariant()
    signed = $true
    internetPermission = $internetPermission
    sixteenKbCompatible = $true
    connectedAndroidDevices = $devices.Count
    installedDeviceSerial = $installedDeviceSerial
    deviceLaunchVerified = $deviceLaunchVerified
}
[System.IO.File]::WriteAllText((Join-Path $outputRoot 'apk-report.json'),($report | ConvertTo-Json) + "`n",[System.Text.UTF8Encoding]::new($false))
Write-Output "ANDROID_APK=$apkPath"
Write-Output "INTERNET_PERMISSION=$internetPermission"
Write-Output "CONNECTED_ANDROID_DEVICES=$($devices.Count)"
if ($installedDeviceSerial) { Write-Output "INSTALLED_DEVICE_SERIAL=$installedDeviceSerial" }
Write-Output "DEVICE_LAUNCH_VERIFIED=$deviceLaunchVerified"
