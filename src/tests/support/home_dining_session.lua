local Test={}
function Test.run(s,host,guests,players,pump,network,received,check)
    local Furniture=require("src.home_furniture");local Residents=require("src.home_residents")
    local Dining=require("src.home_dining");local Find=require("src.tests.home_dining_test")
    s.home.inventory.kitchen_table=1;Furniture.materialize(s,false)
    local tableItem
    for _,item in ipairs(s.home.furniture.items) do if item.kind=="kitchen_table" then tableItem=item end end
    assert(tableItem,"kitchen table did not materialize")
    local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,"kitchen_table",{host.players[1]},tableItem.id))
    tableItem.location="floor";tableItem.x,tableItem.y=spot.x,spot.y
    for i=2,3 do Find.near(s,host.players[i],tableItem.id) end
    s.home.inventory.basic_meal=2
    local serve="dine:serve:"..tableItem.id..":1:basic_meal:"..Dining.ensure(s).revision
    network:duplicateNext("client_to_host",1,1,true);assert(guests[1]:requestInteraction("homeActivity",serve));pump()
    check("home_session_served_meal_debits_once",#s.home.dining.items==1 and s.home.inventory.basic_meal==1
        and #received[3].shop_state.state.home.dining.items==1)
    local meal=s.home.dining.items[1];local eat="dine:eat:"..meal.id..":0:"..s.home.dining.revision
    assert(guests[1]:requestInteraction("homeActivity",eat));assert(guests[2]:requestInteraction("homeActivity",eat));pump()
    local a,b=Residents.get(s,host.players[2]).activity,Residents.get(s,host.players[3]).activity
    check("home_session_last_served_portion_has_one_eater",#s.home.dining.items==0 and (a~=nil)~=(b~=nil)
        and received[1].interaction_result.accepted~=received[2].interaction_result.accepted)
    check("home_session_eating_plate_replicates",#Dining.children({home=received[3].shop_state.state.home},tableItem.id)==1)
    local idle=a and 2 or 1;local busy=a and 1 or 2
    assert(guests[idle]:requestInteraction("homeActivity","dine:serve:"..tableItem.id..":1:basic_meal:"..s.home.dining.revision));pump()
    check("home_session_eating_slot_cannot_be_reused",not received[idle].interaction_result.accepted and s.home.inventory.basic_meal==1)
    assert(guests[busy]:requestInteraction("homeActivity","cancel"));pump()
    assert(guests[2]:requestInteraction("homeActivity","dine:serve:"..tableItem.id..":1:basic_meal:"..s.home.dining.revision));pump()
    meal=s.home.dining.items[1];local back="dine:return:"..meal.id..":"..s.home.dining.revision
    network:duplicateNext("client_to_host",1,1,true);assert(guests[1]:requestInteraction("homeActivity",back));pump()
    check("home_session_return_serving_once",#s.home.dining.items==0 and s.home.inventory.basic_meal==1
        and received[3].shop_state.state.home.inventory.basic_meal==1)
end
return Test
