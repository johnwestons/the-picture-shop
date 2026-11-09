param([switch]$Capture,[ValidateRange(30,600)][int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
$commuteRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$commuteOutput=Join-Path $commuteRoot 'output\commute-runtime'
New-Item -ItemType Directory -Force -Path $commuteOutput | Out-Null
$commuteEnv=@{
    PICTURE_SHOP_SMOKE='1';PICTURE_SHOP_COMMUTE='1';PICTURE_SHOP_SMOKE_FOCUS='commute'
    PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-commute-runtime'
    PICTURE_SHOP_SMOKE_REPORT=(Join-Path $commuteOutput 'report.rpt')
    PICTURE_SHOP_COMMUTE_CAPTURE=$(if($Capture){$commuteOutput}else{''})
}
$commutePrevious=@{}
try {
    foreach($key in $commuteEnv.Keys){$commutePrevious[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$commuteEnv[$key],'Process')}
    $commuteProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$commuteRoot+'"') -WorkingDirectory $commuteRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $commuteOutput 'stdout.txt') -RedirectStandardError (Join-Path $commuteOutput 'stderr.txt')
    # Return the live handle to the tool layer when this exceeds its initial wait.
    $commuteWatch=[Diagnostics.Stopwatch]::StartNew()
    while(-not $commuteProcess.WaitForExit(1000)){
        if($commuteWatch.Elapsed.TotalSeconds -gt $TimeoutSeconds){Stop-Process -Id $commuteProcess.Id -Force;throw 'Commute runtime check timed out'}
    }
    Get-Content (Join-Path $commuteOutput 'stderr.txt')
    Get-Content (Join-Path $commuteOutput 'report.rpt') | Select-Object -Last 12
    if($commuteProcess.ExitCode -ne 0){throw ('Commute runtime check failed: '+$commuteProcess.ExitCode)}
} finally {
    foreach($key in $commuteEnv.Keys){[Environment]::SetEnvironmentVariable($key,$commutePrevious[$key],'Process')}
}
