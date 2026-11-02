-- Registered cooking contacts, with collision-safe stove standing positions.
local R={order={"east","southeast","south","southwest","west","northwest","north","northeast"},fps=4,sequence={1,2,3,4}}
-- Per frame: planted foot anchor and stirring grip, in a 627-square source cell.
R.views={
 east={height=540,bowl={422,310},grips={{205,590,365,260},{206,590,353,270},{205,586,385,283},{208,586,365,273}}},
 southeast={height=583,bowl={468,380},grips={{290,600,420,320},{273,600,403,340},{290,587,406,343},{273,587,403,313}}},
 south={height=565,bowl={355,350},grips={{355,585,305,295},{273,585,258,318},{355,586,345,320},{273,586,248,315}}},
 southwest={height=597,bowl={240,375},grips={{380,605,232,295},{383,605,243,295},{380,603,282,309},{383,603,283,324}}},
 west={height=540,bowl={215,315},grips={{416,580,269,270},{390,580,212,282},{416,581,270,282},{391,581,213,289}}},
 northwest={height=565,bowl={237,277},grips={{430,600,292,250},{433,600,290,250},{430,593,280,263},{433,593,290,263}}},
 north={height=535,bowl={463,270},grips={{270,580,408,236},{273,580,405,247},{270,573,440,252},{273,573,433,254}}},
 northeast={height=565,bowl={466,283},grips={{275,590,405,247},{275,590,405,247},{275,583,415,263},{275,583,433,263}}},
}
-- Explicit atlas regions retain entire handles that cross nominal grid lines.
-- Pan: region, base pivot, soup center. Spoon: region, grip, bowl center.
R.pans={
 {0,0,430,512,148,400,148,250},{430,0,380,512,130,390,130,245},
 {810,0,350,512,150,390,150,240},{1160,0,376,512,209,390,209,242},
 {0,512,410,512,286,397,286,240},{410,512,395,512,192,397,192,240},
 {805,512,350,512,158,397,158,240},{1155,512,381,512,162,397,162,240},
}
R.spoons={
 {0,0,420,512,150,145,340,388},{420,0,380,512,82,147,244,365},
 {800,0,352,512,145,140,145,380},{1152,0,384,512,258,140,123,360},
 {0,512,384,512,268,133,97,343},{384,512,384,512,280,128,127,358},
 {768,512,384,512,180,128,180,373},{1152,512,384,512,88,130,250,358},
}
for i,d in ipairs(R.order) do
 local v=R.views[d];v.index=i;v.scale=76.8/v.height;v.file="stir-"..d.."-body.png"
 v.bowlX=(v.bowl[1]-v.grips[1][1])*v.scale;v.bowlY=(v.bowl[2]-v.grips[1][2])*v.scale
end
return R
