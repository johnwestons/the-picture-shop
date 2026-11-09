function Test-GameplayStageReport {
    param($Stage, [string[]]$Lines, [int]$ExitCode, [bool]$TimedOut, [string]$Identity, [string[]]$RequiredChecks)
    $problems = [Collections.Generic.List[string]]::new()
    $passed = @{}
    foreach ($line in $Lines) {
        if ($line -match '^PASS (.+)$') {
            if ($passed.ContainsKey($Matches[1])) { $problems.Add('Duplicate check: ' + $Matches[1]) }
            $passed[$Matches[1]] = $true
        }
        if ($line -match '^(FAIL|SMOKE_REPORT_ERROR)') { $problems.Add($line) }
    }
    $seed = if ($Stage.seed) { [string]$Stage.seed } else { 'none' }
    $mobile = if ($Stage.mobile) { '1' } else { '0' }
    $config = "SMOKE_CONFIG focus=$($Stage.focus) mobile=$mobile seed=$seed identity=$Identity"
    if ($Lines -notcontains $config) { $problems.Add('Missing or mismatched test configuration.') }
    if ($TimedOut) { $problems.Add('Stage exceeded its wall-clock deadline.') }
    if ($ExitCode -ne 0) { $problems.Add("Process exit code: $ExitCode") }
    foreach ($marker in @('CHECKS_COMPLETE', 'PASS render_three_frames', 'SMOKE_OK')) {
        if (@($Lines | Where-Object { $_ -ceq $marker }).Count -ne 1) { $problems.Add("Missing or repeated completion marker: $marker") }
    }
    if ($passed.Count -lt $Stage.minChecks) { $problems.Add("Only $($passed.Count) checks; expected at least $($Stage.minChecks).") }
    foreach ($name in $RequiredChecks) {
        if (-not $passed.ContainsKey($name)) { $problems.Add('Missing feature evidence: ' + $name) }
    }
    return [pscustomobject]@{ passed=($problems.Count -eq 0); checks=$passed.Count; problems=@($problems.ToArray()) }
}

function Assert-GameplayPlan {
    param($Plan)
    if ($Plan.version -ne 1 -or @($Plan.stages).Count -eq 0 -or @($Plan.features).Count -eq 0) { throw 'Invalid gameplay smoke plan.' }
    $ids = @{}
    foreach ($stage in $Plan.stages) {
        if ($stage.id -notmatch '^[a-z0-9-]+$' -or $ids.ContainsKey($stage.id) -or
            $stage.focus -notmatch '^[a-z0-9-]+$' -or $stage.mobile -isnot [bool] -or
            $stage.timeoutSeconds -lt 10 -or $stage.minChecks -lt 1) { throw "Invalid or duplicate stage: $($stage.id)" }
        $ids[$stage.id] = $false
    }
    $features = @{}
    foreach ($feature in $Plan.features) {
        if (-not $feature.id -or $features.ContainsKey($feature.id) -or @($feature.stages).Count -eq 0 -or
            @($feature.checks).Count -eq 0) { throw "Invalid or duplicate feature: $($feature.id)" }
        $features[$feature.id] = $true
        foreach ($stage in $feature.stages) {
            if (-not $ids.ContainsKey($stage)) { throw "Feature $($feature.id) refers to unknown stage $stage" }
            $ids[$stage] = $true
        }
    }
    foreach ($id in $ids.Keys) { if (-not $ids[$id]) { throw "Stage $id has no feature contract." } }
}

function Get-GameplaySourceFingerprint {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Recurse -File -Filter '*.lua')
    $files += @(Get-Item -LiteralPath (Join-Path $Root 'main.lua'),(Join-Path $Root 'conf.lua'))
    $files += @(Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Recurse -File | Where-Object { $_.Extension -in '.ps1','.json' })
    $records = foreach ($file in ($files | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Root.Length).Replace('\','/')
        $relative + ':' + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n"))))).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose() }
}
