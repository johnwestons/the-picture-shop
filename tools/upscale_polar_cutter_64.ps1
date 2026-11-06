param(
    [string]$InputPath = (Join-Path $PSScriptRoot "..\assets\generated\polar-cutter-64-v1.png"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\assets\generated\polar-cutter-64-v2.png")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$sourcePath = (Resolve-Path -LiteralPath $InputPath).Path
$destinationPath = [IO.Path]::GetFullPath($OutputPath)
$source = [System.Drawing.Bitmap]::new($sourcePath)
$target = $null
$graphics = $null
try {
    if ($source.Width -ne 2048 -or $source.Height -ne 2048) {
        throw "Expected an 8x8 atlas of 256px frames; got $($source.Width)x$($source.Height)."
    }

    $target = [System.Drawing.Bitmap]::new(3072, 3072,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source,
        [System.Drawing.Rectangle]::new(0, 0, 3072, 3072),
        [System.Drawing.Rectangle]::new(0, 0, 2048, 2048),
        [System.Drawing.GraphicsUnit]::Pixel)
    $target.Save($destinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    if ($graphics) { $graphics.Dispose() }
    if ($target) { $target.Dispose() }
    $source.Dispose()
}

Write-Output "Wrote 64-view cutter atlas at 384px per frame: $destinationPath"
