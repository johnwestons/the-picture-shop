local Vegetation=require('src.commute.vegetation')
local Obstacles=require('src.commute.obstacles')
local Flora=require('src.commute.flora')
local Test={}
local function fixture(records)
    local world={size=128,seed=4261,height=function()return 5 end}
    local vegetation=Vegetation.new(world)
    function vegetation:_makePatch(px,pz)
        local props={}
        for _,record in ipairs(records) do
            if math.floor(record.x/16)==px and math.floor(record.z/16)==pz then
                local p={};for k,v in pairs(record) do p[k]=v end
                props[#props+1]=p
            end
        end
        return props
    end
    return vegetation
end
local function near(a,b) return a and b and math.abs(a-b)<1e-8 end
function Test.run(check)
    local tree={id=51,kind='oak',x=16.2,z=24,h=5,scale=1}
    -- Pick an existing mature tree by ID so lifecycle calendar remains forward.
    for id=1,100 do
        tree.id=id;Flora.present(tree,4261,{totalDays=0})
        if tree.plantAge>Flora.catalog.types.oak.mature and tree.lifePhase=='live' and not tree.visualVariant then break end
    end
    local calendar={month=5,totalDays=0}
    local radius,height=Obstacles.shape(tree,4261,calendar)
    local v=fixture({tree})
    local t,nx,nz,kind,id=v:sweepObstacles(10,24,20,24,.42,5,6.2,calendar)
    check('commute_tree_trunk_sweep_returns_near_surface_and_outward_normal',
        near(t,(tree.x-radius-.42-10)/10) and near(nx,-1) and near(nz,0)
        and kind=='oak' and id==tree.id)
    check('commute_trunk_under_canopy_is_clear_beyond_narrow_footprint',
        not v:sweepObstacles(10,25.2,20,25.2,.42,5,6.2,calendar))
    check('commute_tree_collision_respects_vertical_trunk_extent',
        not v:sweepObstacles(10,24,20,24,.42,5+height+.1,6+height,calendar)
        and not v:sweepObstacles(10,24,20,24,.42,3,4,calendar))
    check('commute_zero_length_query_detects_overlap_for_save_recovery',
        v:sweepObstacles(tree.x,tree.z,tree.x,tree.z,.42,5,6.2,calendar)==0)
    check('commute_existing_overlap_can_back_away_without_becoming_trapped',
        not v:sweepObstacles(tree.x-.1,24,tree.x-1,24,.42,5,6.2,calendar)
        and v:sweepObstacles(tree.x-.1,24,tree.x+.1,24,.42,5,6.2,calendar)==0)
    local generated=v:stats().generated
    for _=1,300 do v:sweepObstacles(15,24,15.1,24,.42,5,6.2,calendar) end
    check('commute_collision_reuses_nearby_patches_without_render_or_steady_generation',
        generated<=4 and v:stats().generated==generated)

    local rock={id=7,kind='rock',x=32.2,z=24,h=5,scale=1}
    local rocks=fixture({rock})
    local rr,rh=Obstacles.shape(rock,4261,calendar)
    local hit=rocks:sweepObstacles(27,24,31.5,24,.42,5,6.2,calendar)
    check('commute_rock_footprint_crosses_patch_boundary_before_center',hit and hit<1)
    check('commute_fast_sweep_cannot_tunnel_through_rock_between_endpoints',
        near(rocks:sweepObstacles(2,24,100,24,.42,5,6.2,calendar),(rock.x-rr-.42-2)/98))
    check('commute_jump_above_rock_does_not_hit_invisible_vertical_wall',
        not rocks:sweepObstacles(27,24,38,24,.42,5+rh+.01,7+rh,calendar))
    local scaled={id=rock.id,kind='rock',x=rock.x,z=rock.z,h=rock.h,scale=2}
    local sr,sh=Obstacles.shape(scaled,4261,calendar)
    check('commute_rock_collision_scales_with_rendered_body',near(sr,rr*2) and near(sh,rh*2))
    local harmless={}
    for i,kindName in ipairs({'bramble','blueberry','sumac','chickasaw-plum','grass','log','twig','stone'}) do
        harmless[#harmless+1]={id=i,kind=kindName,x=20+i,z=24,h=5,scale=1}
    end
    check('commute_brush_bushes_logs_and_pebble_clutter_are_not_solid',
        not fixture(harmless):sweepObstacles(10,24,40,24,.42,5,6.2,calendar))

    local stages=fixture({tree})
    local d=Flora.catalog.types.oak
    local initial=tree.plantAge
    local deadDay=d.longevity-initial+1
    local decayDay=deadDay+d.deadDays
    local vacantDay=decayDay+d.decayDays
    local seedDay=vacantDay+d.vacantDays-1
    check('commute_standing_dead_tree_remains_solid',
        stages:sweepObstacles(10,24,20,24,.42,5,6.2,{month=5,totalDays=deadDay})~=nil)
    check('commute_fallen_decayed_and_vacant_trees_do_not_leave_ghost_trunks',
        not stages:sweepObstacles(10,24,20,24,.42,5,6.2,{month=5,totalDays=decayDay})
        and not stages:sweepObstacles(10,24,20,24,.42,5,6.2,{month=5,totalDays=vacantDay}))
    check('commute_new_seed_replacing_tree_has_no_old_trunk_collision',
        not stages:sweepObstacles(10,24,20,24,.42,5,6.2,{month=5,totalDays=seedDay}))
    check('commute_return_to_saved_calendar_restores_original_collision',
        near(stages:sweepObstacles(10,24,20,24,.42,5,6.2,calendar),t))

    local actual=require('src.commute.roads').new():attach(require('src.commute.terrain').new())
    local unseen=Vegetation.new(actual)
    local target
    for pz=5,10 do for px=5,10 do
        for _,p in ipairs(unseen:_getPatch(px,pz).props) do
            if Obstacles.shape(p,actual.seed,calendar) then target=p;break end
        end
        if target then break end
    end if target then break end end
    assert(target,'Expected a seeded solid scenery candidate')
    local hitTime,_,_,hitKind,hitId=actual:sweepObstacles(target.x,target.z,target.x,target.z,.01,target.h,target.h+1)
    check('commute_headless_world_collides_with_same_seeded_scenery_without_renderer',
        hitTime==0 and hitKind==target.kind and hitId==target.id and actual.vegetation~=nil)
    local cached=actual.vegetation
    cached.maxPatches=1
    for _,point in ipairs({{300,100},{400,400},{100,400}}) do
        cached:sweepObstacles(point[1],point[2],point[1]+.1,point[2],.42,5,6.2,calendar)
    end
    local repeatTime,_,_,repeatKind,repeatId=actual:sweepObstacles(target.x,target.z,target.x,target.z,.01,target.h,target.h+1)
    check('commute_solid_identity_survives_patch_eviction_and_regeneration',
        repeatTime==hitTime and repeatKind==hitKind and repeatId==hitId and cached:stats().patches<=1)
    require('src.commute.tests.thin_tree_collision_test').run(check)
end
return Test
