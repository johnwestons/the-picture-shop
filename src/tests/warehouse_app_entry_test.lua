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
        and computer.warehouseConfirmation and computer.warehouseConfirmation.warningRequired and state.money==30000)
    x,y=computer.warehouseButtonCenter("cancel")
    computer.mousepressed(state,x,y,1)
    x,y=computer.warehouseButtonCenter("front_right","storage")
    result=computer.mousepressed(state,x,y,1)
    check("warehouse_app_normal_catalog_blocks_unready_bay",result and result.action=="blocked"
        and result.reason=="warehouse_not_ready" and computer.warehouseConfirmation==nil)
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
