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
        & $candidate -c `
            'import PIL, sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' `
            2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'Python 3.10+ with Pillow was not found. Install Python/Pillow or use the bundled workspace runtime.'
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
    if (Test-Path -LiteralPath (Join-Path $projectRoot 'output\windows\windows-build-report.json')) {
        $report.windowsPackage = Get-Content -Raw (Join-Path $projectRoot 'output\windows\windows-build-report.json') | ConvertFrom-Json
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
            'tools/build_windows_icon.py', 'tools/build_windows_installer.ps1',
            'tools/test_windows_installer.ps1', 'tools/assemble_tester_release.ps1',
            'tools/verify_guest_worker_physical_acceptance.py',
            'tools/tests/test_guest_worker_physical_acceptance.py',
            'tools/tests/test_mobile_package_reproducibility.py',
            'packaging/windows/ThePictureShop.iss',
            'packaging/windows/README-TESTERS.txt',
            'packaging/android/README-TESTERS.txt',
            'packaging/README-TESTERS.txt',
            'tools/verify_public_ipv4_remote_results.py',
            'tools/verify_public_ipv4_remote_results.ps1',
            'tools/tests/test_public_ipv4_remote_results.py',
            'tools/tests/test_public_ipv4_probe_watchdog_integration.py',
            'src/tests/support/network_impairment_harness.lua',
            'src/tests/multiplayer_impairment_test.lua',
            'src/tests/multiplayer_soak_test.lua',
            'src/tests/multiplayer_workshop_boundary_test.lua',
            'src/tests/multiplayer_workshop_reliable_test.lua',
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

    Invoke-GateStep 'Run tooling regression suite' {
        & $script:python -m unittest discover `
            -s (Join-Path $projectRoot 'tools\tests') `
            -p 'test_*.py' -v 2>&1 |
            ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'tooling regression suite'
        'tooling tests passed'
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
        $passedNames = @(Select-String -Path $smokeReport -Pattern '^PASS\s+' |
            ForEach-Object { $_.Line.Substring(5) })
        $requiredImpairmentChecks = @(
            'multiplayer_impairment_four_device_lab_starts_without_real_sockets',
            'multiplayer_impairment_duplicate_and_reordered_admission_converges_to_four_players',
            'multiplayer_impairment_inputs_recover_from_loss_reordering_and_duplication',
            'multiplayer_impairment_round_robin_flood_preserves_quiet_peer_and_throttles_replies',
            'multiplayer_impairment_client_send_failure_disconnect_and_rejoin_are_isolated',
            'multiplayer_impairment_lab_teardown_discards_all_test_packet_state',
            'multiplayer_soak_nine_rotating_rejoins_keep_host_and_guests_bounded',
            'multiplayer_workshop_boundary_current_owner_input_survives_noisy_exact_timeout',
            'multiplayer_workshop_boundary_invalid_and_stale_traffic_cannot_renew_lease',
            'multiplayer_workshop_reliable_replay_and_delay_execute_commands_exactly_once',
            'multiplayer_workshop_reliable_disconnect_barrier_blocks_stale_generation_command',
            'direct_composite_saturated_service_round_robins_all_three_guests'
        )
        foreach ($checkName in $requiredImpairmentChecks) {
            if ($passedNames -notcontains $checkName) {
                throw "Required multiplayer impairment check did not run: $checkName"
            }
        }
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

    Invoke-GateStep 'Build and smoke-test Windows installer' {
        $packagePath = (Get-Content -Raw (
            Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json).package
        & (Join-Path $projectRoot 'tools\build_windows_installer.ps1') `
            -PackagePath $packagePath | ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'Windows installer build'
        $windowsReport = Get-Content -Raw (
            Join-Path $projectRoot 'output\windows\windows-build-report.json') | ConvertFrom-Json
        if ($windowsReport.sourceCommit -ne $script:head -or $windowsReport.sourceDirty) {
            throw 'Windows installer provenance does not match the clean release source.'
        }
        if (-not $windowsReport.installer -or
            -not (Test-Path -LiteralPath $windowsReport.installer)) {
            throw 'Windows installer report does not identify a built installer.'
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $windowsReport.installer).Hash.ToLowerInvariant()
        if ($actualHash -ne $windowsReport.installerSha256) {
            throw 'Windows installer SHA-256 does not match its build report.'
        }
        "checks=$($windowsReport.smokeChecks) bytes=$($windowsReport.installerBytes) sha256=$actualHash"
    }

    Invoke-GateStep 'Install, launch, and uninstall Windows package' {
        $windowsReport = Get-Content -Raw (
            Join-Path $projectRoot 'output\windows\windows-build-report.json') | ConvertFrom-Json
        & (Join-Path $projectRoot 'tools\test_windows_installer.ps1') `
            -InstallerPath $windowsReport.installer | ForEach-Object { Write-Host $_ }
        Assert-ExitCode 'Windows installer acceptance test'
        'installed game launched; uninstall preserved saves'
    }

    if ($BuildApk) {
        Invoke-GateStep 'Build and verify Android APK' {
            & (Join-Path $projectRoot 'tools\build_android_apk.ps1') -PackagePath ((Get-Content -Raw (Join-Path $projectRoot 'output\mobile\build-report.json') | ConvertFrom-Json).package) |
                ForEach-Object { Write-Host $_ }
            Assert-ExitCode 'Android APK build'
            'APK signature, package ID, ZIP alignment, and ELF alignment verified'
        }

        Invoke-GateStep 'Verify three-phone Guest Worker acceptance' {
            & $script:python `
                (Join-Path $projectRoot 'tools\verify_guest_worker_physical_acceptance.py') `
                --report (Join-Path $projectRoot 'output\mobile\device-tests\guest-worker-physical-acceptance.json') `
                --apk-report (Join-Path $projectRoot 'output\mobile\apk-report.json') `
                --build-report (Join-Path $projectRoot 'output\mobile\build-report.json') |
                ForEach-Object { Write-Host $_ }
            Assert-ExitCode 'Guest Worker physical acceptance verification'
            'exact clean APK passed all required checks on three phones'
        }

        Invoke-GateStep 'Assemble separate tester downloads' {
            & (Join-Path $projectRoot 'tools\assemble_tester_release.ps1') |
                ForEach-Object { Write-Host $_ }
            Assert-ExitCode 'tester release assembly'
            'Windows EXE and Android APK staged separately with checksums'
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
