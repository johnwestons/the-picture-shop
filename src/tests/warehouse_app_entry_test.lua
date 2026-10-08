-- Exercise the actual App-provided screen/authority seams, not parallel mocks.
local Test={}
function Test.run(context,check)
    local computer=context.computerScreen
    local state=context.State.new();state.money=30000
    computer.enter(state)
    local x,y=computer.dropdownCenter()
    computer.mousepressed(state,x,y,1)
    x,y=computer.tabCenter("warehouse")
    check("warehouse_app_normal_computer_exposes_live_tab",computer.warehouseEnabled() and x~=nil and y~=nil)
    local selected=x and computer.mousepressed(state,x,y,1)
    check("warehouse_app_dropdown_reaches_warehouse_page",selected~=nil and computer.tab=="warehouse")
    x,y=computer.warehouseButtonCenter("front_left","storage")
    local result=computer.mousepressed(state,x,y,1)
    check("warehouse_app_normal_catalog_reaches_storage_confirmation",result and result.action=="warehouse_confirmation"
        and computer.warehouseConfirmation and computer.warehouseConfirmation.warningRequired==false and state.money==30000)
    x,y=computer.warehouseButtonCenter("cancel")
    computer.mousepressed(state,x,y,1)
    x,y=computer.warehouseButtonCenter("front_right","storage")
    result=computer.mousepressed(state,x,y,1)
    check("warehouse_app_normal_catalog_allows_second_bay",result and result.action=="warehouse_confirmation"
        and computer.warehouseConfirmation and computer.warehouseConfirmation.bayId=="front_right"
        and computer.warehouseConfirmation.optionId=="storage")
    x,y=computer.warehouseButtonCenter("cancel")
    computer.mousepressed(state,x,y,1)
    local Config=require("src.config")
    local view=computer.warehouseView(state)
    local allSixOffered=Config.warehouse.enabled and Config.warehouse.firstStorageOnly==false
    for _,bayId in ipairs({"front_left","front_right"}) do
        for _,optionId in ipairs({"floor","storage","breakroom"}) do
            local offered=false
            for _,bay in ipairs(view.bays or {}) do
                if bay.id==bayId then
                    for _,option in ipairs(bay.options or {}) do
                        if option.id==optionId then offered=option.available==true end
                    end
                end
            end
            allSixOffered=allSixOffered and offered
        end
    end
    check("warehouse_app_normal_catalog_offers_all_six_room_choices",allSixOffered)
    computer.enter(context.state)

    local observedPlayer,observedState
    local oldAccess=context.world.warehouseAccess
    context.world.warehouseAccess=function(player,shop)
        observedPlayer,observedState=player,shop
        return true,"allowed"
    end
    local okay,authority=pcall(context.createWorkshopAuthority)
    local player={id=4,x=500,y=400}
    local grant
    if okay then grant=authority:acquire(player,{requestId=1,resourceId="warehouse"},{state=context.state}) end
    context.world.warehouseAccess=oldAccess
    check("warehouse_app_actual_authority_acquire_receives_worker_not_context",okay and grant and grant.accepted
        and observedPlayer==player and observedState==context.state)
    check("warehouse_app_actual_authority_registers_jack_storage_command",okay
        and authority.resources.pallet_jack.commands.warehouse_action~=nil
        and authority.resources.warehouse.commands.warehouse_action==authority.resources.pallet_jack.commands.warehouse_action)
end
return Test
