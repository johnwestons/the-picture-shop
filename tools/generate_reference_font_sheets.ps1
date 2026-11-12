Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path $PSScriptRoot -Parent
$outputDirectory = Join-Path $repoRoot 'assets\fonts\reference-inspired'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$glyphs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
$fontPlans = @(
    [pscustomobject]@{
        Name = 'groove_slab'
        Title = 'Groovy Slab'
        Family = 'Cooper Black'
        FontStyle = [System.Drawing.FontStyle]::Regular
        Ink = '#261B19'
        Background = '#F6EEDC'
        Accent = '#C77737'
        Gap = 34
        Tracking = 2
        Style = 'slab'
        Caption = 'A plump, sun-warmed slab with the friendly curves of a 1970s shop sign.'
        Sample = 'The Picture Shop  0123456789'
    },
    [pscustomobject]@{
        Name = 'arcade_flash'
        Title = 'Arcade Flash'
        Family = 'Bauhaus 93'
        FontStyle = [System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic
        Ink = '#FFE15B'
        Background = '#151925'
        Accent = '#4ED9F4'
        Gap = 50
        Tracking = 1
        Style = 'jolt'
        Caption = 'A chunky arcade face with angled color plates and bright 1980s depth.'
        Sample = 'The Picture Shop  0123456789'
    }
)

function Get-Color([string]$value) {
    return [System.Drawing.ColorTranslator]::FromHtml($value)
}

function New-TextPath([string]$text, [string]$familyName, [System.Drawing.FontStyle]$fontStyle, [single]$size, [single]$x, [single]$y) {
    $family = [System.Drawing.FontFamily]::new($familyName)
    $format = [System.Drawing.StringFormat]::new([System.Drawing.StringFormat]::GenericTypographic)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddString($text, $family, [int]$fontStyle, $size, [System.Drawing.PointF]::new($x, $y), $format)
    $format.Dispose()
    $family.Dispose()
    return $path
}

function Draw-ShiftedPath($graphics, $path, [single]$dx, [single]$dy, $pen = $null, $brush = $null) {
    $copy = [System.Drawing.Drawing2D.GraphicsPath]$path.Clone()
    $matrix = [System.Drawing.Drawing2D.Matrix]::new()
    $matrix.Translate($dx, $dy)
    $copy.Transform($matrix)
    if ($null -ne $pen) { $graphics.DrawPath($pen, $copy) }
    if ($null -ne $brush) { $graphics.FillPath($brush, $copy) }
    $matrix.Dispose()
    $copy.Dispose()
    if ($null -ne $pen) { $pen.Dispose() }
    if ($null -ne $brush) { $brush.Dispose() }
}

function New-RoundPen([string]$color, [single]$width) {
    $pen = [System.Drawing.Pen]::new((Get-Color $color), $width)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    return $pen
}

function Draw-StyledPath($graphics, $path, [string]$style, [single]$scale, [string]$ink) {
    if ($style -eq 'slab') {
        Draw-ShiftedPath $graphics $path (5 * $scale) (6 * $scale) (New-RoundPen '#BF6A32' (11 * $scale))
        $rim = New-RoundPen '#F4DFC0' (11 * $scale)
        $brush = [System.Drawing.SolidBrush]::new((Get-Color $ink))
        $graphics.DrawPath($rim, $path)
        $graphics.FillPath($brush, $path)
        $rim.Dispose(); $brush.Dispose()
        return
    }

    if ($style -eq 'script') {
        Draw-ShiftedPath $graphics $path (5 * $scale) (12 * $scale) (New-RoundPen '#77122E' (23 * $scale))
        $creamEdge = New-RoundPen '#FFE9D0' (23 * $scale)
        $outline = New-RoundPen '#BD1649' (17 * $scale)
        $glint = New-RoundPen '#FFC1D3' (5 * $scale)
        $fill = [System.Drawing.SolidBrush]::new((Get-Color $ink))
        $graphics.DrawPath($creamEdge, $path)
        $graphics.DrawPath($outline, $path)
        Draw-ShiftedPath $graphics $path (-1 * $scale) (-2 * $scale) $glint
        $graphics.FillPath($fill, $path)
        $creamEdge.Dispose(); $outline.Dispose(); $glint.Dispose(); $fill.Dispose()
        return
    }

    Draw-ShiftedPath $graphics $path (12 * $scale) (12 * $scale) (New-RoundPen '#111624' (19 * $scale))
    Draw-ShiftedPath $graphics $path (7 * $scale) (7 * $scale) (New-RoundPen '#EF3C58' (17 * $scale))
    Draw-ShiftedPath $graphics $path (-5 * $scale) (-3 * $scale) (New-RoundPen '#25B9E5' (13 * $scale))
    $outline = New-RoundPen '#22232A' (10 * $scale)
    $glint = New-RoundPen '#FFF2A4' (2.5 * $scale)
    $bounds = $path.GetBounds()
    $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new($bounds, (Get-Color '#FFF5A0'), (Get-Color $ink), 90.0)
    $graphics.DrawPath($outline, $path)
    $graphics.FillPath($gradient, $path)
    Draw-ShiftedPath $graphics $path (-1.5 * $scale) (-2 * $scale) $glint
    $outline.Dispose(); $glint.Dispose(); $gradient.Dispose()
}

function Draw-BoardText($graphics, [string]$text, $plan, [single]$size, [single]$centerY, [single]$left, [single]$right) {
    $path = New-TextPath $text $plan.Family $plan.FontStyle $size 0 0
    $bounds = $path.GetBounds()
    $availableWidth = $right - $left
    if ($bounds.Width -gt $availableWidth) {
        $path.Dispose()
        $size = $size * ($availableWidth / $bounds.Width)
        $path = New-TextPath $text $plan.Family $plan.FontStyle $size 0 0
        $bounds = $path.GetBounds()
    }
    $x = $left + (($availableWidth - $bounds.Width) / 2) - $bounds.X
    $y = $centerY - ($bounds.Y + ($bounds.Height / 2))
    $matrix = [System.Drawing.Drawing2D.Matrix]::new()
    $matrix.Translate($x, $y)
    $path.Transform($matrix)
    $scale = $size / 132.0
    Draw-StyledPath $graphics $path $plan.Style $scale $plan.Ink
    $matrix.Dispose(); $path.Dispose()
}

function Draw-Label($graphics, [string]$text, [single]$x, [single]$y, [single]$size, [string]$color, [bool]$bold = $false) {
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $font = [System.Drawing.Font]::new('Segoe UI', $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = [System.Drawing.SolidBrush]::new((Get-Color $color))
    $graphics.DrawString($text, $font, $brush, $x, $y, [System.Drawing.StringFormat]::GenericTypographic)
    $font.Dispose(); $brush.Dispose()
}

function Draw-BoardTitle($graphics, $plan, [single]$x, [single]$y, [single]$size) {
    $path = New-TextPath $plan.Title $plan.Family $plan.FontStyle $size $x $y
    Draw-StyledPath $graphics $path $plan.Style ($size / 132.0) $plan.Ink
    $path.Dispose()
}

function New-Atlas($plan) {
    $em = [single]132
    $atlasHeight = 224
    $startX = 28
    $topY = 30
    $paths = [System.Collections.Generic.List[object]]::new()
    $glyphBounds = [System.Collections.Generic.List[object]]::new()
    $cursor = [single]$startX
    foreach ($glyph in $glyphs.ToCharArray()) {
        $path = New-TextPath ([string]$glyph) $plan.Family $plan.FontStyle $em 0 $topY
        $bounds = $path.GetBounds()
        $matrix = [System.Drawing.Drawing2D.Matrix]::new()
        $matrix.Translate(($cursor - $bounds.X), 0)
        $path.Transform($matrix)
        $matrix.Dispose()
        $paths.Add($path)
        $glyphBounds.Add($path.GetBounds())
        $cursor += $bounds.Width + $plan.Gap
    }

    $atlasWidth = [int][Math]::Ceiling($cursor + $startX)
    $bitmap = [System.Drawing.Bitmap]::new($atlasWidth, $atlasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    foreach ($path in $paths) {
        Draw-StyledPath $graphics $path $plan.Style 1 $plan.Ink
        $path.Dispose()
    }
    $graphics.Dispose()
    # LÖVE's ImageFontFormat uses the upper-left pixel as the column separator
    # color. Mark glyph columns with a different, fully transparent top pixel;
    # otherwise the transparent top margin makes every atlas column look like
    # a separator and the image font loads with no visible glyphs.
    $leftPad = if ($plan.Style -eq 'slab') { 6 } else { 12 }
    $rightPad = if ($plan.Style -eq 'slab') { 12 } else { 22 }
    $glyphMarker = [System.Drawing.Color]::FromArgb(0, 1, 0, 1)
    foreach ($bounds in $glyphBounds) {
        $left = [Math]::Max(1, [int][Math]::Floor($bounds.Left - $leftPad))
        $right = [Math]::Min($atlasWidth - 1, [int][Math]::Ceiling($bounds.Right + $rightPad))
        for ($x = $left; $x -le $right; $x++) { $bitmap.SetPixel($x, 0, $glyphMarker) }
    }
    $bitmap.Save((Join-Path $outputDirectory ($plan.Name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    return [pscustomobject]@{ Width = $atlasWidth; Height = $atlasHeight; Em = $em }
}

function New-Specimen($plan) {
    $width = 1720
    $height = 1120
    $bitmap = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear((Get-Color $plan.Background))
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $margin = [single]86
    $right = [single]($width - $margin)

    if ($plan.Style -eq 'slab') {
        $line = [System.Drawing.Pen]::new((Get-Color '#D9CFBA'), 1)
        foreach ($y in @(220, 440, 660, 850, 1000)) { $graphics.DrawLine($line, $margin, $y, $right, $y) }
        $graphics.DrawLine($line, $margin, 220, $margin, 1000)
        $graphics.DrawLine($line, $right, 220, $right, 1000)
        $line.Dispose()
    } elseif ($plan.Style -eq 'script') {
        $border = [System.Drawing.Pen]::new((Get-Color '#F5C6D2'), 2)
        $graphics.DrawRectangle($border, 38, 38, $width - 76, $height - 76)
        $border.Dispose()
        $brush = [System.Drawing.SolidBrush]::new((Get-Color '#F8D7E0'))
        foreach ($x in @(72, ($width - 72))) { $graphics.FillEllipse($brush, $x - 5, 72, 10, 10) }
        $brush.Dispose()
    } else {
        $blue = [System.Drawing.Pen]::new((Get-Color '#263747'), 1)
        $red = [System.Drawing.Pen]::new((Get-Color '#3A2636'), 1)
        for ($x = 28; $x -lt $width; $x += 40) { $graphics.DrawLine($blue, $x, 0, $x, $height) }
        for ($y = 28; $y -lt $height; $y += 40) { $graphics.DrawLine($red, 0, $y, $width, $y) }
        $blue.Dispose(); $red.Dispose()
        $bar = [System.Drawing.SolidBrush]::new((Get-Color '#F04A5B'))
        $graphics.FillRectangle($bar, $margin, 40, 84, 8)
        $bar.Dispose()
    }

    $headerInk = if ($plan.Style -eq 'jolt') { '#AFC5D3' } else { '#554E44' }
    Draw-Label $graphics ('REFERENCE STUDY  /  ' + $plan.Name.Replace('_', ' ').ToUpperInvariant()) $margin 54 18 $headerInk $true
    Draw-BoardTitle $graphics $plan $margin 91 64
    Draw-Label $graphics $plan.Caption $margin 184 22 $headerInk $false

    $labelInk = if ($plan.Style -eq 'jolt') { '#93AAB9' } else { '#8B8174' }
    Draw-Label $graphics 'CAPITAL LETTERS' $margin 252 18 $labelInk $true
    Draw-BoardText $graphics 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' $plan 69 340 $margin $right
    Draw-Label $graphics 'LOWERCASE LETTERS' $margin 464 18 $labelInk $true
    Draw-BoardText $graphics 'abcdefghijklmnopqrstuvwxyz' $plan 70 550 $margin $right
    Draw-Label $graphics 'NUMERALS' $margin 676 18 $labelInk $true
    Draw-BoardText $graphics '0123456789' $plan 100 770 $margin $right
    Draw-BoardText $graphics $plan.Sample $plan 72 932 $margin $right
    Draw-Label $graphics 'A–Z   a–z   0–9' $margin 1030 17 $labelInk $false

    $bitmap.Save((Join-Path $outputDirectory ($plan.Name + '_sheet.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
}

$atlasInformation = @()
foreach ($plan in $fontPlans) {
    $fontFamily = [System.Drawing.FontFamily]::new($plan.Family)
    $fontFamily.Dispose()
    $dimensions = New-Atlas $plan
    New-Specimen $plan
    $atlasInformation += [pscustomobject]@{
        name = $plan.Name
        title = $plan.Title
        family = $plan.Family
        style = $plan.Style
        atlas = ($plan.Name + '.png')
        specimen = ($plan.Name + '_sheet.png')
        width = $dimensions.Width
        height = $dimensions.Height
        emPixels = $dimensions.Em
        glyphOrder = $glyphs
        description = $plan.Caption
    }
}

$atlasInformation | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $outputDirectory 'font-atlases.json')

$readme = @'
# Reference-inspired display font atlases

These two transparent PNGs are single-row bitmap font atlases sized for LÖVE's `love.graphics.newImageFont`. Their glyph order is `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789`. The image font supplies a regular space automatically; the 26 capitals, 26 lowercase letters, and 10 numerals are all present.

The preview sheets show the complete set and a short sample. Each atlas is 132 px em-height in a 224 px canvas, so it can be rendered sharply at large sizes and scaled down with linear filtering.

## Load in LÖVE

```lua
local glyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local base = "assets/fonts/reference-inspired/"

local fonts = {
    groovySlab = love.graphics.newImageFont(base .. "groove_slab.png", glyphs, 2),
    arcadeFlash = love.graphics.newImageFont(base .. "arcade_flash.png", glyphs, 3),
}

for _, font in pairs(fonts) do
    font:setFilter("linear", "linear")
end

love.graphics.setFont(fonts.groovySlab)
love.graphics.push()
love.graphics.translate(32, 32)
love.graphics.scale(0.25) -- 224px atlas height becomes a 56px display font.
love.graphics.print("The Picture Shop 0123456789", 0, 0)
love.graphics.pop()
```

Call `love.graphics.setFont` with either font to switch styles. The atlases are artwork and can be used directly in the game; no system font installation is needed at runtime.

## Styles

- **Groovy Slab** — plump, dark 1970s slab serif with warm ink depth, following the first reference.
- **Arcade Flash** — chunky yellow arcade display letters with red and cyan print plates, following the third reference.

The reference images were used as visual direction. The sets have been redrawn as complete, original atlas artwork using the installed Cooper Black and Bauhaus 93 type styles as construction bases. The included PowerShell generator can recreate the sheets on a Windows machine with those typefaces installed.
'@
$readme | Set-Content -Encoding utf8 (Join-Path $outputDirectory 'README.md')

$luaLoader = @'
local glyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local base = "assets/fonts/reference-inspired/"

local function make(image, spacing)
    local font = love.graphics.newImageFont(base .. image, glyphs, spacing)
    font:setFilter("linear", "linear")
    return font
end

return {
    glyphs = glyphs,
    load = function()
        return {
            groovySlab = make("groove_slab.png", 2),
            arcadeFlash = make("arcade_flash.png", 3),
        }
    end,
}
'@
$luaLoader | Set-Content -Encoding utf8 (Join-Path $outputDirectory 'font-atlases.lua')

Write-Output "Created two font atlases and preview sheets in $outputDirectory"
