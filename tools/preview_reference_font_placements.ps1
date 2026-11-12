$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Rectangle].Assembly.Location) -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public sealed class FontAtlas : IDisposable
{
    public readonly Bitmap Image;
    public readonly float EmPixels;
    public readonly float TopOrigin;
    public readonly float Tracking;
    private readonly string order;
    private readonly Rectangle[] glyphs;

    public FontAtlas(string path, string order, float emPixels, float topOrigin, float tracking)
    {
        Image = new Bitmap(path);
        EmPixels = emPixels;
        TopOrigin = topOrigin;
        Tracking = tracking;
        this.order = order;
        glyphs = new Rectangle[order.Length];
        int runCount = 0;
        int start = -1, minY = Image.Height, maxY = -1;
        for (int x = 0; x < Image.Width; x++)
        {
            bool active = false;
            int columnMin = Image.Height, columnMax = -1;
            for (int y = 0; y < Image.Height; y++)
            {
                if (Image.GetPixel(x, y).A > 0)
                {
                    active = true;
                    columnMin = Math.Min(columnMin, y);
                    columnMax = Math.Max(columnMax, y);
                }
            }
            if (active)
            {
                if (start < 0) { start = x; minY = columnMin; maxY = columnMax; }
                else { minY = Math.Min(minY, columnMin); maxY = Math.Max(maxY, columnMax); }
            }
            else if (start >= 0)
            {
                if (runCount < glyphs.Length) glyphs[runCount++] = new Rectangle(start, minY, x - start, maxY - minY + 1);
                start = -1; minY = Image.Height; maxY = -1;
            }
        }
        if (start >= 0 && runCount < glyphs.Length) glyphs[runCount++] = new Rectangle(start, minY, Image.Width - start, maxY - minY + 1);
        if (runCount != order.Length)
            throw new InvalidOperationException("Atlas glyph segmentation expected " + order.Length + " glyphs, found " + runCount + ".");
    }

    public float Measure(string text, float size)
    {
        float scale = size / EmPixels, width = 0;
        foreach (char ch in text)
        {
            if (ch == ' ') width += size * .34f;
            else
            {
                int index = order.IndexOf(ch);
                if (index < 0) throw new InvalidOperationException("Atlas does not contain the glyph: " + ch);
                width += (glyphs[index].Width + Tracking) * scale;
            }
        }
        return width;
    }

    public float Draw(Graphics g, string text, float x, float y, float size)
    {
        float scale = size / EmPixels;
        foreach (char ch in text)
        {
            if (ch == ' ') { x += size * .34f; continue; }
            int index = order.IndexOf(ch);
            if (index < 0) throw new InvalidOperationException("Atlas does not contain the glyph: " + ch);
            Rectangle r = glyphs[index];
            var dest = new RectangleF(x, y + (r.Y - TopOrigin) * scale, r.Width * scale, r.Height * scale);
            g.DrawImage(Image, dest, r, GraphicsUnit.Pixel);
            x += (r.Width + Tracking) * scale;
        }
        return x;
    }

    public void Dispose() { Image.Dispose(); }
}
"@

$repoRoot = Split-Path $PSScriptRoot -Parent
$reviewDir = Join-Path $repoRoot 'output\font-placement-review'
New-Item -ItemType Directory -Force -Path $reviewDir | Out-Null
$atlasDir = Join-Path $repoRoot 'assets\fonts\reference-inspired'
$glyphOrder = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
$groovy = [FontAtlas]::new((Join-Path $atlasDir 'groove_slab.png'), $glyphOrder, 132, 30, 2)
$arcade = [FontAtlas]::new((Join-Path $atlasDir 'arcade_flash.png'), $glyphOrder, 132, 30, 3)

