param(
    [string]$InstallerPath = (Join-Path $PSScriptRoot '..\output\windows\ThePictureShop-Windows-Setup-0.1.0-test.16.exe')
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$windowsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'output\windows'))
$installer = (Resolve-Path -LiteralPath $InstallerPath -ErrorAction Stop).Path
$testRoot = Join-Path $windowsRoot ('install-test-' + [guid]::NewGuid().ToString('N'))
$saveRoot = Join-Path $env:APPDATA 'LOVE\the-picture-shop'

function Assert-TestPath([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $windowsRoot -or
        [IO.Path]::GetFileName($resolved) -notlike 'install-test-*') {
        throw "Refusing to use unexpected installer test directory: $resolved"
    }
    return $resolved
}

function Save-Fingerprint {
    if (-not (Test-Path -LiteralPath $saveRoot)) { return 'absent' }
    $records = @(Get-ChildItem -LiteralPath $saveRoot -File -Recurse | Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($saveRoot.Length).TrimStart('\')
            "$relative|$($_.Length)|$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)"
        })
    return ($records -join "`n")
}

function Invoke-CheckedProcess([string]$FilePath, [string[]]$Arguments) {
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
        -WindowStyle Hidden -PassThru
    $null = $process.Handle
    if (-not $process.WaitForExit(90000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$FilePath timed out."
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "$FilePath failed with exit code $($process.ExitCode)."
    }
}

$testRoot = Assert-TestPath $testRoot
$beforeSave = Save-Fingerprint
$installed = $false
try {
    Invoke-CheckedProcess $installer @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER',
        ('/DIR="' + $testRoot + '"'), '/NOICONS'
    )
    $installed = $true
    $game = Join-Path $testRoot 'ThePictureShop.exe'
    $uninstaller = Join-Path $testRoot 'unins000.exe'
    foreach ($required in @(
        $game, $uninstaller, (Join-Path $testRoot 'love.dll'),
        (Join-Path $testRoot 'README-TESTERS.txt')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Installed package is missing $required"
        }
    }

    $smokeReport = Join-Path $windowsRoot 'windows-installed-smoke.rpt'
    Remove-Item -LiteralPath $smokeReport -Force -ErrorAction SilentlyContinue
    $previousSmoke = $env:PICTURE_SHOP_SMOKE
    $previousReport = $env:PICTURE_SHOP_SMOKE_REPORT
    try {
        $env:PICTURE_SHOP_SMOKE = '1'
        $env:PICTURE_SHOP_SMOKE_REPORT = $smokeReport
        Invoke-CheckedProcess $game @()
    } finally {
        if ($null -eq $previousSmoke) { Remove-Item Env:PICTURE_SHOP_SMOKE -ErrorAction SilentlyContinue }
        else { $env:PICTURE_SHOP_SMOKE = $previousSmoke }
        if ($null -eq $previousReport) { Remove-Item Env:PICTURE_SHOP_SMOKE_REPORT -ErrorAction SilentlyContinue }
        else { $env:PICTURE_SHOP_SMOKE_REPORT = $previousReport }
    }
    if (-not (Test-Path -LiteralPath $smokeReport)) {
        throw 'Installed game did not produce its smoke report.'
    }
    $failures = @(Select-String -LiteralPath $smokeReport -Pattern '^FAIL(?:\s|$)')
    if ($failures.Count -gt 0) {
        throw "Installed game reported $($failures.Count) failed checks."
    }

    Invoke-CheckedProcess $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    $installed = $false
    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while ((Test-Path -LiteralPath $testRoot) -and
        [DateTime]::UtcNow -lt $cleanupDeadline) {
        Start-Sleep -Milliseconds 100
    }
    if (Test-Path -LiteralPath $testRoot) {
        $remaining = @(Get-ChildItem -LiteralPath $testRoot -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -gt 0) {
            throw 'The Windows uninstaller left application files behind.'
        }
        Remove-Item -LiteralPath $testRoot -Force
    }
    if ((Save-Fingerprint) -ne $beforeSave) {
        throw 'Install or uninstall changed the player save directory.'
    }
    $checks = @(Select-String -LiteralPath $smokeReport -Pattern '^PASS(?:\s|$)').Count
    Write-Output "WINDOWS_INSTALL_TEST=PASS checks=$checks saves_preserved=True"
} finally {
    if ($installed -and (Test-Path -LiteralPath (Join-Path $testRoot 'unins000.exe'))) {
        try {
            Invoke-CheckedProcess (Join-Path $testRoot 'unins000.exe') `
                @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
        } catch { Write-Warning 'Installer test cleanup requires manual review.' }
    }
}
