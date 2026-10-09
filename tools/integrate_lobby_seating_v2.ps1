param()
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
if (-not ('LobbyPatch' -as [type])) {
    $taskDrawingReferences=@(
        [AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES').Split([IO.Path]::PathSeparator)
        [System.Drawing.Bitmap].Assembly.Location
    ) | Select-Object -Unique
    Add-Type -ReferencedAssemblies $taskDrawingReferences -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class LobbyPatch {
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
        Rectangle crop=new Rectangle(1096,210,224,144);
        var sofa=new[]{new Point(68,13),new Point(104,13),new Point(214,46),new Point(214,102),new Point(82,88),new Point(68,69)};
        var rug=new[]{new Point(68,62),new Point(168,70),new Point(188,100),new Point(152,124),new Point(62,103)};
        int changed=0;
        using(Bitmap result=original.Clone(new Rectangle(0,0,original.Width,original.Height),PixelFormat.Format32bppArgb))
        using(Bitmap patch=new Bitmap(crop.Width,crop.Height,PixelFormat.Format32bppArgb)) {
            using(Graphics g=Graphics.FromImage(patch)) {
                g.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.Half;
                g.DrawImage(edited,new Rectangle(0,0,patch.Width,patch.Height),new Rectangle(0,0,edited.Width,edited.Height),GraphicsUnit.Pixel);
            }
            for(int y=0;y<crop.Height;y++)for(int x=0;x<crop.Width;x++) {
                double weight=Math.Max(Weight(x,y,sofa),Weight(x,y,rug));
                if(weight<=0)continue;
                Color a=original.GetPixel(crop.X+x,crop.Y+y),b=patch.GetPixel(x,y);
                Color color=Color.FromArgb(a.A,(int)Math.Round(a.R*(1-weight)+b.R*weight),
                    (int)Math.Round(a.G*(1-weight)+b.G*weight),(int)Math.Round(a.B*(1-weight)+b.B*weight));
                result.SetPixel(crop.X+x,crop.Y+y,color);
                if(a.ToArgb()!=color.ToArgb())changed++;
            }
            for(int y=0;y<original.Height;y++)for(int x=0;x<original.Width;x++) {
                if(crop.Contains(x,y))continue;
                if(original.GetPixel(x,y).ToArgb()!=result.GetPixel(x,y).ToArgb())throw new Exception("Modified a pixel outside the lobby crop");
            }
            result.Save(destination,ImageFormat.Png);
        }
        return changed;
    }
}
'@
}
$taskBasePath=Join-Path $taskRoot 'assets/generated/warehouse-open-office-v1.png'
$taskEditPath=Join-Path $taskRoot 'assets/source/lobby-seating-v2/lobby-refined.png'
$taskDestination=Join-Path $taskRoot 'assets/generated/warehouse-lobby-seating-v2.png'
$taskManifestPath=Join-Path $taskRoot 'assets/source/lobby-seating-v2/integration.json'
$taskSourceHash=(Get-FileHash -LiteralPath $taskBasePath -Algorithm SHA256).Hash
$taskEditHash=(Get-FileHash -LiteralPath $taskEditPath -Algorithm SHA256).Hash
if(Test-Path -LiteralPath $taskManifestPath) {
    $taskPinned=Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
    if($taskPinned.sourceHash -ne $taskSourceHash -or $taskPinned.editHash -ne $taskEditHash) {
        throw 'Reviewed source hashes changed; inspect the art before updating its manifest.'
    }
}
$taskBase=[System.Drawing.Bitmap]::FromFile($taskBasePath)
$taskEdit=[System.Drawing.Bitmap]::FromFile($taskEditPath)
try {
    if($taskBase.Width -ne 1536 -or $taskBase.Height -ne 1024) {throw 'Unexpected warehouse dimensions'}
    $taskChanges=[LobbyPatch]::Apply($taskBase,$taskEdit,$taskDestination)
} finally {$taskBase.Dispose();$taskEdit.Dispose()}
[ordered]@{source='assets/generated/warehouse-open-office-v1.png';sourceHash=$taskSourceHash;
    edit='assets/source/lobby-seating-v2/lobby-refined.png';editHash=$taskEditHash;
    destination='assets/generated/warehouse-lobby-seating-v2.png';crop=@(1096,210,224,144);
    mask='Union of sofa and former table/rug polygons, feathered 3 native pixels inside the boundary';
    changedLobbyPixels=$taskChanges;changedOutsideLobbyPixels=0;generationTool='built-in ImageGen'} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $taskManifestPath -Encoding utf8
Write-Output "Lobby pixels changed: $taskChanges; outside lobby: 0"