function Color([string]$hex, [int]$alpha = 255) {
    $rgb = [System.Drawing.ColorTranslator]::FromHtml($hex)
    return [System.Drawing.Color]::FromArgb($alpha, $rgb.R, $rgb.G, $rgb.B)
}
function Brush([string]$hex, [int]$alpha = 255) {
    return [System.Drawing.SolidBrush]::new((Color $hex $alpha))
}
function Pen([string]$hex, [single]$width = 1, [int]$alpha = 255) {
    return [System.Drawing.Pen]::new((Color $hex $alpha), $width)
}
function New-Graphics($bitmap) {
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return $g
}
function FillRect($g, [string]$hex, [single]$x, [single]$y, [single]$w, [single]$h, [int]$alpha = 255) {
    $b = Brush $hex $alpha; $g.FillRectangle($b, $x, $y, $w, $h); $b.Dispose()
}
function StrokeRect($g, [string]$hex, [single]$x, [single]$y, [single]$w, [single]$h, [single]$width = 1, [int]$alpha = 255) {
    $p = Pen $hex $width $alpha; $g.DrawRectangle($p, $x, $y, $w, $h); $p.Dispose()
}
function Draw-Plain($g, [string]$text, [single]$x, [single]$y, [single]$size, [string]$hex = '#F4EEDB', [bool]$bold = $false, [bool]$center = $false, [single]$maxWidth = 2000) {
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $font = [System.Drawing.Font]::new('Segoe UI', $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
    while ($size -gt 8 -and $g.MeasureString($text, $font).Width -gt $maxWidth) {
        $font.Dispose(); $size -= 1
        $font = [System.Drawing.Font]::new('Segoe UI', $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
    }
    $brush = Brush $hex
    $format = [System.Drawing.StringFormat]::new([System.Drawing.StringFormat]::GenericTypographic)
    if ($center) { $format.Alignment = [System.Drawing.StringAlignment]::Center }
    $g.DrawString($text, $font, $brush, [System.Drawing.RectangleF]::new($x, $y, $maxWidth, 100), $format)
    $format.Dispose(); $font.Dispose(); $brush.Dispose()
}
function Draw-Atlas($g, $atlas, [string]$text, [single]$x, [single]$y, [single]$size, [single]$maxWidth = 0, [string]$align = 'left') {
    if ($maxWidth -gt 0) {
        while ($size -gt 12 -and $atlas.Measure($text, $size) -gt $maxWidth) { $size -= 1 }
        if ($align -eq 'center') { $x += ($maxWidth - $atlas.Measure($text, $size)) / 2 }
        elseif ($align -eq 'right') { $x += $maxWidth - $atlas.Measure($text, $size) }
    }
    $atlas.Draw($g, $text, $x, $y, $size) | Out-Null
}
function Load-Image([string]$relativePath) {
    return [System.Drawing.Bitmap]::new((Join-Path $repoRoot $relativePath))
}
function Draw-Crop($g, $image, [single]$x, [single]$y, [single]$w, [single]$h, [single]$sx = 0, [single]$sy = 0, [single]$sw = -1, [single]$sh = -1) {
    if ($sw -lt 0) { $sw = $image.Width }
    if ($sh -lt 0) { $sh = $image.Height }
    $dest = [System.Drawing.RectangleF]::new($x, $y, $w, $h)
    $src = [System.Drawing.Rectangle]::new([int]$sx, [int]$sy, [int]$sw, [int]$sh)
    $g.DrawImage($image, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
}
function New-Screen() {
    $bitmap = [System.Drawing.Bitmap]::new(960, 678, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    return [pscustomobject]@{ Bitmap = $bitmap; Graphics = (New-Graphics $bitmap) }
}
function Save-Screen($screen, $path) {
    $screen.Graphics.Dispose()
    $screen.Bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $screen.Bitmap.Dispose()
}
function New-Board([string]$title, [string]$subtitle, [string]$background, [int]$height = 760) {
    $bitmap = [System.Drawing.Bitmap]::new(1920, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = New-Graphics $bitmap
    $g.Clear((Color $background))
    Draw-Plain $g $title 60 34 42 '#F5EEDB' $true
    Draw-Plain $g $subtitle 62 84 21 '#AEB9B5'
    $line = Pen '#8D9A8E' 1 110; $g.DrawLine($line, 60, 120, 1860, 120); $line.Dispose()
    return [pscustomobject]@{ Bitmap = $bitmap; Graphics = $g }
}
function Draw-BoardCard($g, [single]$x, [single]$y, [string]$title, [string]$source, [string]$note, $screenBitmap, [single]$cardWidth = 580) {
    Draw-Plain $g $title $x $y 23 '#F4EEDB' $true
    Draw-Plain $g $source $x ($y + 31) 14 '#97A39C'
    $screenY = $y + 57
    $screenHeight = $cardWidth * 678 / 960
    $g.DrawImage($screenBitmap, $x, $screenY, $cardWidth, $screenHeight)
    StrokeRect $g '#C9B98E' $x $screenY $cardWidth $screenHeight 1 170
    Draw-Plain $g $note $x ($screenY + $screenHeight + 8) 15 '#D7D2C2' $false $false $cardWidth
    $screenBitmap.Dispose()
}
function Save-Board($board, [string]$filename) {
    $board.Graphics.Dispose()
    $board.Bitmap.Save((Join-Path $reviewDir $filename), [System.Drawing.Imaging.ImageFormat]::Png)
    $board.Bitmap.Dispose()
}

$warehouse = Load-Image 'assets\generated\warehouse-condition-v1\warehouse-restored-lights-off.png'
$grandOpeningBg = Load-Image 'assets\generated\story-barn-v1\barn-interior-v1.png'
$groceryEmblem = Load-Image 'assets\generated\grocery-ui-v1\grocery-ui-emblem.png'
$groceryProducts = Load-Image 'assets\generated\grocery-ui-v1\grocery-products-atlas.png'
$gasConcept = Load-Image 'assets\generated\gas-station-interior-v1\interior-concept.png'
$barnBg = Load-Image 'assets\generated\story-barn-v1\barn-interior-v1.png'
$grandpa = Load-Image 'assets\generated\story-intro\grandpa-seated-v1.png'
$crisisBg = Load-Image 'assets\generated\critter-crisis-v1\transit-yard.png'
$airHockeyRink = Load-Image 'assets\generated\breakroom-games-v1\air-hockey-rink.png'

$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#111B1A' 0 0 960 678 255
FillRect $g '#1A2927' 64 58 832 562 255; StrokeRect $g '#927C51' 64 58 832 562 2
FillRect $g '#273A36' 80 74 800 82 255
Draw-Atlas $g $groovy 'SHOP CASH FLOW' 104 86 34
Draw-Plain $g 'PAYROLL  /  THIS WEEK' 104 133 13 '#B4C1B4' $true
 $cardLabels = @('AVAILABLE CASH','EXPECTED INCOME','WEEKLY COSTS')
 $cardValues = @('$1,420','$3,860','$2,940')
for ($i=0; $i -lt 3; $i++) {
    $x = 100 + $i * 254
    FillRect $g '#263A37' $x 188 238 84 255; FillRect $g '#BD995C' $x 188 5 84 255
    Draw-Plain $g $cardLabels[$i] ($x + 17) 202 13 '#B8C5BD' $true  $false 205
    Draw-Plain $g $cardValues[$i] ($x + 17) 229 25 '#E2C77E' $true  $false 205
}
Draw-Plain $g 'TODAY  /  CASH ON HAND' 100 308 15 '#69D4CA' $true
Draw-Plain $g 'Bank balance      $2,240' 100 344 16 '#E8E7D8'
Draw-Plain $g 'Unpaid wages        $540' 100 376 16 '#E8E7D8'
Draw-Plain $g 'Bills and loans      $280' 100 408 16 '#E8E7D8'
Draw-Plain $g 'Forecast costs' 492 308 15 '#E2C77E' $true
for ($i=0; $i -lt 4; $i++) { FillRect $g '#3E514C' 492 (348+40*$i) 300 11 255; FillRect $g '#79C6A1' 492 (348+40*$i) (180-22*$i) 11 255 }
FillRect $g '#172421' 100 514 760 62 255
Draw-Plain $g 'ORDER FORECAST' 116 528 14 '#69D4CA' $true
Draw-Plain $g '3 delivered jobs  /  8 work units left' 116 551 13 '#DBE0D2'
Save-Screen $screen (Join-Path $reviewDir 'groovy-finance.png')

$screen = New-Screen; $g = $screen.Graphics
Draw-Crop $g $warehouse 0 0 960 678
FillRect $g '#06312D' 0 0 960 678 155
for ($x=0; $x -lt 112; $x+=38) { FillRect $g '#08706D' $x 0 12 678 72; FillRect $g '#08706D' (848+$x) 0 12 678 72 }
FillRect $g '#9A3127' 90 134 780 132 255; FillRect $g '#E6B64F' 96 140 768 120 255
FillRect $g '#073D3B' 102 146 756 108 255; StrokeRect $g '#F5E6B9' 110 154 740 92 3
Draw-Atlas $g $groovy 'THE PICTURE SHOP' 130 159 25 700 'center'
Draw-Atlas $g $groovy 'GRAND OPENING' 130 188 43 700 'center'
Draw-Plain $g 'TEN YEARS CLOSED  /  ONE MORE CHANCE' 170 302 16 '#F0D892' $true $true 620
for ($i=0; $i -lt 48; $i++) {
    $x = (37 + $i*89) % 960; $y = (17 + $i*61) % 678
    $b = Brush ($(if ($i % 3 -eq 0) {'#F2C15D'} elseif ($i % 3 -eq 1) {'#E4534E'} else {'#78BBA2'})) 220
    $g.FillRectangle($b,$x,$y,5,11);$b.Dispose()
}
Save-Screen $screen (Join-Path $reviewDir 'groovy-grand-opening.png')

$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#071218' 0 0 960 678 255
FillRect $g '#0B1D25' 42 34 876 608 255; StrokeRect $g '#167B78' 42 34 876 608 2
FillRect $g '#B7B7AE' 54 46 852 60 255
Draw-Atlas $g $groovy 'PICTURE SHOP WORK PHONE' 75 54 28 810 'left'
FillRect $g '#0B2028' 62 120 352 476 255; StrokeRect $g '#1F6870' 62 120 352 476 2
FillRect $g '#162A32' 432 120 426 342 255; StrokeRect $g '#34787B' 432 120 426 342 1
Draw-Plain $g 'CONTACT DIRECTORY' 458 145 25 '#B6DEDA' $true
Draw-Plain $g 'Pick up the receiver and dial a contact.' 458 180 16 '#E6ECE6'
foreach ($entry in @(@(197,'TOWN GROCERY'),@(236,'POWER COMPANY'),@(275,'PAPER SUPPLIER'))) {
    FillRect $g '#102C32' 458 $entry[0] 372 34 255; StrokeRect $g '#286E71' 458 $entry[0] 372 34 1
    Draw-Plain $g $entry[1] 470 ($entry[0]+8) 15 '#F3D36D' $true
}
FillRect $g '#145B52' 508 484 330 54 255; StrokeRect $g '#48C8B7' 508 484 330 54 1
Draw-Plain $g 'ANSWER' 508 500 18 '#F1F2E8' $true $true 330
FillRect $g '#681E31' 508 552 330 44 255; StrokeRect $g '#CF5667' 508 552 330 44 1
Draw-Plain $g 'HANG UP' 508 565 16 '#F1F2E8' $true $true 330
Save-Screen $screen (Join-Path $reviewDir 'groovy-work-phone.png')

$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#081414' 0 0 960 678 255
FillRect $g '#102326' 140 56 680 566 255; StrokeRect $g '#77A89A' 140 56 680 566 2
Draw-Atlas $g $groovy 'SHOP CLOCK' 170 80 38 620 'center'
Draw-Plain $g 'MONDAY  /  FEBRUARY 02' 180 130 18 '#D6E5D8' $false $true 600
 $clockFace=Brush '#E8E4D4'; $g.FillEllipse($clockFace,360,185,240,240); $clockFace.Dispose()
 $clockRim=Pen '#BA8A3D' 6; $g.DrawEllipse($clockRim,360,185,240,240); $clockRim.Dispose()
foreach ($entry in @(@('12',470,196),@('3',555,296),@('6',470,394),@('9',385,296))) {
    Draw-Plain $g $entry[0] $entry[1] $entry[2] 18 '#253C3B' $true $true 22
}
 $hourHand=Pen '#253C3B' 7; $g.DrawLine($hourHand,480,305,480,238); $hourHand.Dispose()
 $minuteHand=Pen '#253C3B' 4; $g.DrawLine($minuteHand,480,305,536,280); $minuteHand.Dispose()
 $clockHub=Brush '#8E3528'; $g.FillEllipse($clockHub,472,297,16,16); $clockHub.Dispose()
Draw-Plain $g 'GAME SPEED' 250 468 18 '#A7D1C1' $true $true 460
foreach ($entry in @(@(260,'1X'),@(370,'2X'),@(480,'5X'),@(590,'10X'))) {
    FillRect $g '#193735' $entry[0] 510 90 48 255; StrokeRect $g '#74A796' $entry[0] 510 90 48 1
    Draw-Plain $g $entry[1] $entry[0] 522 17 '#E7E3CF' $true $true 90
}
Save-Screen $screen (Join-Path $reviewDir 'groovy-shop-clock.png')

$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#12191B' 0 0 960 678 255
FillRect $g '#222C2E' 82 54 796 570 255; StrokeRect $g '#747E76' 82 54 796 570 2
Draw-Atlas $g $groovy 'SHOP CONTROL' 116 82 38 728 'left'
Draw-Plain $g 'OPTIONS  /  O KEY OR CONTROLLER START' 118 132 15 '#BEC7C1' $true
foreach ($entry in @(@(165,'GAME'),@(365,'AUDIO'),@(565,'CONTROLS'))) {
    FillRect $g '#344342' $entry[0] 184 180 48 255; StrokeRect $g '#829389' $entry[0] 184 180 48 1
    Draw-Plain $g $entry[1] $entry[0] 198 16 '#ECE8D8' $true $true 180
}
Draw-Plain $g 'DISPLAY, CAMERA & VISIBILITY' 165 264 20 '#D9DED5' $true
foreach ($entry in @(@(165,'Fullscreen'),@(374,'VSync'),@(583,'Follow Player Camera'))) {
    FillRect $g '#2C3534' $entry[0] 308 180 92 255; StrokeRect $g '#65726B' $entry[0] 308 180 92 1
    Draw-Plain $g $entry[1] ($entry[0]+12) 328 15 '#E5E9E0' $false $false 156
    Draw-Plain $g 'ON' ($entry[0]+12) 360 16 '#E9CD73' $true $false 156
}
Save-Screen $screen (Join-Path $reviewDir 'groovy-options.png')

$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#111719' 0 0 960 678 255
FillRect $g '#1E292A' 38 28 884 622 255; StrokeRect $g '#8A7952' 38 28 884 622 2
Draw-Atlas $g $groovy 'POLAR 115 MAINTENANCE CENTER' 64 50 31 832 'left'
Draw-Plain $g 'HELP AND MACHINE CARE' 66 98 16 '#C8D3CC' $true
foreach ($entry in @(@(66,'HELP / INSTRUCTIONS'),@(318,'MAINTENANCE'),@(570,'CLOSE'))) {
    FillRect $g '#34403C' $entry[0] 146 226 46 255; StrokeRect $g '#9B8958' $entry[0] 146 226 46 1
    Draw-Plain $g $entry[1] $entry[0] 159 14 '#F0EAD8' $true $true 226
}
Draw-Plain $g 'MAINTENANCE KITS' 74 228 20 '#E4D49D' $true
Draw-Plain $g 'Choose a kit to inspect its parts and service steps.' 74 258 15 '#C9D3CD'
$maintenanceItems=@('BLADE  /  CUTTING ASSEMBLY','GREASE  /  HIGH-PRESSURE FITTINGS','CLEANING  /  ROLLERS AND GUIDES')
for ($i=0; $i -lt $maintenanceItems.Count; $i++) {
    $rowY=300+$i*62
    FillRect $g '#2A3736' 74 $rowY 812 48 255; StrokeRect $g '#596963' 74 $rowY 812 48 1
    Draw-Plain $g $maintenanceItems[$i] 94 ($rowY+15) 16 '#E7E7D8' $true
}
Save-Screen $screen (Join-Path $reviewDir 'groovy-maintenance.png')

$board = New-Board 'GROOVY SLAB  /  MENUS AND SHOP STORY' 'Use it for short page headings where no handpicked font is assigned. Leave the main title and setup screens in their existing metal and paper faces.' '#18211F' 1220
Draw-BoardCard $board.Graphics 60 142 '01  FINANCE PANEL' 'src/screens/shop_budget.lua:59' 'One title above the figures; keep every number and row label in current UI text.' (Load-Image 'output\font-placement-review\groovy-finance.png')
Draw-BoardCard $board.Graphics 675 142 '02  GRAND OPENING' 'src/story_grand_opening.lua:78-79' 'Headline treatment only; leave welcome dialogue and timing unchanged.' (Load-Image 'output\font-placement-review\groovy-grand-opening.png')
Draw-BoardCard $board.Graphics 1290 142 '03  WORK PHONE' 'src/screens/work_phone_screen.lua:112,189' 'Main device title or contact-page heading only; keep caller details and actions in their current type.' (Load-Image 'output\font-placement-review\groovy-work-phone.png')
Draw-BoardCard $board.Graphics 60 635 '04  SHOP CLOCK' 'src/screens/shop_clock.lua:63' 'Use on the compact time-control panel title; leave date, speed values, and controls alone.' (Load-Image 'output\font-placement-review\groovy-shop-clock.png')
Draw-BoardCard $board.Graphics 675 635 '05  OPTIONS' 'src/screens/options_screen.lua:1270' 'Use on SHOP CONTROL only; leave the tab names and option labels as-is.' (Load-Image 'output\font-placement-review\groovy-options.png')
Draw-BoardCard $board.Graphics 1290 635 '06  MAINTENANCE MENU' 'src/screens/machine/maintenance.lua:78' 'Style the machine-care page title; keep instructions, safety steps, and kit details in the readable UI font.' (Load-Image 'output\font-placement-review\groovy-maintenance.png')
Save-Board $board 'groovy-slab-placements.png'

## Arcade Flash: Critter Crisis titles and an optional short stage card.
$screen = New-Screen; $g = $screen.Graphics
Draw-Crop $g $crisisBg 0 0 960 678
FillRect $g '#07101E' 0 0 960 678 123
FillRect $g '#06101A' 0 0 960 78 245
Draw-Atlas $g $arcade 'CRITTER CRISIS' 165 15 53 630 'center'
FillRect $g '#06101A' 35 145 890 463 205
Draw-Plain $g 'THREE MISSIONS  /  ONE SHOT AT A TIME' 80 177 25 '#F5EEDB' $true $true 800
foreach ($i in 0..2) { Draw-Plain $g @('01  NEON TRANSIT YARD','02  REACTOR TOWER','03  FLOODLIGHT DOCKS')[$i] 112 (244+41*$i) 25 '#AFC4C6' $true $false 736 }
foreach ($i in 0..2) { FillRect $g '#122432' (50+295*$i) 390 270 70 240; StrokeRect $g '#EAB65A' (50+295*$i) 390 270 70 2; Draw-Plain $g @('SOLO MISSION','HOST CO-OP','JOIN PLAYER')[$i] (50+295*$i) 412 17 '#F4EEDB' $true $true 270 }
Draw-Plain $g 'Aim and fire  /  hold cover  /  reload between volleys' 100 551 18 '#DBE0D2' $false $true 760
Save-Screen $screen (Join-Path $reviewDir 'arcade-crisis-menu.png')

$screen = New-Screen; $g = $screen.Graphics
Draw-Crop $g $crisisBg 0 0 960 678
FillRect $g '#07101E' 0 0 960 678 135
FillRect $g '#06101A' 130 203 700 366 225; StrokeRect $g '#52DDF2' 130 203 700 366 3
Draw-Atlas $g $arcade 'CRISIS CLEARED' 154 263 56 652 'center'
Draw-Plain $g 'FINAL SCORE  008420' 180 356 30 '#F8DD79' $true $true 600
Draw-Plain $g 'THREE MISSIONS COMPLETE' 180 416 19 '#D3E2E3' $true $true 600
FillRect $g '#15283A' 335 482 290 58 255; StrokeRect $g '#E8495C' 335 482 290 58 2
Draw-Plain $g 'PLAY AGAIN' 335 500 18 '#F5EEDB' $true $true 290
Save-Screen $screen (Join-Path $reviewDir 'arcade-results.png')

$screen = New-Screen; $g = $screen.Graphics
Draw-Crop $g $crisisBg 0 0 960 678
FillRect $g '#070B16' 0 0 960 678 178
for ($i=0; $i -lt 12; $i++) { FillRect $g '#152436' (40+78*$i) 74 32 530 180 }
Draw-Plain $g 'OPTIONAL STAGE INTRO  /  MOCK-UP' 65 56 18 '#84E4F2' $true
Draw-Atlas $g $arcade 'NEON TRANSIT YARD' 90 239 67 780 'center'
Draw-Atlas $g $arcade 'MISSION ONE' 130 355 43 700 'center'
Draw-Plain $g 'A brief title card before play resumes.' 100 471 19 '#E1E2D8' $false $true 760
Save-Screen $screen (Join-Path $reviewDir 'arcade-stage-card.png')

$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#07101B' 0 0 960 678 255
FillRect $g '#14212B' 42 25 872 626 255; StrokeRect $g '#D2A64D' 42 25 872 626 3
Draw-Atlas $g $arcade 'AIR HOCKEY' 82 43 48 420 'left'
Draw-Plain $g 'FIRST TO SEVEN' 570 52 18 '#D3E0E1' $false $true 300
Draw-Crop $g $airHockeyRink 205 135 550 275
FillRect $g '#091B27' 95 515 225 52 255; FillRect $g '#091B27' 367 515 225 52 255; FillRect $g '#091B27' 640 515 225 52 255
foreach ($entry in @(@(95,'SOLO VS AI'),@(367,'INVITE PLAYER'),@(640,'JOIN'))) {
    StrokeRect $g '#62CFCB' $entry[0] 515 225 52 1
    Draw-Plain $g $entry[1] $entry[0] 531 16 '#F1E6C1' $true $true 225
}
Draw-Plain $g 'Move the wheel to control your paddle. Release to stop.' 80 613 14 '#D6E1DC' $false $true 800
Save-Screen $screen (Join-Path $reviewDir 'arcade-air-hockey.png')

$board = New-Board 'ARCADE FLASH  /  ARCADE TITLES AND CUT-INS' 'Use on the game and transition headlines only. Existing named arcade faces and gameplay HUD labels stay unchanged.' '#111726'
Draw-BoardCard $board.Graphics 60 142 '01  CRITTER CRISIS' 'src/screens/critter_crisis_screen.lua:242-266' 'Your selected arcade face on the title and route names; keep instructions and buttons as they are.' (Load-Image 'output\font-placement-review\arcade-crisis-menu.png') 420
Draw-BoardCard $board.Graphics 525 142 '02  RESULTS' 'src/screens/critter_crisis_screen.lua:328-332' 'Use it on the result headline and AREA CLEAR intermission.' (Load-Image 'output\font-placement-review\arcade-results.png') 420
Draw-BoardCard $board.Graphics 990 142 '03  STAGE CARD' 'New placement idea; not an existing screen' 'Optional one-beat intro before the action.' (Load-Image 'output\font-placement-review\arcade-stage-card.png') 420
Draw-BoardCard $board.Graphics 1455 142 '04  AIR HOCKEY' 'src/screens/air_hockey_screen.lua:152' 'Arcade title only; preserve score text, controls, and buttons.' (Load-Image 'output\font-placement-review\arcade-air-hockey.png') 420
Save-Board $board 'arcade-flash-placements.png'

## Groovy Slab: venue nameplates.
$screen = New-Screen; $g = $screen.Graphics
FillRect $g '#06150F' 0 0 960 678 255
FillRect $g '#0E2418' 26 22 908 634 255; StrokeRect $g '#BAA36F' 26 22 908 634 2
FillRect $g '#183825' 40 34 880 112 255
$awning = @('#C84D3D','#F1DFB8','#627A4C','#F1DFB8')
for ($i=0; $i -lt 16; $i++) { FillRect $g $awning[$i%4] (40+55*$i) 34 56 18 255 }
Draw-Crop $g $groceryEmblem 46 57 91 83
Draw-Atlas $g $groovy 'TOWN GROCERY' 146 57 32 325 'left'
Draw-Plain $g 'FRESH STAPLES AND PANTRY FOOD' 148 105 13 '#E7DEC5' $true
FillRect $g '#102219' 492 63 126 53 255; FillRect $g '#102219' 625 63 126 53 255; FillRect $g '#102219' 758 63 150 53 255
Draw-Plain $g 'HOUSEHOLD' 500 72 10 '#B7C9A8' $true; Draw-Plain $g '$420.00' 500 91 15 '#F5D78E' $true
Draw-Plain $g 'BIKE BAGS' 633 72 10 '#B7C9A8' $true; Draw-Plain $g '1 / 6' 633 91 15 '#D6E5BE' $true
Draw-Plain $g 'SHOPPING CART' 766 72 10 '#B7C9A8' $true; Draw-Plain $g '3  /  $8.50' 766 91 15 '#F5D78E' $true
FillRect $g '#E7D8B8' 46 153 868 27 255; Draw-Plain $g 'FRESH STOCK DELIVERY  /  DUE TODAY' 75 158 12 '#35452F' $true
FillRect $g '#13271B' 46 188 522 326 255; FillRect $g '#E8DABC' 578 188 336 326 255; StrokeRect $g '#9A8452' 578 188 336 326 1
$products=@('VEGETABLES','BREAD','CEREAL','SANDWICH','DRINK','MEAL')
for ($i=0; $i -lt 6; $i++) {
    $y=195+49*$i; FillRect $g $(if ($i -eq 0) {'#405E3C'} else {'#1D3425'}) 53 $y 508 46 255
    FillRect $g '#E8DAB9' 60 ($y+4) 34 36 255
    Draw-Plain $g $products[$i] 105 ($y+5) 14 '#F2EDDB' $true
    Draw-Plain $g 'Stock 12  /  4 servings per item' 105 ($y+25) 10 '#B2C2AE'
    Draw-Plain $g ('$' + @('4.00','3.00','1.50','2.50','1.50','5.00')[$i]) 450 ($y+13) 14 '#F2D98E' $true
}
Draw-Crop $g $groceryProducts 678 205 130 112 0 0 128 128
Draw-Plain $g 'VEGETABLES' 594 326 20 '#233B2A' $true $true 304
Draw-Plain $g 'In store 12  /  On bike 0' 594 373 12 '#46533A' $false $true 304
FillRect $g '#294A33' 596 445 300 45 255; Draw-Plain $g 'ADD TO CART' 596 459 16 '#F7E4B8' $true $true 300
FillRect $g '#102219' 46 520 868 32 255; Draw-Plain $g 'Choose an item, set quantity, then add to cart.' 62 527 12 '#D9CFB5'
Save-Screen $screen (Join-Path $reviewDir 'groovy-grocery.png')

$screen = New-Screen; $g = $screen.Graphics
Draw-Crop $g $gasConcept 0 0 960 678
FillRect $g '#07110F' 0 0 960 74 232
Draw-Atlas $g $groovy 'GAS STATION' 24 7 34 700 'left'
Draw-Plain $g 'CONVENIENCE STORE' 31 50 15 '#F5E4B1' $true
FillRect $g '#0D1D18' 35 539 890 105 226; StrokeRect $g '#947F51' 35 539 890 105 1
foreach ($entry in @(@(70,'SHOP WITH CLERK'),@(365,'FUEL AND OIL'),@(660,'RETURN OUTSIDE'))) {
    FillRect $g '#17362B' $entry[0] 563 230 58 245; StrokeRect $g '#C59E55' $entry[0] 563 230 58 1
    Draw-Plain $g $entry[1] $entry[0] 584 15 '#F5E4B1' $true $true 230
}
Save-Screen $screen (Join-Path $reviewDir 'groovy-gas-station.png')

$screen = New-Screen; $g = $screen.Graphics
Draw-Crop $g $barnBg 0 0 960 678
FillRect $g '#142018' 0 0 960 57 215
Draw-Atlas $g $groovy 'MILLER FARM' 22 7 31 270 'left'
Draw-Plain $g 'BARN' 305 20 17 '#F1D68F' $true
Draw-Crop $g $grandpa 608 238 216 378
FillRect $g '#06110D' 0 615 960 63 218; StrokeRect $g '#AE9560' 175 615 610 45 1 220
Draw-Plain $g 'TALK TO GRANDPA  /  E OR TAP' 185 628 17 '#F2E3BE' $true $true 590
FillRect $g '#10251E' 214 406 532 139 222; StrokeRect $g '#A7915B' 214 406 532 139 1 235
Draw-Plain $g 'GRANDPA' 242 420 16 '#F1D68F' $true
Draw-Plain $g 'I am glad you made it back to town.' 242 458 19 '#F1EAD8'
Draw-Plain $g 'The Picture Shop has been closed for ten years.' 242 491 16 '#DFD7C4'
Save-Screen $screen (Join-Path $reviewDir 'groovy-farm-barn.png')

$board = New-Board 'GROOVY SLAB  /  SHOP AND FARM HEADERS' 'These previews show the former script locations in Groovy. The grocery and fuel headings currently have named metal faces; those assignments remain until you choose these exact overrides.' '#18211F'
Draw-BoardCard $board.Graphics 60 142 '01  TOWN GROCERY' 'src/commute/town_store.lua:457' 'Groovy title preview only. The current TOWN GROCERY heading uses the named metal face.' (Load-Image 'output\font-placement-review\groovy-grocery.png')
Draw-BoardCard $board.Graphics 675 142 '02  GAS STATION' 'src/commute/gas_station_interior.lua:273' 'Groovy sign preview only. The current venue title uses the named metal face.' (Load-Image 'output\font-placement-review\groovy-gas-station.png')
Draw-BoardCard $board.Graphics 1290 142 '03  MILLER FARM' 'src/commute/barn_interior.lua:97' 'Style the farm name only; keep the barn label, prompts, and Grandpa dialogue clear.' (Load-Image 'output\font-placement-review\groovy-farm-barn.png')
Save-Board $board 'groovy-venue-placements.png'

$markdown = @'
# Font placement review

The rejected script atlas is out of the font set, loader, and generator. The approved headings shown here are applied in game screens. Game save data was not touched.

## Groovy Slab

![Groovy Slab menu and story candidates](groovy-slab-placements.png)

1. Finance panel `SHOP CASH FLOW` — `src/screens/shop_budget.lua:61`.
2. Grand Opening banner headline — `src/story_grand_opening.lua:79-80`.
3. Work Phone title / contact heading — `src/screens/work_phone_screen.lua:113,190`.
4. Shop Clock panel title — `src/screens/shop_clock.lua:64`.
5. Options header `SHOP CONTROL` — `src/screens/options_screen.lua:1271`.
6. Machine care page — `src/screens/machine/maintenance.lua:79`.

![Groovy Slab shop and farm candidates](groovy-venue-placements.png)

The approved Town Grocery and Gas Station headings now use Groovy Slab. Their category labels, store details, prices, and prompts keep their existing faces. The farm name uses Groovy Slab while `BARN` remains in the existing screen font.

The earlier `SHOP FILES` and `NEW SHOP` suggestions are excluded because those screens already use the named `metal` and `paper` faces. The selected title fonts remain untouched.

## Arcade Flash

![Arcade Flash title and cut-in candidates](arcade-flash-placements.png)

1. Critter Crisis title and route names — `src/screens/critter_crisis_screen.lua:258-267`.
2. Result and area-clear headings — `src/screens/critter_crisis_screen.lua:348-352`.
3. Stage-intro card — shown at mission start and when a new route begins; the session pauses briefly for the card.
4. Air Hockey title — `src/screens/air_hockey_screen.lua:153`.

The Arcade cabinet selector and Critter Kombat title have their own `VT323` assignment and stay unchanged. Body copy, prices, inventory values, prompts, controls, and dense HUD labels remain in their current fonts.
'@
$markdown | Set-Content -Encoding utf8 (Join-Path $reviewDir 'REVIEW.md')

$html = @'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Font Placement Review</title>
<style>
  :root { color-scheme: dark; font-family: "Segoe UI", sans-serif; background: #111817; color: #ece8da; }
  body { margin: 0 auto; max-width: 1500px; padding: 32px; }
  h1 { margin: 0 0 8px; font-size: 28px; }
  p { color: #aeb9b3; margin: 0 0 24px; line-height: 1.5; }
  section { margin: 28px 0 42px; }
  img { display: block; width: 100%; height: auto; border: 1px solid #59645e; border-radius: 8px; }
  .note { font-size: 14px; }
</style>
<h1>Font Placement Review</h1>
<p>The approved heading placements are applied in game screens. Game save data was not touched.</p>
<section><img src="groovy-slab-placements.png" alt="Groovy Slab menu and story placements"></section>
<section><img src="groovy-venue-placements.png" alt="Groovy Slab shop and farm title placements"></section>
<section><img src="arcade-flash-placements.png" alt="Arcade Flash Critter Crisis and stage cut-in placements"></section>
<p class="note"><a href="REVIEW.md">Placement notes and source locations</a></p>
</html>
'@
$html | Set-Content -Encoding utf8 (Join-Path $reviewDir 'index.html')

$warehouse.Dispose()
$grandOpeningBg.Dispose(); $groceryEmblem.Dispose(); $groceryProducts.Dispose(); $gasConcept.Dispose()
$barnBg.Dispose(); $grandpa.Dispose(); $crisisBg.Dispose()
$groovy.Dispose(); $arcade.Dispose(); $airHockeyRink.Dispose()
Write-Output "Font placement mockups are ready in $reviewDir"
