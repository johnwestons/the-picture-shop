local Layout=require('src.commute.recreation_layout')
local Infrastructure=require('src.commute.infrastructure')
local Geometry=require('src.commute.infrastructure_geometry')
local Test={}
function Test.run(check)
    local areas={{id='park',kind='park',x=40,z=50,h=5,radius=24,heading=1.3,trailId='trail-a'},
        {id='camp',kind='camp',x=100,z=50,h=5,radius=24,heading=-.7,trailId='trail-b'}}
    local world={town={generatorVersion=3,seed=42,roads={},placements={},recreation=areas},
        sites={all={},blocked=function()return false end},height=function()return 5 end}
    world.roads=require('src.commute.roads').new({definitions={},destinations={},sites=world.sites})
    local plan=Infrastructure.ensure(world)
    local c=plan.counts
    check('recreation_park_and_camp_have_full_facilities',c.pond==1 and c.stage==1 and c.tent==3
        and c.fireRing==3 and c.table==7 and c.logSeat==7 and c.rangerHut==1 and c.outhouse==1)
    local parking,campParking=0,0
    for _,surface in ipairs(plan.recreationSurfaces) do
        if surface.kind=='parking' then
            parking=parking+1
            if surface.areaId=='camp' then campParking=campParking+1 end
        end
    end
    check('recreation_only_park_has_parking',parking==1 and campParking==0)
    local passable=true;local blockedAt
    for _,area in ipairs(areas) do
        for _,path in ipairs(Layout.plan(area).paths) do
            local points=Layout.pathPoints(path)
            for i=1,#points-1 do
                local a,b=points[i],points[i+1]
                local dx,dz=b[1]-a[1],b[2]-a[2];local length=math.sqrt(dx*dx+dz*dz)
                for step=0,math.ceil(length*4) do
                    local t=step/math.ceil(length*4)
                    for _,offset in ipairs({-.4,0,.4}) do
                        local x,z=Layout.point(area,a[1]+dx*t-dz/length*offset,a[2]+dz*t+dx/length*offset)
                        if plan:occupied(x,z,.36) then
                            passable=false;blockedAt=area.id..' path '..i..' at '..step
                        end
                    end
                end
            end
        end
    end
    check('recreation_paths_leave_room_for_walking_between_amenities',passable,blockedAt)
    local solid=true
    for _,f in ipairs(plan.fixtures) do solid=solid and plan:blocked(f.x,f.z) end
    check('recreation_pond_buildings_and_furniture_have_physical_collision',solid)
    local ground=require('src.commute.terrain_mesh');local buried=true
    for _,surface in ipairs(plan.recreationSurfaces) do
        local p=surface.corners[1]
        for _,spacing in ipairs({1,1.5}) do
            buried=buried and ground.visualHeight(world,p[1],p[2],5.4,spacing)<p[3]
        end
    end
    check('recreation_paths_cover_coarse_terrain_without_changing_physics',buried and world:height(40,50)==5)
    local finite=true;local count=0
    for _,mesh in ipairs(Geometry.build(plan)) do
        for _,v in ipairs(mesh.vertices) do
            count=count+1
            for _,number in ipairs(v) do finite=finite and number==number and math.abs(number)<10000 end
        end
    end
    check('recreation_models_and_paths_generate_finite_batched_geometry',finite and count>1000 and count<100000)
end
return Test
