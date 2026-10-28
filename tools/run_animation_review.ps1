param([int]$TimeoutSeconds = 300,
    [ValidateSet('all','jack','player-walk','employee-walk','construction','machine-motion')][string]$Focus='all',
    [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$OutputName='engine',
    [switch]$CatSouthProposal,[switch]$PlayerNorthProposal,
    [string]$PlayerNorthProposalFile='output/animation-overhaul/player-north-passing-preview/src/player_walk_art.lua')
$ErrorActionPreference = 'Stop'
$animationProject = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$animationOutput = Join-Path $animationProject ('output/animation-overhaul/'+$OutputName)
New-Item -ItemType Directory -Force -Path $animationOutput | Out-Null
$animationLove = @(
    (Join-Path $animationProject 'runtime/lovec.exe'),
    (Join-Path $env:ProgramFiles 'LOVE/lovec.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $animationLove) { throw 'LÖVE 11.5 was not found.' }
$animationEnvironment = @{
    APPDATA = (Join-Path $animationProject 'output/animation-overhaul/appdata')
    PICTURE_SHOP_SMOKE = '1'
    PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-animation-review'
    PICTURE_SHOP_ANIMATION_REVIEW = '1'
    PICTURE_SHOP_ANIMATION_OUTPUT = $animationOutput
    PICTURE_SHOP_ANIMATION_REVIEW_FOCUS = $Focus
    PICTURE_SHOP_ANIMATION_CAT_PROPOSAL = $(if ($CatSouthProposal) {'1'} else {'0'})
    PICTURE_SHOP_ANIMATION_PLAYER_NORTH_PROPOSAL = $(if ($PlayerNorthProposal) {'1'} else {'0'})
    PICTURE_SHOP_ANIMATION_PLAYER_NORTH_PROPOSAL_FILE = $PlayerNorthProposalFile
}
$animationPrevious = @{}
$animationProcess = $null
$animationRunStarted = Get-Date
try {
    foreach ($key in $animationEnvironment.Keys) {
        $animationPrevious[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$animationEnvironment[$key],'Process')
    }
    $animationProcess = Start-Process -FilePath $animationLove -ArgumentList ('"'+$animationProject+'"') `
        -WorkingDirectory $animationProject -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $animationOutput 'stdout.log') `
        -RedirectStandardError (Join-Path $animationOutput 'stderr.log')
    if (-not $animationProcess.WaitForExit($TimeoutSeconds*1000)) { throw 'Animation review timed out.' }
    $animationProcess.Refresh()
    $animationExitCode = $animationProcess.ExitCode
    $animationReviewPath = Join-Path $animationOutput 'engine-review.txt'
    $animationReport = if (Test-Path -LiteralPath $animationReviewPath) { Get-Content -LiteralPath $animationReviewPath -Raw } else { '' }
    $animationFreshReport = (Test-Path -LiteralPath $animationReviewPath) -and
        (Get-Item -LiteralPath $animationReviewPath).LastWriteTime -ge $animationRunStarted
    $animationErrorPath = Join-Path $animationOutput 'error.txt'
    $animationFreshError = (Test-Path -LiteralPath $animationErrorPath) -and
        (Get-Item -LiteralPath $animationErrorPath).LastWriteTime -ge $animationProcess.StartTime
    if (($null -ne $animationExitCode -and $animationExitCode -ne 0) -or
        -not $animationReport.StartsWith('PASS:') -or -not $animationFreshReport -or $animationFreshError) {
        Get-Content -LiteralPath (Join-Path $animationOutput 'stdout.log') -Tail 20
        throw "Animation review failed: exit=$animationExitCode, reportPass=$($animationReport.StartsWith('PASS:')), freshReport=$animationFreshReport, freshError=$animationFreshError"
    }
    Get-Content -LiteralPath $animationReviewPath
} finally {
    if ($animationProcess -and -not $animationProcess.HasExited) { Stop-Process -Id $animationProcess.Id -Force }
    foreach ($key in $animationPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($key,$animationPrevious[$key],'Process')
    }
}
