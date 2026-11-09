param(
    [string[]]$Stage = @(),
    [string]$OutputDirectory = '',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gameplay_smoke_support.ps1')
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'gameplay_smoke_plan.json') -Raw | ConvertFrom-Json
Assert-GameplayPlan $plan
if ($ValidateOnly) { Write-Output "Valid gameplay plan: $($plan.stages.Count) stages, $($plan.features.Count) feature groups."; exit 0 }
foreach ($id in $Stage) { if ($id -notin $plan.stages.id) { throw "Unknown stage: $id" } }
$selected = @($plan.stages | Where-Object { $Stage.Count -eq 0 -or $_.id -in $Stage })
$fullPlan = $selected.Count -eq $plan.stages.Count
$loveCandidates = @((Join-Path $workspace 'runtime/lovec.exe'),(Join-Path $env:ProgramFiles 'LOVE/lovec.exe'))
$love = $loveCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $love) { $command=Get-Command lovec.exe -ErrorAction SilentlyContinue; if ($command) { $love=$command.Source } }
if (-not $love) { throw 'LÖVE console runtime was not found.' }
if (-not $OutputDirectory) { $OutputDirectory='output/gameplay-smoke/' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
$runRoot = [IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
$workspacePrefix = $workspace.TrimEnd('\') + '\'
if (-not $runRoot.StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Reports must be inside this workspace.' }
if (Test-Path -LiteralPath $runRoot) { throw 'Choose a new output directory; previous evidence is never overwritten.' }
New-Item -ItemType Directory -Path $runRoot | Out-Null
$appData = Join-Path $runRoot 'ad'
New-Item -ItemType Directory -Path $appData | Out-Null
$fingerprint = Get-GameplaySourceFingerprint $workspace
$results = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    version=1; status='RUNNING'; startedAt=[DateTime]::UtcNow.ToString('o'); completedAt=$null
    fullPlan=$fullPlan; sourceFingerprint=$fingerprint; sourceUnchanged=$null
    selectedStages=@($selected.id); totalFeatureGroups=$plan.features.Count; stages=@(); features=@()
}
function Save-Summary {
    $summary.stages=@($results.ToArray())
    $summary.features=@(foreach ($feature in $plan.features) {
        $found=@($results | Where-Object { $_.id -in $feature.stages })
        $status=if (@($found | Where-Object { $_.status -ne 'PASS' }).Count) { 'FAIL' }
            elseif ($found.Count -eq $feature.stages.Count) { 'PASS' } else { 'PENDING' }
        [pscustomobject]@{id=$feature.id;label=$feature.label;status=$status;stages=@($feature.stages);requiredChecks=@($feature.checks)}
    })
    $summary | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $runRoot 'summary.json') -Encoding UTF8
    $lines=@('THE PICTURE SHOP - GAMEPLAY READINESS',"Status: $($summary.status)","Full plan: $fullPlan",
        "Source: $fingerprint",'', 'Stages:')
    foreach ($result in $results) { $lines += "$($result.status) $($result.id): $($result.checks) checks, $($result.seconds)s"; foreach($problem in $result.problems){$lines += "  $problem"} }
    $lines += ''; $lines += 'Feature coverage:'
    foreach($feature in $summary.features){$lines += "$($feature.status) $($feature.id): $($feature.label)"}
    $lines += ''; $lines += 'PASS requires every planned stage and required feature checkpoint, successful exit and render completion, and unchanged source.'
    $lines += 'Automated game-module/UI/physics fixtures and forced mobile layout do not certify physical Android devices or public Internet multiplayer.'
    Set-Content -LiteralPath (Join-Path $runRoot 'summary.txt') -Value $lines -Encoding UTF8
}
$priorEnvironment=@{}
Get-ChildItem Env: | Where-Object { $_.Name -like 'PICTURE_SHOP_*' -or $_.Name -eq 'APPDATA' } | ForEach-Object { $priorEnvironment[$_.Name]=$_.Value }
$process=$null
Save-Summary
Write-Output "Gameplay smoke reports: $runRoot"
try {
    for($index=0;$index -lt $selected.Count;$index++) {
        $entry=$selected[$index]
        # Clear preview/focus/lab flags so inherited environment cannot select a
        # different test or accidentally enter a save-reset helper.
        Get-ChildItem Env: | Where-Object { $_.Name -like 'PICTURE_SHOP_*' } | ForEach-Object { Remove-Item -LiteralPath ('Env:'+$_.Name) }
        $identity='the-picture-shop-test-gameplay-' + ('{0:D2}' -f $index)
        $stageRoot=Join-Path $runRoot $entry.id
        New-Item -ItemType Directory -Path $stageRoot | Out-Null
        $report=Join-Path $stageRoot 'checks.rpt'
        $env:APPDATA=$appData
        $env:PICTURE_SHOP_SMOKE='1'
        $env:PICTURE_SHOP_TEST_IDENTITY=$identity
        $env:PICTURE_SHOP_SMOKE_REPORT=$report
        $env:PICTURE_SHOP_SMOKE_FOCUS=$entry.focus
        $env:PICTURE_SHOP_MOBILE=if($entry.mobile){'1'}else{'0'}
        if($entry.seed){$env:PICTURE_SHOP_GAMEPLAY_SEED=[string]$entry.seed}
        $required=@($plan.features | Where-Object { $entry.id -in $_.stages } | ForEach-Object { $_.checks } | Sort-Object -Unique)
        Write-Output "[$($index+1)/$($selected.Count)] START $($entry.id)"
        $timer=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false;$exitCode=-1;$launchProblem=$null
        try {
            $process=Start-Process -FilePath $love -ArgumentList ('"'+$workspace+'"') -WorkingDirectory $workspace `
                -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stageRoot 'stdout.log') `
                -RedirectStandardError (Join-Path $stageRoot 'stderr.log')
            $null=$process.Handle
            while(-not $process.HasExited -and $timer.Elapsed.TotalSeconds -lt $entry.timeoutSeconds){
                Start-Sleep -Milliseconds 250;$process.Refresh()
            }
            if(-not $process.HasExited){$timedOut=$true;Stop-Process -Id $process.Id -Force}
            $process.WaitForExit();$process.Refresh();$exitCode=$process.ExitCode
        } catch { $launchProblem=$_.Exception.Message }
        finally { if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force};$process=$null;$timer.Stop() }
        $lines=if(Test-Path -LiteralPath $report){@(Get-Content -LiteralPath $report)}else{@()}
        $evaluation=Test-GameplayStageReport $entry $lines $exitCode $timedOut $identity $required
        if($launchProblem){$evaluation.passed=$false;$evaluation.problems+= $launchProblem}
        $status=if($evaluation.passed){'PASS'}else{'FAIL'}
        $results.Add([pscustomobject]@{id=$entry.id;focus=$entry.focus;mobile=$entry.mobile;seed=$entry.seed
            status=$status;checks=$evaluation.checks;seconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
            exitCode=$exitCode;timedOut=$timedOut;problems=@($evaluation.problems);report=$report
            lastCheckpoint=(@($lines | Where-Object {$_ -like 'PASS *'} | Select-Object -Last 1) -join '')})
        Save-Summary
        Write-Output "$status $($entry.id): $($evaluation.checks) checks in $([math]::Round($timer.Elapsed.TotalSeconds,1))s"
        foreach($problem in $evaluation.problems){Write-Output "  $problem"}
    }
    $summary.sourceUnchanged=(Get-GameplaySourceFingerprint $workspace) -eq $fingerprint
    $failed=@($results | Where-Object {$_.status -ne 'PASS'}).Count -gt 0 -or -not $summary.sourceUnchanged
    $summary.status=if($failed){'FAIL'}elseif($fullPlan){'PASS'}else{'PARTIAL'}
    $summary.completedAt=[DateTime]::UtcNow.ToString('o');Save-Summary
    Write-Output "GAMEPLAY_SMOKE_$($summary.status): $(Join-Path $runRoot 'summary.txt')"
    if($failed){exit 1}
} catch {
    $summary.status='ERROR';$summary.completedAt=[DateTime]::UtcNow.ToString('o');$summary.error=$_.Exception.Message
    Save-Summary;throw
} finally {
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force}
    Get-ChildItem Env: | Where-Object {$_.Name -like 'PICTURE_SHOP_*'} | ForEach-Object {Remove-Item -LiteralPath ('Env:'+$_.Name)}
    if(-not $priorEnvironment.ContainsKey('APPDATA')){Remove-Item Env:APPDATA -ErrorAction SilentlyContinue}
    foreach($key in $priorEnvironment.Keys){[Environment]::SetEnvironmentVariable($key,$priorEnvironment[$key],'Process')}
}
