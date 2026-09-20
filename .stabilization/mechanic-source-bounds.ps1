param([string]$ImagePath,[int]$AlphaThreshold=16)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class MechanicSourceBounds {
 public static string Analyze(byte[] pixels, int w, int h, int stride, int threshold) {
   var alpha=new bool[w*h];
   for(int y=0;y<h;y++) for(int x=0;x<w;x++) alpha[y*w+x]=pixels[y*stride+x*4+3]>threshold;
   var queue=new int[w*h]; var lines=new List<string>();
   for(int i=0;i<alpha.Length;i++) {
    if(!alpha[i]) continue;
    int start=0,end=1,minX=w,maxX=0,minY=h,maxY=0; queue[0]=i;alpha[i]=false;
    while(start<end) {
     int p=queue[start++],x=p%w,y=p/w;
     minX=Math.Min(minX,x);maxX=Math.Max(maxX,x);minY=Math.Min(minY,y);maxY=Math.Max(maxY,y);
     for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
      int nx=x+dx,ny=y+dy,n=ny*w+nx;
      if(nx>=0&&nx<w&&ny>=0&&ny<h&&alpha[n]){alpha[n]=false;queue[end++]=n;}
     }
    }
    if(end>100) {
     lines.Add(String.Format("x={0}..{1} y={2}..{3} pixels={4}",minX,maxX,minY,maxY,end));
     if(w==1280&&minX>300&&minX<400&&(minY==315||minY==935)) {
      for(int band=minY;band<minY+80;band+=5) {
       int lo=w,hi=-1; for(int q=0;q<end;q++) {int px=queue[q]%w,py=queue[q]/w;
        if(py>=band&&py<band+5){lo=Math.Min(lo,px);hi=Math.Max(hi,px);}}
       lines.Add(String.Format("band {0}..{1} x={2}..{3}",band,band+4,lo,hi));
      }
     }
    }
   }
   return String.Join(Environment.NewLine,lines);
 }
}
'@
$taskPaths = if ($ImagePath) { @($ImagePath) } else {
 @('concrete','hammer','drill','paint') | ForEach-Object { "assets/source/warehouse-expansion-v1/mechanic-$_-source-v1.png" }
}
foreach ($taskPath in $taskPaths) {
 Write-Output $taskPath
 $bitmap=[System.Drawing.Bitmap]::new((Join-Path (Get-Location) $taskPath))
 $rect=[System.Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height)
 $bits=$bitmap.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
 $bytes=[byte[]]::new($bits.Stride*$bits.Height)
 [System.Runtime.InteropServices.Marshal]::Copy($bits.Scan0,$bytes,0,$bytes.Length)
 [MechanicSourceBounds]::Analyze($bytes,$bitmap.Width,$bitmap.Height,$bits.Stride,$AlphaThreshold)
 $bitmap.UnlockBits($bits);$bitmap.Dispose()
}
