-- Apartment assignments belong to a resident credential, not a temporary
-- network player number. The host's apartment plus these three assignments
-- exhaust the four homes available in a town.
local Catalog=require('src.home_catalog')
local Apartments={MAX_CLIENT_SLOTS=3}

function Apartments.validSlot(slot)
    return type(slot)=='number' and slot==math.floor(slot)
        and slot>=1 and slot<=Apartments.MAX_CLIENT_SLOTS
end

function Apartments.valid(home)
    if not home or not Catalog.APARTMENTS[home.apartmentId] then return false end
    local used={[home.apartmentId]=true};local slots={}
    for id,resident in pairs(home.residents or {}) do
        if id~='owner' and (resident.apartmentId~=nil or resident.clientSlot~=nil) then
            if not Apartments.validSlot(resident.clientSlot) or slots[resident.clientSlot]
                or not Catalog.APARTMENTS[resident.apartmentId]
                or used[resident.apartmentId] then return false end
            slots[resident.clientSlot]=true
            used[resident.apartmentId]=true
        end
    end
    return true
end

function Apartments.assign(home,id,random)
    local resident=home and home.residents and home.residents[id]
    if type(id)~='string' or not id:match('^guest%-%d+$') or not resident then
        return nil,'Choose a saved client identity.'
    end
    if resident.apartmentId or resident.clientSlot then
        if not Apartments.valid(home) then return nil,'Apartment assignments conflict.' end
        return resident.apartmentId
    end
    local used={[home.apartmentId]=true};local slots={}
    for otherId,row in pairs(home.residents) do
        if otherId~=id then
            if row.apartmentId then used[row.apartmentId]=true end
            if row.clientSlot then slots[row.clientSlot]=true end
        end
    end
    local slot
    for candidate=1,Apartments.MAX_CLIENT_SLOTS do
        if not slots[candidate] then slot=candidate;break end
    end
    if not slot then return nil,'All three client save slots are occupied.' end
    local available={}
    for _,apartmentId in ipairs(Catalog.ORDER) do
        if not used[apartmentId] then available[#available+1]=apartmentId end
    end
    if #available==0 then return nil,'No unassigned apartment remains in this town.' end
    local index=(random or math.random)(#available)
    if type(index)~='number' or index~=math.floor(index) or index<1 or index>#available then
        return nil,'Apartment selection failed.'
    end
    resident.clientSlot=slot
    resident.apartmentId=available[index]
    resident.revision=resident.revision+1
    home.revision=home.revision+1
    return resident.apartmentId
end

function Apartments.forPlayer(state,player)
    if not state or not state.home then return nil end
    if not player or (player.id or 1)==1 then
        return state.home.hostApartmentId or state.home.apartmentId
    end
    local id=player.homeResidentId
    local resident=id and state.home.residents and state.home.residents[id]
    return resident and resident.apartmentId or nil
end

function Apartments.resetSlot(state,slot)
    if not Apartments.validSlot(slot) or not state or not state.home then
        return false,'Choose client slot 1, 2, or 3.'
    end
    local home=state.home
    for id,resident in pairs(home.residents or {}) do
        if resident.clientSlot==slot then
            local trip=home.commute
            local okay,transferred=require('src.commute.delivery_run').reassignDeletedDriver(state,id)
            if not okay then return false,transferred end
            if trip and trip.participants then trip.participants[id]=nil end
            if trip then
                for _,truck in ipairs({trip.truck or false,trip.keiTruck or false}) do
                    if truck and truck.owner==id then truck.owner=nil;truck.driver=nil end
                end
            end
            if home.clientHomes then home.clientHomes[id]=nil end
            home.residents[id]=nil
            for index=#(home.trading and home.trading.offers or {}),1,-1 do
                local offer=home.trading.offers[index]
                if offer.from==id or offer.to==id then table.remove(home.trading.offers,index) end
            end
            home.revision=home.revision+1
            return true,transferred and 'Unfinished shop deliveries now belong to the owner. Use Explore Town to resume the route.' or nil
        end
    end
    return false,'That client slot is empty.'
end

return Apartments
