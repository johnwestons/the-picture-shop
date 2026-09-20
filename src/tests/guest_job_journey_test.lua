local Session = require("src.net.session")
local Protocol = require("src.net.protocol")
local Harness = require("src.tests.support.network_impairment_harness")
local Remote = require("src.screens.workshop_remote_screen")
local Projection = require("src.screens.gui_projection")
local Schema = require("src.save_schema")
local Codec = require("src.net.codec")
local Test = {}

local function replace(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
end
local function player()
    return {x=100,y=100,velocityX=0,velocityY=0,intentX=0,intentY=0,moving=false,
        facing=1,animationDistance=0,character="rabbit-worker"}
end

local function runJourney(context, check, printing)
    local report = check
    check = function(name, passed, detail)
        if printing then name=name:gsub("guest_journey_", "guest_print_journey_"):gsub("replacement", "stock") end
        return report(name, passed, detail)
    end
    -- App authority callbacks deliberately use the isolated smoke application's
    -- actual state. Restore it even when an assertion fails; never use a player slot.
    local state, original = context.state, Projection.copy(context.state)
    local assets, previousPack = context.assets, context.assets.activePack
    local originalClock = love.timer.getTime
    local host, client, network, authority
    local ok, failure = xpcall(function()
        assert(love.filesystem.getIdentity() == "the-picture-shop-smoke", "Journey requires isolated smoke identity")
        replace(state, context.State.new())
        state.activeSlot, state.screen, state.money = nil, "world", 10000
        if printing then
            state.money = 50000
            assert(context.machineFleet.buy(state,"dealer",3))
            for _, item in ipairs({"raw_press_plates","negative_film","plate_adhesive","plate_chemistry",
                "black_ink","color_ink","tympan_sheets","press_wash"}) do state.inventory.stock[item]=4 end
        end
        local startingCash = state.money
        context.world.load()
        context.machine.reset(state)
        context.wrapper.reset(state)
        authority = context.createWorkshopAuthority()
        local guest = context.State.new()
        network = Harness.new({maxClients=1,classify=function(bytes)
            local envelope = Protocol.decode(bytes)
            return envelope and envelope.type or "invalid"
        end})
        host = Session.new({transportFactory=network.factory})
        local hp, gp, target = player(), player(), {x=100,y=100}
        local results, errors, readyCount = {}, {}, 0
        local hc = {
            localPlayer=hp,resolveGuestSpawn=function() return target.x,target.y end,
            -- Walking and staging are fixture operations, not teleport commands
            -- sent by a guest. Every workstation still checks the host position.
            moveRemote=function(p) p.x,p.y=target.x,target.y end,
            touchWorkshop=function(p) authority:touchPlayer(p) end,
            updateWorkshop=function() authority:update({state=state}) end,
            getShopSnapshot=function() return {state=Schema.snapshot(state),player={x=100,y=100,character=hp.character}} end,
            getCutterSnapshot=function() return {resourceRevision=authority:resourceRevision("cutter"),view=context.machine.networkView(state,true)} end,
            getWindmillSnapshot=function() return {resourceRevision=authority:resourceRevision("windmill"),
                view=context.windmillLiveNetworkView()} end,
            getWorkshopSnapshot=function() return {resources=authority:snapshot(),wrapper=context.wrapperNetworkView()} end,
        }
        hc.performWorkshop=function(p,operation,payload)
            if operation=="workshop_acquire" then
                return authority:acquire(p,{requestId=payload.requestId,resourceId=payload.resourceId},{state=state})
            elseif operation=="workshop_release" then
                return authority:release(p,{requestId=payload.requestId,resourceId=payload.resourceId,
                    leaseId=payload.leaseId,reason=payload.reason},{state=state})
            end
            local args={}
            for _,field in ipairs({"officeIntent","callId","jobId","palletId","itemIndex","programIndex","gaugeCentiInch","clamp","barrierClear",
                "plateId","setupTask","setupAction"}) do
                args[field]=payload[field]
            end
            local result=authority:command(p,{requestId=payload.commandId,resourceId=payload.resourceId,
                leaseId=payload.leaseId,action=payload.action,args=args,expectedRevision=payload.expectedRevision},{state=state})
            return result
        end
        local gc={localPlayer=gp,inputX=0,inputY=0}
        local function receive()
            client:update(0,gc)
            for _,event in ipairs(client:drainEvents()) do
                if event.type=="ready" then
                    assert(context.State.applySharedSnapshot(guest,event.state))
                    readyCount=readyCount+1
                elseif event.type=="shop_state" then assert(context.State.applySharedUpdate(guest,event.state))
                elseif event.type=="workshop_grant" then
                    assert(event.granted,event.message)
                    event.useHostLayout=true
                    Remote.enter(event,guest)
                    assets.activatePack(Remote.requiredAssetPack() or previousPack)
                elseif event.type=="workshop_result" then
                    results[#results+1]=event
                    Remote.applyResult(event)
                elseif event.type=="cutter_state" then Remote.applyCutterSnapshot(event)
                elseif event.type=="windmill_state" then Remote.applyWindmillSnapshot(event)
                elseif event.type=="workshop_snapshot" then Remote.applySnapshot(event)
                elseif event.type=="disconnected" or event.type=="workshop_lost" then Remote.clear(); guest.screen="world"
                elseif event.type=="error" then errors[#errors+1]=event.message end
            end
        end
        local function pump(dt)
            host:update(dt or 0,hc)
            for _,event in ipairs(host:drainEvents()) do
                if event.type=="player_left" then authority:cleanupPlayer({id=event.playerId},"disconnected",{state=state})
                elseif event.type=="error" then errors[#errors+1]=event.message end
            end
            receive()
        end
        local function sync()
            host:markShopDirty(true)
            pump(0.3)
        end
        assert(host:startHost({name="Journey Host",character=hp.character,addressOptions={socket={dns={
            gethostname=function() return "journey-host" end,getaddrinfo=function() return {{addr="192.168.1.94"}} end}}}}))
        host.sessionId="guest-job-journey"
        local function connect()
            client=Session.new({transportFactory=network.factory})
            assert(client:startClient("192.168.1.94:22122",{name="Journey Guest",character=gp.character}))
            client.clientNonce="journey-guest-"..(readyCount+1)
            client:update(0,gc); pump(); pump(0.1)
            assert(client.ready,"Guest did not connect")
        end
        connect()
        local function release()
            if client:workshopInfo() then assert(client:releaseWorkshop("closed")); pump() end
            Remote.clear(); guest.screen="world"
        end
        local function acquire(resource)
            release()
            if resource=="office_computer" then target=context.config.interactables.computer
            elseif resource=="cutter" then target=state.cutter
            elseif resource=="skid_wrapper" then target=state.wrapper
            elseif resource=="windmill" then target=state.windmill
            elseif resource=="truck" then target=assert(context.world.truck:getInteraction()) end
            assert(client:requestWorkshopAcquire(resource)); pump()
            assert(Remote.isOpen() and Remote.resourceId==resource,"Missing shared guest GUI")
        end
        local function send(action,args) return client:requestWorkshopCommand(action,args) end
        local function click(x,y) return Remote.mousepressed(guest,x,y,1,send) end
        local function key(name) return Remote.keypressed(name,guest,send) end
        local function confirmed(label,operation,duplicate)
            local count=#results
            if duplicate then assert(network:duplicateNext("client_to_host",1,1,true)) end
            operation(); pump()
            local result=results[#results]
            check("guest_journey_"..label,#results>count and result.accepted,
                (result and (result.code..": "..tostring(result.message)) or "No command result").." "..table.concat(errors,"; ")
                    .." GUI="..tostring(Remote.status).." waiting="..tostring(Remote.waiting))
            sync()
            return result
        end
        local function tab(name)
            click(Remote.sharedComputer.dropdownCenter()); click(Remote.sharedComputer.tabCenter(name))
        end
        local function advanceMachine(dt)
            context.machine.update(dt,state)
            context.wrapper.update(dt,state)
            sync(); Remote.update(0.1)
        end
        local function render(label)
            local canvas=love.graphics.newCanvas(960,680)
            love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0,0,0,1)
            local rendered,err=pcall(Remote.draw,guest,nil,nil,assets)
            love.graphics.pop(); canvas:release()
            check("guest_journey_render_"..label,rendered,err)
        end
        local offer=assert(context.jobs.createOffer({id=printing and "JOB-GUEST-PRINT" or "JOB-GUEST-JOURNEY",company="Journey Print Co.",
            sourceSize=printing and {width=10,height=15} or {width=20,height=16},
            finishedSize=printing and {width=5,height=7} or {width=10,height=8},
            sheetCounts={500},packaging="flat",artworkKey="flower",
            details={stockDescription="100 lb uncoated cover"},
            press=printing and {colors=2,coverage=0.35,artworkSize={width=4.25,height=6.25},
                colorSequence={"Black","Red"},requestedCopies={450}} or nil}))
        assert(context.jobService.requestEstimateDetails(state,offer,100))
        -- Advance only the host's business clock; never accept an estimate directly.
        local function deliverEmail()
            local pending=assert(state.clientEmails.pending[1])
            local now=context.businessCalendar.absoluteHours(state)
            context.businessCalendar.update(state,(pending.readyAtHours-now)/24*context.config.businessCalendar.secondsPerDay+0.01)
            context.jobService.updateClientEmails(state)
            sync()
        end
        deliverEmail()
        acquire("office_computer"); tab("estimating")
        click(Remote.sharedComputer.rowCenter(1)); click(Remote.sharedComputer.textInputCenter("quote"))
        Remote.textinput(tostring(offer.quote.totalPrice))
        render("written_estimate")
        confirmed("typed_quote_sent_once",function()
            local x,y=Remote.sharedComputer.emailButtonCenter("accept")
            click(x,y); click(x,y)
        end,true)
        check("guest_journey_no_instant_award",#state.jobs.active==0 and #guest.jobs.active==0 and #state.clientEmails.pending==1)
        release(); deliverEmail()
        local job=assert(state.jobs.active[1]); local originalPallet=job.pallets[1]
        local invoicePrice=job.quote.totalPrice
        check("guest_journey_host_acceptance_reaches_guest",#guest.jobs.active==1 and guest.jobs.active[1].id==job.id
            and state.accountsReceivable==invoicePrice and guest.activeSlot==nil)
        local function truck(mode)
            release()
            -- Dock motion is covered separately. Here the real cargo authority
            -- receives the same parked/open manifest the world scheduler produces.
            context.world.truck.mode=mode; context.world.truck.jobId=job.id
            context.world.truck.state="cargo_open"; context.world.truck.backingProgress=1; context.world.truck.cargoProgress=1
            context.world._state=state
            acquire("truck")
        end
        local function unload(label)
            truck("delivery")
            confirmed(label,function()
                local x,y=context.truckInventoryScreen.unloadButtonCenter(1); click(x,y); click(x,y)
            end,true)
            release(); context.world.truck.state="absent"
        end
        unload("inbound_stock_unloaded_once")
        local function stage(pallet,x,y)
            assert(context.PalletState.transition(state,pallet,"on_pallet_jack"))
            assert(context.PalletState.transition(state,pallet,"warehouse",{world={x=x,y=y,fromX=x,fromY=y,
                direction="northwest",rotation=1,spawnProgress=1}}))
            sync()
        end
        local function load(pallet,label)
            stage(pallet,context.CutterZones.inputAnchor(state,context.config.cutterPlacement))
            acquire("cutter"); key("l")
            confirmed(label,function() key("return") end)
            advanceMachine(context.machine.transferTime+0.05)
        end
        load(originalPallet,"load_customer_stock")
        local replacement, claim = originalPallet, 0
        if not printing then
            confirmed("rotate_first_lift",function() key("q") end)
            click(Remote.sharedMachine.screen.gaugeInputCenter()); Remote.textinput("1")
            confirmed("wrong_size_allowed",function() key("return") end)
            click(500,200) -- Leave the numeric field before using machine shortcuts.
            confirmed("position_wrong_size",function() key("p") end); advanceMachine(context.machine.transferTime+0.05)
            confirmed("clamp_wrong_size",function() key("space") end)
            confirmed("wrong_cut_started_once",function() key("j"); key("j") end,true)
            advanceMachine(context.machine.cycleTime+0.05)
            replacement=assert(job.pallets[2]); claim=state.bills.balance
            check("guest_journey_spoil_claim_and_exact_replacement",originalPallet.damagedSheets==500 and replacement.initialSheets==500
                and replacement.replacementFor==originalPallet.id and #job.pallets==2 and claim>0 and state.reputation.score<0)
            check("guest_journey_spoil_converges_on_guest",guest.bills.balance==claim and guest.reputation.score==state.reputation.score
                and #guest.jobs.active[1].pallets==2 and Remote.view.paper.offSpec)
            render("spoiled_stock")
            confirmed("discard_ruined_stock",function() key("u") end)
            unload("replacement_unloaded_once")
            load(replacement,"load_replacement_stock")
        end
        for cut=1,4 do
            confirmed("rotate_replacement_"..cut,function() key("q") end)
            local gauge=replacement.paper.cuts[cut].gauge
            click(Remote.sharedMachine.screen.gaugeInputCenter()); Remote.textinput(tostring(gauge))
            confirmed("gauge_replacement_"..cut,function() key("return") end)
            click(500,200)
            confirmed("position_replacement_"..cut,function() key("p") end)
            advanceMachine(context.machine.transferTime+0.05)
            confirmed("clamp_replacement_"..cut,function() key("space") end)
            if cut==2 and not printing then
                local oldLease=Remote.leaseId
                assert(network:delayNext("host_to_client",1,5))
                key("j"); key("j"); host:update(0,hc)
                context.machine.update(0.2,state)
                assert(network:disconnectPeer(1,0))
                pump(); Remote.clear(); client:stop("interrupted")
                -- One already-authorized blade stroke may finish on the host;
                -- a disconnected GUI may not issue or complete another stroke.
                advanceMachine(context.machine.cycleTime+0.1)
                check("guest_journey_disconnect_does_not_repeat_cut",#replacement.paper.history==cut)
                connect()
                check("guest_journey_reconnect_has_no_old_control",not client:workshopInfo() and guest.activeSlot==nil)
                acquire("cutter")
                network:advanceSteps(8); pump()
                check("guest_journey_reconnect_gets_fresh_lease_and_paper",Remote.leaseId~=oldLease
                    and Remote.view.paper.activeCut==cut+1 and guest.jobs.active[1].pallets[2].paper.activeCut==cut+1)
            else
                confirmed("cut_replacement_"..cut,function() key("k"); key("k") end,true)
                advanceMachine(context.machine.cycleTime+0.05)
            end
        end
        check("guest_journey_replacement_finishes_exactly_one_lift",replacement.completedLifts==1 and replacement.finishedSheets==replacement.initialSheets
            and replacement.remainingSheets==0 and #replacement.paper.history==4 and state.bills.balance==claim)
        confirmed("return_finished_paper",function() key("u") end)
        advanceMachine(context.machine.transferTime+0.05)
        check("guest_journey_unloaded_cutter_drops_old_paper",Remote.view.step=="finished" and Remote.view.paper==nil)
        release()
        if printing then
            require("src.tests.support.guest_print_production").run(context, check, {
                state=state,guest=guest,job=job,pallet=replacement,remote=Remote,network=network,
                acquire=acquire,release=release,stage=stage,click=click,key=key,confirmed=confirmed,
                sync=sync,pump=pump,connect=connect,render=render,
                disconnect=function()
                    assert(network:disconnectPeer(1,0)); pump(); client:stop("print_interrupted")
                    Remote.clear()
                end,
            })
        end
        stage(replacement,state.wrapper.x-60,state.wrapper.y)
        context.wrapper.reset(state)
        acquire("skid_wrapper"); render("wrapper")
        local wrapBefore=state.inventory.plasticWrapUses
        confirmed("wrap_started_once",function() click(760,547); click(760,547) end,true)
        advanceMachine(context.wrapper.cycleTime+0.05)
        check("guest_journey_wrapped_stock_converges",replacement.wrapped and guest.jobs.active[1].pallets[printing and 1 or 2].wrapped
            and state.inventory.plasticWrapUses==wrapBefore-1 and guest.inventory.plasticWrapUses==state.inventory.plasticWrapUses)
        acquire("office_computer")
        if not printing then
            tab("bills")
            confirmed("spoil_bill_paid_once",function()
                local x,y=Remote.sharedComputer.payBillsCenter(); click(x,y); click(x,y)
            end,true)
        end
        tab("active"); click(Remote.sharedComputer.rowCenter(1))
        confirmed("pickup_requested_once",function()
            local x,y=Remote.sharedComputer.completeCenter(); click(x,y); click(x,y)
        end,true)
        release(); context.world.load()
        context.world.update(context.config.truck.scheduleDelay+0.1,0,0,assets,state)
        context.world.update(context.config.loadingBay.duration+0.1,0,0,assets,state)
        context.world.update(context.config.truck.backingDuration+0.1,0,0,assets,state)
        assert(context.world.toggleTruckCargoDoor(state))
        context.world.update(context.config.truck.cargoDuration+0.1,0,0,assets,state)
        sync(); acquire("truck")
        confirmed("finished_pickup_loaded_once",function()
            local x,y=context.truckInventoryScreen.unloadButtonCenter(1); click(x,y); click(x,y)
        end,true)
        local moneyBefore=state.money
        confirmed("loaded_truck_released",function() click(context.truckInventoryScreen.closeDoorCenter()) end)
        release()
        context.world.update(context.config.truck.cargoDuration+0.1,0,0,assets,state)
        context.world.update(context.config.truck.backingDuration+0.1,0,0,assets,state)
        sync()
        check("guest_journey_completed_job_paid_once",#state.jobs.active==0 and #state.jobs.completed==1
            and state.money==moneyBefore+invoicePrice and state.money==startingCash-claim+invoicePrice
            and state.accountsReceivable==0)
        check("guest_journey_final_host_guest_agree",#guest.jobs.completed==1 and #guest.jobs.active==0
            and guest.money==state.money and guest.bills.balance==0 and guest.accountsReceivable==0
            and guest.reputation.score==state.reputation.score and guest.activeSlot==nil)
        local limits={maxBytes=512*1024,maxDepth=32,maxEntries=32768,maxStringBytes=128*1024}
        local bytes=assert(Codec.encode(Schema.snapshot(state),limits))
        local reopened=context.State.new()
        assert(context.State.applyLocalSave(reopened,{state=assert(Codec.decode(bytes,limits)),slot=3}))
        check("guest_journey_offline_round_trip_preserves_outcome",#reopened.jobs.completed==1 and reopened.money==state.money
            and reopened.bills.balance==0 and (printing and reopened.jobs.completed[1].pallets[1].press.completedColors==2
                or not printing and reopened.jobs.completed[1].spoiledSheets==500)
            and not reopened.palletJack.operating)
        check("guest_journey_no_network_errors",#errors==0,table.concat(errors,"; "))
    end,function(err) return debug.traceback(type(err)=="table" and (Codec.encode(err) or tostring(err)) or tostring(err)) end)
    love.timer.getTime = originalClock
    if client then client:stop("journey_complete") end
    if authority then authority:cleanupPlayer({id=2},"disconnected",{state=state}) end
    if host then host:stop("journey_complete") end
    if network then network:dispose() end
    Remote.clear(); replace(state,original)
    context.machine.reset(state); context.wrapper.reset(state); context.world.load(); assets.activatePack(previousPack)
    if not ok then error(failure) end
end
function Test.run(context, check)
    runJourney(context, check, false)
    runJourney(context, check, true)
end
return Test
