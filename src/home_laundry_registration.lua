-- Source pixels are immutable generated PNGs. Every view is independently
-- authored; the two rear three-quarter columns are mapped to their real view.
local R={version=1,order={"east","southeast","south","southwest","west","northwest","north","northeast"},views={}}
local sourceIndex={1,2,3,4,5,8,7,6}
-- Per source column: planted foot x/y, then the two cupped hand centres.
-- Phase 1 uses explicit row rectangles because its first row crosses y=512.
local frames={
 {{164,365,277,328,331,310},{195,365,242,330,317,311},{193,365,142,322,239,322},{238,365,88,311,145,328},
  {225,357,112,284,135,272},{198,366,308,265,326,257},{197,362,107,260,280,260},{206,363,73,270,110,263}},
 {{171,465,265,350,316,334},{192,465,236,355,299,339},{193,463,168,353,230,353},{227,470,100,341,151,355},
  {220,432,94,293,125,287},{195,435,299,278,326,266},{194,435,107,275,278,275},{200,430,75,267,108,273}},
 {{154,471,281,337,328,306},{167,478,250,353,327,328},{194,466,176,350,239,350},{236,480,89,324,145,360},
  {245,443,90,289,93,265},{186,443,311,265,329,263},{192,446,114,269,277,269},{202,447,82,265,100,278}},
 {{180,482,191,350,244,333},{190,476,161,350,282,331},{194,470,126,333,270,333},{230,480,122,331,215,350},
  {200,458,158,322,126,305},{190,444,284,310,105,292},{194,445,108,302,284,302},{200,445,94,310,266,291}},
}
for i,d in ipairs(R.order) do
 local si=sourceIndex[i];local v={index=i,sourceIndex=si,rear=i>=6,scale=.175,frames={}}
 for phase=1,4 do
  local top=si<=4
  local crop={((si-1)%4)*384,phase==1 and (top and 170 or 580) or (top and 0 or 512),384,phase==1 and 390 or 512}
  if phase==4 then crop[2]=top and 0 or 500;crop[4]=top and 500 or 524 end
  v.frames[phase]={crop=crop,foot={frames[phase][si][1],frames[phase][si][2]},
   hands={{frames[phase][si][3],frames[phase][si][4]},{frames[phase][si][5],frames[phase][si][6]}}}
  if phase==4 and not top then
   local f=v.frames[phase];f.foot[2]=f.foot[2]+12
   for _,h in ipairs(f.hands) do h[2]=h[2]+12 end
  end
 end
 R.views[d]=v
end
-- Prop coordinates are local to their untouched 384x512 atlas cells.
R.basket={scale=.085,base={{192,398},{192,417},{192,405},{192,418},{192,368},{192,380},{192,375},{192,380}}}
R.bundle={scale=.070,centre={{192,305},{192,309},{192,310},{192,309},{192,229},{192,221},{192,220},{192,226}}}
for _,prop in ipairs({R.basket,R.bundle}) do
 prop.rects={}
 for i=1,8 do prop.rects[i]={(i-1)%4*384,math.floor((i-1)/4)*512,384,512} end
end
-- These generated silhouettes cross the nominal column boundary by a few
-- pixels. Preserve the complete object and exclude it from the next view.
R.basket.rects[5]={0,512,400,512};R.basket.rects[6]={400,512,368,512};R.basket.base[6][1]=176
R.bundle.rects[1]={0,0,400,512};R.bundle.rects[2]={400,0,368,512};R.bundle.centre[2][1]=176
-- Contact centres read from the actual 1536x1024 floor art, not floor hotspots.
R.washers={
 ["brick-walkup"]={direction="northwest",door={1077,437}},
 garden={direction="north",door={987,213}},
 courtyard={direction="northwest",door={716,232}},
 corner={direction="northwest",door={1097,282}},
}
return R
