-- Read-only help belongs to each console; browsing never changes the household.
local Shopping=require("src.home_shopping")
local Food=require("src.home_food_catalog")
local Guide={}
Guide.TOPICS={"FIRST WEEKEND","FOOD & WATER","FURNITURE","CHORES","SLEEP & WORK","MONEY & GUESTS"}
local controls={back={x=104,y=554,width=230,height=44},action={x=374,y=554,width=218,height=44},
    secondary={x=608,y=554,width=230,height=44}}
function Guide.rect(name,index)
    if name=="topic" and Guide.TOPICS[index] then return {x=104,y=242+(index-1)*48,width=230,height=44} end
    return controls[name]
end
local function money(cents) return string.format("$%.2f",cents/100) end
function Guide.content(state,page)
    local home=state.home
    if page==1 then
        local portions=0
        for id,n in pairs(home.inventory) do
            local food=Food.ITEMS[id]
            if food and food.action and id~="bottled_drink" then portions=portions+n end
        end
        local bed=Shopping.quote("bed",1);local meals=Shopping.quote("meal_pack",1)
        local total=bed.totalCents+meals.totalCents
        return {title="Make yourself at home",blocks={
            "Household funds: "..money(home.balanceCents)..". Ready-to-eat pantry portions: "..portions..". Parcels ready at the door: "..Shopping.waiting(state)..".",
            "An empty start includes fixed plumbing and a movable laptop. Drink free tap water at a sink, wash in the bathroom, and use Home / Rest on floor while you furnish the apartment.",
            "Optional first purchases: a single bed ("..money(bed.totalCents)..") and four ready meals ("..money(meals.totalCents).."). Total including delivery: "..money(total)..". "..(home.balanceCents>=total and "Your household can afford this now." or "Buy food first and rest on the floor while saving."),
            "At the door, Receive arrived parcels. Meals go to shared supplies; furniture goes to Furnish storage. Extra guests need their own food and sleeping places. Time keeps passing while you browse."},
            action={"GROCERIES","groceries"},secondary={"DELIVERY STATUS","home_orders"}}
    elseif page==2 then
        return {title="Eat, drink and prepare meals",blocks={
            "Buy groceries or pizza/Chinese takeout with household funds. Groceries arrive in one game hour; takeout in 30 minutes. Receive parcels at the entrance. Take food out of a fridge or cabinet before use.",
            "At a table/counter or kitchen sink, choose Meals [D] to serve a portion in a clear slot. Eat there or from a nearby chair/couch facing the surface. Packing returns uneaten portions; stopping an eating activity does not.",
            "Tap water is free at either sink. A cup is optional: pick it up, fill it, drink, then wash before refilling. Home routines also eat directly from supplies; furniture is optional. Food does not spoil.",
            "Open the fridge to manage its portions. Prepare two sandwiches using 1 bread + 1 vegetable at a kitchen work area. The stove opens cooking; tend once in the green band. Moving or stopping discards the batch; poor timing still makes edible food."},
            action={"GROCERIES","groceries"},secondary={"TAKEOUT","takeout"}}
    elseif page==3 then
        return {title="Buy, unpack and arrange",blocks={
            "Home & Living shows prices, sizes and placement requirements before checkout. Furniture arrives after two game hours. Receive it at the door; waiting parcels stay safe during sleep or while everyone is at work.",
            "Open Furnish to select a stored item. Choose a position, rotate, then confirm the green preview. Use the on-screen controls or arrows / Q / Enter; Escape cancels. On a controller use the D-pad / Y / A / B.",
            "Keep paths to the door, fixtures, laptop and residents clear. The stove snaps to its kitchen power point. Small objects use clear desk/table/counter slots and follow the supporting furniture. Interact with a placed lamp to switch it on or off.",
            "Store keeps an object for later. Selling shows its value first. Packing or selling a supporting surface puts its small objects in storage. An occupied object or one being edited by someone else cannot move."},
            action={"HOME & LIVING","furniture"},secondary={"DELIVERY STATUS","home_orders"}}
    elseif page==4 then
        return {title="Keep the apartment usable",blocks={
            "The washer opens its own laundry controls. Use Home routines for sinks, baths and shared chores; shared fixtures serve one resident at a time.",
            "Laundry: load/start for 5 game minutes, leave it washing for 45, then return to unload for 5. Change into fresh clothes for 2 minutes to use a clean bundle. Store clean bundles in a wardrobe and change there too.",
            "Wash dishes and wipe the kitchen at the sink, clean the bathroom, or use Home routines to sweep. A trash can collects loose waste; remove a bag, then take it out beside the entrance. New mess stays for the next batch.",
            "Move away or choose Stop to cancel. Unfinished cleaning gives no result; a washer already running continues by itself. Weekday routines cover basic needs, and absent guests' needs stay frozen."}}
    elseif page==5 then
        return {title="Sleep together, return on time",blocks={
            "Interact with a bed to lie down, or a chair/couch to sit. If a TV is on and visible from the couch, that interaction starts watching. Home / Sleep & Alarms lets you choose overnight sleep and set an alarm. Each bed, couch or mat holds one sleeper.",
            "Time speeds up only when every connected resident chooses sleep. An awake or joining guest, cancellation or the first alarm restores normal speed. Needs, rent, laundry and deliveries continue during sleep.",
            "From Sunday 20:00, choose Sleep until Monday 07:00. The wake reminder stops shared acceleration. Home / Readiness shows everyone's needs; eat, drink and wash before leaving.",
            "At the apartment door on Monday, the host starts Return to shop. Guests confirm readiness, or the host can bring everyone. Return becomes available at 07:30, before the 08:00 employee shift; the shop opens at 09:00, and a late return opens late. On Friday, shut down and leave through the shop's front entrance."},
            action={"SLEEP & ALARMS","sleep"}}
    end
    local limit,_,remaining=Shopping.budget(state)
    return {title="One home, two accounts",blocks={
        "My Home shows rent, the saving target for remaining Fridays, and your last actual pay. Leave extra for food and furniture. Higher rent or more residents may need a larger personal-pay share or more shop earnings. Unpaid rent remains due without eviction.",
        "The host chooses 0-100%. Friday pays from collected earnings after costs, prior losses and reserves. A higher rate cannot create earnings or release protected cash. Quotes, loans and starting capital do not count. Check the earnings preview and history.",
        "Guests share the pantry and furniture and may eat, wash, cook, clean and rest. Food/takeout budget for all guests together: "..money(limit).." per shop week; "..money(remaining).." remains. Rejoining does not reset spending.",
        "The host grants separate furniture-buying, moving and selling permissions in Furnish. Guests can read this guide and browse catalogs without those permissions. Reading never places an order or spends money."},
        action={"PERSONAL PAY","earnings"},secondary={"GUEST FOOD BUDGET","home_orders"}}
