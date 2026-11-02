-- Each frame registers planted feet and the underside of the wiping palm.
local R={order={"east","southeast","south","southwest","west","northwest","north","northeast"},
 sequence={1,2,3,2},fps=5,views={}}
local anchors={
 {{167,456,298,285},{200,456,296,289},{192,456,151,309},{224,456,83,294},
  {215,428,80,252},{245,424,100,235},{190,428,267,203},{175,428,303,249}},
 {{155,456,346,280},{180,456,347,285},{190,456,131,305},{223,456,41,286},
  {240,430,53,243},{255,424,73,238},{189,428,272,196},{170,428,333,241}},
 {{155,456,299,296},{180,456,281,299},{190,456,246,302},{842,990,480,546,.079},
  {240,430,78,255},{255,424,101,245},{189,428,274,207},{170,428,320,248}},
}
local cloth={{196,304},{202,310},{198,314},{196,310},{192,275},{196,275},{188,280},{200,280}}
for index,d in ipairs(R.order) do
 local v={index=index,frames={},scale=.18,cloth=cloth[index],rear=index>=6}
 for phase=1,3 do v.frames[phase]=anchors[phase][index] end
 R.views[d]=v
end
-- The fully extended hands in phase 2 cross the nominal first two cell edges.
-- Explicit regions preserve the fingers and exclude the neighbouring character.
R.regions={[2]={{0,0,400,500},{400,0,400,500},{800,0,352,500}}}
R.views.southwest.override={[3]="phase-3-southwest.png"}
R.fixtureOffsets={courtyard={sink={-5,0}},corner={sink={30,0}}}
return R
