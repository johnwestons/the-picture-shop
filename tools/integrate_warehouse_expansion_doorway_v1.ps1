param()
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
if (-not ('WarehouseExpansionPatch' -as [type])) {
    $taskTrustedAssemblies=[AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES')
    if ($taskTrustedAssemblies) {
        $taskDrawingReferences=@(
            $taskTrustedAssemblies.Split([IO.Path]::PathSeparator)
            [System.Drawing.Bitmap].Assembly.Location
        ) | Select-Object -Unique
    } else {
        $taskDrawingReferences=@([System.Drawing.Bitmap].Assembly.Location) | Select-Object -Unique
    }
    Add-Type -ReferencedAssemblies $taskDrawingReferences -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class WarehouseExpansionPatch {
    static double Weight(int x,int y,Point[] polygon) {
        bool inside=false;double distance=double.MaxValue;
        for(int i=0,j=polygon.Length-1;i<polygon.Length;j=i++) {
            Point a=polygon[j],b=polygon[i];
            if((a.Y>y)!=(b.Y>y) && x<(double)(b.X-a.X)*(y-a.Y)/(b.Y-a.Y)+a.X) inside=!inside;
            double dx=b.X-a.X,dy=b.Y-a.Y;
            double t=Math.Max(0,Math.Min(1,((x-a.X)*dx+(y-a.Y)*dy)/(dx*dx+dy*dy)));
            double ex=x-a.X-t*dx,ey=y-a.Y-t*dy;
            distance=Math.Min(distance,Math.Sqrt(ex*ex+ey*ey));
        }
        return inside ? Math.Min(1,distance/3) : 0;
    }
    public static int Apply(Bitmap original,Bitmap edited,string destination) {
        Rectangle crop=new Rectangle(900,80,520,380);
        var portal=new[]{new Point(66,52),new Point(179,50),new Point(184,211),
            new Point(174,226),new Point(72,226),new Point(66,212)};
        var formerDoor=new[]{new Point(178,65),new Point(226,67),new Point(229,214),
            new Point(219,224),new Point(177,220)};
        var newExteriorDoorAndChairClearance=new[]{new Point(220,40),new Point(282,41),
            new Point(282,128),new Point(278,145),new Point(272,160),new Point(269,176),
            new Point(266,196),new Point(255,219),new Point(226,215),new Point(213,204),
            new Point(213,181),new Point(220,166)};
        int changed=0;
        using(Bitmap result=original.Clone(new Rectangle(0,0,original.Width,original.Height),PixelFormat.Format32bppArgb))
        using(Bitmap patch=new Bitmap(crop.Width,crop.Height,PixelFormat.Format32bppArgb)) {
            using(Graphics g=Graphics.FromImage(patch)) {
                g.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.Half;
                g.DrawImage(edited,new Rectangle(0,0,patch.Width,patch.Height),
                    new Rectangle(0,0,edited.Width,edited.Height),GraphicsUnit.Pixel);
            }
            for(int y=0;y<crop.Height;y++)for(int x=0;x<crop.Width;x++) {
                double weight=Math.Max(Weight(x,y,portal),
                    Math.Max(Weight(x,y,formerDoor),Weight(x,y,newExteriorDoorAndChairClearance)));
                if(weight<=0)continue;
                Color a=original.GetPixel(crop.X+x,crop.Y+y),b=patch.GetPixel(x,y);
                Color color=Color.FromArgb(a.A,(int)Math.Round(a.R*(1-weight)+b.R*weight),
                    (int)Math.Round(a.G*(1-weight)+b.G*weight),(int)Math.Round(a.B*(1-weight)+b.B*weight));
                result.SetPixel(crop.X+x,crop.Y+y,color);
                if(a.ToArgb()!=color.ToArgb())changed++;
            }
            for(int y=0;y<original.Height;y++)for(int x=0;x<original.Width;x++) {
                if(crop.Contains(x,y))continue;
                if(original.GetPixel(x,y).ToArgb()!=result.GetPixel(x,y).ToArgb())
                    throw new Exception("Modified a pixel outside the warehouse entrance crop");
            }
            result.Save(destination,ImageFormat.Png);
        }
        return changed;
    }
}
'@
}
$taskBasePath=Join-Path $taskRoot 'assets/generated/warehouse-lobby-seating-v2.png'
$taskEditPath=Join-Path $taskRoot 'assets/source/warehouse-expansion-doorway-v1/warehouse-expansion-doorway-final-edit.png'
$taskDestination=Join-Path $taskRoot 'assets/generated/warehouse-lobby-seating-v3.png'
$taskManifestPath=Join-Path $taskRoot 'assets/source/warehouse-expansion-doorway-v1/integration.json'
$taskSourceHash=(Get-FileHash -LiteralPath $taskBasePath -Algorithm SHA256).Hash
$taskEditHash=(Get-FileHash -LiteralPath $taskEditPath -Algorithm SHA256).Hash
$taskBase=[System.Drawing.Bitmap]::FromFile($taskBasePath)
$taskEdit=[System.Drawing.Bitmap]::FromFile($taskEditPath)
try {
    if($taskBase.Width -ne 1536 -or $taskBase.Height -ne 1024) {throw 'Unexpected warehouse dimensions'}
    $taskChanges=[WarehouseExpansionPatch]::Apply($taskBase,$taskEdit,$taskDestination)
} finally {$taskBase.Dispose();$taskEdit.Dispose()}
[ordered]@{source='assets/generated/warehouse-lobby-seating-v2.png';sourceHash=$taskSourceHash;
    edit='assets/source/warehouse-expansion-doorway-v1/warehouse-expansion-doorway-final-edit.png';editHash=$taskEditHash;
    destination='assets/generated/warehouse-lobby-seating-v3.png';crop=@(900,80,520,380);
    masks=@('pallet-jack expansion passage replacing the former window','closed former exterior-door opening',
        'new exterior entrance and cleared marked chair area');
    changedPixels=$taskChanges;changedOutsideEntranceCrop=0;featherPixels=3;generationTool='built-in ImageGen'} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $taskManifestPath -Encoding utf8
Write-Output "Warehouse entrance pixels changed: $taskChanges; outside entrance crop: 0"
