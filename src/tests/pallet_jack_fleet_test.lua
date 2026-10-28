local State=require("src.state")
local Schema=require("src.save_schema")
local Fleet=require("src.pallet_jack_fleet")
local Jack=require("src.pallet_jack")
local Transport=require("src.employee_pallet_jack")
local Employees=require("src.employees")
local Procurement=require("src.procurement")
local Jobs=require("src.jobs")
local Machines=require("src.machine_fleet")
local Schedule=require("src.employee_schedule")
local Pallets=require("src.pallet_state")
local Config=require("src.config")
local Test={}

local function capture(name,draw)
    local directory=os.getenv("PICTURE_SHOP_PALLET_FLEET_CAPTURE_DIR")
    if not directory then return end
    local canvas=love.graphics.newCanvas(Config.baseWidth,Config.baseHeight)
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.06,.07,.09,1)
    draw();love.graphics.pop()
    local pixels=canvas:newImageData();local png=pixels:encode("png")
    local file=assert(io.open(directory.."/"..name..".png","wb"))
    file:write(png:getString());file:close();png:release();pixels:release();canvas:release()
end

local function hire(state)
    local a=assert(Employees.createApplicant(state,0))
    a.shiftPreference="flexible"
    Employees.requestResume(state,a.id,0);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=math.max(2400,a.requestedWage),days=31,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=state.employment.staff[#state.employment.staff]
    w.visible,w.clockedIn,w.phase=true,true,"idle"
    w.x,w.y,w.cutterSkill,w.pressSkill,w.wrappingSkill=600,560,100,100,100
    return w
end

local function job(state,id,x,y)
    local j=assert(Jobs.createOffer({id=id,company="Jack fleet QA",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(j);state.jobs.active[#state.jobs.active+1]=j
    j.status,j.delivery="in_production",{status="received"}
    local p=j.pallets[1]
    p.location,p.status="warehouse","raw"
    p.world={x=x,y=y,direction="northwest",spawnProgress=1}
    return j,p
end

local function purchases(context,check)
    local s=State.new();s.money=2000
    local category,item=4,3
    local okay,a=Procurement.buy(s,category,item,"salesman")
    local online,b=Procurement.buyRetail(s,category,item)
    check("jack_fleet_both_catalogs_charge_and_order",okay and online and s.money==1225
        and a.channel=="salesman" and b.channel=="computer" and #s.extraPalletJacks==0)
    local lanes={{x=600,y=550},{x=720,y=550}}
    local received=Procurement.unload(s,a.id,a.pallets[1].id,lanes)
    local second=Procurement.unload(s,b.id,b.pallets[1].id,lanes)
    check("jack_fleet_deliveries_create_separate_vehicles",received and second and #Fleet.all(s)==3
        and s.extraPalletJacks[1].x~=s.extraPalletJacks[2].x and not s.inventory.stock.pallet_jack
        and a.pallets[1].location=="none" and b.pallets[1].location=="none")
    check("jack_fleet_delivery_replay_cannot_duplicate",not Procurement.unload(s,a.id,a.pallets[1].id,lanes)
        and #Fleet.all(s)==3)
    local saved=Schema.snapshot(s)
    local loaded=State.new()
    check("jack_fleet_purchases_survive_save_and_reload",saved and Schema.validState(saved)
        and State.applySave(loaded,{state=saved,slot=1}) and #Fleet.all(loaded)==3)
    local poor=State.new();local money=poor.money
    check("jack_fleet_insufficient_cash_creates_no_order",not Procurement.buyRetail(poor,category,item)
        and poor.money==money and #poor.procurement.orders==0 and #Fleet.all(poor)==1)
    local legacy=State.new();legacy.extraPalletJacks=nil
    check("jack_fleet_legacy_single_jack_save_loads",Schema.snapshot(legacy)~=nil)
    local chosen=loaded.extraPalletJacks[2]
    Fleet.selectPlayer(loaded,{x=chosen.x,y=chosen.y,sceneId="warehouse"})
    check("jack_fleet_player_can_mount_a_purchased_jack",loaded.palletJack==chosen
        and Jack.mount(loaded,Config.palletJack,1) and #Fleet.all(loaded)==3 and Fleet.validate(loaded))
    local ui=State.new();ui.money=2000;ui.vendorCategory=4
    local vendor=require("src.screens.vendor_screen")
    local bought=vendor.mousepressed(ui,764,320,1)
    local computer=require("src.screens.computer_screen").new()
    computer.tab,computer.wwwSite="www",4
    local x,y=computer.retailButtonCenter(3)
    local added=computer.mousepressed(ui,x,y,1)
    x,y=computer.cartButtonCenter();computer.mousepressed(ui,x,y,1)
    x,y=computer.cartCheckoutCenter()
    local checked=computer.mousepressed(ui,x,y,1)
    check("jack_fleet_salesman_and_critternet_purchase_buttons_work",bought and bought.action=="purchased"
        and bought.order.item=="pallet_jack" and added and added.action=="cart_item_added"
        and checked and checked.action=="cart_checked_out" and checked.result.orders[1].item=="pallet_jack")
    capture("salesman",function() vendor.draw(ui,context.assets) end)
    computer.cartOpen=false
    capture("critternet",function() computer.draw(ui,nil,nil,context.assets) end)
end

local function network(context,check,state,saved,extra,employee)
    local Protocol=require("src.net.protocol")
    local Session=require("src.net.session")
    local unit=Fleet.snapshots(state)[1]
    local packet,reason=Protocol.encode("extra_pallet_jack_snapshot",{
        sessionId="jack-fleet-qa",serverTick=2,jackId=unit.id,jack=unit.jack})
    check("jack_fleet_extra_realtime_packet_fits_mtu",packet and #packet<=Protocol.MAX_PACKET_BYTES,reason)
    local client=Session.new();client.mode,client.ready,client.sessionId="client",true,"jack-fleet-qa"
    local decoded=assert(Protocol.decode(packet))
    client:_handleClientEnvelope(decoded);client:_handleClientEnvelope(decoded)
    local events=client:drainEvents()
    local guest=State.new();assert(State.applySharedSnapshot(guest,saved))
    check("jack_fleet_guest_applies_extra_vehicle_by_stable_id",#events==1 and events[1].type=="extra_pallet_jack_state"
        and Fleet.applySnapshot(guest,events[1].jackId,events[1].jack)
        and guest.extraPalletJacks[1].operatorEmployeeId==employee.id
        and guest.extraPalletJacks[1].x==extra.x and Pallets.validate(guest))
    local main=context.world.networkPalletJackSnapshot(state)
    check("jack_fleet_primary_snapshot_keeps_other_jacks_load",context.world.applyNetworkPalletJackSnapshot(guest,
        main,context.world.networkMachinePoseSnapshot(state),state.palletJack.id) and Pallets.validate(guest))
    check("jack_fleet_durable_update_keeps_live_extra_operator",State.applySharedUpdate(guest,Schema.snapshot(state))
        and guest.extraPalletJacks[1].operating and guest.extraPalletJacks[1].operatorEmployeeId==employee.id
        and guest.extraPalletJacks[1].carriedPalletId==extra.carriedPalletId)
    check("jack_fleet_unknown_realtime_vehicle_waits_for_delivery",not Fleet.applySnapshot(guest,"UNDELIVERED-JACK",unit.jack))
    local host=Session.new();host.mode,host.sessionId="host","jack-fleet-qa";host.idToPeer[2]="guest"
    local sent={}
    host._broadcastJoined=function(_,kind,payload)
        assert(Protocol.encode(kind,payload));sent[kind]=payload;return true
    end
    host:_updateHost(.1,{getExtraPalletJackSnapshots=function() return Fleet.snapshots(state) end})
    check("jack_fleet_host_broadcasts_extra_vehicle",sent.extra_pallet_jack_snapshot
        and sent.extra_pallet_jack_snapshot.jackId==extra.id)
    unit.jack.operatorPlayerId=2
    check("jack_fleet_extra_stream_rejects_dual_operator",not Protocol.encode("extra_pallet_jack_snapshot",{
        sessionId="jack-fleet-qa",serverTick=3,jackId=unit.id,jack=unit.jack}))
end

local function concurrent(context,check)
    local s=State.new();s.money=100000
    local a,b=hire(s),hire(s)
    a.x,a.y,b.x,b.y=380,600,730,600
    local primary=s.palletJack
    primary.x,primary.y=380,550
    local extra=Fleet.add(s,"FLEET-QA-JACK",{x=730,y=550})
    local ja,pa=job(s,"JOB-FLEET-A",330,550)
    local jb,pb=job(s,"JOB-FLEET-B",780,550)
    local cutter=Machines.installedUnits(s,"polar_115")[1]
    assert(Machines.buy(s,"dealer",1))
    check("jack_fleet_schedule_resolves_second_worker_while_first_drives",
        Jack.mountEmployee(s,Config.palletJack,a.id)
        and select(2,Schedule.resolve(s,b,{jobId=jb.id,machineId=cutter.id}))~=nil)
    assert(Jack.mountEmployee(Fleet.view(s,extra),Config.palletJack,b.id))
    a.assignment={jobId=ja.id,palletId=pa.id,machineId=cutter.id,machineModel="polar_115"}
    b.assignment={jobId=jb.id,palletId=pb.id,machineId=cutter.id,machineModel="polar_115"}
    assert(Jack.lift(s,Config.palletJack,pa.id))
    assert(Jack.lift(Fleet.view(s,extra),Config.palletJack,pb.id))
    check("jack_fleet_two_employees_hold_distinct_loads",Transport.owns(s,a) and Transport.owns(s,b)
        and primary.carriedPalletId==pa.id and extra.carriedPalletId==pb.id and Pallets.validate(s))
    check("jack_fleet_employee_cannot_mount_two_jacks",not Jack.mountEmployee(s,Config.palletJack,b.id))
    local snapshot=Schema.snapshot(s)
    local restored=State.new()
    check("jack_fleet_loaded_save_parks_both_without_losing_cargo",snapshot and Schema.validState(snapshot)
        and not snapshot.palletJack.operating and not snapshot.extraPalletJacks[1].operating
        and State.applySave(restored,{state=snapshot,slot=1}) and Pallets.validate(restored)
        and restored.palletJack.carriedPalletId==pa.id and restored.extraPalletJacks[1].carriedPalletId==pb.id)
    local written=context.save.save(3,s,context.world.snapshot())
    local disk=written and context.save.load(3)
    check("jack_fleet_two_loaded_jacks_survive_disk_save",disk and disk.state.palletJack.carriedPalletId==pa.id
        and disk.state.extraPalletJacks[1].carriedPalletId==pb.id and Schema.validState(disk.state))
    context.save.delete(3)
    local resume=State.new()
    Fleet.add(resume,"RESUME-QA-JACK",{x=800,y=550}).carriedPalletId=pb.id
    check("jack_fleet_resume_prefers_parked_load_over_nearer_empty_jack",
        Fleet.employee(resume,{id=b.id,x=resume.palletJack.x,y=resume.palletJack.y},pb.id)==resume.extraPalletJacks[1])
    local invalid=Schema.copy(snapshot)
    invalid.extraPalletJacks[1].carriedPalletId=pa.id
    check("jack_fleet_duplicate_cargo_is_rejected",not Schema.snapshot(invalid) and not State.applySave(State.new(),{state=invalid,slot=1}))
    local ctx=context.world.employeeContext(s,context.assets)
    local startA,startB=primary.x,extra.x
    for _=1,12 do
        Transport.move(s,a,{x=startA+30,y=550},.1,ctx)
        Transport.move(s,b,{x=startB-30,y=550},.1,ctx)
    end
    check("jack_fleet_both_employees_move_at_same_time",primary.x>startA+10 and extra.x<startB-10
        and pa.world.x==primary.x and pb.world.x==extra.x and Pallets.validate(s),
        string.format("A %.1f -> %.1f; B %.1f -> %.1f",startA,primary.x,startB,extra.x))
    local nav=ctx.jackNavigation(a,pa.id)
    check("jack_fleet_routes_collide_with_other_loaded_jack",not context.Navigation.isWalkable(nav.assets,
        extra.x,extra.y,nav.obstacles()))
    check("jack_fleet_two_loaded_jacks_render",pcall(context.world.draw,context.assets,context.characterAssets,s))
    capture("two-employees",function() context.world.draw(context.assets,context.characterAssets,s) end)
    network(context,check,s,snapshot,extra,b)
    local held=extra.carriedPalletId
    Transport.release(s,a,{})
    check("jack_fleet_releasing_one_does_not_release_the_other",not primary.operating
        and extra.operating and extra.operatorEmployeeId==b.id and extra.carriedPalletId==held)
    local x,y=primary.x,primary.y
    Fleet.selectPlayer(s,{x=x,y=y,sceneId="warehouse"})
    check("jack_fleet_player_can_use_free_jack_beside_working_employee",Jack.mount(s,Config.palletJack,1)
        and extra.operatorEmployeeId==b.id)
end

local function routes(context,check)
    local s=State.new();s.money=100000
    local a,b=hire(s),hire(s)
    a.x,a.y,b.x,b.y=380,600,730,600
    s.palletJack.x,s.palletJack.y=380,550
    Fleet.add(s,"ROUTE-QA-JACK",{x=730,y=550})
    local ja,pa=job(s,"JOB-FLEET-ROUTE-A",330,550)
    local jb,pb=job(s,"JOB-FLEET-ROUTE-B",780,550)
    local first=Machines.installedUnits(s,"polar_115")[1]
    local _,second=Machines.buy(s,"dealer",1)
    a.assignment={jobId=ja.id,palletId=pa.id,machineId=first.id,machineModel="polar_115"}
    b.assignment={jobId=jb.id,palletId=pb.id,machineId=second.id,machineModel="polar_115"}
    a.reserved,b.reserved=true,true
    local ctx=context.world.employeeContext(s,context.assets)
    ctx.move=function(actor,goal,dt) return require("src.employee_ai").move(actor,goal,dt,ctx) end
    local movedA,movedB,deliveredA,deliveredB,overlap=false,false,false,false,false
    for _=1,3000 do
        if not deliveredA then
            Transport.update(s,a,first,pa,"cutter",.1,ctx)
            movedA=movedA or pa.location=="on_pallet_jack"
            deliveredA=movedA and pa.location=="warehouse"
        elseif Transport.owns(s,a) then Transport.park(s,a,.1,ctx) end
        if not deliveredB then
            Transport.update(s,b,second,pb,"cutter",.1,ctx)
            movedB=movedB or pb.location=="on_pallet_jack"
            deliveredB=movedB and pb.location=="warehouse"
        elseif Transport.owns(s,b) then Transport.park(s,b,.1,ctx) end
        overlap=overlap or (Transport.owns(s,a) and Transport.owns(s,b))
        if deliveredA and deliveredB and not Transport.owns(s,a) and not Transport.owns(s,b) then break end
    end
    local view=setmetatable({cutter=second.world},{__index=s})
    check("jack_fleet_two_workers_pick_up_deliver_and_park",movedA and movedB and deliveredA and deliveredB and overlap
        and not Transport.owns(s,a) and not Transport.owns(s,b) and Pallets.validate(s)
        and context.CutterZones.inInputZone(s,pa,Config.cutterPlacement)
        and context.CutterZones.inInputZone(view,pb,Config.cutterPlacement),
        tostring(a.activity).." / "..tostring(b.activity).." moved="..tostring(movedA).."/"..tostring(movedB))
end

function Test.run(context,check)
    purchases(context,check)
    local world=context.world
    local oldOptions,oldX,oldY=world._employeeOptions,world.player.x,world.player.y
    world.configureEmployees({players=function() return {} end})
    world.player.x,world.player.y=930,640
    concurrent(context,check)
    routes(context,check)
    world.player.x,world.player.y=oldX,oldY
    world.configureEmployees(oldOptions)
end

return Test
