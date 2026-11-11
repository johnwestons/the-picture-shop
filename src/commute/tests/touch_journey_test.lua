local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Gear=require('src.commute.gear')
local Town=require('src.commute.town')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Test={}
function Test.run(check)
    local state=require('src.state').new();state.screen='world'
    local world=Town.world(state.home.town)
    local player={id=1,sceneId='commute'}
    local week=state.home.weekend
    week.phase='ready';week.closedAtHours=week.closesAtHours;week.travelToken=42;week.readyMask=1
    assert(Trip.start(state,{player},42,world))
    local saves=0
    local R={state=state,World={player=player},Config={baseWidth=960,baseHeight=678},
        App={settings={motorcycleControls=Bindings.defaults()}},_commute={world=world,renderer={}},
        mobileControls={enabled=true,cancelAll=function()end},
        multiplayer={isClient=function()return false end,isHost=function()return false end},
        saveCurrent=function()saves=saves+1 end}
    local rider=C.localPart(R).rider
    local function step(seconds)
        for _=1,math.ceil(seconds/.05) do Trip.update(state,player,{},.05,world);C.syncPlayer(player,C.localPart(R)) end
    end
    local function tap(x,y)
        local hit=C.touchPressed(R,'finger',x,y)
        C.touchReleased(R,'finger');return hit
    end
    local function gearTap()
        local b=assert(C.gearTouchButton(R));return tap(b.x+b.width/2,b.y+b.height/2)
    end
    local function useTap()
        local p=C.bindings(R).layout.touch4
        return tap(p.x*R.Config.baseWidth,p.y*R.Config.baseHeight)
    end
    local function actionTap(action)
        local target
        for _,button in ipairs(Touch.actionButtons(R.Config.baseWidth,R.Config.baseHeight,C.bindings(R),
            C.controlContext(R,C.localPart(R)),{mobile=true})) do
            if button.action==action then target=button end
        end
        return target and tap(target.x,target.y)
    end
    step(.1)
    check('touch_commute_blank_pointer_owns_warehouse_fallback',require('src.input').mousepressed(400,200,1,
        {state=state,world=R.World})==true)
    R._commute.renderer=nil
    check('touch_commute_first_loading_frame_consumes_touch',C.touchPressed(R,'early',400,200)
        and R._commute.touchControls==nil)
    R._commute.renderer={};R._commute.loading=true
    local held=C.bindings(R).layout.touch1
    C.touchPressed(R,'loading',held.x*R.Config.baseWidth,held.y*R.Config.baseHeight)
    local loadingTouch=C.touch(R)
    check('touch_commute_loading_never_latches_acceleration',next(loadingTouch.contacts)==nil and next(loadingTouch.held)==nil)
    check('touch_commute_loading_pointer_cannot_latch_cockpit_boost',C.pointer(R,400,200,'loading') and not R._commute.touchBoost)
    R._commute.camera={}
    check('touch_commute_loading_blocks_camera_drag',not C.cameraPointerPressed(R,3,false) and R._commute.cameraDrag==nil)
    R._commute.camera=nil;R._commute.loading=nil
    player.sceneId='warehouse'
    check('touch_commute_does_not_capture_local_warehouse_player',not C.touchPressed(R,'shop',400,200))
    player.sceneId='commute'
    check('touch_gear_default_button_is_explicit',C.gearTouchButton(R).label=='PUT ON GEAR')
    local nearbyX,nearbyZ=rider.ped.x,rider.ped.z
    rider.ped.x,rider.ped.z=rider.bike.x+5,rider.bike.z
    check('touch_gear_button_only_appears_near_bike',C.gearTouchButton(R)==nil)
    rider.ped.x,rider.ped.z=nearbyX,nearbyZ
    -- The dock bay is on the far side of the expanded lot, so approach it on
    -- foot before tapping the truck interaction control.
    rider.ped.x,rider.ped.z=state.home.commute.truck.x-4,state.home.commute.truck.z
    useTap();step(.1)
    check('touch_use_enters_nearby_delivery_truck_without_dressing',rider.vehicle=='truck'
        and rider.gear.outfit=='normal' and not rider.gear.transition and saves==1 and C.gearTouchButton(R)==nil)
    useTap();step(.1)
    check('touch_use_exits_delivery_truck_before_gear_actions',rider.vehicle==nil
        and rider.gear.outfit=='normal' and not rider.gear.transition and saves==2)
    state.home.commute.truck=nil
    rider.ped.x,rider.ped.z=rider.bike.x,rider.bike.z
    step(.1)
    check('touch_gear_button_starts_real_equip_command',gearTap() and rider.gear.transition.kind=='equip' and saves==3)
    local revision=rider.gear.revision
    gearTap()
    check('touch_gear_transition_button_disabled',not C.gearTouchButton(R).enabled and rider.gear.revision==revision and saves==3)
    local graphics=love.graphics;local label
    love.graphics={push=function()end,pop=function()end,setColor=function()end,rectangle=function()end,
        printf=function(text)label=text end}
    local drew=C.drawGearTouch(R)
    love.graphics=graphics
    check('touch_gear_transition_has_visible_disabled_label',drew and label=='CHANGING GEAR...')
    step(Gear.duration('equip')+.1)
    check('touch_gear_equip_completes_on_foot',rider.gear.outfit=='geared' and not rider.gear.mounted)
    useTap();step(Gear.duration('mount')+.1)
    check('touch_gear_use_mounts_and_starts_engine',Gear.allowed(rider.gear,'ride'))
    check('touch_gear_button_hidden_while_mounted',C.gearTouchButton(R)==nil)
    actionTap('ignition')
    check('touch_gear_shared_ignition_button_switches_off',rider.gear.mounted and not rider.gear.engine)
    actionTap('ignition')
    check('touch_gear_shared_ignition_button_restarts',rider.gear.engine)
    useTap();step(Gear.duration('dismount')+.2)
    check('touch_gear_use_dismounts_without_removing_outfit',not rider.gear.mounted and not rider.gear.engine
        and rider.gear.outfit=='geared' and C.gearTouchButton(R).label=='REMOVE GEAR')
    gearTap();step(Gear.duration('remove')+.1)
    check('touch_gear_remove_completes_without_keyboard',rider.gear.outfit=='normal' and not rider.gear.mounted and not rider.gear.transition)
    check('touch_gear_preserves_customizable_driving_bindings',C.bindings(R).touch.gear==''
        and Bindings.action(C.bindings(R),'touch','touch1')=='accelerate'
        and Bindings.action(C.bindings(R),'touch','touch4')=='interact')
    for _,size in ipairs({{640,480},{960,678},{1280,880}}) do
        R.Config.baseWidth,R.Config.baseHeight=unpack(size)
        local b=C.gearTouchButton(R)
        check('touch_gear_layout_stays_visible_'..size[1],b.x>=0 and b.y>=0
            and b.x+b.width<=size[1] and b.y+b.height<=size[2] and b.height>=44)
    end
    state.screen='options'
    check('touch_gear_button_not_active_behind_options',C.gearTouchButton(R)==nil)
end
return Test
