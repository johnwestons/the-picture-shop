local Tutorial={VERSION=2}
Tutorial.steps={
    {id='computer',title='Visit the office computer',detail='Walk to the office computer and use it.',
        body='Welcome to The Picture Shop! Move with WASD / arrow keys, the controller stick, or the touch movement stick.\n\nWalk up to the office computer. When its prompt appears, press E / controller A or tap USE.\n\nThe computer holds your email, job estimates, supplies, and hiring. These lessons advance as you work. Open NOTICES on the HUD, or press F6, to read them again.'},
    {id='job',title='Take your first job',detail='Read a client request and get a job awarded.',
        body='At the computer, use the arrow beside the address bar to find EMAIL and ESTIMATING. Select a client message to read the paper sizes, quantity, and deadline.\n\nPrepare and send the estimate, then watch for the client reply. An awarded job appears in your active jobs. If you have no request yet, meet a customer at reception or answer the work phone; the client will send written details.\n\nNew email and call notices also stay in this inbox. Close this panel to return to the screen you were using.'},
    {id='delivery',title='Receive the job paper',detail='Wait for the job paper to reach the warehouse.',
        body='An awarded job still needs its paper delivered. Check the active job and delivery information on the computer.\n\nWhen the delivery truck arrives, follow the dock prompts and sign for the delivery if asked. Let unloading finish and leave the dock clear.\n\nYour next lesson starts when the job paper is available in the shop.'},
    {id='load',title='Load the paper cutter',detail='Bring a job pallet to the cutter, then load a batch.',
        body='Use the manual pallet jack to move the job paper to the cutter input area. Approach the jack and use the on-screen pickup, move, and park prompts. Leave room to stand at the cutter controls.\n\nOpen the Polar 115 cutter and choose LOAD (L on a keyboard), then select your job pallet. The cutter loads a batch from that pallet.\n\nThe machine help button explains each control. You can return to this lesson whenever you need it.'},
    {id='cut',title='Make your first cut',detail='Set the backgauge, position the paper, clamp, and cut.',
        body='Read the current cut in the program / job instructions. Set the backgauge to its requested measurement and rotate the paper if the cut requires it.\n\nPush the paper into position against the backgauge, lower the clamp, then operate the highlighted cut controls. Solo play uses both cut controls together; multiplayer allows either control.\n\nIf the cutter blocks the cut, read its message and correct the gauge, paper position, clamp, or safety condition. Wait for the blade cycle to finish.'},
    {id='wrap',title='Finish and wrap a stack',detail='Complete the cuts and wrap a finished pallet.',
        body='Raise the clamp and follow the next cut in the program. Rotate or reposition the paper when requested, and repeat for the remaining batches.\n\nMove a completed pallet from the cutter output to the skid wrapper. Follow its loading and wrapping controls. Jobs that require printing must also go through the press before final wrapping.\n\nA wrapped pallet is ready for its next delivery or pickup step. Keep the staging area and loading dock clear.'},
    {id='shipping',title='Deliver a finished job',detail='Inspect, arrange transport, and get paid.',
        body='Use the active job ticket on the office computer to inspect the finished pallets and arrange transport. If the client supplies transport, keep the dock clear for their pickup. Otherwise choose an employee driver or player delivery.\n\nFor player delivery, use the front entrance and PLAN PAPER DELIVERIES. Select jobs within the truck capacity, back up to the shop dock, and load every pallet. Follow GPS to each stop and its handoff prompt. Payment arrives when the job is completed.\n\nIndustrial receiving and dispatch operate Monday-Friday, 09:00-20:00. You can prepare pallets after hours, but a closed customer will not accept them.'},
    {id='commute',title='Explore the commute map',detail='Use the shop front entrance to explore town.',
        body='Walk to the front entrance and use its TOWN prompt. Choose EXPLORE TOWN to walk outside. In multiplayer, each player can travel independently while others keep working.\n\nYour shop, apartment, shops, roads, and parking areas share the commute map. Use MAP to choose a destination and GPS to follow the roads. Park near an entrance, stop, dismount, and use the door prompt.\n\nYou can visit town during the week. Friday shutdown is a separate choice at the shop entrance. The remaining travel and home lessons are available now under NOTICES > TUTORIAL.'},
    {id='map',title='Find your way with GPS',detail='Open MAP outside and choose a destination.',
        body='While outside, tap or click MAP to open the town map. Choose your apartment, the warehouse, or a business as the GPS destination. The marked route follows the road network; use the mini-map while driving and follow your side of the road.\n\nClose the map to move again. The camera controls let you change your view without changing your destination.\n\nArriving nearby does not enter a building automatically: park, stop the engine, dismount, and use the entrance prompt. Watch business opening hours before making a trip.'},
    {id='motorcycle',title='Ride your motorcycle',detail='Put on riding gear, mount, and take a short ride.',
        body='Walk to your motorcycle and use the riding-gear prompt. Wait for the outfit and helmet sequence, then use the mount prompt. Follow the engine prompt if it is off.\n\nUse the displayed driving controls: keyboard movement keys, the controller stick, or mobile steering and throttle. Start slowly, brake before bends, and keep to the correct lane. You can choose your preferred touch steering in settings.\n\nStop completely before switching off the engine or dismounting. Remove riding gear before operating shop equipment. Watch fuel and condition: visit the gas station for fuel and the mechanic for servicing.'},
    {id='apartment',title='Visit your apartment',detail='Navigate home and use your apartment entrance.',
        body='Choose your apartment on the town map and follow GPS there. Park your motorcycle, stop and dismount, then use the apartment entrance.\n\nInside, approach furniture and fixtures to see their use prompts. Your home has needs such as hunger, energy, and hygiene; use the home controls to choose appropriate activities.\n\nMY HOME on the computer lets you review rent, household money, and home purchases. Furniture and grocery deliveries arrive at the apartment entrance. Use the apartment exit whenever you want to return to town.'},
    {id='homecare',title='Eat, wash, and rest',detail='Use an apartment activity and set up your routine.',
        body='Use the kitchen and groceries to prepare food, then eat using the dining prompts. Bathroom fixtures let you look after hygiene. Approach a bed, couch, or sleeping spot to rest.\n\nThe home controls include alarm settings and sleep choices, including sleeping until Monday. Shared fast sleep requires everyone to be sleeping; waking up returns time to normal.\n\nBuy food at the grocery store and bring it home. Furnishings, pantry supplies, rent, and personal spending belong to the household budget, which you can review under MY HOME.'},
    {id='errands',title='Use the town businesses',detail='Visit a town shop for supplies, food, or fuel.',
        body='Use MAP and GPS to visit the grocery store, gas station, mechanic, diner, or general store. Park and use the entrance or service prompt. Check the price and your available money before buying.\n\nGrocery hours are 07:00-21:00 and gas station hours are 06:00-22:00, including weekends. Industrial suppliers and receiving docks close on weekends.\n\nAs the shop grows, use the office computer for hiring, equipment, supplies, finances, and job tracking. Keep aisles and loading bays clear so employees and trucks can reach their work.'},
    {id='weekend',title='Close up for the weekend',detail='Finish shutdown and choose CLOSE SHOP & LEAVE.',
        body=require('src.business_notifications').weekendBody},
}
function Tutorial.new(enabled)return {version=Tutorial.VERSION,enabled=enabled==true,step=1,seen={},finished=false}end
function Tutorial.travelContext(runtime)
    local part=require('src.commute.runtime').localPart(runtime)
    return {sceneId=runtime.World.player.sceneId,rider=part and part.rider,
        mapOpen=runtime._commute and runtime._commute.mapOpen,
        shopOpen=runtime._commute and runtime._commute.mechanicOffer~=nil,
        resident=require('src.home_residents').get(runtime.state,runtime.World.player)}
