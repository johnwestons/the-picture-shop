param(
    [string]$PackagePath,
    [string]$LoveRoot = 'C:\Program Files\LOVE',
    [string]$InnoCompiler,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$windowsRoot = Join-Path $projectRoot 'output\windows'
$stageRoot = Join-Path $windowsRoot 'stage'
$configPath = Join-Path $projectRoot 'mobile\config.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json

function Find-Python {
    $candidates = @(
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
    )
    foreach ($name in @('python.exe', 'python', 'py.exe', 'py')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        & $candidate -c 'import PIL, sys; sys.exit(0)' 2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'Python with Pillow is required to build the Windows icon.'
}

function Find-InnoCompiler {
    if ($InnoCompiler) {
        if (-not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) {
            throw "Inno Setup compiler not found: $InnoCompiler"
        }
        return (Resolve-Path -LiteralPath $InnoCompiler).Path
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    $candidates += @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Inno Setup 6 is required. Install JRSoftware.InnoSetup with winget.'
}

function Reset-Stage {
    $resolvedWindows = [IO.Path]::GetFullPath($windowsRoot)
    $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
    if ([IO.Path]::GetDirectoryName($resolvedStage) -ne $resolvedWindows) {
        throw "Refusing to reset unexpected stage directory: $resolvedStage"
    }
    if (Test-Path -LiteralPath $resolvedStage) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolvedStage -Force | Out-Null
}

function Get-PeMachine([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 256 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw "$Path is not a Windows executable."
    }
    $header = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($header -lt 0 -or $header + 6 -gt $bytes.Length) {
        throw "$Path has an invalid PE header."
    }
    return [BitConverter]::ToUInt16($bytes, $header + 4)
}

function Add-FileToStream([IO.Stream]$Destination, [string]$Path) {
    $source = [IO.File]::OpenRead($Path)
    try { $source.CopyTo($Destination) } finally { $source.Dispose() }
}

$versionMatch = [regex]::Match([string]$config.versionName, '^(\d+)\.(\d+)\.(\d+)-android\.(\d+)$')
if (-not $versionMatch.Success) {
    throw 'mobile/config.json versionName must use X.Y.Z-android.N for tester packaging.'
}
$numericVersion = '{0}.{1}.{2}.{3}' -f $versionMatch.Groups[1].Value,
    $versionMatch.Groups[2].Value, $versionMatch.Groups[3].Value,
    $versionMatch.Groups[4].Value
$displayVersion = '{0}.{1}.{2}-test.{3}' -f $versionMatch.Groups[1].Value,
    $versionMatch.Groups[2].Value, $versionMatch.Groups[3].Value,
    $versionMatch.Groups[4].Value
$outputName = "ThePictureShop-Windows-Setup-$displayVersion"

$python = Find-Python
if (-not $PackagePath) {
    & $python (Join-Path $projectRoot 'tools\build_mobile_package.py')
    if ($LASTEXITCODE -ne 0) { throw 'Shared game package build failed.' }
    $PackagePath = (Get-Content -Raw -LiteralPath (
        Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json).package
}
$package = (Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($package) -ne '.love') {
    throw 'PackagePath must point to a .love package.'
}

$loveExecutable = Join-Path $LoveRoot 'love.exe'
if (-not (Test-Path -LiteralPath $loveExecutable -PathType Leaf)) {
    throw "LÖVE runtime was not found at $LoveRoot"
}
if ((Get-PeMachine $loveExecutable) -ne 0x8664) {
    throw 'The Windows tester package requires the 64-bit LÖVE runtime.'
}
$runtimeFiles = @(
    'love.dll', 'lua51.dll', 'mpg123.dll', 'msvcp120.dll', 'msvcr120.dll',
    'OpenAL32.dll', 'SDL2.dll', 'license.txt'
)
foreach ($name in $runtimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $LoveRoot $name) -PathType Leaf)) {
        throw "LÖVE runtime is missing $name"
    }
}

New-Item -ItemType Directory -Path $windowsRoot -Force | Out-Null
Reset-Stage
foreach ($name in $runtimeFiles) {
    Copy-Item -LiteralPath (Join-Path $LoveRoot $name) -Destination $stageRoot
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'packaging\windows\README-TESTERS.txt') `
    -Destination $stageRoot
$iconPath = Join-Path $stageRoot 'ThePictureShop.ico'
& $python (Join-Path $projectRoot 'tools\build_windows_icon.py') `
    (Join-Path $projectRoot 'mobile\android\polar-cutter-launcher.png') $iconPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $iconPath)) {
    throw 'Windows icon build failed.'
}

$gameExecutable = Join-Path $stageRoot 'ThePictureShop.exe'
$destination = [IO.File]::Create($gameExecutable)
try {
    Add-FileToStream $destination $loveExecutable
    Add-FileToStream $destination $package
} finally {
    $destination.Dispose()
}
if ((Get-PeMachine $gameExecutable) -ne 0x8664) {
    throw 'The fused game executable is not x64.'
}

