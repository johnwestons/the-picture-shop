param(
    [ValidateSet('cutter','computer')][string]$Screen='cutter',
    [ValidateSet('active','www','calendar','inventory','email','bills','credit','credit-confirm','credit-pressed','hiring','schedule','warehouse','warehouse-confirm','clock','dropdown')][string]$Tab='active',
    [switch]$Mobile,
    [int]$Width=960,
    [int]$Height=678,
    [int]$TimeoutSeconds=90
)
$ErrorActionPreference='Stop'
$guiRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$guiOutput=Join-Path $guiRoot 'output/gui-integration-review'
$guiVariant=if($Screen -eq 'computer' -and $Tab -ne 'active'){'-'+$Tab}else{''}
$guiDimensions=if($Width -ne 960 -or $Height -ne 678){'-'+$Width+'x'+$Height}else{''}
$guiTag=$Screen+$guiVariant+$guiDimensions+$(if($Mobile){'-mobile'}else{'-pc'})
$guiPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $guiPython (Join-Path $guiRoot '.stabilization/gui-review/build_review.py')
if($LASTEXITCODE -ne 0){throw 'Could not package GUI review.'}
$guiEnvironment=@{
    PICTURE_SHOP_SMOKE='1'
    PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-gui-review-'+$guiTag
    PICTURE_SHOP_SMOKE_REPORT=Join-Path $guiOutput ($guiTag+'.rpt')
    PICTURE_SHOP_SMOKE_SCREENSHOT='1'
    PICTURE_SHOP_CUTTER_PREVIEW='0'
    PICTURE_SHOP_GUI_SCREEN=$Screen
    PICTURE_SHOP_GUI_TAB=$Tab
    PICTURE_SHOP_COMPUTER_ACTIVE_PREVIEW=$(if($Screen -eq 'computer' -and $Tab -eq 'active'){'1'}else{'0'})
    PICTURE_SHOP_COMPUTER_WWW_PREVIEW=$(if($Screen -eq 'computer' -and $Tab -eq 'www'){'1'}else{'0'})
    PICTURE_SHOP_COMPUTER_CALENDAR_PREVIEW=$(if($Screen -eq 'computer' -and $Tab -eq 'calendar'){'1'}else{'0'})
    PICTURE_SHOP_COMPUTER_INVENTORY_PREVIEW=$(if($Screen -eq 'computer' -and $Tab -eq 'inventory'){'1'}else{'0'})
    PICTURE_SHOP_COMPUTER_EMAIL_PREVIEW=$(if($Screen -eq 'computer' -and $Tab -eq 'email'){'1'}else{'0'})
    PICTURE_SHOP_COMPUTER_DROPDOWN_PREVIEW=$(if($Screen -eq 'computer' -and $Tab -eq 'dropdown'){'1'}else{'0'})
    PICTURE_SHOP_MOBILE=$(if($Mobile){'1'}else{'0'})
    PICTURE_SHOP_GUI_WIDTH=[string]$Width
    PICTURE_SHOP_GUI_HEIGHT=[string]$Height
}
$guiPrevious=@{}
$guiProcess=$null
try {
    foreach($key in $guiEnvironment.Keys){
        $guiPrevious[$key]=[Environment]::GetEnvironmentVariable($key,'Process')
        [Environment]::SetEnvironmentVariable($key,$guiEnvironment[$key],'Process')
    }
    $guiProcess=Start-Process -FilePath (Join-Path $env:ProgramFiles 'LOVE/lovec.exe') `
        -ArgumentList ('"'+(Join-Path $guiOutput 'game-review.love')+'"') `
        -WorkingDirectory $guiRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $guiOutput ($guiTag+'-stdout.log')) `
        -RedirectStandardError (Join-Path $guiOutput ($guiTag+'-stderr.log'))
    if(-not $guiProcess.WaitForExit($TimeoutSeconds*1000)){throw 'GUI review timed out.'}
    Get-Content (Join-Path $guiOutput ($guiTag+'-stdout.log')) -Tail 12
    if($guiProcess.ExitCode -ne 0){throw 'GUI review failed.'}
    $guiReport=Join-Path $guiOutput ($guiTag+'.rpt')
    if(-not (Select-String -LiteralPath $guiReport -SimpleMatch 'SMOKE_OK' -Quiet)){throw 'GUI review did not complete its checks.'}
    $guiSaveRoot=Join-Path $env:APPDATA ('LOVE/'+$guiEnvironment.PICTURE_SHOP_TEST_IDENTITY)
    Copy-Item -LiteralPath (Join-Path $guiSaveRoot 'smoke-preview.png') -Destination (Join-Path $guiOutput ($guiTag+'.png'))
    Get-Content $guiReport -Tail 4
} finally {
    if($guiProcess -and -not $guiProcess.HasExited){Stop-Process -Id $guiProcess.Id -Force}
    foreach($key in $guiPrevious.Keys){[Environment]::SetEnvironmentVariable($key,$guiPrevious[$key],'Process')}
}
