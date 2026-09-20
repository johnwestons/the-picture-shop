local Test = {}
local Lab = require("src.screens.forklift_lift_lab")
local Presentation = require("src.forklift_presentation")

local function near(a, b) return math.abs(a - b) < 0.000001 end
function Test.run(_, check)
    local function test(name, value) check("forklift_lab_" .. name, value) end
    local model = Lab.newModel()
    test("isolated_fixture_has_no_shop_or_inventory", model.state.jobs == nil and model.state.inventory == nil
        and model.state.activeSlot == nil and model.state.forklift.owned and model.state.forklift.operating
        and model.state.forklift.carriedPalletId == nil)
    test("space_commands_real_lift_without_teleport", model:keypressed("space")
        and model.state.forklift.targetForkHeight == 1 and model.state.forklift.forkHeight == 0)
    model:update(1.5)
    test("real_simulation_reaches_mid_height", near(model.state.forklift.forkHeight, 0.5))
    model:keypressed("p")
    model:update(1)
    test("pause_freezes_height", model.paused and near(model.state.forklift.forkHeight, 0.5))
    model:keypressed("p")
    model:keypressed("space")
    model:update(0.5)
    test("space_reverses_real_lift", near(model.state.forklift.forkHeight, 0.3))
    model:keypressed("t")
    model:update(1)
    test("travel_button_uses_configured_height", near(model.state.forklift.forkHeight, 0.08))
    model:keypressed("g")
    model:update(1)
    model:update(0.1, 1, 1)
    test("drive_uses_normalized_domain_motion", near(math.sqrt(model.state.forklift.x ^ 2
        + model.state.forklift.y ^ 2), 8))
    model:advanceToHeight(1)
    local x, y = model.state.forklift.x, model.state.forklift.y
    model:update(0.1, 1, 0)
    test("lab_drive_respects_raised_fork_lock", model.state.forklift.x == x and model.state.forklift.y == y)
    model:keypressed("8")
    test("direction_digit_selects_west", model.state.forklift.direction == "west")
    model:keypressed("right")
    test("direction_wraps_clockwise", model.state.forklift.direction == "northwest")
    model:keypressed("left")
    test("direction_wraps_counterclockwise", model.state.forklift.direction == "west")
    model:keypressed("r")
    test("reset_isolated_fixture", model.state.forklift.direction == "west"
        and model.state.forklift.forkHeight == 0 and model.state.forklift.x == 0)
    for _, size in ipairs({ { 960, 678 }, { 720, 509 }, { 420, 740 } }) do
        local layout = Lab.layout(size[1], size[2])
        local valid = #layout.buttons == 12
        for _, button in ipairs(layout.buttons) do
            valid = valid and button.x >= 0 and button.y >= 0
                and button.x + button.width <= size[1]
                and button.y + button.height <= size[2]
                and button.height >= 44 and button.width >= 44
        end
        test("responsive_touch_targets_" .. size[1], valid)
        local button = layout.buttons[3]
        model:activateAt(button.x + 5, button.y + 5, size[1], size[2])
        test("touch_selects_view_" .. size[1], model.state.forklift.direction == "northeast")
        local catalog = Presentation.reviewCatalog()
        local preview = layout.preview
        local transform = Lab.previewTransform(preview, catalog)
        test("preview_scale_and_two_sided_margin_" .. size[1], transform
            and transform.scale > 0 and transform.scale <= 0.65
            and transform.padding > 0 and transform.extents.above > 0 and transform.extents.below > 0)
        for _, direction in ipairs({ "northwest", "north", "northeast", "east",
            "southeast", "south", "southwest", "west" }) do
            local sheet = catalog[direction]
            for index, frame in ipairs(sheet.frames) do
                local vehicle = { owned = true, operating = true, direction = direction,
                    forkHeight = frame.height, x = transform.x, y = transform.y }
                local plan = Presentation.plan(vehicle,
                    { review = true, scale = transform.scale, catalog = catalog })
                local left = plan.x - plan.originX * plan.scale
                local top = plan.y - plan.originY * plan.scale
                local right = left + plan.source.width * plan.scale
                local bottom = top + plan.source.height * plan.scale
                local epsilon = 0.000001
                test("whole_pose_fits_" .. size[1] .. "_" .. direction .. "_" .. index,
                    left >= preview.x + transform.padding - epsilon
                    and top >= preview.y + transform.padding - epsilon
                    and right <= preview.x + preview.width - transform.padding + epsilon
                    and bottom <= preview.y + preview.height - transform.padding + epsilon
                    and near(plan.x, transform.x) and near(plan.y, transform.y)
                    and near(plan.scale, transform.scale))
            end
        end
    end
    test("invalid_preview_rejected", not Lab.previewTransform({ x = 0, y = 0, width = 100, height = 0 }))
    test("incomplete_preview_catalog_rejected", not Lab.previewTransform(
        { x = 0, y = 0, width = 100, height = 100 }, {}))
    test("outside_touch_ignored", not model:activateAt(-10, -10, 960, 678))
    local expected = "C:/Project/output/warehouse-expansion-v1/forklift-lab-captures"
    test("exact_capture_directory_allowed", Lab.captureDirectoryAllowed(expected, "C:/Project"))
    test("windows_slash_and_case_normalized", Lab.captureDirectoryAllowed(
        "c:\\project\\output\\warehouse-expansion-v1\\forklift-lab-captures", "C:/Project/"))
    test("outside_capture_directory_rejected", not Lab.captureDirectoryAllowed("C:/Other", "C:/Project"))
    test("capture_parent_traversal_rejected", not Lab.captureDirectoryAllowed(
        "C:/Project/output/../output/warehouse-expansion-v1/forklift-lab-captures", "C:/Project"))
    test("capture_path_control_char_rejected", not Lab.captureDirectoryAllowed(expected .. "\n", "C:/Project"))
    test("relative_capture_path_rejected", not Lab.captureDirectoryAllowed(
        "Project/output/warehouse-expansion-v1/forklift-lab-captures", "Project"))
    local names, allValid = {}, true
    for index = 1, 24 do
        local shot = Lab.captureShot(index)
        model:reset()
        model:selectDirection(shot.directionIndex)
        local reached, steps = model:advanceToHeight(shot.height)
        allValid = allValid and reached and steps <= 180 and not names[shot.name]
            and model.state.forklift.direction == shot.direction
        names[shot.name] = true
    end
    test("capture_24_unique_real_simulation_views", allValid)
    test("capture_cycle_bounded", Lab.captureShot(25) == nil and Lab.captureShot(0) == nil)
    test("bad_direction_rejected", not model:selectDirection(0 / 0))
    test("bad_elapsed_time_rejected", not model:update(math.huge))
end

return Test
