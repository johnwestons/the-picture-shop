$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../gameplay_smoke_support.ps1')
$stage=[pscustomobject]@{id='probe';focus='full';mobile=$false;minChecks=2;timeoutSeconds=10}
$good=@('SMOKE_CONFIG focus=full mobile=0 seed=none identity=test','PASS completes','CHECKS_COMPLETE','PASS render_three_frames','SMOKE_OK')
function Require([bool]$Okay,[string]$Name){if(-not $Okay){throw $Name};Write-Output "PASS $Name"}
Require (Test-GameplayStageReport $stage $good 0 $false 'test' @('completes')).passed 'complete_report_passes'
Require (-not (Test-GameplayStageReport $stage ($good | Where-Object {$_ -ne 'SMOKE_OK'}) 0 $false 'test' @('completes')).passed) 'exit_zero_without_completion_fails'
Require (-not (Test-GameplayStageReport $stage $good 1 $false 'test' @('completes')).passed) 'nonzero_exit_fails_even_with_success_text'
Require (-not (Test-GameplayStageReport $stage $good 0 $true 'test' @('completes')).passed) 'watchdog_timeout_fails'
Require (-not (Test-GameplayStageReport $stage $good 0 $false 'test' @('missing')).passed) 'missing_feature_checkpoint_fails'
Require (-not (Test-GameplayStageReport $stage $good 0 $false 'different-save' @('completes')).passed) 'stale_report_identity_fails'
Require (-not (Test-GameplayStageReport $stage ($good+@('PASS completes')) 0 $false 'test' @('completes')).passed) 'duplicate_check_fails'
Require (-not (Test-GameplayStageReport $stage ($good+@('FAIL hidden failure')) 0 $false 'test' @('completes')).passed) 'failure_marker_overrides_success'
$plan=Get-Content (Join-Path $PSScriptRoot '../gameplay_smoke_plan.json') -Raw | ConvertFrom-Json
Assert-GameplayPlan $plan
Require $true 'real_plan_is_valid'
$plan.features[0].stages=@('missing-stage');$rejected=$false
try{Assert-GameplayPlan $plan}catch{$rejected=$true}
Require $rejected 'unknown_stage_evidence_fails'
