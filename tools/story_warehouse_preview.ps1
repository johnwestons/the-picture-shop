Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'assets/generated/warehouse-lobby-seating-v5-three-tier.png'
$destination = Join-Path $root 'docs/story-update/warehouse-render-options.png'
$image = [System.Drawing.Bitmap]::new($source)
$canvas = [System.Drawing.Bitmap]::new(1020, 390)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
function Brush([int]$r,[int]$green,[int]$b,[int]$a=255) {
    return [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a,$r,$green,$b))
}
function Polygon($points,$brush) {
    $g.FillPolygon($brush,[System.Drawing.PointF[]]$points)
    $brush.Dispose()
}
$g.Clear([System.Drawing.Color]::FromArgb(25,32,38))
$wall=Brush 155 150 137
$g.FillRectangle($wall,20,42,480,150)
$wall.Dispose()
for($i=0;$i -lt 7;$i++) {
    $pen=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(125,121,111),1)
    $g.DrawLine($pen,20,58+$i*19,500,58+$i*19)
    $pen.Dispose()
}
Polygon @([System.Drawing.PointF]::new(20,172),[System.Drawing.PointF]::new(500,172),[System.Drawing.PointF]::new(500,338),[System.Drawing.PointF]::new(20,338)) (Brush 118 117 110)
$floorPen=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(80,80,78),1)
foreach($y in @(212,260,311)){$g.DrawLine($floorPen,20,$y,500,$y)}
foreach($x in @(90,210,335,450)){$g.DrawLine($floorPen,$x,173,$x,338)}
$floorPen.Dispose()
$door=Brush 65 70 73
$g.FillRectangle($door,43,90,100,88);$door.Dispose()
$frame=Brush 55 62 67
foreach($x in @(180,293,406)){$g.FillRectangle($frame,$x,68,5,112)}
$frame.Dispose()
$shelf=Brush 127 80 43
foreach($y in @(88,119,150)){$g.FillRectangle($shelf,182,$y,282,5)}
$shelf.Dispose()
$dark=Brush 64 68 68
$g.FillRectangle($dark,362,104,112,70);$dark.Dispose()
$g.DrawImage($image,[System.Drawing.Rectangle]::new(520,42,480,296))
$dim=Brush 24 31 35 65
$g.FillRectangle($dim,520,42,480,296);$dim.Dispose()
$dust=Brush 122 103 75 82
foreach($p in @(@(570,279,94,15),@(704,301,56,11),@(846,255,75,16),@(552,231,48,8))) {
    $g.FillEllipse($dust,$p[0],$p[1],$p[2],$p[3])
}
$dust.Dispose()
$debris=Brush 82 72 57 180
foreach($p in @(@(600,290),@(777,285),@(888,315),@(971,271))) {
    $g.FillEllipse($debris,$p[0],$p[1],8,3)
}
$debris.Dispose()
$font=[System.Drawing.Font]::new('Arial',13,[System.Drawing.FontStyle]::Bold)
$white=Brush 239 240 231
$g.DrawString('ALL CODE: structure, floor, racks',$font,$white,20,351)
$g.DrawString('HYBRID: original art + coded wear',$font,$white,520,351)
$white.Dispose();$font.Dispose();$g.Dispose();$image.Dispose()
$canvas.Save($destination,[System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
Write-Output $destination

$restoration = Join-Path $root 'docs/story-update/warehouse-restoration-preview.png'
$compare = [System.Drawing.Bitmap]::new(1020,390)
$g = [System.Drawing.Graphics]::FromImage($compare)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::FromArgb(25,32,38))
$base = [System.Drawing.Bitmap]::new($source)
$g.DrawImage($base,[System.Drawing.Rectangle]::new(20,42,480,296))
$g.DrawImage($base,[System.Drawing.Rectangle]::new(520,42,480,296))
$g.SetClip([System.Drawing.Rectangle]::new(20,42,480,296))
$unpowered = Brush 12 24 34 125
$g.FillRectangle($unpowered,20,42,480,296);$unpowered.Dispose()
$grime = Brush 72 64 47 125
foreach($p in @(@(30,255,112,37),@(168,289,96,25),@(284,237,75,20),@(396,298,104,41),@(77,145,57,30))) {
    $g.FillEllipse($grime,$p[0],$p[1],$p[2],$p[3])
}
$grime.Dispose()
$puddle = Brush 34 76 91 200
$g.FillEllipse($puddle,366,250,105,29);$puddle.Dispose()
$shine = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(175,110,156,163),1.4)
$g.DrawArc($shine,379,253,68,17,3,152);$shine.Dispose()
$pipe = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(173,169,156),4)
$g.DrawLine($pipe,448,69,448,172);$g.DrawLine($pipe,448,172,420,172);$pipe.Dispose()
$stain = Brush 55 80 85 100
$g.FillEllipse($stain,412,163,40,22);$stain.Dispose()
$breaker = Brush 48 55 53 230
$g.FillRectangle($breaker,111,97,26,32);$breaker.Dispose()
$trim = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(190,177,149),1.5)
$g.DrawRectangle($trim,111,97,26,32);$trim.Dispose()
$g.ResetClip()
$font = [System.Drawing.Font]::new('Arial',13,[System.Drawing.FontStyle]::Bold)
$white = Brush 239 240 231
$g.DrawString('CLOSED: disconnected, dirty, damp',$font,$white,20,350)
$g.DrawString('RESTORED: powered and cleaned',$font,$white,520,350)
$white.Dispose();$font.Dispose();$base.Dispose();$g.Dispose()
$compare.Save($restoration,[System.Drawing.Imaging.ImageFormat]::Png)
$compare.Dispose()
Write-Output $restoration
