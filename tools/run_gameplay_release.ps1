param([string]$OutputDirectory = '', [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'gameplay_smoke_support.ps1')
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'gameplay_smoke_plan.json') -Raw | ConvertFrom-Json
Assert-GameplayPlan $plan
# Independent processes retain separate APPDATA identities and report folders.
$groups = @(
    [pscustomobject]@{name='desktop';ids=@('core-desktop')},
    [pscustomobject]@{name='mobile';ids=@('core-mobile')},
    [pscustomobject]@{name='routes';ids=@('delivery-routes')},
    [pscustomobject]@{name='features';ids=@($plan.stages.id | Where-Object {$_ -notin @('core-desktop','core-mobile','delivery-routes')})}
)
if($ValidateOnly){Write-Output "Release plan: $($plan.stages.Count) stages, $($plan.features.Count) feature groups, $($groups.Count) isolated processes.";exit 0}
if(-not $OutputDirectory){$OutputDirectory='output/gameplay-release/'+(Get-Date -Format 'yyyyMMdd-HHmmss')}
$runRoot=[IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
if(-not $runRoot.StartsWith($workspace.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Reports must be inside this workspace.'}
if(Test-Path -LiteralPath $runRoot){throw 'Choose a new report folder.'}
New-Item -ItemType Directory -Path $runRoot | Out-Null
$fingerprint=Get-GameplaySourceFingerprint $workspace
$started=[DateTime]::UtcNow
$processes=[Collections.Generic.List[object]]::new()
$problems=[Collections.Generic.List[string]]::new()
$stages=@{}
function Quote-PsLiteral([string]$Value){return "'"+$Value.Replace("'","''")+"'"}
try {
    foreach($group in $groups){
        $child=Join-Path $runRoot ($group.name+'.ps1')
        $relative=$OutputDirectory.TrimEnd('/','\')+'/'+$group.name
        $script="& "+(Quote-PsLiteral (Join-Path $PSScriptRoot 'run_gameplay_smoke.ps1'))+
            ' -Stage @('+(($group.ids | ForEach-Object {Quote-PsLiteral $_}) -join ',')+') -OutputDirectory '+(Quote-PsLiteral $relative)
        [IO.File]::WriteAllText($child,$script,[Text.UTF8Encoding]::new($false))
        $process=Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-File',('"'+$child+'"')) `
            -WorkingDirectory $workspace -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $runRoot ($group.name+'.log')) `
            -RedirectStandardError (Join-Path $runRoot ($group.name+'-error.log'))
        $null=$process.Handle
        $processes.Add([pscustomobject]@{process=$process;group=$group})
        Write-Output "START $($group.name): $($group.ids.Count) stages"
    }
    foreach($entry in $processes){
        $entry.process.WaitForExit()
        $summaryPath=Join-Path $runRoot ($entry.group.name+'/summary.json')
        if(-not (Test-Path -LiteralPath $summaryPath)){$problems.Add("Missing $($entry.group.name) summary");continue}
        $summary=Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        if($entry.process.ExitCode -ne 0 -or $summary.status -notin @('PASS','PARTIAL')){$problems.Add("Failed group: $($entry.group.name)")}
        if(-not $summary.sourceUnchanged -or $summary.sourceFingerprint -ne $fingerprint){$problems.Add("Source changed in $($entry.group.name)")}
        for($index=0;$index -lt $entry.group.ids.Count;$index++){
            $id=$entry.group.ids[$index]
            $found=@($summary.stages | Where-Object {$_.id -eq $id})
            if($found.Count -ne 1){$problems.Add("Missing or repeated stage: $id");continue}
            if($stages.ContainsKey($id)){throw "Duplicate stage: $id"}
            $result=$found[0]
            $definition=$plan.stages | Where-Object {$_.id -eq $id}
            $required=@($plan.features | Where-Object {$id -in $_.stages} | ForEach-Object {$_.checks} | Sort-Object -Unique)
            $lines=@(Get-Content -LiteralPath $result.report)
            $identity='the-picture-shop-test-gameplay-'+('{0:D2}' -f $index)
            $validation=Test-GameplayStageReport $definition $lines $result.exitCode $result.timedOut $identity $required
            if(-not $validation.passed -or $result.status -ne 'PASS'){
                $problems.Add("Failed stage: $id");foreach($problem in $validation.problems){$problems.Add($problem)}
            }
            $stages[$id]=$result
        }
    }
    $unchanged=(Get-GameplaySourceFingerprint $workspace) -eq $fingerprint
    if(-not $unchanged){$problems.Add('Source changed during release validation')}
    if($stages.Count -ne $plan.stages.Count){$problems.Add('Incomplete release plan')}
    $report=[ordered]@{status=$(if($problems.Count){'FAIL'}else{'PASS'});fullPlan=$true;
        startedAt=$started.ToString('o');completedAt=[DateTime]::UtcNow.ToString('o');sourceFingerprint=$fingerprint;
        sourceUnchanged=$unchanged;parallelProcesses=$groups.Count;problems=@($problems.ToArray());
        stages=@($plan.stages | ForEach-Object {$stages[$_.id]});
        features=@($plan.features | ForEach-Object {
            $okay=@($_.stages | Where-Object {-not $stages.ContainsKey($_) -or $stages[$_].status -ne 'PASS'}).Count -eq 0
            [pscustomobject]@{id=$_.id;label=$_.label;status=$(if($okay){'PASS'}else{'FAIL'});stages=$_.stages;requiredChecks=$_.checks}
        })}
    $report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $runRoot 'summary.json') -Encoding UTF8
    $lines=@("GAMEPLAY_RELEASE_$($report.status)","Source unchanged: $unchanged",'')
    foreach($stage in $report.stages){if($stage){$lines+="$($stage.status) $($stage.id): $($stage.checks) checks"}}
    $lines+=@($problems.ToArray())
    $lines | Set-Content -LiteralPath (Join-Path $runRoot 'summary.txt') -Encoding UTF8
    Write-Output "GAMEPLAY_RELEASE_$($report.status): $runRoot"
    if($problems.Count){exit 1}
} finally {
    foreach($entry in $processes){if(-not $entry.process.HasExited){Stop-Process -Id $entry.process.Id -Force}}
}
