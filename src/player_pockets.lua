-- Personal, persistent portions; host commands use a revision to reject repeats.
local Food=require('src.home_food_catalog')
local P={CAPACITY=2}
function P.valid(p)
    if p==nil then return true end
    if type(p)~='table' or type(p.revision)~='number' or p.revision<0 or p.revision>1e12 or p.revision%1~=0 or type(p.items)~='table' then return false end
    local n=0
    for id,q in pairs(p.items) do
        if not Food.ITEMS[id] or not Food.ITEMS[id].action or type(q)~='number' or q<1 or q%1~=0 then return false end
        n=n+q
    end
    return n<=P.CAPACITY
end
function P.ensure(r) r.pockets=r.pockets or {revision=0,items={}};return r.pockets end
function P.decode(command)
    if type(command)~='string' or #command>80 then return end
    local action,id,rev=command:match('^pocket:([a-z]+):([a-z_]+):(%d+)$')
    if (action=='pack' or action=='use' or action=='store') and Food.ITEMS[id] and Food.ITEMS[id].action and tonumber(rev)<=1e12 then
        return action,id,tonumber(rev)
    end
end
function P.command(state,player,command)
    local action,id,rev=P.decode(command)
    local Residents=require('src.home_residents');local r=Residents.get(state,player)
    if not action or not r then return false,'invalid_action','Choose an item in your pockets.' end
    local p=P.ensure(r)
    if rev~=p.revision then return false,'changed','Your pockets changed. Choose the item again.' end
    if r.activity or require('src.player_medical').blocked(state,player) then return false,'busy','Finish your current activity first.' end
    local allowed,reason=require('src.commute.outfit').allowed(state,player,'eat')
    if not allowed then return false,'blocked',reason end
    if action~='use' and player.sceneId~='home' then return false,'wrong_scene','Pack or store supplies at your apartment.' end
    if action=='pack' then
        local count=0;for _,q in pairs(p.items) do count=count+q end
        if count>=P.CAPACITY then return false,'full','Both pockets are full.' end
        if (state.home.inventory[id] or 0)<1 then return false,'empty','There are no portions in home storage.' end
        state.home.inventory[id]=state.home.inventory[id]-1;p.items[id]=(p.items[id] or 0)+1
    else
        if (p.items[id] or 0)<1 then return false,'empty','That pocket is empty.' end
        if action=='store' then
            if not require('src.home_cooking').hasRoom(state,id,1) then return false,'full','Home storage is full.' end
            state.home.inventory[id]=(state.home.inventory[id] or 0)+1
        else
            local definition=Residents.ACTIONS[Food.ITEMS[id].action]
            for need,gain in pairs(definition.gain) do r[need]=math.min(100,r[need]+gain) end
        end
        p.items[id]=p.items[id]-1;if p.items[id]==0 then p.items[id]=nil end
    end
    p.revision=p.revision+1;r.revision=r.revision+1;state.home.revision=state.home.revision+1
    return true,'accepted',(action=='use' and 'Finished ' or action=='pack' and 'Packed ' or 'Stored ')..Food.ITEMS[id].name..'.'
end
function P.rows(state,player)
    local r=require('src.home_residents').get(state,player);if not r then return {} end
    local p=P.ensure(r);local rows={};local ids={}
    for id,food in pairs(Food.ITEMS) do if food.action then ids[#ids+1]=id end end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local name=Food.ITEMS[id].name
        if (p.items[id] or 0)>0 then
            rows[#rows+1]={foodId=id,label=(id=='bottled_drink' and 'DRINK ' or 'EAT ')..name..' / '..p.items[id],command='pocket:use:'..id..':'..p.revision}
            if player.sceneId=='home' then rows[#rows+1]={foodId=id,label='STORE '..name,command='pocket:store:'..id..':'..p.revision} end
        end
        if player.sceneId=='home' and (state.home.inventory[id] or 0)>0 then rows[#rows+1]={foodId=id,label='PACK '..name,command='pocket:pack:'..id..':'..p.revision} end
    end
    return rows
end
return P
