$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourcePath = Join-Path $root 'assets/source/grocery-cart-motion-v1/grocery-cart-directions-refined-source.png'
$generated = Join-Path $root 'assets/generated/grocery-cart-v1'
$review = Join-Path $root 'output/grocery-cart-v1'
New-Item -ItemType Directory -Force -Path $generated, $review | Out-Null

$size = 128
$columns = 4
$rows = 5
$alphaCutoff = 180
$directions = @('north', 'northeast', 'east', 'southeast', 'south')
$source = [System.Drawing.Bitmap]::new($sourcePath)
$cells = @{}
$maximumHeight = 0

try {
    for ($row = 0; $row -lt $rows; $row++) {
        $rowCells = @()
        $frameCenters = @()
        $rowBaseline = 0

        for ($column = 0; $column -lt $columns; $column++) {
            $cellLeft = [int][Math]::Round($column * $source.Width / $columns)
            $cellRight = [int][Math]::Round(($column + 1) * $source.Width / $columns)
            $cellTop = [int][Math]::Round($row * $source.Height / $rows)
            $cellBottom = [int][Math]::Round(($row + 1) * $source.Height / $rows)
            $inset = 20
            $left = $cellLeft + $inset
            $right = $cellRight - $inset
            $top = $cellTop + $inset
            $bottom = $cellBottom - $inset
            $minX = $right
            $maxX = $left
            $minY = $bottom
            $maxY = $top

            for ($y = $top; $y -lt $bottom; $y++) {
                for ($x = $left; $x -lt $right; $x++) {
                    if ($source.GetPixel($x, $y).A -ge $alphaCutoff) {
                        if ($x -lt $minX) { $minX = $x }
                        if ($x -gt $maxX) { $maxX = $x }
                        if ($y -lt $minY) { $minY = $y }
                        if ($y -gt $maxY) { $maxY = $y }
                    }
                }
            }
            if ($maxX -lt $minX -or $maxY -lt $minY) {
                throw "No cart pixels found in direction row $($row + 1), frame $($column + 1)."
            }

            $bounds = [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
            $rowCells += ,@{ Bounds = $bounds; CellLeft = $cellLeft; CellTop = $cellTop; Cell = $column }
            $frameCenters += (($minX + $maxX + 1) / 2 - $cellLeft)
            $rowBaseline = [Math]::Max($rowBaseline, $maxY + 1 - $cellTop)
            $maximumHeight = [Math]::Max($maximumHeight, $bounds.Height)
        }

        $cells[$directions[$row]] = @{
            Frames = $rowCells
            CenterX = ($frameCenters | Measure-Object -Average).Average
            BaselineY = $rowBaseline
        }
    }

    $scale = 88.0 / $maximumHeight
    $atlas = [System.Drawing.Bitmap]::new($size * $columns, $size * $rows, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $atlasGraphics = [System.Drawing.Graphics]::FromImage($atlas)
    $atlasGraphics.Clear([System.Drawing.Color]::Transparent)
    $atlasGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $atlasGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    foreach ($row in 0..($rows - 1)) {
        $direction = $directions[$row]
        $directionData = $cells[$direction]
        $strip = [System.Drawing.Bitmap]::new($size * $columns, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stripGraphics = [System.Drawing.Graphics]::FromImage($strip)
        $stripGraphics.Clear([System.Drawing.Color]::Transparent)
        $stripGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $stripGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        foreach ($cell in $directionData.Frames) {
            $bounds = $cell.Bounds
            $destinationWidth = [int][Math]::Round($bounds.Width * $scale)
            $destinationHeight = [int][Math]::Round($bounds.Height * $scale)
            $localCenterX = $bounds.X + $bounds.Width / 2 - $cell.CellLeft
            $destinationX = $cell.Cell * $size + [int][Math]::Round($size / 2 - $localCenterX * $scale)
            $destinationY = [int][Math]::Round(112 - $directionData.BaselineY * $scale)
            $destination = [System.Drawing.Rectangle]::new($destinationX, $destinationY, $destinationWidth, $destinationHeight)
            $stripGraphics.DrawImage($source, $destination, $bounds, [System.Drawing.GraphicsUnit]::Pixel)
        }

        # The generator left a faint gray matte inside the transparent cell margins.
        # Keep the opaque cart structure and discard only its low-alpha residue.
        for ($y = 0; $y -lt $size; $y++) {
            for ($x = 0; $x -lt $size; $x++) {
                $pixel = $strip.GetPixel($x, $y)
                if ($pixel.A -lt $alphaCutoff) { $strip.SetPixel($x, $y, [System.Drawing.Color]::Transparent) }
            }
        }
        $atlasGraphics.DrawImageUnscaled($strip, 0, $row * $size)
        $strip.Save((Join-Path $generated "roll_$direction.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $idle = $strip.Clone([System.Drawing.Rectangle]::new(0, 0, $size, $size), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $idle.Save((Join-Path $generated "idle_$direction.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $idle.Dispose()
        $stripGraphics.Dispose()
        $strip.Dispose()
    }

    $atlas.Save((Join-Path $generated 'cart-roll-atlas.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $atlasGraphics.Dispose()
    $atlas.Dispose()
}
finally {
    $source.Dispose()
}

$contact = [System.Drawing.Bitmap]::new(4 * 160, 5 * 178, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$contactGraphics = [System.Drawing.Graphics]::FromImage($contact)
$contactGraphics.Clear([System.Drawing.Color]::FromArgb(255, 38, 43, 42))
$contactGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
for ($row = 0; $row -lt $rows; $row++) {
    $direction = $directions[$row]
    $strip = [System.Drawing.Bitmap]::new((Join-Path $generated "roll_$direction.png"))
    try {
        for ($column = 0; $column -lt $columns; $column++) {
            $sourceRect = [System.Drawing.Rectangle]::new($column * $size, 0, $size, $size)
            $destRect = [System.Drawing.Rectangle]::new($column * 160 + 16, $row * 178 + 8, 128, 128)
            $contactGraphics.DrawImage($strip, $destRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        }
    }
    finally { $strip.Dispose() }
}
$contact.Save((Join-Path $review 'cart-directions-contact.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$contactGraphics.Dispose()
$contact.Dispose()

Write-Output "Built 5 rolling directions and 5 idle views from $sourcePath"
Write-Output "Normalized source scale: $([Math]::Round($scale, 4)); shared wheel baseline: 112/$size"
