local Station=require('src.commute.gas_station')
local BikeService=require('src.commute.bike_service')
local State=require('src.state')
local Calendar=require('src.business_calendar')
local Test={}

function Test.run(check)
    local rider={ped={x=2,z=7.8,speed=0,crash=false},bike={x=2,z=6.5,speed=0,
        service={fuel=1.5,oil=3,chain=4,tread=0,tire='mixed',miles=0,revision=0}},
        gear={mounted=false,transition=nil},vehicle=nil,transport=nil}
    local site={door={x=0,z=0},pumpBays={{x=2,z=6.5}},localForecourt={minX=-5.5,maxX=5.5,minZ=4,maxZ=13.5},
        toLocal=function(_,x,z)return x,z end}
    local world={sites={byId={['gas-station']=site}}}
    local wallet={balanceCents=10000}
    local state=State.new()
    state.calendar.elapsed=9/24*Calendar.secondsPerDay(state)
    local function buy(id,revision,amount)
        return Station.buy(rider,world,wallet,id,revision,nil,nil,state,amount)
    end
    local args={rider=rider,world=world,service=rider.bike.service,householdCents=wallet.balanceCents,
        close=function()end,buy=buy}

    check('gas_station_requires_motorcycle_at_marked_pump',Station.pumpMode(rider,nil,world)=='bike')
    rider.bike.x=40
    local balance=wallet.balanceCents
    local accepted=Station.buy(rider,world,wallet,'fuel',rider.bike.service.revision,nil,nil,state,1000)
    check('gas_station_rejects_fuel_without_motorcycle_at_pump',not accepted
        and wallet.balanceCents==balance and rider.bike.service.fuel==1.5)
    rider.bike.x=2
    local chainRevision=rider.bike.service.revision
    accepted=Station.buy(rider,world,wallet,'chain',chainRevision,nil,nil,state,0)
    check('gas_station_does_not_sell_mechanic_chain_upgrade',not accepted
        and rider.bike.service.revision==chainRevision and rider.bike.service.chain==4)

    check('gas_station_2d_fuel_sprites_exist',love.filesystem.getInfo('assets/commute/ui/gas-pump-fuel-loop-v1.png')~=nil
        and love.filesystem.getInfo('assets/commute/ui/fuel-drop-loop-v1.png')~=nil)
    local view=Station.open('bike')
    Station.key(view,'left',args)
    check('gas_station_fuel_gui_selects_partial_fill',view.amountMl==2250)
    Station.key(view,'return',args)
    local reviewReady=view.quote~=nil and view.notice and view.notice:find('Review',1,true)~=nil
    Station.key(view,'return',args)
    check('gas_station_fuel_gui_confirms_payment_and_fills_present_vehicle',reviewReady
        and rider.bike.service.fuel==3.75 and wallet.balanceCents==9640 and view.pending~=nil)
    Station.update(view,.1,args)
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(.02,.03,.03,1)
    check('gas_station_animated_sprite_gui_draws',Station.draw(view,args,960,678)==true)
    love.graphics.pop();love.graphics.setCanvas();canvas:release()

    rider.ped.x,rider.ped.z=0,1
    args.householdCents=wallet.balanceCents
    local oilBefore=rider.bike.service.oil
    local oilOkay=Station.buy(rider,world,wallet,'oil',rider.bike.service.revision,nil,nil,state)
    check('gas_station_counter_sells_oil_change_at_station',Station.atCounter(rider,world)
        and oilOkay and rider.bike.service.oil==0 and oilBefore>0)
    check('gas_station_service_scope_is_fuel_and_oil_only',#BikeService.orders==2
        and BikeService.orders[1]=='fuel' and BikeService.orders[2]=='oil')
end

return Test
