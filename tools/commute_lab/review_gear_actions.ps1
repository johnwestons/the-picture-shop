param([switch]$Capture,[switch]$GridCapture)
$ErrorActionPreference='Stop'
$commuteRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reviewOutput=Join-Path $commuteRoot 'output\commute-gear-actions-review'
New-Item -ItemType Directory -Force -Path $reviewOutput | Out-Null
$commutePrevious=@{}
$commuteEnv=@{
    PICTURE_SHOP_SMOKE='1'
    PICTURE_SHOP_COMMUTE_LAB='1'
    PICTURE_SHOP_GEAR_ACTION_REVIEW='1'
    PICTURE_SHOP_GEAR_ACTION_REVIEW_CAPTURE=$(if($Capture){'1'}else{''})
    PICTURE_SHOP_GEAR_ACTION_REVIEW_GRID_CAPTURE=$(if($GridCapture){'1'}else{''})
    PICTURE_SHOP_GEAR_ACTION_REVIEW_OUTPUT=$reviewOutput
}
try {
    foreach($key in $commuteEnv.Keys){
        $commutePrevious[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$commuteEnv[$key],'Process')
    }
    $commuteProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' `
        -ArgumentList ('"'+$commuteRoot+'"') -WorkingDirectory $commuteRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $reviewOutput 'native-review-stdout.txt') `
        -RedirectStandardError (Join-Path $reviewOutput 'native-review-stderr.txt')
    if(-not $commuteProcess.WaitForExit(60000)){
        Stop-Process -Id $commuteProcess.Id -Force
        throw 'Gear action review timed out'
    }
    Get-Content (Join-Path $reviewOutput 'native-review-stdout.txt')
    Get-Content (Join-Path $reviewOutput 'native-review-stderr.txt')
    if($commuteProcess.ExitCode -ne 0){throw ('Gear action review failed: '+$commuteProcess.ExitCode)}
    if($Capture -and -not (Test-Path (Join-Path $reviewOutput 'native-review.png'))){
        throw 'Gear action review did not write native-review.png'
    }
    if($GridCapture -and -not (Test-Path (Join-Path $reviewOutput 'native-colorway-grid.png'))){
        throw 'Gear action review did not write native-colorway-grid.png'
    }
    if($GridCapture -and -not (Test-Path (Join-Path $reviewOutput 'native-colorway-grid-checks.txt'))){
        throw 'Gear action review did not write native-colorway-grid-checks.txt'
    }
} finally {
    foreach($key in $commuteEnv.Keys){
        [Environment]::SetEnvironmentVariable($key,$commutePrevious[$key],'Process')
    }
}