end
function Tutorial.normalize(value)
    if value==nil then return Tutorial.new(false) end
    if type(value)~='table' or type(value.enabled)~='boolean' or type(value.finished)~='boolean'
        or type(value.step)~='number' or value.step%1~=0 or value.step<1 or value.step>#Tutorial.steps+1
        or type(value.seen)~='table' or (value.version~=nil and value.version~=1 and value.version~=Tutorial.VERSION) then return nil end
    local result=Tutorial.new(value.enabled);result.step=value.step;result.finished=value.finished
    if (value.version or 1)<2 and value.finished and value.step==7 then result.finished=false end
    for key,v in pairs(value.seen) do
        local known=false;for _,s in ipairs(Tutorial.steps) do if s.id==key then known=true end end
        if not known or v~=true then return nil end
        result.seen[key]=true
    end
    return result
end
function Tutorial.addReferences(state)
    local notices=require('src.notifications');local changed=false
    -- Reverse insertion presents the reference library in lesson order.
    for i=#Tutorial.steps,1,-1 do
        local step=Tutorial.steps[i]
        local n,added=notices.add(state,'tutorial',step.title,step.detail,step.body,'tutorial:'..step.id)
        if added then n.unread=false;changed=true end
    end
    return changed
end
local function observe(context,t)
    local state=context.state
    local seen=t.seen
    if state.screen=='computer' or (context.computerOpen and context.computerOpen()) then seen.computer=true end
    local jobs=state.jobs or {};local active=jobs.active or {};local done=jobs.completed or {}
    if #active>0 or #done>0 then seen.job=true end
    for _,list in ipairs({active,done}) do for _,job in ipairs(list) do
        for _,pallet in ipairs(job.pallets or {}) do
            local location=pallet.location
            if location=='warehouse' or location=='on_pallet_jack' or location=='at_cutter'
                or location=='cutter_output' or location=='at_press' or location=='press_output'
                or location=='at_wrapper' or pallet.wrapped then seen.delivery=true end
            if location=='at_cutter' or location=='cutter_output' then seen.load=true end
            if pallet.wrapped or pallet.status=='wrapped' then seen.wrap=true end
        end
    end end
    if context.machine and context.machine.loaded and context.machine.paper then seen.load=true end
    if state.shopProgress and (state.shopProgress.completedCuts or 0)>0 then seen.cut=true end
    if #done>0 then seen.delivery=true;seen.load=true;seen.cut=true;seen.wrap=true end
    if #done>0 then seen.shipping=true end
    local travel=context.travel and context.travel() or {}
    local player=context.world and context.world.player
    local scene=travel.sceneId or player and player.sceneId
    if scene=='commute' then seen.commute=true end
    if travel.mapOpen then seen.map=true end
    local rider=travel.rider
    if rider and rider.gear and rider.gear.mounted and rider.gear.engine
        and rider.bike and (rider.bike.speed or 0)>.2 then seen.motorcycle=true end
    if scene=='home' then seen.apartment=true end
    if scene=='home' and travel.resident and travel.resident.activity then seen.homecare=true end
    if travel.shopOpen or state.screen=='grocery' then seen.errands=true end
    local week=state.home and state.home.weekend
    if week and (week.phase=='ready' or week.phase=='home') then seen.weekend=true end
    return scene,travel
