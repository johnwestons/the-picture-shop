-- Apartment registration is authored in the original 1536x1024 art space.
-- One uniform transform is shared by rendering, collision, and interactions.
local Layout={SCALE=.58,X=34,Y=55}
Layout.DATA={
    ["brick-walkup"]={
        floor={380,188,1015,287,1047,232,1399,292,1384,883,937,777,911,805,717,766,687,823,96,681,278,383,275,361},
        walls={{224,482,794,581},{895,601,902,578},{921,870,991,622},
            {1028,453,1115,472},{1134,477,1408,525},{719,302,750,219},{845,337,876,250}},
        perimeter={{370,183,1010,274},{1037,204,1425,264},{1425,264,1408,1004},
            {1408,1004,917,932},{917,932,685,983},{685,983,22,854},{22,854,370,183}},
        spawn={807,719},rooms={living={520,681},bedroom={520,350},bathroom={1165,340},kitchen={1170,675},closet={785,280}},
        fixtures={
            toilet={x=1070,y=285,approach={1110,302},outline={1050,152,1102,161,1106,192,1093,214,1103,234,1094,266,1061,272,1040,250,1043,219,1051,205}},
            basin={x=1184,y=251,approach={1176,294},outline={1150,165,1207,173,1202,205,1195,211,1197,248,1177,250,1175,213,1151,203}},
            bath={x=1312,y=313,approach={1260,356},outline={1239,123,1374,143,1398,146,1401,254,1393,316,1250,301,1217,278,1222,218,1243,202}},
            laundry={x=1082,y=469,approach={1150,440},outline={1050,314,1117,321,1123,354,1110,476,1043,463,1045,352}},
            sink={x=1368,y=688,approach={1250,617},outline={1271,443,1363,459,1444,524,1425,692,1355,697,1275,566,1264,499}},
        },laptop={x=1380,y=552,approach={1303,706}},
    },
    garden={
        floor={255,196,702,275,734,191,829,207,807,278,922,299,957,227,1441,307,1386,681,1143,631,1010,907,85,638,200,408,159,383},
        walls={{163,491,821,610},{825,612,853,520},{890,437,940,306},
            {1037,510,1176,539},{1202,543,1379,566},{659,342,686,251},{812,288,827,239}},
        perimeter={{275,172,913,271},{938,213,1455,281},{1455,281,1350,914},
            {1350,914,1023,885},{1023,885,984,1008},{984,1008,35,796},{35,796,275,172}},
        spawn={970,724},rooms={living={492,700},bedroom={460,355},bathroom={1170,361},kitchen={1158,594},closet={758,254}},
        fixtures={
            toilet={x=1117,y=305,approach={1090,345},outline={1097,180,1157,190,1152,231,1136,243,1147,261,1135,299,1109,309,1089,292,1092,257,1104,243}},
            basin={x=1219,y=278,approach={1194,330},outline={1196,193,1256,208,1251,241,1234,247,1237,277,1215,277,1215,246,1187,235}},
            bath={x=1361,y=366,approach={1302,395},outline={1303,158,1460,187,1465,290,1441,368,1283,351,1267,329,1272,267,1297,245}},
            laundry={x=990,y=252,approach={1001,298},outline={973,95,1034,105,1032,149,1020,254,956,242,957,127}},
            sink={x=1377,y=685,approach={1190,574},outline={1211,409,1318,427,1451,526,1429,576,1387,691,1303,607,1204,540,1202,454}},
        },laptop={x=1395,y=550,approach={1285,654}},
    },
    courtyard={
        floor={352,196,628,239,884,253,914,208,1062,233,1080,201,1464,265,1440,380,1459,389,1416,631,1427,641,1388,842,1235,801,1190,952,90,616},
        walls={{238,420,637,458},{744,476,1385,592},{844,478,875,379},
            {610,321,640,227},{778,286,795,217},{1008,246,1021,208}},
        perimeter={{366,184,848,242},{897,197,1410,235},{1410,235,1424,1009},
            {1424,1009,1217,974},{1217,974,1153,1022},{1153,1022,92,795},{92,795,366,184}},
        spawn={1140,765},rooms={living={750,713},bedroom={1110,410},bathroom={465,304},kitchen={310,580},closet={720,300}},
        fixtures={
            toilet={x=574,y=278,approach={544,317},outline={554,163,607,173,602,211,591,221,604,242,592,275,568,282,549,260,553,230,559,215}},
            basin={x=493,y=238,approach={495,280},outline={469,157,532,171,528,203,508,214,509,236,488,239,487,211,460,200}},
            bath={x=383,y=270,approach={409,300},outline={330,49,427,58,423,172,455,188,453,232,435,273,326,258,310,240,313,213,330,177}},
            laundry={x=719,y=274,approach={758,312},outline={696,121,760,134,756,173,750,275,687,265,687,154}},
            sink={x=161,y=622,approach={270,576},outline={197,395,254,407,261,435,243,497,166,621,86,605,82,556,133,462,159,434}},
        },laptop={x=131,y=534,approach={240,600}},
    },
    corner={
        floor={370,250,708,323,760,220,1012,275,1205,307,1220,275,1403,314,1353,580,1431,605,1382,902,896,738,823,905,103,654},
        walls={{918,685,966,548},{1008,445,1412,521},{696,352,729,267},
            {1008,322,1025,280},{1163,336,1179,295}},
        perimeter={{354,262,691,307},{771,215,1009,256},{1054,261,1445,315},
            {1445,315,1427,974},{1427,974,1056,907},{1056,907,853,1003},{853,1003,194,947},
            {194,947,70,704},{70,704,354,262}},
        spawn={848,737},rooms={living={530,635},bedroom={1162,632},bathroom={845,315},kitchen={530,400},closet={1230,377}},
        fixtures={
            toilet={x=777,y=263,approach={762,298},outline={761,153,810,164,806,200,793,208,802,225,787,263,762,269,750,246,753,221,761,205}},
            basin={x=862,y=233,approach={843,278},outline={842,161,893,171,888,205,871,212,871,233,854,232,852,211,833,201}},
            bath={x=957,y=310,approach={933,350},outline={895,99,1014,128,1012,237,1027,237,1011,312,892,284,885,266,890,229,915,210,933,213,939,134}},
            laundry={x=1102,y=320,approach={1150,354},outline={1083,160,1146,174,1141,214,1130,322,1069,310,1065,193}},
            sink={x=552,y=362,approach={534,407},outline={445,204,509,215,697,258,700,305,675,370,578,344,579,293,508,275,497,332,417,315,414,247}},
        },laptop={x=635,y=282,approach={641,407}},
    },
}
function Layout.toWorld(x,y) return Layout.X+x*Layout.SCALE,Layout.Y+y*Layout.SCALE end
function Layout.toSource(x,y) return (x-Layout.X)/Layout.SCALE,(y-Layout.Y)/Layout.SCALE end
function Layout.get(state) return Layout.DATA[state.home.apartmentId] end
-- Authored world-grid power points. Every rotation preserves the apartment's
-- essential routes with either starter preset; furniture can be cleared first.
Layout.KITCHEN_HOOKUPS={
    ["brick-walkup"]={stove={x=712,y=444,direction="west"},refrigerator={x=768,y=492,direction="south"}},
    garden={stove={x=720,y=414,direction="west"},refrigerator={x=776,y=462,direction="south"}},
    courtyard={stove={x=224,y=378,direction="west"},refrigerator={x=288,y=402,direction="south"}},
    corner={stove={x=344,y=312,direction="west"},refrigerator={x=408,y=336,direction="south"}},
}
-- Preserve the existing stove accessor while keeping its authored facing.
Layout.KITCHEN_POWER={}
for apartmentId,points in pairs(Layout.KITCHEN_HOOKUPS) do
    Layout.KITCHEN_POWER[apartmentId]={points.stove.x,points.stove.y}
