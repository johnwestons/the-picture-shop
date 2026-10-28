local Animation = require("src.character_animation")
local HighFiveArt = require("src.high_five_art")
local Lab = require("src.screens.sprite_motion_lab")
local Catalog = require("src.worker_catalog")
local Renderer = require("src.employee_renderer")
local Config = require("src.config")
local Test = {}

function Test.run(context, check)
    local assets = context.characterAssets
    local rectangularLayout = {
        frameWidth = 256, frameHeight = 352, columns = 16, rows = 2,
        frameCount = 32, normalizationHeight = 205,
    }
    local rectangularGrid = assets.frameGrid(4096, 704, rectangularLayout, 512)
    local squareGrid = assets.frameGrid(4096, 512, nil, 512)
    local lastTopRowFrame = rectangularGrid and assets.frameRectFor(16, rectangularGrid)
    local firstBottomRowFrame = rectangularGrid and assets.frameRectFor(17, rectangularGrid)
    local lastFrame = rectangularGrid and assets.frameRectFor(32, rectangularGrid)
    check("character_assets_accept_rectangular_multrow_walk_atlases",
        rectangularGrid and rectangularGrid.frameCount == 32
            and lastTopRowFrame and lastTopRowFrame.x == 3840 and lastTopRowFrame.y == 0
            and firstBottomRowFrame and firstBottomRowFrame.x == 0 and firstBottomRowFrame.y == 352
            and lastFrame and lastFrame.x == 3840 and lastFrame.y == 352
            and lastFrame.width == 256 and lastFrame.height == 352)
    check("character_assets_reject_misaligned_rectangular_walk_atlases",
        assets.frameGrid(4095, 704, rectangularLayout, 512) == nil
            and assets.frameRectFor(33, rectangularGrid) == nil
            and assets.frameGrid(4096, 704, { frameWidth = 0, frameHeight = 352 }, 512) == nil
            and assets.frameGrid(4096, 704, { frameWidth = 256, frameHeight = 352, frameCount = 31 }, 512) == nil)
    check("character_assets_keep_legacy_square_strip_frame_layouts",
        squareGrid and squareGrid.frameCount == 8 and squareGrid.columns == 8
            and squareGrid.rows == 1 and assets.frameRectFor(8, squareGrid).x == 3584)
    local northMetadata = assets.metadata["rabbit-worker"].walk_north
    check("character_asset_metadata_exposes_the_legacy_quad_grid",
        northMetadata and northMetadata.columns == 8 and northMetadata.rows == 1
            and assets.frameRectFor(8, northMetadata).x == 3584)
    assets.metadata["rabbit-worker"].walk_north = {
        visibleHeight = 352, normalizationHeight = rectangularGrid and rectangularGrid.normalizationHeight,
    }
    local normalization = assets.getNormalization("rabbit-worker", "walk_north")
    assets.metadata["rabbit-worker"].walk_north = northMetadata
    check("extended_gait_reach_keeps_the_neutral_body_core_scale",
        rectangularGrid and math.abs(normalization - Config.characterRendering.referenceHeight / 205) < 0.0001)
    local image, quad, count = assets.get("rabbit-worker", "high_five", 1)
    check("high_five_eight_authored_poses_load", image and quad and count == 8)
    local elapsed, sequence = 0, true
    for frame, weight in ipairs(HighFiveArt.durationWeights) do
        sequence = sequence and Animation.frameForHighFive(count, (elapsed + weight / 2) * .95, .95) == frame
        local ax, ay = assets.getAnchor("rabbit-worker", "high_five", frame)
        sequence = sequence and ax == 256 and ay == 465
        elapsed = elapsed + weight
    end
    check("high_five_anticipates_contacts_and_recovers_with_planted_feet", sequence and math.abs(elapsed - 1) < .0001)
    check("high_five_contact_is_brief", HighFiveArt.durationWeights[5] * .95 <= .10)
    check("high_five_stays_settled_after_one_shot", Animation.frameForHighFive(8, 4, .95) == 8
        and Animation.frameForHighFive(8, -.1, .95) == 1)

    local consistent=true
    for _,spacing in ipairs({13,20}) do
        for _,count in ipairs({8,16,24}) do
            local subdivision=count/8
            for phase=0,7 do
                local distance=phase*spacing+.001
                consistent=consistent and Animation.frameForGait(count,distance,spacing)==phase*subdivision+1
            end
            for drawing=0,count-1 do
                consistent=consistent and Animation.frameForGait(count,(drawing+.1)*spacing*8/count,spacing)==drawing+1
            end
            consistent=consistent and Animation.frameForGait(count,spacing*8,spacing)==1
                and Animation.frameForGait(count,0,spacing)==Animation.frameForGait(count,-4,spacing)
        end
    end
    check("authored_inbetweens_subdivide_the_same_eight_pose_stride",consistent)
    check("subdivided_samples_preserve_the_requested_physical_cycle",Animation.frameForPlayerAction("walk_north",16,80,100,20,.65)==9
        and Animation.frameForPalletJackPush(16,true,80,20)==9
        and Animation.frameForPalletJackPush(16,false,80,20)==3)
    local entry={worker={character="cat-worker"},actor={phase="walking",moving=true,
        intentX=0,intentY=1,distance=13*4,idleClock=0}}
    local sixteen={getFrameCount=function() return 16 end}
    local action,frame=Renderer.pose(entry,sixteen)
    check("employee_renderer_uses_the_loaded_walk_count_without_lengthening_stride",action=="walk_south" and frame==9)
    entry.actor.phase="pushing";entry.actor.jackDistance=Config.palletJack.gaitPixelsPerFrame*4
    action,frame=Renderer.pose(entry,sixteen)
    check("employee_renderer_uses_the_loaded_push_count_and_jack_stride",action=="push_south" and frame==9)
    entry.actor.moving=false
    check("employee_expanded_push_keeps_the_canonical_planted_stance",select(2,Renderer.pose(entry,sixteen))==3)
    local resident=assets.cachedTextureBytes()
    check("frame_count_metadata_reads_do_not_load_textures",assets.getFrameCount("rabbit-worker","push")==16
        and assets.getFrameCount("missing","walk")==0 and assets.cachedTextureBytes()==resident)

    Lab.enter(assets)
    for index, name in ipairs(assets.characterNames()) do
        if name == "cat-worker" then Lab.selected = index end
    end
    Lab.update(.1, assets)
    check("sprite_lab_uses_the_employees_real_movement_profile", Lab.distance > 0
        and Lab.distance <= Catalog.motion.speed * 1.06 * .1)
    Lab.distance=Config.palletJack.gaitPixelsPerFrame*4
    local playerPreview=Lab.frameForAction("push",16,"rabbit-worker")
    Lab.distance=Config.palletJack.gaitPixelsPerFrame*4
    check("sprite_lab_pushes_match_runtime_stride_for_player_and_workers",playerPreview==9
        and Lab.frameForAction("push_south",8,"cat-worker")==5)
    Lab.clock=2/.65-.07
    check("sprite_lab_planted_push_idle_is_not_treated_as_a_walk",not Animation.isWalkAction("push_idle")
        and not Animation.isWalkAction("push_south_idle") and Lab.frameForAction("push_idle",2,"rabbit-worker")==2)
    Lab.keypressed("tab", assets)
    local before = Lab.selected
    Lab.keypressed("down", assets)
    check("sprite_lab_can_review_individual_worker_actions", Lab.mode == "actions"
        and Lab.selectedAction == 2 and Lab.selected == before)
    Lab.enter(assets)
end

return Test
