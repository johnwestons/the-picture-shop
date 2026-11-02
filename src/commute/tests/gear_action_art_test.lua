local Art = require('src.commute.gear_action_art')
local Gear = require('src.commute.gear')

local Test = {}
function Test.run(check)
    local registration = Art.registration
    local actions = {'suit_on', 'zip_up', 'boots_gloves', 'helmet_on'}
    local expectedDurations = {suit_on=1.2, zip_up=.8, boots_gloves=.7, helmet_on=1}
    local okay = registration.status == 'staged_unapproved'
        and registration.direction == 'southeast'
        and registration.character == 'rabbit-worker'
        and registration.anchor[1] == 128 and registration.anchor[2] == 238
    for _, name in ipairs(actions) do
        local action = registration.actions[name]
        okay = okay and action ~= nil
            and action.duration == expectedDurations[name]
            and action.frameCount == 4 and #action.frames == 4
            and action.normalizationHeight > 0
        for _, frame in ipairs(action.frames or {}) do
            okay = okay and frame.groundAnchor[1] == registration.anchor[1]
                and frame.groundAnchor[2] == registration.anchor[2]
        end
    end
    local helmet = registration.actions.helmet_on
    okay = okay and helmet.frames[3].furMaskPixels == 0
        and helmet.frames[4].furMaskPixels == 0
        and helmet.frames[3].overallsMaskPixels == 0
        and helmet.frames[4].overallsMaskPixels == 0
    check('commute_gear_action_art_stays_review_only_and_ground_registered', okay)

    local suit = registration.actions.suit_on
    check('commute_gear_action_art_manual_anchors_track_planted_suit_on_shoes',
        suit.frames[1].groundAnchorMethod == 'manual_planted_foot'
        and suit.frames[2].groundAnchorMethod == 'manual_planted_foot'
        and suit.frames[1].sourceGroundAnchor[1] == 151
        and suit.frames[1].sourceGroundAnchor[2] == 488
        and suit.frames[2].sourceGroundAnchor[1] == 566
        and suit.frames[2].sourceGroundAnchor[2] == 488)

    local progressOkay = true
    for _, name in ipairs(actions) do
        progressOkay = progressOkay and Art.frameForProgress(name, 0) == 1
            and Art.frameForProgress(name, .25) == 2
            and Art.frameForProgress(name, .5) == 3
            and Art.frameForProgress(name, .75) == 4
            and Art.frameForProgress(name, 1) == 4
    end
    check('commute_gear_action_art_uses_each_gear_pose_progress', progressOkay)

    check('commute_gear_action_art_requires_matching_rabbit_identity',
        Art.supportsAppearance({character='rabbit-worker', furColorway=4, overallsColorway=5})
        and not Art.supportsAppearance({character='business-fox'})
        and not Art.supportsAppearance(nil))

    check('commute_gear_action_art_does_not_fake_missing_removal_art',
        registration.actions.helmet_off == nil and registration.actions.unzip == nil and registration.actions.suit_off == nil
        and Gear.poseNames.helmet_off and Gear.poseNames.unzip and Gear.poseNames.suit_off)

    local scale = Art.normalization('suit_on')
    check('commute_gear_action_art_normalizes_to_rabbit_reference_height',
        scale ~= nil and scale > 1 and scale < 1.4)
end

return Test
