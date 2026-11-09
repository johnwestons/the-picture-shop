local Gear=require('src.commute.gear')
local Test={}
local beside={nearBike=true,safeFooting=true,speed=0}
function Test.run(check)
    local g=Gear.new()
    check('commute_gear_normal_cannot_mount',not Gear.begin(g,'mount',beside))
    check('commute_gear_equip_requires_parked_bike',not Gear.begin(g,'equip',{}))
    assert(Gear.begin(g,'equip',beside))
    check('commute_gear_visible_suit_first',Gear.pose(g)=='suit_on' and not Gear.allowed(g,'walk'))
    Gear.update(g,1.2);check('commute_gear_visible_zip_second',Gear.pose(g)=='zip_up')
    Gear.update(g,.8);check('commute_gear_boots_gloves_before_helmet',Gear.pose(g)=='boots_gloves')
    Gear.update(g,.7);check('commute_gear_helmet_last',Gear.pose(g)=='helmet_on')
    check('commute_gear_interrupted_dressing_cannot_ride',Gear.restore(Gear.snapshot(g)).outfit=='normal'
        and not Gear.allowed(g,'ride') and not Gear.begin(g,'mount',beside))
    Gear.update(g,1.01)
    check('commute_gear_suited_walk_and_door_allowed',Gear.allowed(g,'walk') and Gear.allowed(g,'door') and g.outfit=='geared')
    check('commute_gear_blocks_food_and_household_actions',not Gear.allowed(g,'eat') and not Gear.allowed(g,'household'))
    assert(Gear.begin(g,'mount',beside));Gear.update(g,.8)
    check('commute_gear_ignition_precedes_driving',Gear.pose(g)=='ignition' and not Gear.allowed(g,'ride'))
    Gear.update(g,1);check('commute_gear_full_equipment_drives',Gear.allowed(g,'ride') and not Gear.allowed(g,'door'))
    check('commute_gear_no_removal_or_dismount_at_speed',not Gear.begin(g,'remove',beside)
        and not Gear.begin(g,'dismount',{speed=5,safeFooting=true}))
    check('commute_gear_dismount_requires_clear_footing',not Gear.begin(g,'dismount',{}))
    assert(Gear.begin(g,'dismount',beside));local restored=Gear.restore(Gear.snapshot(g))
    check('commute_gear_interrupted_dismount_safe_and_suited',not restored.mounted and not restored.engine and restored.outfit=='geared')
    Gear.update(g,1.2)
    check('commute_gear_dismount_retains_equipment',g.outfit=='geared' and Gear.allowed(g,'walk'))
    assert(Gear.begin(g,'remove',{}));Gear.update(g,.8)
    check('commute_gear_removal_has_visible_unzip',Gear.pose(g)=='unzip')
    check('commute_gear_interrupted_removal_retains_stable_outfit',Gear.restore(Gear.snapshot(g)).outfit=='geared')
    Gear.update(g,2)
    check('commute_gear_explicit_removal_restores_actions',g.outfit=='normal' and Gear.allowed(g,'eat'))
    local corrupt=Gear.new();corrupt.mounted=true;corrupt.engine=true
    check('commute_gear_rejects_unprotected_saved_rider',not Gear.valid(corrupt) and Gear.restore(corrupt)==nil)
    corrupt=Gear.new();corrupt.transition={kind='mount',elapsed=.1}
    check('commute_gear_rejects_forged_incomplete_mount',not Gear.valid(corrupt) and Gear.restore(corrupt)==nil)
end
return Test
