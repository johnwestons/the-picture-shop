param(
    [Parameter(Mandatory = $true)] [string] $Source,
    [string] $AtlasOutput = 'assets/commute/truck/moving-64.png',
    [string] $PreviewOutput = 'output/delivery-truck-moving-64-preview.png',
    [string] $ManifestOutput = 'assets/commute/truck/moving-64.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security.Cryptography

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$sourceImage = [System.Drawing.Bitmap]::FromFile($sourcePath)
$frameSize = 320
$sourceCell = 160
$grid = 8
$groundAnchorY = 286
$pixelCount = $sourceCell * $sourceCell
$atlas = [System.Drawing.Bitmap]::new($frameSize * $grid, $frameSize * $grid, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$preview = [System.Drawing.Bitmap]::new(1280, 1280, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$atlasGraphics = [System.Drawing.Graphics]::FromImage($atlas)
$previewGraphics = [System.Drawing.Graphics]::FromImage($preview)
$atlasGraphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
$atlasGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$atlasGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$previewGraphics.Clear([System.Drawing.Color]::FromArgb(255, 34, 41, 39))
$previewGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$previewGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$frameRecords = [System.Collections.Generic.List[object]]::new()
$frameHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$nonemptyFrames = 0

try {
    for ($index = 0; $index -lt 64; $index++) {
        $row = [int][Math]::Floor($index / $grid)
        $column = $index % $grid
        $sourceX = [single]($sourceImage.Width * $column / $grid)
        $sourceY = [single]($sourceImage.Height * $row / $grid)
        $sourceWidth = [single]($sourceImage.Width / $grid)
        $sourceHeight = [single]($sourceImage.Height / $grid)
        $tile = [System.Drawing.Bitmap]::new($sourceCell, $sourceCell, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $tileGraphics = [System.Drawing.Graphics]::FromImage($tile)
        $tileGraphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $tileGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $tileGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $tileGraphics.DrawImage($sourceImage,
            [System.Drawing.RectangleF]::new(0, 0, $sourceCell, $sourceCell),
            [System.Drawing.RectangleF]::new($sourceX, $sourceY, $sourceWidth, $sourceHeight),
            [System.Drawing.GraphicsUnit]::Pixel)
        $tileGraphics.Dispose()

        $foreground = [bool[]]::new($pixelCount)
        $visited = [bool[]]::new($pixelCount)
        for ($pixel = 0; $pixel -lt $pixelCount; $pixel++) {
            $color = $tile.GetPixel($pixel % $sourceCell, [int][Math]::Floor($pixel / $sourceCell))
            $foreground[$pixel] = $color.A -ge 24
        }

        $components = [System.Collections.Generic.List[object]]::new()
        for ($pixel = 0; $pixel -lt $pixelCount; $pixel++) {
            if (-not $foreground[$pixel] -or $visited[$pixel]) { continue }
            $queue = [System.Collections.Generic.Queue[int]]::new()
            $pixels = [System.Collections.Generic.List[int]]::new()
            $minX = $sourceCell; $minY = $sourceCell; $maxX = -1; $maxY = -1
            $visited[$pixel] = $true
            $queue.Enqueue($pixel)
            while ($queue.Count -gt 0) {
                $current = $queue.Dequeue()
                $pixels.Add($current)
                $x = $current % $sourceCell
                $y = [int][Math]::Floor($current / $sourceCell)
                $minX = [Math]::Min($minX, $x); $minY = [Math]::Min($minY, $y)
                $maxX = [Math]::Max($maxX, $x); $maxY = [Math]::Max($maxY, $y)
                for ($dy = -1; $dy -le 1; $dy++) {
                    for ($dx = -1; $dx -le 1; $dx++) {
                        if ($dx -eq 0 -and $dy -eq 0) { continue }
                        $nx = $x + $dx; $ny = $y + $dy
                        if ($nx -lt 0 -or $nx -ge $sourceCell -or $ny -lt 0 -or $ny -ge $sourceCell) { continue }
                        $next = $ny * $sourceCell + $nx
                        if ($foreground[$next] -and -not $visited[$next]) {
                            $visited[$next] = $true
                            $queue.Enqueue($next)
                        }
                    }
                }
            }
            $components.Add([pscustomobject]@{
                Pixels = $pixels
                Area = $pixels.Count
                MinX = $minX; MinY = $minY; MaxX = $maxX; MaxY = $maxY
            }) | Out-Null
        }
        if ($components.Count -eq 0) { throw "Empty truck sprite in frame $($index + 1)." }

        $primary = $components[0]
        foreach ($component in $components) {
            if ($component.Area -gt $primary.Area) { $primary = $component }
        }
        $keep = [bool[]]::new($pixelCount)
        $minimumSatelliteArea = [Math]::Max(5, [int][Math]::Floor($primary.Area / 1500))
        foreach ($component in $components) {
            $isPrimary = [object]::ReferenceEquals($component, $primary)
            $nearPrimary = $component.MinX -ge $primary.MinX - 2 -and $component.MaxX -le $primary.MaxX + 2 `
                -and $component.MinY -ge $primary.MinY - 2 -and $component.MaxY -le $primary.MaxY + 2
            if ($isPrimary -or ($nearPrimary -and $component.Area -ge $minimumSatelliteArea)) {
                foreach ($keptPixel in $component.Pixels) { $keep[$keptPixel] = $true }
            }
        }

        $minX = $sourceCell; $minY = $sourceCell; $maxX = -1; $maxY = -1
        $hashBytes = [byte[]]::new($pixelCount * 4)
        for ($pixel = 0; $pixel -lt $pixelCount; $pixel++) {
            $x = $pixel % $sourceCell
            $y = [int][Math]::Floor($pixel / $sourceCell)
            $color = $tile.GetPixel($x, $y)
            if (-not $keep[$pixel] -or $color.A -lt 24) {
                $tile.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
                continue
            }
            $minX = [Math]::Min($minX, $x); $minY = [Math]::Min($minY, $y)
            $maxX = [Math]::Max($maxX, $x); $maxY = [Math]::Max($maxY, $y)
            $offset = $pixel * 4
            $hashBytes[$offset] = $color.R; $hashBytes[$offset + 1] = $color.G
            $hashBytes[$offset + 2] = $color.B; $hashBytes[$offset + 3] = $color.A
        }
        if ($maxX -lt $minX -or $maxY -lt $minY -or $maxX - $minX -lt 20 -or $maxY - $minY -lt 20) {
            throw "Invalid truck silhouette in frame $($index + 1)."
        }
        $nonemptyFrames++
        $sha = [System.Security.Cryptography.SHA256]::HashData($hashBytes)
        $frameHash = [Convert]::ToHexString($sha).ToLowerInvariant()
        [void]$frameHashes.Add($frameHash)

        $boundsWidth = $maxX - $minX + 1
        $boundsHeight = $maxY - $minY + 1
        $scale = [Math]::Min(2.0, [Math]::Min(288.0 / $boundsWidth, 246.0 / $boundsHeight))
        $centerX = ($minX + $maxX + 1) * 0.5
        $groundY = $maxY + 1
        $drawX = $column * $frameSize + 160 - $centerX * $scale
        $drawY = $row * $frameSize + $groundAnchorY - $groundY * $scale
        $drawWidth = $sourceCell * $scale
        $drawHeight = $sourceCell * $scale
        $atlasGraphics.DrawImage($tile,
            [System.Drawing.RectangleF]::new([single]$drawX, [single]$drawY, [single]$drawWidth, [single]$drawHeight),
            [System.Drawing.Rectangle]::new(0, 0, $sourceCell, $sourceCell),
            [System.Drawing.GraphicsUnit]::Pixel)

        $frameRecords.Add([ordered]@{
            frame = $index + 1; row = $row + 1; column = $column + 1
            sourceCell = @($column, $row); sourceBounds = @($minX, $minY, $boundsWidth, $boundsHeight)
            sourceComponents = $components.Count; scale = [Math]::Round($scale, 4); sha256 = $frameHash
        }) | Out-Null
        $tile.Dispose()
        if (($index + 1) % 8 -eq 0) { "Compiled $($index + 1)/64 truck views" }
    }

    for ($index = 0; $index -lt 64; $index++) {
        $row = [int][Math]::Floor($index / $grid); $column = $index % $grid
        $previewGraphics.DrawImage($atlas,
            [System.Drawing.Rectangle]::new($column * 160, $row * 160, 160, 160),
            [System.Drawing.Rectangle]::new($column * $frameSize, $row * $frameSize, $frameSize, $frameSize),
            [System.Drawing.GraphicsUnit]::Pixel)
    }

    $atlasPath = [IO.Path]::GetFullPath($AtlasOutput)
    $previewPath = [IO.Path]::GetFullPath($PreviewOutput)
    $manifestPath = [IO.Path]::GetFullPath($ManifestOutput)
    foreach ($path in @($atlasPath, $previewPath, $manifestPath)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    }
    $manifestData = [ordered]@{
        version = 1; status = 'generated_64_view_turntable'
        source = 'assets/source/delivery-truck-turntable-v1/turntable-source.png'
        frameSize = $frameSize; columns = $grid; rows = $grid; frameCount = 64
        anchor = @(160, $groundAnchorY)
        sourceGrid = '8x8 clockwise full-turn atlas'
        angles = [ordered]@{ stepDegrees = 5.625; direction = 'clockwise'; frameOne = 'source-frame-01'; runtimeOffsetFrames = 0 }
        frames = @($frameRecords)
        validation = [ordered]@{
            expectedFrames = 64; nonemptyFrames = $nonemptyFrames; uniqueSourceFrameHashes = $frameHashes.Count
            transparentBackground = $true; mirroredAtRuntime = $false; connectedComponentCleanup = $true
        }
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    }
    $atlas.Save($atlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $preview.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $manifestData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
    "TRUCK_TURNTABLE_OK: 64 nonempty frames, $($frameHashes.Count) unique source frames"
    "ATLAS=$atlasPath"
    "PREVIEW=$previewPath"
    "MANIFEST=$manifestPath"
}
finally {
    $previewGraphics.Dispose(); $atlasGraphics.Dispose()
    $preview.Dispose(); $atlas.Dispose(); $sourceImage.Dispose()
}
