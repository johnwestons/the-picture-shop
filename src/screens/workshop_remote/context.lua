-- Remote console state, dependencies, and layout.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.BackButton = require("src.screens.back_button")
    Runtime.Config = require("src.config")
    Runtime.CutterPresentation = require("src.screens.cutter_presentation")
    Runtime.MachineScreen = require("src.screens.machine_screen")
    Runtime.JobService = require("src.job_service")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.MachineResource = require("src.machine_resource_id")
    Runtime.PressSetupGames = require("src.press_setup_games")
    Runtime.Ui = require("src.screens.ui")
    Runtime.Wrapper = require("src.wrapper")
    Runtime.WorkPhoneScreen = require("src.screens.work_phone_screen")
    Runtime.ComputerScreen = require("src.screens.computer_screen")
    Runtime.Projection = require("src.screens.gui_projection")
    Runtime.OfficeIntent = require("src.office_intent")
    Runtime.SharedMachineGui = require("src.screens.shared_machine_gui")
    Runtime.SharedPressGui = require("src.screens.shared_press_gui")
    Runtime.VendorScreen = require("src.screens.vendor_screen")
    Runtime.JobOfferScreen = require("src.screens.job_offer_screen")
    Runtime.TruckScreen = require("src.screens.truck_inventory_screen")
    Runtime.request = nil
    Runtime.utf8 = require("utf8")

    Runtime.Screen = {
        resourceId = nil,
        leaseResourceId = nil,
        leaseId = nil,
        revision = 0,
        workshopTick = 0,
        view = nil,
        quoteText = "",
        quoteFocused = false,
        quoteReplaceOnType = true,
        selectedJobId = nil,
        selectedPalletId = nil,
        waiting = false,
        safetyWaiting = false,
        status = "",
        gaugeText = "0.00",
        gaugeFocused = false,
        gaugeReplaceOnType = true,
        cutterTab = "production",
        cutterPresentation = Runtime.CutterPresentation.new(),
        wrapperTab = "production",
        wrapperClock = 0,
        windmillTab = "run",
        windmillJobId = nil,
        windmillPlateId = nil,
    }

    Runtime.PANEL = { x = 92, y = 44, width = 776, height = 590 }
    Runtime.BACK = { x = 714, y = 58, width = 126, height = 40 }
    Runtime.QUOTE_INPUT = { x = 566, y = 452, width = 180, height = 42 }
    Runtime.DECLINE = { x = 246, y = 538, width = 174, height = 48 }
    Runtime.CONFIRM = { x = 540, y = 538, width = 174, height = 48 }
    Runtime.ROW_X, Runtime.ROW_Y, Runtime.ROW_W, Runtime.ROW_H, Runtime.ROW_GAP = 142, 174, 676, 48, 8
    Runtime.TRUCK_PREVIOUS = { x = 142, y = 372, width = 150, height = 42 }
    Runtime.TRUCK_NEXT = { x = 668, y = 372, width = 150, height = 42 }

    Runtime.WRAPPER_TABS = {
        production = { x = 142, y = 124, width = 328, height = 34 },
        service = { x = 490, y = 124, width = 328, height = 34 },
    }
    Runtime.WRAPPER_SERVICE_BEGIN = { x = 250, y = 472, width = 460, height = 58 }
    Runtime.WRAPPER_SERVICE_CANCEL = { x = 142, y = 548, width = 174, height = 40 }
    Runtime.WRAPPER_SERVICE_WORK = { x = 142, y = 202, width = 476, height = 294 }

    Runtime.CUTTER_SCENE = { x = 464, y = 120, width = 364, height = 243 }
    Runtime.CUTTER_GAUGE_INPUT = { x = 122, y = 230, width = 106, height = 42 }
    Runtime.CUTTER_CONTROLS = {
        gauge_set = { x = 236, y = 230, width = 78, height = 42 },
        auto_gauge = { x = 322, y = 230, width = 100, height = 42 },
        save_gauge = { x = 122, y = 280, width = 144, height = 42 },
        recall_gauge = { x = 278, y = 280, width = 144, height = 42 },
        rotate_paper = { x = 122, y = 374, width = 222, height = 44 },
        position_paper = { x = 356, y = 374, width = 222, height = 44 },
        set_clamp = { x = 590, y = 374, width = 222, height = 44 },
        set_barrier = { x = 122, y = 424, width = 222, height = 44 },
        reset_safety = { x = 356, y = 424, width = 222, height = 44 },
        emergency_stop = { x = 590, y = 424, width = 222, height = 44 },
        return_to_pallet = { x = 122, y = 474, width = 339, height = 42 },
        run_next_lift = { x = 473, y = 474, width = 339, height = 42 },
        cut_left = { x = 122, y = 526, width = 339, height = 62 },
        cut_right = { x = 473, y = 526, width = 339, height = 62 },
        load_stock = { x = 298, y = 354, width = 338, height = 46 },
    }

    Runtime.CUTTER_UNLOADED_CONTROLS = {
        load_stock = { x = 122, y = 374, width = 222, height = 44 },
        set_barrier = { x = 356, y = 374, width = 222, height = 44 },
        reset_safety = { x = 590, y = 374, width = 222, height = 44 },
        run_next_lift = { x = 122, y = 430, width = 456, height = 48 },
        emergency_stop = { x = 590, y = 430, width = 222, height = 48 },
    }

    Runtime.CUTTER_PROGRAMS = {
        { x = 122, y = 182, width = 68, height = 40 },
        { x = 200, y = 182, width = 68, height = 40 },
        { x = 278, y = 182, width = 68, height = 40 },
        { x = 356, y = 182, width = 68, height = 40 },
    }

    Runtime.CUTTER_SERVICE_NAV = { x = 638, y = 548, width = 174, height = 40 }
    Runtime.CUTTER_SERVICE_CONTROLS = {
        lubrication = { x = 122, y = 210, width = 324, height = 54 },
        blade = { x = 488, y = 210, width = 324, height = 54 },
        technician = { x = 122, y = 292, width = 324, height = 54 },
        weekly = { x = 488, y = 292, width = 324, height = 54 },
        advance = { x = 222, y = 286, width = 516, height = 66 },
        pump = { x = 122, y = 430, width = 210, height = 48 },
        gear = { x = 350, y = 430, width = 210, height = 48 },
        finish = { x = 578, y = 430, width = 234, height = 48 },
        cancel = { x = 122, y = 548, width = 174, height = 40 },
        bladeAction = { x = 250, y = 360, width = 460, height = 60 },
    }

    Runtime.CUTTER_SERVICE_VIEWS = { "REAR", "FRONT", "SIDE", "GEAR", "CENTRAL" }
    Runtime.CUTTER_SERVICE_TOOLS = { "RAG", "GREASE", "INSPECT", "GEAR OIL" }

    function Runtime.cutterServiceViewRect(index)
        return { x = 122 + (index - 1) * 140, y = 200, width = 128, height = 38 }
    end

    function Runtime.cutterServiceToolRect(index)
        return { x = 122 + (index - 1) * 175, y = 252, width = 162, height = 38 }
    end

    function Runtime.cutterServiceItemRect(index)
        return { x = 122, y = 310 + (index - 1) * 52, width = 690, height = 44 }
    end

    function Runtime.cutterBladeBoltRect(index)
        return { x = 162 + (index - 1) * 170, y = 260, width = 126, height = 54 }
    end

    Runtime.WINDMILL_TAB_ORDER = { "run", "plates", "setup", "service" }
    Runtime.WINDMILL_TABS = {
        run = { x = 112, y = 124, width = 172, height = 34 },
        plates = { x = 292, y = 124, width = 172, height = 34 },
        setup = { x = 472, y = 124, width = 172, height = 34 },
        service = { x = 652, y = 124, width = 176, height = 34 },
    }

    Runtime.WINDMILL_RUN_CONTROLS = {
        toggle_motor = { x = 112, y = 252, width = 116, height = 42 },
        toggle_feeder = { x = 236, y = 252, width = 116, height = 42 },
        toggle_impression = { x = 360, y = 252, width = 132, height = 42 },
        speed_down = { x = 500, y = 252, width = 92, height = 42 },
        speed_up = { x = 600, y = 252, width = 92, height = 42 },
        emergency_stop = { x = 700, y = 252, width = 128, height = 42 },
        reset_safety = { x = 112, y = 302, width = 120, height = 42 },
        take_proof = { x = 240, y = 302, width = 140, height = 42 },
        verify_artwork = { x = 388, y = 302, width = 140, height = 42 },
        approve_proof = { x = 536, y = 302, width = 140, height = 42 },
        run = { x = 684, y = 302, width = 144, height = 42 },
        clean_unload = { x = 112, y = 352, width = 220, height = 44 },
    }

    Runtime.WINDMILL_PLATE_CONTROLS = {
        order_plate = { x = 112, y = 430, width = 220, height = 46 },
        begin_plate = { x = 354, y = 430, width = 220, height = 46 },
        process_plate = { x = 596, y = 430, width = 232, height = 46 },
    }

    Runtime.WINDMILL_SERVICE_CONTROLS = {
        begin_service = { x = 180, y = 432, width = 280, height = 50 },
        book_technician = { x = 500, y = 432, width = 280, height = 50 },
        service_lockout = { x = 260, y = 338, width = 440, height = 58 },
        service_task = { x = 260, y = 338, width = 440, height = 72 },
    }

    Runtime.WINDMILL_SETUP_TASKS = { "chase", "packing", "rollers", "ink", "feeder", "register" }

    function Runtime.windmillCandidateRect(index)
        return { x = 112, y = 430 + (index - 1) * 42, width = 716, height = 34 }
    end

    function Runtime.windmillPlateJobRect(index)
        return { x = 112, y = 184 + (index - 1) * 42, width = 220, height = 36 }
    end

    function Runtime.windmillPlateRect(index)
        return { x = 344, y = 184 + (index - 1) * 48, width = 484, height = 42 }
    end

    function Runtime.windmillSetupTaskRect(index)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        return { x = 112 + column * 366, y = 198 + row * 82, width = 350, height = 64 }
    end

    function Runtime.windmillSetupControlRect(task, index)
        local controls = Runtime.PressSetupGames.controls(task)
        local gap, totalWidth = 8, 716
        local width = math.floor((totalWidth - gap * (#controls - 1)) / math.max(1, #controls))
        return { x = 112 + (index - 1) * (width + gap), y = 350, width = width, height = 50 }
    end

    Runtime.WINDMILL_SETUP_CANCEL = { x = 330, y = 426, width = 300, height = 48 }

    function Runtime.cutterCandidateRect(index)
        return {
            x = 122,
            y = 206 + (index - 1) * 50,
            width = 318,
            height = 44,
        }
    end

    function Runtime.contains(rect, x, y)
        return Runtime.Ui.contains(rect, x, y)
    end

    function Runtime.button(rect, label, pointerX, pointerY, enabled, green)
        local hovered = enabled and pointerX and pointerY and Runtime.contains(rect, pointerX, pointerY)
        if not enabled then
            love.graphics.setColor(0.24, 0.27, 0.29)
        elseif green then
            love.graphics.setColor(hovered and 0.18 or 0.11, hovered and 0.58 or 0.45, 0.29)
        else
            love.graphics.setColor(hovered and 0.72 or 0.57, hovered and 0.28 or 0.20, 0.18)
        end
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
        love.graphics.setColor(enabled and 0.98 or 0.60, enabled and 0.98 or 0.63,
            enabled and 0.96 or 0.65)
        love.graphics.printf(label, rect.x, rect.y + math.floor(rect.height / 2) - 6,
            rect.width, "center")
    end

    function Runtime.header(title, subtitle, pointerX, pointerY, assets)
        love.graphics.setColor(0.01, 0.02, 0.03, 0.76)
        love.graphics.rectangle("fill", 0, 0, Runtime.Config.baseWidth, Runtime.Config.baseHeight)
        love.graphics.setColor(0.91, 0.90, 0.83)
        love.graphics.rectangle("fill", Runtime.PANEL.x, Runtime.PANEL.y, Runtime.PANEL.width, Runtime.PANEL.height, 6, 6)
        love.graphics.setColor(0.16, 0.21, 0.24)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", Runtime.PANEL.x, Runtime.PANEL.y, Runtime.PANEL.width, Runtime.PANEL.height, 6, 6)
        love.graphics.rectangle("fill", Runtime.PANEL.x, Runtime.PANEL.y, Runtime.PANEL.width, 72, 6, 6)
        love.graphics.setColor(0.97, 0.84, 0.30)
        love.graphics.printf(title, Runtime.PANEL.x + 16, Runtime.PANEL.y + 14, Runtime.PANEL.width - 32, "center")
        love.graphics.setColor(0.82, 0.87, 0.88)
        love.graphics.printf(subtitle, Runtime.PANEL.x + 16, Runtime.PANEL.y + 40, Runtime.PANEL.width - 32, "center")
        Runtime.BackButton.draw(assets, Runtime.BACK, "BACK", pointerX, pointerY,
            Runtime.Screen.waiting or Runtime.Screen.safetyWaiting)
    end
end

return Component
