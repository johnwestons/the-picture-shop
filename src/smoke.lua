local Suites = require("src.tests.suites")
local CutterIntegration = require("src.tests.cutter_integration_test")
local JobLoopIntegration = require("src.tests.job_loop_integration_test")
local SaveIntegration = require("src.tests.save_integration_test")
local UiIntegration = require("src.tests.ui_integration_test")

local Smoke = {
    active = false,
    completed = false,
    failed = false,
    drawCount = 0,
    report = nil,
    passed = {},
}

local function requested()
    return os.getenv("PICTURE_SHOP_SMOKE") == "1"
end

function Smoke.spriteLabRequested()
    return requested() and os.getenv("PICTURE_SHOP_SPRITE_LAB") == "1"
end

local function writeLine(text)
    if not Smoke.report then return end
    Smoke.report:write(text .. "\n")
    Smoke.report:flush()
end

local function check(name, condition, detail)
    if not condition then
        error(name .. ": " .. tostring(detail or "check failed"))
    end
    if Smoke.passed[name] then error("duplicate smoke check name: " .. name) end
    Smoke.passed[name] = true
    writeLine("PASS " .. name)
end

local function selectComputerTab(screen, state, tabId)
    local arrowX, arrowY = screen.dropdownCenter()
    local opened = screen.mousepressed(state, arrowX, arrowY, 1)
    if not opened or opened.action ~= "dropdown_opened" then return opened end
    local itemX, itemY = screen.tabCenter(tabId)
    return screen.mousepressed(state, itemX, itemY, 1)
end

local function maskHasBothValues(mask)
    if not mask then return false, "mask image data missing" end
    local width, height = mask:getDimensions()
    local white, black = 0, 0
    for y = 0, height - 1, 24 do
        for x = 0, width - 1, 24 do
            local red, green, blue = mask:getPixel(x, y)
            if red > 0.9 and green > 0.9 and blue > 0.9 then
                white = white + 1
            else
                black = black + 1
            end
        end
    end
    return white > 20 and black > 20, "white=" .. white .. " black=" .. black
end

local function routeIsWalkable(mask, route, config)
    if not mask or type(route) ~= "table" or #route < 2 then return false, "route unavailable" end
    local width, height = mask:getDimensions()
    for segment = 1, #route - 1 do
        local startPoint, endPoint = route[segment], route[segment + 1]
        local dx, dy = endPoint.x - startPoint.x, endPoint.y - startPoint.y
        local samples = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 3))
        for sample = 0, samples do
            local ratio = sample / samples
            local x = startPoint.x + dx * ratio
            local y = startPoint.y + dy * ratio
            local pixelX = math.floor(x / config.baseWidth * width)
            local pixelY = math.floor(y / config.baseHeight * height)
            local red, green, blue = mask:getPixel(pixelX, pixelY)
            if red < 0.9 or green < 0.9 or blue < 0.9 then
                return false, string.format("segment=%d point=%.1f,%.1f", segment, x, y)
            end
        end
    end
    return true
end

local function centerOnlyWalkmaskPoint(context, halfWidth, halfHeight)
    for y = 92, context.config.baseHeight - 48, 2 do
        for x = 56, context.config.baseWidth - 56, 2 do
            if context.Navigation.isWalkable(context.assets, x, y, {})
                and not context.Navigation.isAreaWalkable(
                    context.assets, x, y, halfWidth, halfHeight)
            then
                return x, y
            end
        end
    end
end

local function runChecks(context)
    local Context = {
        context = context,
        CutterIntegration = CutterIntegration,
        JobLoopIntegration = JobLoopIntegration,
        SaveIntegration = SaveIntegration,
        UiIntegration = UiIntegration,
        check = check,
        selectComputerTab = selectComputerTab,
        maskHasBothValues = maskHasBothValues,
        routeIsWalkable = routeIsWalkable,
        centerOnlyWalkmaskPoint = centerOnlyWalkmaskPoint,
    }
    require("src.tests.smoke_checks.healthy_1").run(Context)
    require("src.tests.smoke_checks.checks_2").run(Context)
    require("src.tests.smoke_checks.checks_3").run(Context)
    require("src.tests.smoke_checks.checks_4").run(Context)
    require("src.tests.smoke_checks.art_state_a_5").run(Context)
    require("src.tests.smoke_checks.receiving_state_6").run(Context)
    require("src.tests.smoke_checks.checks_7").run(Context)

