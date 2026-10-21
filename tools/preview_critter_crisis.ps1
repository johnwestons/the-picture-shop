param([switch]$Review,[switch]$CoopReview,[switch]$PhoneReview)
$ErrorActionPreference='Stop'
$crisisRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$crisisLove=Join-Path $env:ProgramFiles 'LOVE/love.exe'
if (-not (Test-Path -LiteralPath $crisisLove)) { $crisisLove=(Get-Command love.exe -ErrorAction Stop).Source }
$crisisEnvironment=@{}
foreach ($crisisName in @('PICTURE_SHOP_CRISIS_PREVIEW','PICTURE_SHOP_SMOKE','CRITTER_PREVIEW_REVIEW','CRITTER_COOP_REVIEW','CRITTER_PHONE_REVIEW')) {
    $crisisEnvironment[$crisisName]=[Environment]::GetEnvironmentVariable($crisisName,'Process')
}
try {
    $env:PICTURE_SHOP_CRISIS_PREVIEW='1'
    Remove-Item Env:PICTURE_SHOP_SMOKE -ErrorAction SilentlyContinue
    if ($Review -or $CoopReview -or $PhoneReview) {
    if ($PhoneReview) { $env:CRITTER_PHONE_REVIEW='1' } else { Remove-Item Env:CRITTER_PHONE_REVIEW -ErrorAction SilentlyContinue }
    if ($CoopReview) { $env:CRITTER_COOP_REVIEW='1' } else { Remove-Item Env:CRITTER_COOP_REVIEW -ErrorAction SilentlyContinue }
    $crisisOutput=Join-Path $crisisRoot $(if ($PhoneReview) { 'output/critter-crisis-phone-review' } elseif ($CoopReview) { 'output/critter-crisis-coop-review' } else { 'output/critter-crisis-review-v3' })
    New-Item -ItemType Directory -Force -Path $crisisOutput | Out-Null
    $env:CRITTER_PREVIEW_REVIEW=$crisisOutput
    $crisisProcess=Start-Process -FilePath $crisisLove -ArgumentList '.' -WorkingDirectory $crisisRoot -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $crisisOutput 'stdout.txt') -RedirectStandardError (Join-Path $crisisOutput 'stderr.txt')
    Get-Content -LiteralPath (Join-Path $crisisOutput 'review.txt') -Tail 4
    if ($crisisProcess.ExitCode -ne 0) { Get-Content -LiteralPath (Join-Path $crisisOutput 'stderr.txt');throw 'Arcade review failed.' }
    } else {
    Remove-Item Env:CRITTER_PREVIEW_REVIEW -ErrorAction SilentlyContinue
    # The visible game window is the requested interactive preview.
    Start-Process -FilePath $crisisLove -ArgumentList '.' -WorkingDirectory $crisisRoot -PassThru | Select-Object Id,ProcessName
    }
} finally {
    foreach ($crisisName in $crisisEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($crisisName,$crisisEnvironment[$crisisName],'Process')
    }
}
