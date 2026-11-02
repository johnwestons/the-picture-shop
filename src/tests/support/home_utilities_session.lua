local Test={}
function Test.run(s,host,guests,players,pump,network,received,check)
    local Furniture=require("src.home_furniture");local Residents=require("src.home_residents")
    local Objects=require("src.home_objects");local Calendar=require("src.business_calendar")
    local utility=require("src.home_utilities");local items={}
    for _,kind in ipairs({"wardrobe","cabinet","old_tv","trash_can"}) do
        s.home.inventory[kind]=1;Furniture.materialize(s,false);local item=s.home.furniture.items[#s.home.furniture.items]
        local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,kind,players(),item.id))
        item.location="floor";item.x,item.y=spot.x,spot.y;items[kind]=item
    end
    s.home.chores.laundry.clean=1;s.home.chores.trash=2;s.home.inventory.bread=1
    for _,kind in ipairs({"wardrobe","cabinet","trash_can"}) do
        local item=items[kind];local target=assert(Furniture.targets(s,host.players[2])["furniture"..item.id])
        for i=2,3 do host.players[i].x,host.players[i].y=target.x,target.y end
        local command="object:"..(kind=="cabinet" and "put" or "stow")..":"..item.id..":"..item.revision..(kind=="cabinet" and ":bread" or "")
        network:duplicateNext("client_to_host",1,1,true);assert(guests[1]:requestInteraction("homeActivity",command));pump()
        assert(guests[2]:requestInteraction("homeActivity",command));pump()
        check("home_session_utility_transfer_once_"..kind,item.revision==1 and not received[2].interaction_result.accepted
            and (kind=="wardrobe" and item.contents.clean==1 and s.home.chores.laundry.clean==0
                or kind=="cabinet" and item.contents.bread==1 and s.home.inventory.bread==0
                or kind=="trash_can" and item.contents.trash==2 and s.home.chores.trash==0))
        local remote=require("src.home_surfaces").find({home=received[3].shop_state.state.home},item.id)
        check("home_session_utility_contents_replicate_"..kind,Objects.count(remote)==Objects.count(item))
    end
    local tv=items.old_tv;local target=assert(Furniture.targets(s,host.players[2])["furniture"..tv.id])
    for i=2,3 do host.players[i].x,host.players[i].y=target.x,target.y end
    network:duplicateNext("client_to_host",1,1,true);assert(guests[1]:requestInteraction("homeActivity","object:on:"..tv.id..":0"));pump()
    assert(guests[2]:requestInteraction("homeActivity","object:off:"..tv.id..":0"));pump()
    check("home_session_tv_stale_switch_rejected",tv.powered and tv.revision==1 and not received[2].interaction_result.accepted)
    for _,a in ipairs(Furniture.approaches(tv)) do if utility.visibleTV(s,{x=a.x,y=a.y},tv,tv) then host.players[2].x,host.players[2].y=a.x,a.y;break end end
    assert(guests[1]:requestInteraction("homeActivity","watch:furniture"..tv.id));pump()
    check("home_session_tv_watch_replicates",Residents.get(s,host.players[2]).activity.tvId==tv.id
        and received[3].shop_state.state.home.residents[guests[1].residentId].activity.kind=="watch")
    assert(guests[2]:requestInteraction("homeActivity","object:off:"..tv.id..":"..tv.revision));pump()
    Residents.advance(s,players(),Calendar.absoluteHours(s),Calendar.absoluteHours(s));host:markShopDirty();pump()
    check("home_session_tv_off_interrupts_other_viewer",not Residents.get(s,host.players[2]).activity and not received[3].shop_state.state.home.residents[guests[1].residentId].activity)
end
return Test
