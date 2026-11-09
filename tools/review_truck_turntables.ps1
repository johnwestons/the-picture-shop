$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$stage=Join-Path $root 'output/truck-angle-review/runtime-stage'
$output=Join-Path $root 'output/truck-angle-review'
$love=Join-Path $env:ProgramFiles 'LOVE/lovec.exe'
$saveRoot=Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-truck-capture'
if (-not (Test-Path -LiteralPath $love)) { throw "LÖVE console runtime not found: $love" }
if (Test-Path -LiteralPath $saveRoot) {
    $resolved=[IO.Path]::GetFullPath($saveRoot)
    $expected=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-truck-capture'))
    if ($resolved -ne $expected) { throw 'Unexpected truck capture save path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage,$output,(Join-Path $stage 'src/commute'),
    (Join-Path $stage 'assets/commute/truck/turntables'),(Join-Path $stage 'assets/commute/truck/decals') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'truck_turntable_capture/runtime_review.lua') -Destination (Join-Path $stage 'main.lua') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'truck_turntable_capture/conf.lua') -Destination $stage -Force
foreach ($name in @('truck_art.lua','truck_turntable_pages.lua','truck_decals.lua','truck_liveries.lua')) {
    Copy-Item -LiteralPath (Join-Path $root "src/commute/$name") -Destination (Join-Path $stage 'src/commute') -Force
}
Copy-Item -Path (Join-Path $root 'assets/commute/truck/turntables/*.png') -Destination (Join-Path $stage 'assets/commute/truck/turntables') -Force
Copy-Item -LiteralPath (Join-Path $root 'assets/commute/truck/decals/picture-shop.png') -Destination (Join-Path $stage 'assets/commute/truck/decals') -Force
$env:PICTURE_SHOP_TRUCK_CAPTURE_OUTPUT=$output
try {
    & $love $stage
    if ($LASTEXITCODE -ne 0) { throw "Truck runtime review failed with exit code $LASTEXITCODE" }
} finally {
    Remove-Item Env:PICTURE_SHOP_TRUCK_CAPTURE_OUTPUT -ErrorAction SilentlyContinue
    $resolvedStage=[IO.Path]::GetFullPath($stage)
    $expectedStage=[IO.Path]::GetFullPath((Join-Path $root 'output/truck-angle-review/runtime-stage'))
    if ($resolvedStage -ne $expectedStage) { throw 'Unexpected truck runtime stage path' }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
