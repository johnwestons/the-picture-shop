local State=require('src.state')
local Residents=require('src.home_residents')
local Apartments=require('src.client_apartments')
local Schema=require('src.save_schema')
local Catalog=require('src.home_catalog')
local Test={}

function Test.run(_,check)
    for _,hostApartment in ipairs(Catalog.ORDER) do
        local state=State.new()
        state.home=assert(require('src.home').new({apartmentId=hostApartment}))
        local host={id=1,name='Host',sceneId='warehouse'}
        local assigned,players={},{}
        for i=1,3 do
            local player={id=i+1,name='Client '..i,sceneId='warehouse'}
            players[#players+1]=player
            local id=assert(Residents.bind(state,player,string.rep(tostring(i),64),{host}))
            local resident=state.home.residents[id]
            assigned[resident.apartmentId]=true
            check('client_apartment_slot_'..hostApartment..'_'..i,
                resident.clientSlot==i and resident.apartmentId~=hostApartment
                    and Apartments.forPlayer(state,player)==resident.apartmentId)
        end
        local count=0
        for apartmentId in pairs(assigned) do
            count=count+1
            check('client_apartment_unique_'..hostApartment..'_'..apartmentId,
                Catalog.APARTMENTS[apartmentId]~=nil)
        end
        check('client_apartment_all_four_owned_'..hostApartment,count==3 and Apartments.valid(state.home))
        local extra={id=4,name='Fourth client',sceneId='warehouse'}
        local rejected=Residents.bind(state,extra,string.rep('4',64),{host})
        check('client_apartment_fourth_saved_client_rejected_'..hostApartment,
            rejected==nil and state.home.residents['guest-4']==nil)
        local firstApartment=state.home.residents['guest-1'].apartmentId
        local returning={id=2,name='Returning client',sceneId='warehouse'}
        local id=assert(Residents.bind(state,returning,string.rep('1',64),{host}))
        check('client_apartment_reconnect_keeps_slot_'..hostApartment,
            id=='guest-1' and state.home.residents[id].clientSlot==1
                and Apartments.forPlayer(state,returning)==firstApartment)
        local private=state.home.clientHomes[id]
        private.balanceCents=4321
        for key,row in pairs(state.home.residents) do
            if key~='owner' then row.activePlayerId=nil end
        end
        local newToken=string.rep('a',64)
        local unknown=assert(Residents.profileOptions(state,newToken,{host}))
        check('client_profile_unknown_lists_claimable_saves_'..hostApartment,
            not unknown.matched and #unknown.choices==3 and not unknown.canCreate)
        local newDevice={id=2,name='Replacement device',sceneId='warehouse'}
        local claimed=assert(Residents.bind(state,newDevice,newToken,{host},1))
        local matched=assert(Residents.profileOptions(state,newToken,{host}))
        local oldIdentity=assert(Residents.profileOptions(state,string.rep('1',64),{host}))
        check('client_profile_host_claim_preserves_progress_'..hostApartment,
            claimed==id and newDevice.homeResidentId==id
                and state.home.residents[id].apartmentId==firstApartment
                and state.home.clientHomes[id]==private and private.balanceCents==4321)
        check('client_profile_claim_rebinds_identity_'..hostApartment,
            matched.matched and matched.matchedSlot==1 and not oldIdentity.matched)
        local duplicate=Residents.bind(state,{id=3,name='Duplicate',sceneId='warehouse'},newToken,
            {host,newDevice})
        check('client_profile_claim_cannot_connect_twice_'..hostApartment,duplicate==nil)
        local saved,reason=Schema.snapshot(state)
        check('client_apartment_host_save_valid_'..hostApartment,saved~=nil,
            tostring(reason)..' home='..tostring(require('src.home').valid(state.home))
                ..' private='..tostring(require('src.client_households').valid(state.home)))
    end
end

return Test
