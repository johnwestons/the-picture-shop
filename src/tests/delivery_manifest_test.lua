local Test={}

function Test.run(_,check)
    local State=require('src.state')
    local Procurement=require('src.procurement')
    local Screen=require('src.screens.truck_inventory_screen')
    local Truck=require('src.truck')
    local Driver=require('src.warehouse_delivery_driver')
    local state=State.new()
    state.money=100000
    local shipmentId
    for _=1,4 do
        local bought,order=Procurement.buy(state,1,1,'computer')
        assert(bought and order)
        shipmentId=shipmentId or order.shipmentId
        assert(order.shipmentId==shipmentId)
    end
    local truck=Truck.new({start={x=0,y=0,scale=1},parked={x=1,y=1,scale=1},
        interaction={x=1,y=1,radius=1},obstacle={offsetX=0,offsetY=0,radius=1}})
    truck.state,truck.mode,truck.jobId='cargo_open','vendor_delivery',shipmentId
    truck.backingProgress,truck.cargoProgress=1,1
    local world={
        truckSnapshot=function()return truck:snapshot()end,
        unloadTruckPallet=function(_,palletId)
            local _,items=Procurement.truckInventory(state,shipmentId)
            for _,item in ipairs(items) do
                if item.id==palletId and item.pallet.location=='awaiting_delivery' then
                    item.pallet.location='warehouse'
                    return true,item.pallet,Procurement.remainingOnTruck(state,shipmentId)
                end
            end
            return false
        end,
        closeTruckAfterUnload=function()
            return Procurement.remainingOnTruck(state,shipmentId)==0 and truck:toggleCargoDoor()
        end,
    }
    for row=1,3 do
        local x,y=Screen.unloadButtonCenter(row)
        local result=Screen.mousepressed(state,world,x,y,1)
        assert(result and result.action=='unloaded')
    end
    check('grouped_delivery_keeps_fourth_pallet_on_manifest',Procurement.remainingOnTruck(state,shipmentId)==1)
    local nextPage=Screen.mousepressed(state,world,803,429,1)
    local x,y=Screen.unloadButtonCenter(1)
    local last=Screen.mousepressed(state,world,x,y,1)
    check('local_truck_manifest_reaches_later_shipment_pages',nextPage and nextPage.action=='page_changed'
        and last and last.action=='unloaded' and last.remaining==0
        and Procurement.remainingOnTruck(state,shipmentId)==0)
    assert(Driver.start(state,shipmentId,'vendor_delivery'))
    local visit=Driver.matching(state,shipmentId)
    local actor=Driver.actor(state)
    visit.status,actor.phase,actor.x,actor.y='waiting','waiting',151,236
    local signed=Driver.sign(state,{x=151,y=236,sceneId='warehouse'})
    actor.phase,actor.x,actor.y='exit_cab',120,230
    Driver.update(state,.1,{})
    local returned=visit.driverReturned
    local closing=Driver.departIfReady(state,truck)
    local closed=truck:update(1,'open',1)
    local departing=Driver.departIfReady(state,truck)
    local departed=truck:update(3,'open',3)
    check('signed_empty_grouped_delivery_leaves_warehouse',closing
        and closed=='cargo_closed' and signed and returned and departing
        and departed=='departed' and truck.state=='absent')
end

return Test
