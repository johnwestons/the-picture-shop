-- Reviewed source-space contacts for the eight directional sweeping views.
local R={order={"east","southeast","south","southwest","west","northwest","north","northeast"},sequence={1,2,3,4,3,2},fps=6}
-- Per frame: foot anchor, upper grip and lower grip, all in the local source cell.
R.views={
 east={file="sweep-east-empty-hands.png",cols=4,w=384,h=512,scale=.19,grips={
 {180,478,185,274,290,334},{183,478,190,282,280,341},{183,478,186,284,256,346},{188,478,185,287,224,347}}},
 southeast={file="sweep-southeast-grip-study.png",scale=76.8/583,grips={
 {273,613,295,336,513,441},{267.5,613,257,334,447,445},{281,600,300,320,375,376},{281,600,282,303,357,377}}},
 south={file="sweep-south-study.png",scale=76.8/568,grips={
 {352.5,584,300,311,380,435},{280.5,585,225,310,290,432},{358.5,580,300,290,385,388},{287.5,581,235,303,305,365}}},
 southwest={file="sweep-southwest-grip-study.png",scale=76.8/578,grips={
 {407,594,380,337,194,431},{391,596,395,327,225,430},{407,592,412,334,350,369},{372.5,590,390,320,324,370}}},
 west={file="sweep-west-grip-study.png",scale=76.8/561,grips={
 {423.5,591,379,315,180,415},{423,591,380,323,200,415},{423,591,375,333,295,381},{397,591,363,338,303,373}}},
 northwest={file="sweep-northwest-separated.png",scale=76.8/536,ground=0,regions={{0,0,670,627},{670,0,584,627},{0,627,670,627},{670,627,584,627}},grips={
 {489,588,430,295,290,385},{418,588,312,308,273,376},{490,560,390,283,378,343},{418,560,300,283,290,343}}},
 north={file="sweep-north-rear.png",scale=76.8/574,grips={
 {367.5,600,457,259,502,323},{249.5,600,340,265,364,325},{368,583,460,244,490,309},{250.5,583,341,245,365,309}}},
 northeast={file="sweep-northeast-study.png",scale=76.8/578,grips={
 {291.5,587,435,272,553,339},{292,587,408,281,484,351},{307,593,433,281,477,350},{312,593,435,281,453,336}}},
}
-- Upper shaft endpoint, lower shaft endpoint and bristle ground contact.
R.brooms={
 {74,34,223,315,280,475},{59,34,211,328,265,475},{192,34,192,326,192,475},{310,34,160,326,110,475},
 {302,20,151,312,90,463},{303,22,169,318,104,463},{192,20,192,314,192,463},{76,20,218,310,275,463},
}
-- The generated mop atlas preserves the shaft and floor-contact geometry, so
-- it uses the same frame-specific body grip registration without adjustment.
R.mops=R.brooms
for i,d in ipairs(R.order) do local v=R.views[d];v.index=i;v.cols=v.cols or 2;v.w=v.w or 627;v.h=v.h or 627 end
return R
