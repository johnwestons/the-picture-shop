param(
    [switch]$BuildApk
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseRoot = Join-Path $projectRoot 'output\release'
$reportPath = Join-Path $releaseRoot 'release-report.json'
$startedAt = [DateTime]::UtcNow
$steps = [System.Collections.Generic.List[object]]::new()

function Invoke-GateStep {
    param([string]$Name, [scriptblock]$Action)
    Write-Output "[RELEASE] $Name"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $detail = & $Action
        $timer.Stop()
        $script:steps.Add([ordered]@{
            name = $Name
            passed = $true
            seconds = [math]::Round($timer.Elapsed.TotalSeconds, 3)
            detail = if ($null -eq $detail) { 'ok' } else { [string]$detail }
        })
    }
    catch {
        $timer.Stop()
        $script:steps.Add([ordered]@{
            name = $Name
            passed = $false
            seconds = [math]::Round($timer.Elapsed.TotalSeconds, 3)
            detail = $_.Exception.Message
        })
        throw
    }
}

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
    throw 'Python with Pillow was not found. Install Python/Pillow or use the bundled workspace runtime.'
}

function Assert-ExitCode {
    param([string]$CommandName)
    if ($LASTEXITCODE -ne 0) { throw "$CommandName failed with exit code $LASTEXITCODE" }
}

