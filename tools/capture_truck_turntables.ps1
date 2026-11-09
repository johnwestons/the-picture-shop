param(
    [string] $Output = 'assets/commute/truck/turntables'
)

$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$captureSource=Join-Path $PSScriptRoot 'truck_turntable_capture'
$stage=Join-Path $root 'output/truck-angle-review/capture-stage'
$destination=[IO.Path]::GetFullPath((Join-Path $root $Output))
$masterDirectory=Join-Path $root 'assets/source/delivery-truck-64'
$master=Join-Path $masterDirectory 'truck-complete.png'
$saveRoot=Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-truck-capture'
$love=Join-Path $env:ProgramFiles 'LOVE/lovec.exe'
if (-not (Test-Path -LiteralPath $love)) { throw "LÖVE console runtime not found: $love" }

# This isolated capture identity may only contain disposable truck test data.
if (Test-Path -LiteralPath $saveRoot) {
    $resolved=[IO.Path]::GetFullPath($saveRoot)
    $expected=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-truck-capture'))
    if ($resolved -ne $expected) { throw 'Unexpected truck capture save path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $stage,$destination,$masterDirectory | Out-Null
foreach ($kind in @('chase','isometric')) {
    foreach ($page in 1..4) {
        foreach ($obsoleteName in @("$kind-64-picture-shop-$page.png","$kind-64-plain-$page.png")) {
            $obsolete=Join-Path $destination $obsoleteName
            if (Test-Path -LiteralPath $obsolete) { Remove-Item -LiteralPath $obsolete -Force }
        }
    }
}
Copy-Item -LiteralPath (Join-Path $captureSource 'main.lua'),(Join-Path $captureSource 'conf.lua') -Destination $stage -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'src/commute'),(Join-Path $stage 'assets/commute/truck') | Out-Null
foreach ($name in @('truck_elevated_art.lua','truck_cab_mesh.lua')) {
    Copy-Item -LiteralPath (Join-Path $root "src/commute/$name") -Destination (Join-Path $stage 'src/commute') -Force
}
Copy-Item -LiteralPath (Join-Path $root 'assets/commute/truck/elevated-panels.png') -Destination (Join-Path $stage 'assets/commute/truck') -Force
$env:PICTURE_SHOP_TRUCK_CAPTURE_OUTPUT=$destination
$env:PICTURE_SHOP_TRUCK_MASTER=$master
try {
    & $love $stage
    if ($LASTEXITCODE -ne 0) { throw "Truck capture failed with exit code $LASTEXITCODE" }
} finally {
    Remove-Item Env:PICTURE_SHOP_TRUCK_CAPTURE_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:PICTURE_SHOP_TRUCK_MASTER -ErrorAction SilentlyContinue
    $resolvedStage=[IO.Path]::GetFullPath($stage)
    $expectedStage=[IO.Path]::GetFullPath((Join-Path $root 'output/truck-angle-review/capture-stage'))
    if ($resolvedStage -ne $expectedStage) { throw 'Unexpected truck capture stage path' }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
Write-Output "TRUCK_TURNTABLE_CAPTURED=$destination"
Write-Output "TRUCK_COMPLETE_SHEET=$master"
& (Join-Path $PSScriptRoot 'validate_truck_turntables.ps1') -AtlasDirectory $Output
