-- Real ENet sockets bound only to loopback; never loads or writes game saves.
local root=assert(os.getenv("PICTURE_SHOP_PROBE_ROOT"),"Set PICTURE_SHOP_PROBE_ROOT to the repository")
package.path=root.."/?.lua;"..package.path
local Session=require("src.net.session")
local State=require("src.state")
local Schema=require("src.save_schema")
local Rooms=require("src.shop_rooms")
local Upgrades=require("src.warehouse_upgrades")
local Storage=require("src.pallet_storage")
local Procurement=require("src.procurement")
local Config=require("src.config")
local sessions={}
local checks=0
local function check(name,condition)
    assert(condition,name);checks=checks+1;print("PASS "..name)
end
local function player(id)
    return {id=id,x=Rooms.entrance.x,y=Rooms.entrance.y+20,sceneId="warehouse",
        velocityX=0,velocityY=0,intentX=0,intentY=0,moving=false,facing=1,
        animationDistance=0,character="rabbit-worker"}
end
local function complete(state,id,kind,number)
    local now=(number-1)*100
    assert(Upgrades.purchase(state,id,kind,"LOOP-"..id,now))
    Upgrades.update(state,now)
    local project=string.format("WUP-%04d",number)
    Upgrades.update(state,now,{noticeDeliveredProjectId=project,noticeCallId="CALL-"..number})
    Upgrades.update(state,now+2,{workerArrivedProjectId=project})
    Upgrades.update(state,now+98)
    Upgrades.update(state,now+98,{workerReleasedProjectId=project})
    if kind=="storage" then state.storage.racks[id.."-rack"]=Storage.rackDefinition(id) end
end
local function run()
    local state=State.new();state.money=50000
    complete(state,"front_left","storage",1);complete(state,"front_right","breakroom",2)
    local host=Session.new();sessions[#sessions+1]=host
    local port=tonumber(os.getenv("PICTURE_SHOP_PROBE_PORT")) or 23946
    assert(host:startHost({bind="127.0.0.1",port=port,name="Loopback Host",
        addressOptions={socket={dns={gethostname=function() return "loopback" end,
            toip=function() return "127.0.0.1" end}}}}))
    local hp=player(1)
    local hc={localPlayer=hp,resolveGuestSpawn=function() return Rooms.entrance.x,Rooms.entrance.y+20 end,
        getShopSnapshot=function() return {state=assert(Schema.snapshot(state)),player=hp} end,
        moveRemote=function(p,dt,x,y) p.x=p.x+x*80*dt;p.y=p.y+y*80*dt end,
        performInteraction=function(p,kind,command)
            local okay,code,message=Rooms.perform(p,state,kind,command)
            if okay and kind=="roomStock" then host:markShopDirty(true) end
            return okay,code,message
        end}
    local clients,contexts,received={},{},{}
    for i=1,3 do
        clients[i]=Session.new();sessions[#sessions+1]=clients[i]
        contexts[i]={localPlayer=player(i+1),inputX=0,inputY=0}
        assert(clients[i]:startClient("127.0.0.1:"..port,{name="Loopback Guest "..i}))
    end
    local function events(session,index)
        for _,event in ipairs(session:drainEvents()) do
            assert(event.type~="error",event.message)
            if index and (event.type=="ready" or event.type=="shop_state") then received[index]=event.state end
        end
    end
    local function pump(seconds)
        local deadline=love.timer.getTime()+seconds
        while love.timer.getTime()<deadline do
            host:update(.01,hc);events(host)
            for i,c in ipairs(clients) do if c:isActive() then c:update(.01,contexts[i]);events(c,i) end end
            love.timer.sleep(.01)
        end
    end
    pump(1)
    for i,c in ipairs(clients) do check("real_udp_guest_"..i.."_receives_shop",c.ready and received[i]~=nil) end
    assert(Rooms.transition(hp,state,"front_right"))
    assert(clients[1]:requestInteraction("shopRoom","front_left"));pump(.5)
    check("real_udp_three_scenes_replicate",contexts[1].localPlayer.sceneId=="front_left"
        and clients[2].players[1].sceneId=="front_right"
        and clients[3].players[clients[1].localId].sceneId=="front_left"
        and contexts[2].localPlayer.sceneId=="warehouse")
    local guest=host.players[clients[1].localId];guest.x,guest.y=Rooms.shelves.x,Rooms.shelves.y
    local okay,order=Procurement.buy(state,4,1);assert(okay)
    assert(Procurement.unload(state,order.id,order.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin))
    local pallet=order.pallets[1];pallet.world={x=Rooms.entrance.x,y=Rooms.entrance.y+70,spawnProgress=1}
    assert(clients[1]:requestInteraction("roomStock","store:"..pallet.id));pump(.5)
    check("real_udp_guest_stores_stock_on_host",pallet.location=="rack" and Storage.validate(state))
    for i=1,3 do
        local found=Storage.find(received[i],pallet.id)
        check("real_udp_stock_reaches_guest_"..i,found and found.pallet.location=="rack")
    end
    local revision=state.storage.revision
    assert(clients[1]:requestInteraction("roomStock","store:"..pallet.id));pump(.3)
    check("real_udp_repeat_transfer_has_one_owner",state.storage.revision==revision and Storage.validate(state))
    contexts[2].inputX=1;local before=contexts[2].localPlayer.x;pump(.3)
    check("real_udp_other_room_does_not_stop_movement",contexts[2].localPlayer.x>before+5 and hp.sceneId=="front_right")
    contexts[2].inputX=0
    local departed=clients[3].localId
    assert(clients[3]:stop("Loopback reconnect test"));pump(.3)
    check("real_udp_guest_exit_leaves_host_and_peers_connected",host.ready and not host.players[departed] and clients[1].ready and clients[2].ready)
    assert(clients[3]:startClient("127.0.0.1:"..port,{name="Rejoined Guest"}));pump(.7)
    local restored=Storage.find(received[3],pallet.id)
    check("real_udp_rejoin_receives_current_stock_and_room_roster",clients[3].ready and restored and restored.pallet.location=="rack"
        and clients[3].players[1].sceneId=="front_right")
end
function love.load()
    local okay,reason=xpcall(run,debug.traceback)
    for _,session in ipairs(sessions) do session:stop("Loopback probe complete") end
    if okay then print("LAN_LOOPBACK_OK checks="..checks) else print("LAN_LOOPBACK_FAILED "..tostring(reason)) end
    love.event.quit(okay and 0 or 1)
end