end

function Smoke.requested()
    return requested()
end

function Smoke.start(context)
    if not requested() then return end
    Smoke.active = true
    local reportPath = os.getenv("PICTURE_SHOP_SMOKE_REPORT") or "smoke-report.rpt"
    local report, errorMessage = io.open(reportPath, "w")
    if not report then
        io.stderr:write("SMOKE_REPORT_ERROR: " .. tostring(errorMessage) .. "\n")
        love.event.quit(1)
        return
    end
    Smoke.report = report
    Smoke.passed = {}
    writeLine("THE_PICTURE_SHOP_SMOKE version=3")

    local ok, message = xpcall(function()
        local focus=os.getenv("PICTURE_SHOP_SMOKE_FOCUS")
        if focus=="performance" then
            runChecks(context)
            for _,name in ipairs({"performance_regression","asset_pack","save_contract",
                "warehouse_save","network_protocol","truck_authority","multiplayer_session","multiplayer_impairment",
                "multiplayer_workshop_reliable","guest_job_journey","employees","employee_schedule",
                "employee_billing","shared_gui","options","sound","pallet_jack_motion",
                "pallet_state","warehouse_controls","warehouse_app_entry","windmill_integration",
                "warehouse_rack_presentation","warehouse_breakroom_presentation",
                "forklift_lift_lab","mechanic_work_presentation","warehouse_construction_presentation",
                "multiplayer_world_layers","camera_follow","computer_viewport"}) do
                require("src.tests."..name.."_test").run(context,check)
            end
        elseif focus=="employee-schedule" then
            require("src.tests.employee_schedule_test").run(context,check)
        elseif focus=="progression" then
            require("src.tests.progression_balance_test").run(context,check)
            require("src.tests.network_protocol_test").run(context,check)
            require("src.tests.shared_gui_test").run(context,check)
            require("src.tests.employees_test").run(context,check)
            require("src.tests.employee_capacity_test").run(context,check)
            require("src.tests.employee_schedule_test").run(context,check)
            require("src.tests.employee_billing_test").run(context,check)
            require("src.tests.shop_workflow_test").run(context,check)
            require("src.tests.press_economics_test").run(context,check)
        elseif focus=="employee-shifts" then
            require("src.tests.employees_test").run(context,check)
            require("src.tests.employee_schedule_test").run(context,check)
            require("src.tests.employee_billing_test").run(context,check)
        elseif focus=="employee-animation" then
            require("src.tests.customer_motion_test").run(context,check)
            require("src.tests.employee_schedule_test").run(context,check)
            require("src.tests.worker_animation_test").run(context,check)
            require("src.tests.outdoor_weather_test").run(context,check)
            check("title_screen_exposes_the_embedded_running_build_version",
                context.title.versionText():match("^v[%w%._%+%-]+$") ~= nil)
        elseif focus=="recent-updates" then
            require("src.tests.recent_updates_test").run(context,check)
        elseif focus=="pallet-jack" then
            require("src.tests.pallet_jack_motion_test").run(context,check)
            require("src.tests.pallet_jack_audit_test").run(context,check)
            require("src.tests.pallet_state_test").run(context,check)
            require("src.tests.pallet_storage_test").run(context,check)
            require("src.tests.machine_relocation_authority_test").run(context,check)
            require("src.tests.machine_relocation_session_test").run(context,check)
            require("src.tests.workshop_authority_test").run(context,check)
            require("src.tests.warehouse_controls_test").run(context,check)
            require("src.tests.network_protocol_test").run(context,check)
            require("src.tests.multiplayer_session_test").run(context,check)
            require("src.tests.warehouse_save_test").run(context,check)
            require("src.tests.save_contract_test").run(context,check)
        elseif focus=="radio-network" then
            require("src.tests.network_protocol_test").run(context,check)
            require("src.tests.multiplayer_session_test").run(context,check)
        elseif focus=="lan-connection" then
            require("src.tests.lan_screen_test").run(context,check)
            require("src.tests.lan_discovery_test").run(context,check)
            require("src.tests.transport_enet_test").run(context,check)
            require("src.tests.keyboard_mobile_test").run(context,check)
            require("src.tests.options_test").run(context,check)
        else
            runChecks(context)
            Suites.runDomain(context, check)
            Suites.verifyAuditCoverage(Smoke.passed, check)
        end
        local maintenancePreview = os.getenv("PICTURE_SHOP_CUTTER_MAINTENANCE_PREVIEW")
        local wrapperMaintenancePreview = os.getenv("PICTURE_SHOP_WRAPPER_MAINTENANCE_PREVIEW")
        local previewTab = os.getenv("PICTURE_SHOP_COMPUTER_ACTIVE_PREVIEW") == "1" and "active"
            or (os.getenv("PICTURE_SHOP_COMPUTER_CALENDAR_PREVIEW") == "1" and "calendar")
            or (os.getenv("PICTURE_SHOP_COMPUTER_INVENTORY_PREVIEW") == "1" and "inventory")
            or (os.getenv("PICTURE_SHOP_COMPUTER_WWW_PREVIEW") == "1" and "www")
            or (os.getenv("PICTURE_SHOP_COMPUTER_EMAIL_PREVIEW") == "1" and "email")
        local pressPreview = os.getenv("PICTURE_SHOP_PRESS_PREVIEW")
        local workPhonePreview = os.getenv("PICTURE_SHOP_WORK_PHONE_PREVIEW")
        if os.getenv("PICTURE_SHOP_WORK_ORDER_PREVIEW") == "1" then
            local previewJob = assert(context.jobs.createOffer({
                id = "JOB-0042", company = "Blue Ridge Packaging",
                sourceSize = { width = 25, height = 19 },
                finishedSize = { width = 12.5, height = 9.5 },
                sheetCounts = { 1000 }, packaging = "boxed", difficulty = "medium",
                artworkKey = "ad-pizza",
                artwork = { key = "ad-pizza", displayName = "Blue Ridge Pizza Card",
                    fileName = "blue-ridge-pizza-final.png", suppliedBy = "client" },
                stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
                    finish = "uncoated", color = "warm white", grain = "long",
                    description = "80 lb customer-supplied cover stock" },
                details = { stockDescription = "80 lb customer-supplied cover stock" },
            }))
            previewJob.status = "in_production"
            previewJob.delivery = previewJob.delivery or {}
            previewJob.delivery.status = "received"
            local pallet = previewJob.pallets[1]
            pallet.location, pallet.status = "warehouse", "raw"
            context.state.jobs.active = { previewJob }
            context.palletWorkOrderScreen.enter({ job = previewJob, pallet = pallet })
            context.state.screen = "pallet_work_order"
        elseif maintenancePreview == "hub" or maintenancePreview == "oil" then
            context.state.screen = "machine"
            context.state.machineType = "cutter"
            context.state.inventory.stock.maintenance_kit = 2
            context.machineScreen.enter()
            local x, y = context.machineScreen.maintenanceCenter()
            context.machineScreen.mousepressed(context.state, x, y, 1)
            if maintenancePreview == "oil" then
                x, y = context.machineScreen.maintenanceTaskCenter("oil")
                context.machineScreen.mousepressed(context.state, x, y, 1)
                for _, action in ipairs({ "disconnect", "key", "tag" }) do
                    x, y = context.machineScreen.lubricationLockoutCenter(action)
                    context.machineScreen.mousepressed(context.state, x, y, 1)
                end
                for _, action in ipairs({ "cartridge", "prime" }) do
                    x, y = context.machineScreen.lubricationPrepCenter(action)
                    context.machineScreen.mousepressed(context.state, x, y, 1)
                end
                x, y = context.machineScreen.lubricationPointCenter("backgauge_left")
                context.machineScreen.mousepressed(context.state, x, y, 1)
                local tx, ty = context.machineScreen.lubricationToolCenter("grease")
                context.machineScreen.mousepressed(context.state, tx, ty, 1)
                context.machineScreen.mousepressed(context.state, x, y, 1)
                tx, ty = context.machineScreen.lubricationPumpCenter()
                context.machineScreen.mousepressed(context.state, tx, ty, 1)
                context.machineScreen.update(0.35)
            end
        elseif wrapperMaintenancePreview == "hub" or wrapperMaintenancePreview == "task" then
            context.state.screen = "machine"
            context.state.machineType = "skid_wrapper"
            context.state.inventory.stock.maintenance_kit = 2
            context.machineScreen.enter()
            local x, y = context.machineScreen.wrapperMaintenanceCenter()
            context.machineScreen.mousepressed(context.state, x, y, 1)
            if wrapperMaintenancePreview == "task" then
                x, y = context.machineScreen.wrapperServiceCenter()
                context.machineScreen.mousepressed(context.state, x, y, 1)
                context.machineScreen.update(0.35)
            end
        elseif pressPreview == "world" then
            context.state.money = 20000
            assert(context.machineFleet.buy(context.state, "dealer", 3))
            context.state.screen = "world"
        elseif pressPreview == "run" or pressPreview == "plates" or pressPreview == "proof"
            or pressPreview == "finished" or (pressPreview and pressPreview:match("^setup_"))
            or pressPreview == "drying"
            or pressPreview == "help"
        then
            local previewJob = assert(context.jobs.createOffer({
                id = "PRESS-PREVIEW", company = "Harbor Pizza Club",
                sourceSize = { width = 10, height = 15 }, finishedSize = { width = 6, height = 9 },
                sheetCounts = { 1050 }, packaging = "flat", difficulty = "medium",
                artworkKey = "ad-pizza",
                artwork = { key = "ad-pizza", displayName = "Harbor Pizza Night Poster",
                    fileName = "harbor-pizza-night-final.png", suppliedBy = "client", orientation = "portrait" },
                stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
                    finish = "uncoated", color = "warm white", grain = "long",
                    description = "80 lb warm-white uncoated cover" },
                press = { colors = 2, coverage = 0.44, artworkSize = { width = 5.4, height = 8.2 },
                    colorSequence = { "Tomato Red", "Black" }, requestedCopies = { 1000 } },
                details = { stockDescription = "80 lb warm-white uncoated cover" },
            }))
            previewJob.status = "in_production"
            local pallet = previewJob.pallets[1]
            pallet.paper.status, pallet.remainingSheets, pallet.finishedSheets = "complete", 0, 1050
            pallet.location, pallet.status = "at_press", "press_setup"
            pallet.press.status, pallet.press.availableSheets = "proof", 1050
            context.state.jobs.active = { previewJob }
            local plates = context.plateService.ensureJob(previewJob)
            for _, plate in ipairs(plates) do
                plate.status, plate.source, plate.quality, plate.mounted = "ready", "in_house", 0.94, true
            end
            local process = context.windmill.ensure(context.state)
            process.jobId, process.palletId, process.colorIndex = previewJob.id, pallet.id, 1
            process.status, process.speed = pressPreview == "run" and "production"
                or pressPreview == "finished" and "pass_complete"
                or (pressPreview and pressPreview:match("^setup_")) and "setup" or "proof", 3000
            process.setup = { chase = 0.91, packing = 0.88, rollers = 0.93,
                ink = 0.86, feeder = 0.92, register = 0.84 }
            process.proofQuality, process.proofApproved, process.artworkVerified = 0.87, false, false
            process.targetSheets, process.feedStart, process.feedRemaining = 1025, 1050, 1049
            process.counter, process.goodSheets, process.spoilage = 1, 0, 1
            process.motor, process.feeder, process.impression = true, true, true
            if pressPreview == "drying" then
                pallet.location, pallet.status = "press_output", "press_setup"
                pallet.press.status, pallet.press.completedColors = "drying", 1
                pallet.press.availableSheets, pallet.press.goodSheets = 1025, 1025
                pallet.press.dryUntilHours = context.businessCalendar.absoluteHours(context.state) + 1
                process.status, process.jobId, process.palletId, process.colorIndex = "idle", nil, nil, nil
                process.setup, process.motor, process.feeder, process.impression = {}, false, false, false
            end
            context.state.screen = "press"
            context.pressScreen.enter(context.state)
            local setupTask = pressPreview and pressPreview:match("^setup_(.+)$")
            context.pressScreen.tab = pressPreview == "drying" and "run"
                or pressPreview == "finished" and "run"
                or setupTask and "setup" or pressPreview
            if setupTask then assert(context.pressScreen.beginSetup(context.state, setupTask)) end
            if pressPreview == "help" then
                context.pressScreen.tutorialStep = math.max(1, math.min(15,
                    tonumber(os.getenv("PICTURE_SHOP_PRESS_HELP_PAGE")) or 4))
            end
        elseif os.getenv("PICTURE_SHOP_COMPUTER_DROPDOWN_PREVIEW") == "1" then
            context.state.screen = "computer"
            context.computerScreen.enter(context.state)
            local x, y = context.computerScreen.dropdownCenter()
            context.computerScreen.mousepressed(context.state, x, y, 1)
        elseif previewTab then
            context.state.screen = "computer"
            context.computerScreen.enter(context.state)
            selectComputerTab(context.computerScreen, context.state, previewTab)
        elseif workPhonePreview == "world" or workPhonePreview == "screen" then
            context.workPhone.ensure(context.state)
            context.state.workPhone.incoming = nil
            assert(context.workPhone.queueCall(context.state, {
                kind = "customer_status", caller = "Blue Ridge Packaging",
                role = "CUSTOMER", subject = "CURRENT JOB QUESTION",
                message = "Where is job JOB-0042, and when will it be done?",
                jobId = "JOB-0042",
            }))
            context.state.screen = workPhonePreview == "screen" and "work_phone" or "world"
            if workPhonePreview == "screen" then
                context.workPhoneScreen.enter(context.state)
            end
        elseif os.getenv("PICTURE_SHOP_WORLD_FAN_PREVIEW") == "1" then
            context.state.screen = "world"
        end
    end, debug.traceback)
    if not ok then
        Smoke.failed = true
        writeLine("FAIL " .. tostring(message))
        io.stderr:write("SMOKE_ERROR: " .. tostring(message) .. "\n")
        io.stderr:flush()
    else
        if os.getenv("PICTURE_SHOP_SMOKE_TITLE_PREVIEW") == "1" then
            context.state.screen = "title"
            context.title.enter(nil, nil, nil)
        elseif os.getenv("PICTURE_SHOP_SMOKE_WEATHER_PREVIEW") == "rain"
            or os.getenv("PICTURE_SHOP_SMOKE_WEATHER_PREVIEW") == "night" then
            local preview = os.getenv("PICTURE_SHOP_SMOKE_WEATHER_PREVIEW")
            local Weather = require("src.outdoor_weather")
            local selectedDay, selectedHour
            for day = 0, 120 do
                local conditions = Weather.conditionsForDay(day)
                if preview == "rain" and conditions.rain then
                    local hour = (conditions.rainStart + conditions.rainEnd) / 2
                    if Weather.daylightForHour(hour) > 0.7 then
                        selectedDay, selectedHour = day, hour
                        break
                    end
                elseif preview == "night" and not conditions.rain then
                    selectedDay, selectedHour = day, 22
                    break
                end
            end
            assert(selectedDay, "no suitable day found for weather preview")
            context.state.calendar.totalDays = selectedDay
            context.state.calendar.elapsed = context.state.calendar.secondsPerDay * selectedHour / 24
            context.world.bayDoor.state, context.world.bayDoor.progress = "open", 1
            context.state.screen = "world"
        end
        Smoke.completed = true
        writeLine("CHECKS_COMPLETE")
    end
end

function Smoke.drawn()
    if not Smoke.active then return end
    Smoke.drawCount = Smoke.drawCount + 1
    if Smoke.drawCount == 1 and os.getenv("PICTURE_SHOP_SMOKE_SCREENSHOT") == "1" then
        love.graphics.captureScreenshot("smoke-preview.png")
    end
    if Smoke.failed then
        if Smoke.report then Smoke.report:close() end
        love.event.quit(1)
    elseif Smoke.completed and Smoke.drawCount >= 3 then
        writeLine("PASS render_three_frames")
        writeLine(Smoke.spriteLabRequested() and "SMOKE_OK_SPRITE_LAB" or "SMOKE_OK")
        Smoke.report:close()
        Smoke.report = nil
        print("SMOKE_OK: module checks and three draw frames completed")
        io.flush()
        if Smoke.spriteLabRequested() then
            Smoke.active = false
        else
            love.event.quit(0)
        end
    end
end

return Smoke
