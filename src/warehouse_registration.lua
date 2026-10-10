-- Contacts measured on the B6 / room artwork, in the 960 x 678 game canvas.
-- Walking contacts are feet on the floor; hover contacts are visible objects.
-- Keep both here so changing an image cannot leave NPCs using a former door.
local Map={VERSION=1}
-- The old wall window is now the expansion passage; the customer door moved
-- into the lounge wall beside the sofa.
Map.entrance={x=720,y=202,radius=44,hoverX=720,hoverY=151,hoverRadius=22}
Map.roomEntrance={x=648,y=212,radius=52,hoverX=648,hoverY=161,hoverRadius=30}
Map.exit={x=100,y=225,radius=44,hoverX=78,hoverY=167,hoverRadius=25}
Map.exitPoints={{x=720,y=202},{x=710,y=211},{x=728,y=214},{x=718,y=224}}
Map.reception={x=697,y=235}
Map.computer={x=913,y=229,radius=44,hoverX=909,hoverY=175,hoverRadius=23}
Map.phone={x=848,y=213,wallX=879,wallY=144,hoverRadius=18}
Map.clock={x=480,y=260,wallX=480,wallY=50,clockRadius=13,hoverRadius=16}
Map.dock={x=194,y=213,radius=44,hoverX=184,hoverY=129,hoverRadius=18}
Map.aperture={{x=58,y=125},{x=151,y=87},{x=151,y=174},{x=58,y=213}}
Map.truck={parked={x=-10.7,y=235,scale=.72},start={x=-166,y=170,scale=.72},
    interaction={x=127,y=242,radius=48,hoverX=109,hoverY=169,hoverRadius=32}}
Map.shelves={x=530,y=285,radius=160,hoverX=530,hoverY=170,hoverRadius=110}
Map.rest={x=775,y=260,radius=65,hoverX=765,hoverY=184,hoverRadius=80}
Map.roomSeats={{x=745,y=195},{x=785,y=202},{x=643,y=202},{x=830,y=231}}
Map.customerRoute={{x=720,y=202},{x=720,y=230},{x=715,y=259},{x=746,y=266},{x=770,y=258}}
Map.vendorRoute={{x=720,y=202},{x=720,y=230},{x=715,y=259},{x=760,y=280}}
Map.technicianRoute={{x=720,y=202},{x=720,y=230},{x=715,y=259},{x=720,y=310}}
Map.lobbySeats={
    {name="sofa-left",x=750,y=198,facing=-1,approach={{x=720,y=253},{x=729,y=215}},
        seatedPose={x=754,y=176,mirror=1}},
    {name="sofa-right",x=788,y=202,facing=1,approach={{x=817,y=253},{x=817,y=231}},
        seatedPose={x=794,y=185,mirror=1}},
    {name="right-chair",x=804,y=220,facing=-1,approach={{x=815,y=267},{x=815,y=249}},animation="sitting",
        seatedPose={x=811,y=201,mirror=1}},
}
Map.floorEdges={
    warehouse={{0,266},{50,238},{195,171},{219,164},{235,170},{568,246},
        {594,230},{664,192},{684,180},{695,181},{817,209},{828,219},{837,201},{935,230},{960,261}},
    storage={{0,248},{195,174},{220,174},{875,271},{960,284}},
    breakroom={{0,252},{195,170},{530,211},{562,202},{606,188},{874,250},{960,261}},
    floor={{0,252},{195,174},{535,224},{960,282}},
}
Map.furniture={
    {x=773,y=183,halfWidth=34,halfHeight=15,kind="lobby_sofa"},
    {x=811,y=212,halfWidth=14,halfHeight=12,kind="lobby_chair"},
    {x=828,y=210,halfWidth=6,halfHeight=13,kind="office_pillar"},
    {x=862,y=188,halfWidth=12,halfHeight=18,kind="office_cabinet"},
    {x=922,y=205,halfWidth=22,halfHeight=13,kind="office_desk"},
    {x=899,y=214,halfWidth=14,halfHeight=10,kind="office_chair"},
}
Map.breakFurniture={
    {x=730,y=210,halfWidth=54,halfHeight=20,kind="break_table"},
    {x=765,y=184,halfWidth=66,halfHeight=17,kind="break_sofa"},
    {x=641,y=179,halfWidth=30,halfHeight=17,kind="break_chair"},
    {x=833,y=213,halfWidth=27,halfHeight=20,kind="break_chair"},
    {x=920,y=213,halfWidth=28,halfHeight=40,kind="break_shelves"},
}
Map.lobbyForegrounds={
    ["right-chair"]={797,203,819,210,819,225,797,218},
}
function Map.walkable(x,y,kind)
    if x<8 or x>952 or y>670 then return false end
    -- Give the new rack-wall passage enough floor-mask clearance for the
    -- loaded jack footprint to reach its room-transition interaction point.
    if kind=="warehouse" and x>=604 and x<=692 and y>=186 and y<=236 then return true end
    local edge=Map.floorEdges[kind] or Map.floorEdges.floor
    for i=2,#edge do
        local a,b=edge[i-1],edge[i]
        if x<=b[1] then return y>=a[2]+(b[2]-a[2])*(x-a[1])/(b[1]-a[1]) end
    end
    return false
end
function Map.obstacles(kind)
    local result={}
    for _,shape in ipairs(kind=="breakroom" and Map.breakFurniture or Map.furniture) do
        local item={};for key,value in pairs(shape) do item[key]=value end
        result[#result+1]=item
    end
    return result
end
return Map