function Write-ReleaseReport {
    param([bool]$Passed, [string]$Failure)
    New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
    $head = (& git -C $projectRoot rev-parse HEAD 2>$null | Out-String).Trim()
    $report = [ordered]@{
        schemaVersion = 1
        passed = $Passed
        failure = $Failure
        startedAtUtc = $startedAt.ToString('o')
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceCommit = $head
        branch = (& git -C $projectRoot branch --show-current 2>$null | Out-String).Trim()
        steps = $steps
    }
    if (Test-Path -LiteralPath (Join-Path $projectRoot 'output\mobile\build-report.json')) {
        $report.mobilePackage = Get-Content -Raw (Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json
    }
    if ($BuildApk -and (Test-Path -LiteralPath (Join-Path $projectRoot 'output\mobile\apk-report.json'))) {
        $report.androidApk = Get-Content -Raw (Join-Path $projectRoot 'output\mobile\apk-report.json') | ConvertFrom-Json
    }
    [System.IO.File]::WriteAllText(
        $reportPath,
        (($report | ConvertTo-Json -Depth 12) + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

$python = $null
$config = $null
$head = $null
$smokeChecks = 0
$assetChecks = 0

try {
    Invoke-GateStep 'Verify clean tracked source' {
        $inside = (& git -C $projectRoot rev-parse --is-inside-work-tree | Out-String).Trim()
        Assert-ExitCode 'git rev-parse'
        if ($inside -ne 'true') { throw 'Project root is not a Git working tree.' }
        $status = @(& git -C $projectRoot status --porcelain --untracked-files=all)
        Assert-ExitCode 'git status'
        if ($status.Count -gt 0) { throw "Working tree is dirty:`n$($status -join "`n")" }
        $required = @(
            'main.lua', 'conf.lua', 'README.md', 'RELEASE.ps1',
            'tools/release_gate.ps1', 'tools/asset_doctor.py',
            'tools/generate_sfx.py', 'tools/build_mobile_package.py',
            'assets/audio/SOURCES.md', 'assets/audio/source_manifest.json',
            'mobile/config.json'
        )
        $untrackedRequired = @()
        foreach ($path in $required) {
            & git -C $projectRoot ls-files --error-unmatch -- $path *> $null
            if ($LASTEXITCODE -ne 0) { $untrackedRequired += $path }
        }
        if ($untrackedRequired.Count -gt 0) {
            throw "Required release files are not tracked: $($untrackedRequired -join ', ')"
        }
        $script:head = (& git -C $projectRoot rev-parse HEAD | Out-String).Trim()
        "commit=$script:head"
    }

    Invoke-GateStep 'Verify synchronized main branch' {
        $branch = (& git -C $projectRoot branch --show-current | Out-String).Trim()
        if ($branch -ne 'main') { throw "Releases must be built from main, not $branch." }
        & git -C $projectRoot fetch --quiet origin main
        Assert-ExitCode 'git fetch origin main'
        $upstream = (& git -C $projectRoot rev-parse '@{upstream}' 2>$null | Out-String).Trim()
        Assert-ExitCode 'git rev-parse upstream'
        if ($upstream -ne $script:head) {
            throw "Local main ($script:head) does not match its upstream ($upstream)."
        }
        'main matches origin/main'
    }

    Invoke-GateStep 'Locate validation runtime' {
        $script:python = Find-Python
        "python=$script:python"
    }

    Invoke-GateStep 'Validate release version' {
        $script:config = Get-Content -Raw (Join-Path $projectRoot 'mobile\config.json') | ConvertFrom-Json
        if ($script:config.versionName -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
            throw "Invalid semantic versionName: $($script:config.versionName)"
        }
        if ([int]$script:config.versionCode -lt 1) { throw 'versionCode must be positive.' }
        "version=$($script:config.versionName) code=$($script:config.versionCode)"
    }

    Invoke-GateStep 'Run engine regression suite' {
        & (Join-Path $projectRoot '.stabilization\run-smoke.ps1') |
            ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'engine smoke suite'
        $smokeReport = Join-Path $projectRoot '.stabilization\smoke-report.rpt'
        $failures = @(Select-String -Path $smokeReport -Pattern '^FAIL(?:\s|$)')
        if ($failures.Count -gt 0) { throw "$($failures.Count) smoke checks failed." }
        $script:smokeChecks = @(Select-String -Path $smokeReport -Pattern '^PASS(?:\s|$)').Count
        if ($script:smokeChecks -lt 1) { throw 'Smoke report contains no passing checks.' }
        "checks=$script:smokeChecks failures=0"
    }

    Invoke-GateStep 'Audit raster assets' {
        $assetReport = Join-Path $projectRoot 'output\asset-audit.json'
        & $script:python (Join-Path $projectRoot 'tools\asset_doctor.py') --report $assetReport |
            ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'asset doctor'
        $audit = Get-Content -Raw $assetReport | ConvertFrom-Json
        $failures = @($audit.checks | Where-Object { -not $_.passed })
        if (-not $audit.passed -or $failures.Count -gt 0) {
            throw "$($failures.Count) raster checks failed."
        }
        $script:assetChecks = @($audit.checks).Count
        "checks=$script:assetChecks failures=0"
    }

    Invoke-GateStep 'Verify licensed audio sources' {
        & $script:python (Join-Path $projectRoot 'tools\generate_sfx.py') --verify-only |
            ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'audio source verification'
        $manifest = Get-Content -Raw (Join-Path $projectRoot 'assets\audio\source_manifest.json') | ConvertFrom-Json
        "sources=$(@($manifest.sources).Count)"
    }

    Invoke-GateStep 'Build and smoke-test mobile package' {
        & (Join-Path $projectRoot 'BUILD_ANDROID.ps1') -PackageOnly |
            ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'mobile package build'
        'package smoke passed'
    }

    Invoke-GateStep 'Verify package provenance and contents' {
        $buildReport = Get-Content -Raw (Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json
        if ($buildReport.sourceCommit -ne $script:head) { throw 'Package source commit does not match HEAD.' }
        if ($buildReport.sourceDirty) { throw 'Package reports dirty source.' }
        if ($buildReport.versionName -ne $script:config.versionName -or
            [int]$buildReport.versionCode -ne [int]$script:config.versionCode) {
            throw 'Package version does not match mobile/config.json.'
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $buildReport.package).Hash.ToLowerInvariant()
        if ($actualHash -ne $buildReport.sha256) { throw 'Package SHA-256 does not match its build report.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($buildReport.package)
        try {
            $entries = @($archive.Entries.FullName)
            foreach ($required in @(
                'main.lua', 'conf.lua', 'mobile-build.json',
                'assets/audio/SOURCES.md', 'assets/audio/source_manifest.json'
            )) {
                if ($entries -notcontains $required) { throw "Package is missing $required" }
            }
            $audioCues = @($entries | Where-Object { $_ -like 'assets/audio/sfx/*.wav' })
            if ($audioCues.Count -ne 16) { throw "Package contains $($audioCues.Count) runtime audio cues; expected 16." }
            if ($entries -contains 'assets/audio/sfx/picture_shop_sfx_preview.wav') {
                throw 'Package contains the non-runtime audio audition reel.'
            }
        }
        finally { $archive.Dispose() }
        "files=$($buildReport.runtimeFiles) bytes=$($buildReport.packageBytes) sha256=$actualHash"
    }

    if ($BuildApk) {
        Invoke-GateStep 'Build and verify Android APK' {
            & (Join-Path $projectRoot 'tools\build_android_apk.ps1') -PackagePath ((Get-Content -Raw (Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json).package) |
                ForEach-Object { Write-Host $_ }
            Assert-ExitCode 'Android APK build'
            'APK signature, package ID, ZIP alignment, and ELF alignment verified'
        }
    }

    Write-ReleaseReport -Passed $true -Failure $null
    Write-Output "[RELEASE] PASS smoke=$smokeChecks assets=$assetChecks report=$reportPath"
}
catch {
    $failure = $_.Exception.Message
    Write-ReleaseReport -Passed $false -Failure $failure
    Write-Error "[RELEASE] FAIL: $failure"
    exit 1
}