$smokeReport = Join-Path $windowsRoot 'windows-package-smoke.rpt'
$stdoutPath = Join-Path $windowsRoot 'windows-package-smoke-out.txt'
$stderrPath = Join-Path $windowsRoot 'windows-package-smoke-err.txt'
Remove-Item -LiteralPath $smokeReport, $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
$previousSmoke = $env:PICTURE_SHOP_SMOKE
$previousReport = $env:PICTURE_SHOP_SMOKE_REPORT
try {
    $env:PICTURE_SHOP_SMOKE = '1'
    $env:PICTURE_SHOP_SMOKE_REPORT = $smokeReport
    $process = Start-Process -FilePath $gameExecutable -WorkingDirectory $stageRoot `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -WindowStyle Hidden -PassThru
    $null = $process.Handle
    if (-not $process.WaitForExit(90000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Fused Windows game smoke test timed out.'
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $errorText = if (Test-Path -LiteralPath $stderrPath) {
            (Get-Content -Raw -LiteralPath $stderrPath).Trim()
        } else { '' }
        throw "Fused Windows game smoke test failed with exit code $($process.ExitCode): $errorText"
    }
    if (-not (Test-Path -LiteralPath $smokeReport)) {
        throw 'Fused Windows game did not produce a smoke report.'
    }
    $failures = @(Select-String -LiteralPath $smokeReport -Pattern '^FAIL(?:\s|$)')
    if ($failures.Count -gt 0) {
        throw "Fused Windows game reported $($failures.Count) failed checks."
    }
} finally {
    if ($null -eq $previousSmoke) { Remove-Item Env:PICTURE_SHOP_SMOKE -ErrorAction SilentlyContinue }
    else { $env:PICTURE_SHOP_SMOKE = $previousSmoke }
    if ($null -eq $previousReport) { Remove-Item Env:PICTURE_SHOP_SMOKE_REPORT -ErrorAction SilentlyContinue }
    else { $env:PICTURE_SHOP_SMOKE_REPORT = $previousReport }
}

$installerPath = $null
if (-not $SkipInstaller) {
    $compiler = Find-InnoCompiler
    $installerPath = Join-Path $windowsRoot ($outputName + '.exe')
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    $definitionArguments = @(
        "/DStageDir=$stageRoot",
        "/DOutputDir=$windowsRoot",
        "/DAppVersion=$displayVersion",
        "/DNumericVersion=$numericVersion",
        "/DOutputName=$outputName",
        "/DAppIcon=$iconPath",
        (Join-Path $projectRoot 'packaging\windows\ThePictureShop.iss')
    )
    & $compiler @definitionArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $installerPath)) {
        throw 'Windows installer compilation failed.'
    }
    if ((Get-PeMachine $installerPath) -notin @(0x014c, 0x8664)) {
        throw 'The generated installer has an unexpected executable architecture.'
    }
}

$head = (& git -C $projectRoot rev-parse HEAD 2>$null | Out-String).Trim()
$sourceDirty = [bool]((& git -C $projectRoot status --porcelain | Out-String).Trim())
$stageFiles = @(Get-ChildItem -LiteralPath $stageRoot -File | Sort-Object Name | ForEach-Object {
    [ordered]@{
        name = $_.Name
        bytes = $_.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    }
})
$report = [ordered]@{
    schemaVersion = 1
    applicationName = 'The Picture Shop'
    version = $displayVersion
    numericVersion = $numericVersion
    architecture = 'windows-x64'
    loveVersion = [string]$config.loveVersion
    sourceCommit = $head
    sourceDirty = $sourceDirty
    package = $package
    packageSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $package).Hash.ToLowerInvariant()
    gameExecutable = $gameExecutable
    gameExecutableBytes = (Get-Item -LiteralPath $gameExecutable).Length
    gameExecutableSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $gameExecutable).Hash.ToLowerInvariant()
    smokeChecks = @(Select-String -LiteralPath $smokeReport -Pattern '^PASS(?:\s|$)').Count
    stageFiles = $stageFiles
    installer = $installerPath
    installerBytes = if ($installerPath) { (Get-Item -LiteralPath $installerPath).Length } else { $null }
    installerSha256 = if ($installerPath) {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash.ToLowerInvariant()
    } else { $null }
    signed = if ($installerPath) {
        (Get-AuthenticodeSignature -LiteralPath $installerPath).Status -eq 'Valid'
    } else { $false }
    perUserInstall = $true
    preservesSavesOnUninstall = $true
    firewallRuleAdded = $false
}
$reportPath = Join-Path $windowsRoot 'windows-build-report.json'
[IO.File]::WriteAllText(
    $reportPath,
    (($report | ConvertTo-Json -Depth 8) + "`n"),
    [Text.UTF8Encoding]::new($false)
)
Write-Output "WINDOWS_GAME_EXE=$gameExecutable"
if ($installerPath) { Write-Output "WINDOWS_INSTALLER=$installerPath" }
Write-Output "WINDOWS_REPORT=$reportPath"