end
function Tutorial.update(feedback)
    local context=feedback.context;local state=context.state;local t=state.tutorial
    if not t or not t.enabled or t.finished then return end
    local before=0;for _ in pairs(t.seen) do before=before+1 end
    local scene,travel=observe(context,t)
    local after=0;for _ in pairs(t.seen) do after=after+1 end
    if after~=before then feedback.dirty=true end
    local step=Tutorial.steps[t.step]
    while step and t.seen[step.id] do
        t.step=t.step+1;feedback.dirty=true;step=Tutorial.steps[t.step]
        -- Retire the completed popup instead of holding the next instruction
        -- behind a lesson the player has already performed.
        for i=#feedback.notices,1,-1 do
            if feedback.notices[i].kind=='tutorial' then table.remove(feedback.notices,i) end
        end
    end
    if not step then
        t.finished=true;feedback.dirty=true
        feedback:enqueue('tutorial','The basics are yours','Keep your jobs moving through the shop.',
            'You have followed a job through the shop, explored town, used the motorcycle and your apartment, and closed for a weekend.\n\nKeep an eye on business hours, deadlines, supplies, household needs, and your finances. Your tutorial lessons remain under NOTICES > TUTORIAL for reference.','tutorial:complete-v2')
    elseif feedback.tutorialStep~=t.step then
        feedback.tutorialStep=t.step
        feedback:enqueue('tutorial',('LESSON %d / %d: %s'):format(t.step,#Tutorial.steps,step.title),
            step.detail,step.body,'tutorial:'..step.id)
    end
    -- Teach travel when the player explores early, even while a production
    -- lesson is waiting for a real job or shipment. Never advance someone
    -- else's local tutorial from a multiplayer peer's activity.
    local contextual=scene=='commute' and (not t.seen.map and 'map'
        or not t.seen.motorcycle and not travel.mapOpen and 'motorcycle')
        or scene=='home' and not t.seen.homecare and 'homecare'
    if contextual and not require('src.notifications').findKey(state,'tutorial:visited:'..contextual) then
        for _,s in ipairs(Tutorial.steps) do if s.id==contextual then
            feedback:enqueue('tutorial',s.title,s.detail,s.body,'tutorial:visited:'..contextual)
            break
        end end
    end
end
return Tutorial
