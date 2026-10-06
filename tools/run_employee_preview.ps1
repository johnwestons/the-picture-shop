param([int]$TimeoutSeconds=50)
$ErrorActionPreference='Stop'
$employeeRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$employeeOutput=Join-Path $employeeRoot 'output/cat-worker-review/engine'
New-Item -ItemType Directory -Force -Path $employeeOutput | Out-Null
$employeeLove=Join-Path $env:ProgramFiles 'LOVE/lovec.exe'
$employeeEnvironment=@{
    PICTURE_SHOP_SMOKE='1'
    PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-employees-'+[guid]::NewGuid().ToString('N')
    PICTURE_SHOP_EMPLOYEE_PREVIEW='1'
    PICTURE_SHOP_PREVIEW_OUTPUT=$employeeOutput
}
$employeePrevious=@{}
$employeeProcess=$null
try {
    foreach($key in $employeeEnvironment.Keys){$employeePrevious[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$employeeEnvironment[$key],'Process')}
    $employeeProcess=Start-Process -FilePath $employeeLove -ArgumentList ('"'+$employeeRoot+'"') -WorkingDirectory $employeeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $employeeOutput 'stdout.log') -RedirectStandardError (Join-Path $employeeOutput 'stderr.log')
    if(-not $employeeProcess.WaitForExit($TimeoutSeconds*1000)){throw 'Employee preview timed out.'}
    if($employeeProcess.ExitCode -ne 0){Get-Content (Join-Path $employeeOutput 'stdout.log') -Tail 15;throw 'Employee preview failed.'}
    Get-Content (Join-Path $employeeOutput 'engine-review.txt')
} finally {
    if($employeeProcess -and -not $employeeProcess.HasExited){Stop-Process -Id $employeeProcess.Id -Force}
    foreach($key in $employeePrevious.Keys){[Environment]::SetEnvironmentVariable($key,$employeePrevious[$key],'Process')}
}