end
function Layout.applianceHookup(state,kind)
    local points=Layout.KITCHEN_HOOKUPS[state.home.apartmentId]
    return points and points[kind]
end
function Layout.kitchenPower(state)
    local point=Layout.applianceHookup(state,"stove")
    return point.x,point.y
end
local function inside(p,x,y)
    local result=false;local j=#p-1
    for i=1,#p,2 do
        local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1]
        if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then result=not result end
        j=i
    end
    return result
end
local function distance(segment,x,y)
    local ax,ay,bx,by=unpack(segment);local dx,dy=bx-ax,by-ay
    local t=math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy)))
    return math.sqrt((x-ax-dx*t)^2+(y-ay-dy*t)^2)
end
function Layout.walkable(id,x,y)
    local entry=Layout.DATA[id];if not entry then return false end
    x,y=Layout.toSource(x,y)
    if not inside(entry.floor,x,y) then return false end
    for _,wall in ipairs(entry.walls) do if distance(wall,x,y)<11 then return false end end
    -- Only the bases of fixed appliances block feet; their tall silhouettes do not.
    for _,fixture in pairs(entry.fixtures) do
        if math.abs(x-fixture.x)<(fixture==entry.fixtures.sink and 70 or fixture==entry.fixtures.bath and 65 or 24)
            and math.abs(y-fixture.y)<(fixture==entry.fixtures.bath and 23 or 14) then return false end
    end
    return true
end
function Layout.spawn(state,index)
    local p=Layout.get(state).spawn
    return Layout.toWorld(p[1]-((index or 1)-1)*31,p[2]-((index or 1)-1)*8)
end
local masks={}
function Layout.mask(id)
    if masks[id] then return masks[id] end
    -- A stable cached bitmap-shaped adapter lets the existing pathfinder and
    -- movement controller use their normal foot samples without art alpha scans.
    local columns={}
    local mask={}
    function mask:getDimensions() return 960,678 end
    function mask:getPixel(x,y)
        local column=columns[x]
        if not column then column={};columns[x]=column end
        local v=column[y]
        if v==nil then v=Layout.walkable(id,x,y) and 1 or 0;column[y]=v end
        return v,v,v,1
    end
    masks[id]=mask;return mask
end
function Layout.targets(player,state)
    local HomeInteractions=require("src.home_interactions")
    local entry=Layout.get(state);local targets={}
    targets.computer=require("src.home_surfaces").computer(state,player)
    local bikeCargo=require('src.home_bike_cargo').target(player,state)
    if bikeCargo then targets.bikeCargo=bikeCargo end
    for id,fixture in pairs(entry.fixtures) do
        local fx,fy=Layout.toWorld(unpack(fixture.approach))
        local hx,hy=Layout.toWorld(fixture.x,fixture.y)
        local interaction=HomeInteractions.describe(nil,id)
        targets["home_"..id]={kind="homeActivity",fixtureId=id,x=fx,y=fy,radius=48,
            hoverX=hx,hoverY=hy,hoverRadius=24,prompt="E: "..interaction.prompt,
            interaction=interaction.category,actionLabel=interaction.actionLabel}
    end
    for id,target in pairs(require("src.home_furniture").targets(state,player)) do targets[id]=target end
    return targets
end
return Layout
