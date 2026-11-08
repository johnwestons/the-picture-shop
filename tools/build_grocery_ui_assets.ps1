$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $root 'assets/source/grocery-ui-v1'
$generated = Join-Path $root 'assets/generated/grocery-ui-v1'
$review = Join-Path $root 'output/grocery-ui-v1'
New-Item -ItemType Directory -Force -Path $generated, $review | Out-Null

$products = @('vegetables', 'bread', 'cereal', 'sandwich', 'drink', 'meal', 'cup', 'meal_pack')
$source = [System.Drawing.Bitmap]::new((Join-Path $sourceRoot 'grocery-product-icons-transparent-source.png'))
$atlas = [System.Drawing.Bitmap]::new(512, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$atlasGraphics = [System.Drawing.Graphics]::FromImage($atlas)
$atlasGraphics.Clear([System.Drawing.Color]::Transparent)
$atlasGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$atlasGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

try {
    for ($index = 0; $index -lt $products.Count; $index++) {
        $column = $index % 4
        $row = [int][Math]::Floor($index / 4)
        $cellLeft = [int][Math]::Round($column * $source.Width / 4)
        $cellRight = [int][Math]::Round(($column + 1) * $source.Width / 4)
        $cellTop = [int][Math]::Round($row * $source.Height / 2)
        $cellBottom = [int][Math]::Round(($row + 1) * $source.Height / 2)
        $minX, $minY = $cellRight, $cellBottom
        $maxX, $maxY = $cellLeft, $cellTop

        for ($y = $cellTop + 8; $y -lt $cellBottom - 8; $y++) {
            for ($x = $cellLeft + 8; $x -lt $cellRight - 8; $x++) {
                if ($source.GetPixel($x, $y).A -ge 32) {
                    $minX = [Math]::Min($minX, $x)
                    $minY = [Math]::Min($minY, $y)
                    $maxX = [Math]::Max($maxX, $x)
                    $maxY = [Math]::Max($maxY, $y)
                }
            }
        }
        if ($maxX -lt $minX -or $maxY -lt $minY) { throw "No product pixels found for $($products[$index])." }

        $bounds = [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
        $scale = 104.0 / [Math]::Max($bounds.Width, $bounds.Height)
        $width = [int][Math]::Round($bounds.Width * $scale)
        $height = [int][Math]::Round($bounds.Height * $scale)
        $destination = [System.Drawing.Rectangle]::new(
            $column * 128 + [int][Math]::Floor((128 - $width) / 2),
            $row * 128 + [int][Math]::Floor((128 - $height) / 2),
            $width, $height)
        $atlasGraphics.DrawImage($source, $destination, $bounds, [System.Drawing.GraphicsUnit]::Pixel)
    }

    $atlas.Save((Join-Path $generated 'grocery-products-atlas.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $atlasGraphics.Dispose()
    $atlas.Dispose()
    $source.Dispose()
}

$emblemSource = [System.Drawing.Bitmap]::new((Join-Path $sourceRoot 'grocery-ui-emblem-transparent-source.png'))
$emblem = [System.Drawing.Bitmap]::new(128, 128, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$emblemGraphics = [System.Drawing.Graphics]::FromImage($emblem)
$emblemGraphics.Clear([System.Drawing.Color]::Transparent)
$emblemGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$emblemGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
try {
    $minX, $minY = $emblemSource.Width, $emblemSource.Height
    $maxX, $maxY = 0, 0
    for ($y = 0; $y -lt $emblemSource.Height; $y++) {
        for ($x = 0; $x -lt $emblemSource.Width; $x++) {
            if ($emblemSource.GetPixel($x, $y).A -ge 32) {
                $minX = [Math]::Min($minX, $x)
                $minY = [Math]::Min($minY, $y)
                $maxX = [Math]::Max($maxX, $x)
                $maxY = [Math]::Max($maxY, $y)
            }
        }
    }
    if ($maxX -lt $minX -or $maxY -lt $minY) { throw 'No grocery emblem pixels found.' }
    $bounds = [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
    $scale = 120.0 / [Math]::Max($bounds.Width, $bounds.Height)
    $width = [int][Math]::Round($bounds.Width * $scale)
    $height = [int][Math]::Round($bounds.Height * $scale)
    $destination = [System.Drawing.Rectangle]::new([int][Math]::Floor((128 - $width) / 2),
        [int][Math]::Floor((128 - $height) / 2), $width, $height)
    $emblemGraphics.DrawImage($emblemSource, $destination, $bounds, [System.Drawing.GraphicsUnit]::Pixel)
    $emblem.Save((Join-Path $generated 'grocery-ui-emblem.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $emblemGraphics.Dispose()
    $emblem.Dispose()
    $emblemSource.Dispose()
}

$contact = [System.Drawing.Bitmap]::new(800, 460, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$contactGraphics = [System.Drawing.Graphics]::FromImage($contact)
$contactGraphics.Clear([System.Drawing.Color]::FromArgb(255, 32, 40, 34))
$contactGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
try {
    $sheet = [System.Drawing.Bitmap]::new((Join-Path $generated 'grocery-products-atlas.png'))
    try {
        for ($index = 0; $index -lt $products.Count; $index++) {
            $column = $index % 4
            $row = [int][Math]::Floor($index / 4)
            $sourceRect = [System.Drawing.Rectangle]::new($column * 128, $row * 128, 128, 128)
            $destRect = [System.Drawing.Rectangle]::new(26 + $column * 150, 20 + $row * 150, 128, 128)
            $contactGraphics.DrawImage($sheet, $destRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        }
    }
    finally { $sheet.Dispose() }
    $emblemPreview = [System.Drawing.Bitmap]::new((Join-Path $generated 'grocery-ui-emblem.png'))
    try { $contactGraphics.DrawImage($emblemPreview, 624, 318, 128, 128) }
    finally { $emblemPreview.Dispose() }
    $contact.Save((Join-Path $review 'grocery-ui-art-contact.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $contactGraphics.Dispose()
    $contact.Dispose()
}

Write-Output "Built 8 product icons and a grocery UI emblem from $sourceRoot"