end
function Guide.mousepressed(state,page,x,y,contains)
    for i=1,#Guide.TOPICS do if contains(Guide.rect("topic",i),x,y) then return i end end
    if contains(controls.back,x,y) then return page,"back" end
    local content=Guide.content(state,page)
    for _,key in ipairs({"action","secondary"}) do
        if content[key] and contains(controls[key],x,y) then return page,content[key][2] end
    end
    return page
end
function Guide.draw(Runtime,state,page,px,py)
    local function label(text,x,y,w,color)
        love.graphics.setColor(unpack(color or {.85,.92,.87,1}));love.graphics.printf(text,x,y,w,"left")
    end
    local function button(rect,title,enabled,selected)
        local hover=px and py and Runtime.contains(rect,px,py)
        Runtime.drawComputerButton(rect,title,not enabled and "disabled" or (hover or selected) and "primaryHover" or "primary")
    end
    label("HOME GUIDE  /  "..page.." of "..#Guide.TOPICS,104,208,730,{1,.86,.41,1})
    for i,title in ipairs(Guide.TOPICS) do button(Guide.rect("topic",i),title,true,i==page) end
    local content=Guide.content(state,page)
    label(content.title,360,242,478,{1,.86,.41,1})
    local y=272;local font=love.graphics.getFont()
    for _,block in ipairs(content.blocks) do
        label(block,360,y,478)
        local _,lines=font:getWrap(block,478);y=y+#lines*font:getHeight()*font:getLineHeight()+12
    end
    button(controls.back,"MY HOME",true)
    for _,key in ipairs({"action","secondary"}) do
        if content[key] then button(controls[key],content[key][1],content[key][2]~="sleep" or require("src.weekend_flow").atHome(state)) end
    end
    return y -- Allows layout checks against the shared footer.
end
return Guide
