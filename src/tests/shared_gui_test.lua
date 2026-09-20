local Remote = require("src.screens.workshop_remote_screen")
local Computer = require("src.screens.computer_screen")
local MachineScreen = require("src.screens.machine_screen")
local PressScreen = require("src.screens.press_screen")
local Projection = require("src.screens.gui_projection")
local Games = require("src.press_setup_games")
local SetupView = require("src.press_setup_view")
local Protocol = require("src.net.protocol")
local Codec = require("src.net.codec")
local Jobs = require("src.jobs")
local Fleet = require("src.machine_fleet")
local Phone = require("src.work_phone")
local Vendor = require("src.vendor_authority")
local Test = {}

function Test.run(context,check)
    local state=context.State.new()
    state.money=1000000
    state.inventory.stock.maintenance_kit=3
    Fleet.buy(state,"dealer",3)
    local job=Jobs.createOffer({id="GUI-001",company="Critter Print Co.",
        sourceSize={width=10,height=15},finishedSize={width=5,height=7},sheetCounts={1050},
        packaging="flat",artworkKey="flower",press={colors=1,coverage=0.35,
        artworkSize={width=4.25,height=6.25},colorSequence={"Black"},requestedCopies={1000}},
        details={stockDescription="80 lb uncoated cover"}})
    Jobs.accept(job)
    state.jobs.active={job}
    local pallet=job.pallets[1]
    local sent={}
    local function send(action,args) sent[#sent+1]={action=action,args=args}; return true end
    local function enter(resource,view)
        Remote.enter({resourceId=resource,leaseId="gui-parity",revision=1,view=view,
            useHostLayout=true,message="Host connected."},state)
    end
    local function click(x,y) Remote.waiting=false; Remote.safetyWaiting=false; return Remote.mousepressed(state,x,y,1,send) end
    local function last(action) return sent[#sent] and sent[#sent].action==action end
    local assets,previousPack=context.assets,context.assets.activePack
    local canvas=love.graphics.newCanvas(960,680)
    local previousTime=love.timer.getTime
    love.timer.getTime=function() return 10 end
    local function render(name,draw,save)
        love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0,0,0,1)
        local ok,err=pcall(draw or function() Remote.draw(state,nil,nil,assets) end)
        love.graphics.pop()
        check("shared_gui_renders_"..name..(ok and "" or ": "..tostring(err)),ok)
        local data=canvas:newImageData()
        if save then data:encode("png","gui-parity-"..name..".png") end
        local hash=love.data.hash("sha256",data:getString()); data:release()
        return hash
    end

    enter("office_computer",{})
    local host=Computer.new(); host.enter(Projection.copy(state))
    local money,kit=state.money,state.inventory.stock.maintenance_kit
    for _,tab in ipairs({"active","completed","deliveries","estimating","calendar","inventory","www","email","bills"}) do
        Remote.sharedComputer.tab,host.tab=tab,tab
        local remoteHash=render("office_"..tab,nil,tab=="active" or tab=="www")
        local hostState=Projection.copy(state); hostState.message=Remote.status
        local hostHash=render("host_office_"..tab,function() host.draw(hostState,nil,nil,assets) end)
        check("shared_gui_office_"..tab.."_pixel_matches_host",remoteHash==hostHash)
    end
    Remote.sharedComputer.tab="www"
    for site=1,5 do Remote.sharedComputer.wwwSite=site; render("office_site_"..site) end
    Remote.sharedComputer.wwwSite=1
    click(Remote.sharedComputer.retailButtonCenter(1))
    click(Remote.sharedComputer.cartButtonCenter())
    render("office_cart",nil,true)
    click(Remote.sharedComputer.cartCheckoutCenter())
    check("shared_gui_checkout_sends_bounded_intent_without_local_purchase",last("office_action")
        and sent[#sent].args.officeIntent.kind=="checkout" and state.money==money)
    local count=#sent
    local checkoutX,checkoutY=Remote.sharedComputer.cartCheckoutCenter()
    Remote.mousepressed(state,checkoutX,checkoutY,1,send)
    check("shared_gui_office_pending_purchase_not_repeated",#sent==count)
    Remote.sharedComputer.cartOpen=false; Remote.sharedComputer.tab="bills"
    click(Remote.sharedComputer.payBillsCenter())
    check("shared_gui_host_bill_button_routes_guest_payment",last("office_action") and sent[#sent].args.officeIntent.kind=="pay_bills")

    local cutter={runtimeRevision=1,step="loaded",phasePermille=0,loaded=true,clamp=false,
        clampPermille=0,bladePermille=0,barrierClear=true,emergencyStopped=false,gaugeCentiInch=700,
        programIndex=1,memoryCentiInch={},paper={palletId=pallet.id,orientation=0,status="uncut",activeCut=1,
        cutCount=4,activeLift=1,requiredLifts=3,remainingSheets=1050}}
    enter("cutter",cutter); assets.activatePack("cutter")
    render("cutter",nil,true)
    click(Remote.sharedMachine.screen.gaugeInputCenter())
    Remote.textinput("2"); Remote.keypressed("return",state,send)
    check("shared_gui_cutter_wrong_size_reaches_host_without_local_cut",last("set_gauge") and sent[#sent].args.gaugeCentiInch==200
        and pallet.paper.currentSize.width==10)
    Remote.waiting=false; Remote.keypressed("q",state,send)
    count=#sent; Remote.keypressed("g",state,send); Remote.keypressed("x",state,send)
    check("shared_gui_cutter_pending_blocks_repeat_but_allows_emergency",#sent==count+1 and last("emergency_stop"))
    cutter.paper=nil; cutter.loaded=false; cutter.step="idle"; cutter.candidates={}; cutter.genericSheets=1000
    enter("cutter",cutter)
    Remote.keypressed("l",state,send); render("cutter_load_menu",nil,true)
    Remote.sharedMachine.screen.loadMenu=nil
    for page=1,6 do Remote.sharedMachine.screen.helpOpen=true; Remote.sharedMachine.screen.helpStep=page; render("cutter_help_"..page) end
    Remote.sharedMachine.screen.helpOpen=false
    Remote.sharedMachine.screen.maintenanceView="hub"; render("cutter_service",nil,true)
    click(Remote.sharedMachine.screen.maintenanceTaskCenter("oil"))
    check("shared_gui_cutter_service_button_sends_host_command",last("begin_lubrication"))
    for _,step in ipairs({"lockout_disconnect","lockout_key","lockout_tag","prep_cartridge","prep_prime","lubricate","blade_bolts","blade_lift","blade_sleeve"}) do
        cutter.serviceStep=step; cutter.serviceView=1; cutter.serviceTool=1; cutter.serviceItems={}
        cutter.bladeBoltsDone=step=="blade_bolts" and 1 or 4; cutter.bladeBoltMask=step=="blade_bolts" and 8 or 15
        render("cutter_"..step,nil,step=="lubricate")
        if step=="blade_bolts" then
            check("shared_gui_blade_tracks_exact_host_bolt_not_just_count",Remote.sharedMachine.screen.bladeBolts[4] and not Remote.sharedMachine.screen.bladeBolts[1])
        end
    end

    local wrapper={step="idle",progress=0,cycleTime=3,pallets={}}
    enter("skid_wrapper",wrapper); assets.activatePack("wrapper")
    wrapper=Remote.view
    render("wrapper",nil,true)
    Remote.sharedMachine.screen.maintenanceView="wrapper_hub"; render("wrapper_service")
    wrapper.serviceStep="task"; wrapper.serviceTaskIndex=1; wrapper.servicePhase=1
    render("wrapper_task",nil,true)
    local tx,ty=Remote.sharedMachine.screen.wrapperTaskTargetCenter()
    if tx then click(tx,ty) end
    check("shared_gui_wrapper_visible_service_target_routes_host_intent",tx~=nil and last("service_target"))

    local press={runtimeRevision=1,status="setup",speed=3000,motor=false,feeder=false,impression=false,emergency=false,
        counter=0,goodSheets=0,spoilage=0,targetSheets=1000,feedStart=1050,feedRemaining=1050,proofApproved=false,
        artworkVerified=false,setupPermille={0,0,0,0,0,0},candidates=Codec.array({}),serviceStep="idle",servicePermille=0,
        plateMarkerPermille=670,jobId=job.id,palletId=pallet.id,colorIndex=1,colorCount=1}
    enter("windmill",press); assets.activatePack("press")
    press=Remote.view
    for _,tab in ipairs({"run","plates","setup","proof","maintenance","tutorial"}) do
        Remote.sharedPress.screen.tab=tab; render("press_"..tab,nil,tab=="run" or tab=="plates")
    end
    Remote.sharedPress.screen.tab="run"; click(130,365)
    check("shared_gui_press_motor_uses_host_intent",last("toggle_motor"))
    count=#sent; Remote.keypressed("f",state,send); Remote.keypressed("x",state,send)
    check("shared_gui_press_pending_blocks_repeat_but_allows_emergency",#sent==count+1 and last("emergency_stop"))
    for _,task in ipairs({"chase","packing","rollers","ink","feeder","register"}) do
        local game=Games.new(task,job)
        press.setupTask,press.setupVisual,press.setupSummary=task,SetupView.encode(game),
            task=="feeder" and Games.instruction(game) or Games.summary(game)
        Remote.sharedPress.screen.tab="setup"; render("press_setup_"..task,nil,task=="chase")
        local packet,err=Protocol.encode("workshop_grant",{sessionId="gui",requestId=1,resourceId="windmill",granted=true,
            leaseId="gui-parity",code="granted",message="Connected.",revision=1,view=press})
        check("shared_gui_press_"..task.."_display_fits_packet"..(packet and "" or ": "..tostring(err)),packet~=nil and Protocol.decode(packet)~=nil)
        click(100,596)
        check("shared_gui_press_"..task.."_animated_control_sends_intent",last("setup_action") and sent[#sent].args.setupAction==Games.controls(task)[1][1])
    end
    press.setupTask,press.setupVisual,press.setupSummary=nil,nil,nil
    press.status,press.palletId,press.jobId="idle",nil,nil
    Remote.sharedPress.screen.tab="maintenance"
    for _,step in ipairs({"lockout_disconnect","lockout_key","lockout_tag","task"}) do
        press.serviceStep=step; render("press_service_"..step)
    end
    check("shared_gui_press_setup_rejects_forged_display",SetupView.normalize("chase",{1,2,3,4})==nil
        and SetupView.normalize("feeder",{2,2,2,0})==nil)

    enter("vendor",Vendor.view(state)); assets.activatePack(previousPack)
    render("vendor",nil,true)
    local reception={jobId=job.id,company=job.company,sourceSize=job.sourceSize,finishedSize=job.finishedSize,
        stock="80 lb uncoated cover",packaging="flat",delivery="Standard delivery",artworkKey="flower",artworkName="Flower",
        printJob=true,colorCount=1,colorSequence="Black",quoteRows=job.quote.pallets,recommendedTotal=job.quote.totalPrice}
    enter("reception_customer",reception); render("reception",nil,true)
    click(require("src.screens.job_offer_screen").buttonCenter("accept"))
    check("shared_gui_reception_requests_email_not_instant_quote",last("request_details"))
    enter("truck",{mode="delivery",state="cargo_open",manifestId=job.id,title=job.company,page=1,pageCount=1,remaining=1,canClose=false,
        items={{itemIndex=1,available=true,label="Pallet 1",detail="Customer stock"}}})
    render("truck",nil,true)
    click(require("src.screens.truck_inventory_screen").unloadButtonCenter(1))
    check("shared_gui_truck_host_row_sends_bounded_move",last("move_item") and sent[#sent].args.itemIndex==1)
    Phone.queueCall(state,{kind="customer_order",caller="Critter Print Co.",role="CUSTOMER",subject="NEW JOB",message="Please quote a print job."})
    enter("work_phone",{})
    render("phone_ringing",nil,true)
    click(require("src.screens.work_phone_screen").buttonCenter("action"))
    check("shared_gui_phone_answer_does_not_change_client_call",last("phone_answer") and not state.workPhone.incoming.answered)
    state.workPhone.incoming.answered=true; Remote.waiting=false
    render("phone_connected")
    click(require("src.screens.work_phone_screen").buttonCenter("action"))
    check("shared_gui_phone_response_does_not_create_local_order",last("phone_respond") and #state.workPhone.history==0)
    check("shared_gui_rendering_never_spends_stock_or_runs_client_job",state.money==money and state.inventory.stock.maintenance_kit==kit
        and pallet.paper.currentSize.width==10)
    Remote.clear(); canvas:release(); love.timer.getTime=previousTime; assets.activatePack(previousPack)
end
return Test
