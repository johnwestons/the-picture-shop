-- Private household data is embedded in the host's save. Shared town,
-- commute, resident identities, and shop data stay on the host home record.
local Households={}
local personal={
    'version','revision','apartmentId','furnishingPreset','balanceCents',
    'allowanceGranted','payPercent','inventory','furniture','shopping',
    'chores','dining','finance','lease',
}
local keys={}
for _,key in ipairs(personal) do keys[key]=true end

function Households.create(state,id)
    local home=state and state.home
    local resident=home and home.residents and home.residents[id]
    if not resident or not resident.apartmentId then return nil,'Assign a client apartment first.' end
    local day=math.floor(require('src.business_calendar').absoluteHours(state)/24)
    local fresh,reason=require('src.home').new({
        apartmentId=resident.apartmentId,furnishingPreset='empty',town=home.town,
    },day)
    if not fresh then return nil,reason end
    local private={}
    for _,key in ipairs(personal) do private[key]=fresh[key] end
    return private
end

function Households.view(host,private)
    local view={}
    for key,value in pairs(host) do if key~='clientHomes' and key~='commute' then view[key]=value end end
    for _,key in ipairs(personal) do view[key]=private[key] end
    return view
end

function Households.runtimeView(host,private)
    local view={}
    for key,value in pairs(host) do view[key]=value end
    for _,key in ipairs(personal) do view[key]=private[key] end
    view.hostApartmentId=host.hostApartmentId or host.apartmentId
    return view
end

function Households.activateClient(state,id)
    local host=state and state.home
    local private=host and host.clientHomes and host.clientHomes[id]
    if not private then return false end
    state.home=Households.runtimeView(host,private)
    return true
end
function Households.commit(host,id,view)
    local private=host and host.clientHomes and host.clientHomes[id]
    if not private then return false end
    for _,key in ipairs(personal) do private[key]=view[key] end
    host.revision=host.revision+1
    return true
end
function Households.playersHere(runtime,player)
    local apartments=require('src.client_apartments')
    local target=apartments.forPlayer(runtime.state,player)
    local result={}
    for _,candidate in ipairs(require('src.weekend_runtime').players(runtime)) do
        if apartments.forPlayer(runtime.state,candidate)==target then
            result[#result+1]=candidate
        end
    end
    return result
end

-- Host commands use the client's household for the duration of the action.
-- Save calls inside existing controls are delayed until the canonical host
-- home and its three private records have been restored.
function Households.withPlayer(runtime,player,action)
    if not player or (player.id or 1)==1 then return action() end
    local state=runtime.state
    local host=state and state.home
    local id=player.homeResidentId
    local private=id and host and host.clientHomes and host.clientHomes[id]
    if not private then return false,'resident_required','This client has no saved apartment.' end
    local originalSave=runtime.saveCurrent
    local saveRequested=false
    local view=Households.runtimeView(host,private)
    state.home=view
    runtime.saveCurrent=function() saveRequested=true end
    local result={pcall(action)}
    runtime.saveCurrent=originalSave
    state.home=host
    if result[2] then
        host.commute=view.commute
        Households.commit(host,id,view)
    end
    if saveRequested then originalSave() end
    if not result[1] then error(result[2]) end
    return unpack(result,2)
end

function Households.advanceResidents(state,players,first,last)
    local host=state.home
    local hostPlayers={}
    for _,player in ipairs(players or {}) do
        local id=player.homeResidentId
        local resident=id and host.residents and host.residents[id]
        if not resident or not resident.clientSlot then hostPlayers[#hostPlayers+1]=player end
    end
    local Residents=require('src.home_residents')
    local changed=Residents.advance(state,hostPlayers,first,last,'owner')
    for id,private in pairs(host.clientHomes or {}) do
        local clientPlayers={}
        for _,player in ipairs(players or {}) do
            if player.homeResidentId==id then clientPlayers[#clientPlayers+1]=player end
        end
        local view=Households.runtimeView(host,private)
        state.home=view
        local clientChanged=Residents.advance(state,clientPlayers,first,last,id)
        state.home=host
        if clientChanged then Households.commit(host,id,view) end
        changed=clientChanged or changed
    end
    return changed
end

function Households.advance(state)
    local host=state and state.home
    if not host or not host.clientHomes then return false end
    local changed=false
    for _,private in pairs(host.clientHomes) do
        local view=Households.runtimeView(host,private)
        state.home=view
        local rent=require('src.home').advance(state,true)
        local deliveries=require('src.home_shopping').advance(state,true)
        for _,key in ipairs(personal) do private[key]=view[key] end
        changed=rent or deliveries or changed
    end
    state.home=host
    if changed then host.revision=host.revision+1 end
    return changed
end

function Households.valid(host)
    local homes=host.clientHomes
    if homes==nil then
        for _,resident in pairs(host.residents or {}) do
            if resident.clientSlot then return false end
        end
        return true
    end
    if type(homes)~='table' then return false end
    local count=0
    for id,private in pairs(homes) do
        count=count+1
        local resident=host.residents and host.residents[id]
        if count>3 or not resident or not resident.clientSlot
            or type(private)~='table' or private.apartmentId~=resident.apartmentId then return false end
        for key in pairs(private) do if not keys[key] then return false end end
        for _,key in ipairs(personal) do if private[key]==nil then return false end end
        if not require('src.home').valid(Households.view(host,private),true) then return false end
    end
    for id,resident in pairs(host.residents or {}) do
        if resident.clientSlot and homes[id]==nil then return false end
    end
    return true
end

function Households.forPlayer(state,player)
    local host=state and state.home
    if not host then return nil end
    if not player or (player.id or 1)==1 then return host end
    local id=player.homeResidentId
    local private=id and host.clientHomes and host.clientHomes[id]
    return private and Households.runtimeView(host,private) or nil
end

return Households
