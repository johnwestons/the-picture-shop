local Home=require('src.home')
local Gear=require('src.commute.gear')
local Outfit=require('src.commute.outfit')
local Residents=require('src.home_residents')
local Test={}
function Test.run(check)
    local state={home=assert(Home.new(nil,0))}
    local player={id=1,homeResidentId='owner',sceneId='home'}
    check('commute_old_households_need_no_gear_migration',Home.valid(state.home) and Outfit.allowed(state,player,'household'))
    check('commute_outfit_tolerates_missing_player_or_state',Outfit.get(nil,player)==nil and Outfit.get(state,nil)==nil)
    local gear=Gear.new();assert(Gear.begin(gear,'equip',{nearBike=true}));Gear.update(gear,4)
    assert(Outfit.store(state,player,gear))
    local normalized=assert(Home.normalize(state.home,0))
    check('commute_suited_outfit_survives_household_normalization',normalized.residents.owner.ridingGear.outfit=='geared')
    for _,command in ipairs({'eat:floor','bottle:floor','rest:floor'}) do
        local okay,code=Residents.command(state,player,command)
        check('commute_suit_blocks_authoritative_home_action_'..command,not okay and code=='riding_gear')
    end
    Residents.recover(state)
    local _,gearReason=Gear.allowed(gear,'household')
    local furnitureOkay,furnitureReason=require('src.home_furniture').command(state,player,'permission:move:1',{})
    local deliveryOkay,deliveryReason=require('src.home_shopping').collect(state,player)
    check('commute_suit_blocks_direct_furniture_commands',not furnitureOkay and furnitureReason==gearReason)
    check('commute_suit_blocks_direct_delivery_collection',not deliveryOkay and deliveryReason==gearReason)
    check('commute_home_recovery_does_not_remove_suit',Outfit.get(state,player).outfit=='geared')
    player.sceneId='warehouse'
    check('commute_scene_change_retains_suit',Outfit.get(state,player).outfit=='geared')
    assert(Gear.begin(state.home.residents.owner.ridingGear,'remove',{}))
    normalized=assert(Home.normalize(state.home,0))
    check('commute_household_snapshot_rolls_back_partial_removal',normalized.residents.owner.ridingGear.outfit=='geared'
        and normalized.residents.owner.ridingGear.transition==nil)
    Gear.update(state.home.residents.owner.ridingGear,3)
    check('commute_removed_suit_restores_home_action_permission',Outfit.allowed(state,player,'household'))
    state.home.residents.owner.ridingGear.mounted=true
    check('commute_household_schema_rejects_incomplete_gear_rider',not Home.valid(state.home))
end
return Test
