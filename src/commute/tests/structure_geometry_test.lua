local Sites=require('src.commute.sites')
local Geometry=require('src.commute.structure_geometry')
local Test={}
local function near(a,b)return math.abs(a-b)<1e-6 end
local function sameVertices(a,b)
    if #a~=#b then return false end
    for i,v in ipairs(a) do for k,value in ipairs(v) do if value~=b[i][k] then return false end end end
    return true
end
function Test.run(check)
    local registry=Sites.create()
    check('structure_catalog_covers_all_five_destinations',#registry.all==5 and registry.byId.warehouse
        and registry.byId['brick-walkup'] and registry.byId.garden and registry.byId.courtyard and registry.byId.corner)
    local roads=require('src.commute.roads').new()
    local world=roads:attach(require('src.commute.terrain').new())
    local Rider=require('src.commute.rider');local Bike=require('src.commute.motorcycle')
    local total=0
    for _,site in ipairs(registry.all) do
        local pad=roads.destinations[site.id]
        check('structure_registered_door_'..site.id,near(site.door.x,pad.x) and near(site.door.z,pad.z-3)
            and near(site.threshold.x,pad.x) and near(site.threshold.z,pad.z-4) and near(site.h,pad.h))
        check('structure_clear_entry_and_parking_'..site.id,Rider.clear(world,site.door.x,site.door.z,Rider.RADIUS)
            and Rider.clear(world,pad.x,pad.z,Bike.RADIUS))
        local mesh=Geometry.build(site);total=total+#mesh.vertices
        local valid=#mesh.vertices>600 and #mesh.vertices%3==0
        for _,v in ipairs(mesh.vertices) do
            valid=valid and #v==12
            for _,n in ipairs(v) do valid=valid and n==n and math.abs(n)<1e9 end
            valid=valid and near(v[4]^2+v[5]^2+v[6]^2,1) and v[12]==1
                and v[1]>=mesh.bounds.minX and v[1]<=mesh.bounds.maxX
                and v[2]>=mesh.bounds.minZ and v[2]<=mesh.bounds.maxZ
                and v[3]>=mesh.bounds.minH and v[3]<=mesh.bounds.maxH
        end
        check('structure_finite_normals_bounds_'..site.id,valid)
        check('structure_has_recessed_windows_roof_and_entry_'..site.id,
            mesh.counts.windows>=4 and mesh.counts.roofs>=1 and mesh.counts.entries==1
                and mesh.features.entrance[1].x==site.threshold.x and mesh.features.entrance[1].z==site.threshold.z)
        check('structure_build_is_deterministic_'..site.id,sameVertices(mesh.vertices,Geometry.build(site).vertices))
        check('structure_static_vertex_budget_'..site.id,#mesh.vertices<65000)
    end
    check('structure_total_static_geometry_budget',total<180000)
    local shop=Geometry.build(registry.byId.warehouse)
    check('structure_warehouse_models_loading_door_and_roof_plant',shop.counts.loadingDoors==1
        and shop.counts.mechanical==1 and shop.counts.cylinders>=2 and shop.counts.signs==1)
    check('structure_garden_has_pitched_roof_and_balconies',Geometry.build(registry.byId.garden).counts.pitchedRoofs==1
        and Geometry.build(registry.byId.garden).counts.balconies==2)
    local court=registry.byId.courtyard
    local courtX,courtZ=court:toWorld(0,3,0)
    local wingX,wingZ=court:toWorld(-9,3,0)
    check('structure_courtyard_composite_collision_preserves_open_court',not court:blocked(courtX,courtZ)
        and court:blocked(wingX,wingZ) and not registry:vegetationAllowed(courtX,courtZ)
        and near(registry:grade(100,courtX,courtZ),court.h))
    check('structure_corner_has_three_storey_bay',Geometry.build(registry.byId.corner).features.cornerBays[1].floors==3)
    local bayX,bayZ=registry.byId.corner:toWorld(8.2,4,0)
    check('structure_corner_bay_extension_blocks_walkthrough',registry:blocked(bayX,bayZ))

    -- The same architecture can be placed on another map without any knowledge
    -- of Roads.destinations or the authored town's world coordinates.
    local moved=Sites.create({placements={{id='other-shop',design='warehouse',origin={x=-70,z=900,h=21},
        yaw=math.pi*.37,size={width=18,depth=4.16,height=6.75}}}}).byId['other-shop']
    local localSite=Sites.create({placements={{id='local-shop',design='warehouse',origin={x=0,z=0,h=0}}}}).byId['local-shop']
    local original,transformed=Geometry.build(localSite),Geometry.build(moved)
    local transformedCorrectly=#original.vertices==#transformed.vertices
    for i,v in ipairs(original.vertices) do
        local x,z,h=moved:toWorld(v[1],v[2],v[3]);local nx,ny,nz=moved:normalToWorld(v[4],v[5],v[6])
        local out=transformed.vertices[i]
        transformedCorrectly=transformedCorrectly and near(x,out[1]) and near(z,out[2]) and near(h,out[3])
            and near(nx,out[4]) and near(ny,out[5]) and near(nz,out[6])
    end
    check('structure_archetype_translates_rotates_and_resizes_exactly',transformedCorrectly)
    local insideX,insideZ=moved:toWorld(0,0,0)
    local outsideX,outsideZ=moved:toWorld(7,0,0)
    local dx,dz=moved:toLocal(moved.door.x,moved.door.z)
    check('structure_rotated_collision_and_anchors_share_transform',moved:blocked(insideX,insideZ)
        and not moved:blocked(outsideX,outsideZ) and near(dx,moved.design.door.x) and near(dz,moved.design.door.z)
        and near(moved.door.h,21))
    local definition={style='residential',width=8,depth=6,height=6,floors=2,
        threshold={x=0,z=3},door={x=0,z=4},parking={x=0,z=7}}
    local isolated=Sites.create({designs={small=definition},placements={{id='private',design='small',origin={x=0,z=0,h=1}}}})
    definition.width=200;definition.door.x=100
    check('structure_registry_detaches_external_design_edits',isolated.all[1].design.width==8
        and isolated:door('private').x==0 and isolated.all[1].design.door.x==0)
    local clear=true
    for _,segment in ipairs(roads.segments) do
        clear=clear and not registry:blocked(segment.a.x,segment.a.z)
            and not registry:blocked(segment.b.x,segment.b.z)
    end
    check('structure_default_footprints_leave_all_road_centerlines_open',clear)
    local spatiallyEquivalent=true
    for x=72,448,8 do for z=72,448,8 do
        local blocked,allowed,height=false,true,20
        local total,weighted,influence,flat=0,0,0,nil
        for _,site in ipairs(registry.all) do
            blocked=blocked or site:blocked(x,z)
            local distance=site:distance(x,z,true)
            local hardscape=site:hardscapeDistance(x,z)
            allowed=allowed and distance>=3 and hardscape>=1.2
            if distance<1e-8 or hardscape<1e-8 then flat=site.h
            elseif distance<Sites.GRADE_APRON or hardscape<5 then
                local blend=0
                if distance<Sites.GRADE_APRON then
                    local b=distance/Sites.GRADE_APRON;blend=1-b*b*(3-2*b)
                end
                if hardscape<5 then
                    local b=hardscape/5;blend=math.max(blend,1-b*b*(3-2*b))
                end
                local weight=blend/(distance*distance)
                total,weighted=total+weight,weighted+site.h*weight;influence=math.max(influence,blend)
            end
        end
        height=flat or (total>0 and height+(weighted/total-height)*influence or height)
        spatiallyEquivalent=spatiallyEquivalent and registry:blocked(x,z)==blocked
            and registry:vegetationAllowed(x,z)==allowed and near(registry:grade(20,x,z),height)
    end end
    check('structure_spatial_index_preserves_all_foundation_and_collision_results',spatiallyEquivalent)
    check('structure_distant_terrain_skips_building_queries',#registry:nearby(-100,-100)==0)
    local required={mechanic='garageBays',grocery='shelteredStorefronts',['post-office']='mailboxes',
        police='porticos',['fire-station']='hoseTowers',diner='curvedCanopies',
        ['coffee-shop']='pergolas',['general-store']='coveredPorches',residential='corbelledCornices'}
    for id,signature in pairs(required) do
        local placed=Sites.create({placements={{id='test-'..id,design=id,
            origin={x=1000,z=-300,h=14},yaw=.6}}}).all[1]
        local geometry=Geometry.build(placed)
        if id=='mechanic' then
            check('structure_mechanic_displays_majic_blue',geometry.features.signs[1].text=='MAJIC BLUE')
        end
        check('structure_service_archetype_'..id,geometry.counts[signature] and geometry.counts[signature]>0
            and geometry.counts.windows>=4 and geometry.counts.entries==1 and #geometry.vertices<65000)
        local normals=true
        for i=1,#geometry.vertices,3 do
            local a,b,c=geometry.vertices[i],geometry.vertices[i+1],geometry.vertices[i+2]
            local function dot(p)
                return (p[1]-a[1])*a[4]+(p[3]-a[3])*a[5]+(p[2]-a[2])*a[6]
            end
            normals=normals and math.abs(dot(b))<1e-5 and math.abs(dot(c))<1e-5
                and near(a[4]^2+a[5]^2+a[6]^2,1)
        end
        check('structure_surface_normals_follow_geometry_'..id,normals)
        check('structure_service_local_anchors_'..id,not placed:blocked(placed.door.x,placed.door.z)
            and not placed:blocked(placed.parking.x,placed.parking.z)
            and near(placed.threshold.h,14) and placed.front.z>0)
    end
    local allValid=true;for _,design in pairs(Sites.designs) do allValid=allValid and Sites.validDesign(design) end
    check('structure_all_frozen_design_schemas_are_valid',allValid)
    local function invalid(edit)
        local design=Sites.create().byId.warehouse.design
        edit(design);return not Sites.validDesign(design)
    end
    check('structure_rejects_invalid_frozen_foundation_and_obstacles',
        invalid(function(d)d.foundation={minX=2,maxX=1,minZ=0,maxZ=1}end)
        and invalid(function(d)d.obstacles={{minX=0,maxX=1,minZ=0/0,maxZ=1}}end)
        and invalid(function(d)d.obstacles={{minX=3,maxX=4,minZ=3,maxZ=4}}end))
    check('structure_rejects_sparse_frozen_footprint_arrays',invalid(function(d)
        d.footprints={[1]={minX=-5,maxX=-2,minZ=-2,maxZ=2},[3]={minX=2,maxX=5,minZ=-2,maxZ=2}}
    end))
    check('structure_rejects_unsafe_frozen_design_values',
        invalid(function(d)d.door.h=false end) and invalid(function(d)d.style='unknown' end)
        and invalid(function(d)d.extra=d end) and invalid(function(d)d.height=math.huge end)
        and invalid(function(d)d.threshold.x=100 end))
    local Codec=require('src.net.codec')
    local encoded=assert(Codec.encode(Sites.designs.courtyard,{maxBytes=8192,maxEntries=512}))
    local decoded=assert(Codec.decode(encoded,{maxBytes=8192,maxEntries=512}))
    check('structure_validates_official_decoded_array_markers',Sites.validDesign(decoded))
    check('structure_rejects_untrusted_custom_metatables',invalid(function(d)setmetatable(d,{__index={width=10}})end))
end
return Test
