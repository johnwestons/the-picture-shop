-- Workshop resource, command, and state allowlists.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.WORKSHOP_RESOURCES = {
        warehouse = true,
        work_phone = true,
        reception_customer = true,
        vendor = true,
        truck = true,
        office_computer = true,
        skid_wrapper = true,
        pallet_jack = true,
        cutter = true,
        windmill = true,
    }

    Runtime.WORKSHOP_ACTION_ARGUMENTS = {
        warehouse = { warehouse_action = "warehouseIntent" },
        reception_customer = {
            request_details = false,
            submit_quote = "amount",
            decline = false,
        },
        vendor = {
            purchase_stock = "itemIndex",
            purchase_machine = "itemIndex",
            dismiss = false,
        },
        truck = {
            move_item = "itemIndex",
            page_next = false,
            page_previous = false,
            close_truck = false,
        },
        office_computer = {
            request_pickup = "jobId",
            office_action = "officeIntent",
        },
        work_phone = { phone_answer = "callId", phone_respond = "callId", phone_dismiss = "callId" },
        skid_wrapper = {
            select_pallet = "palletId",
            start_cycle = "palletId",
            begin_service = false,
            service_target = "itemIndex",
            service_miss = false,
            cancel_service = false,
        },
        pallet_jack = {
            warehouse_action = "warehouseIntent",
            lift_pallet = "palletId",
            lower_pallet = "palletId",
            park_jack = false,
            move_machine = "machineIndex",
            rotate_machine = false,
            place_machine = "placementCell",
        },
        cutter = {
            load_pallet = "palletId",
            load_stock = false,
            select_program = "programIndex",
            set_gauge = "gaugeCentiInch",
            auto_gauge = false,
            save_gauge = false,
            recall_gauge = false,
            rotate_paper = false,
            position_paper = false,
            set_clamp = "clamp",
            set_barrier = "barrierClear",
            guarded_cut = false,
            emergency_stop = false,
            reset_safety = false,
            return_to_pallet = false,
            run_next_lift = false,
            begin_lubrication = false,
            service_advance = false,
            service_view = "itemIndex",
            service_tool = "itemIndex",
            service_point = "itemIndex",
            service_pump = false,
            service_gear = false,
            finish_lubrication = false,
            cancel_service = false,
            begin_blade = false,
            remove_blade_bolt = "itemIndex",
            lift_blade = false,
            sleeve_blade = false,
            book_blade_technician = false,
            set_weekly_technician = "enabled",
        },
        windmill = {
            load_pallet = "palletId",
            toggle_motor = false,
            toggle_feeder = false,
            toggle_impression = false,
            speed_up = false,
            speed_down = false,
            emergency_stop = false,
            reset_safety = false,
            take_proof = false,
            verify_artwork = false,
            approve_proof = false,
            start_run = false,
            stop_run = false,
            clean_unload = false,
            order_plate = "plateId",
            begin_plate = "plateId",
            process_plate = "plateId",
            begin_setup = "setupTask",
            setup_action = "setupAction",
            cancel_setup = false,
            begin_service = false,
            service_lockout = false,
            service_task = false,
            book_technician = false,
        },
    }

    Runtime.WORKSHOP_RELEASE_REASONS = {
        closed = true,
        cancelled = true,
    }

    Runtime.WORKSHOP_PACKAGING = {
        flat = true,
        boxed = true,
    }

    Runtime.WORKSHOP_WRAPPER_STEPS = {
        idle = true,
        wrapping = true,
        finished = true,
    }

    Runtime.WORKSHOP_WRAPPER_SERVICE_TASKS = {
        turntableBearing = 3,
        filmCarriage = 3,
        driveBelt = 1,
        controlBoard = 3,
    }

    Runtime.WORKSHOP_TRUCK_MODES = {
        delivery = true,
        vendor_delivery = true,
        machine_delivery = true,
        pickup = true,
    }

    Runtime.WORKSHOP_TRUCK_STATES = {
        parked_closed = true,
        cargo_open = true,
        cargo_closing = true,
        departing = true,
    }

    Runtime.WORKSHOP_CUTTER_STEPS = {
        idle = true,
        loading = true,
        loaded = true,
        positioning = true,
        positioned = true,
        clamped = true,
        armed = true,
        cutting = true,
        cut_complete = true,
        lift_returning = true,
        repeat_ready = true,
        unloading = true,
        finished = true,
        blocked = true,
        resetting = true,
    }

    Runtime.WORKSHOP_CUTTER_SERVICE_STEPS = {
        idle = true,
        lockout_disconnect = true,
        lockout_key = true,
        lockout_tag = true,
        prep_cartridge = true,
        prep_prime = true,
        lubricate = true,
        blade_bolts = true,
        blade_lift = true,
        blade_sleeve = true,
    }

    Runtime.WORKSHOP_CUTTER_ORIENTATIONS = {
        [0] = true,
        [90] = true,
        [180] = true,
        [270] = true,
    }

    Runtime.WORKSHOP_CUTTER_PAPER_STATUSES = {
        uncut = true,
        in_process = true,
        complete = true,
    }

    Runtime.WORKSHOP_CUTTER_EDGES = {
        right = true,
        bottom = true,
        left = true,
        top = true,
    }

    Runtime.WORKSHOP_WINDMILL_STATUSES = {
        idle = true,
        setup = true,
        proof = true,
        approved = true,
        production = true,
        pass_complete = true,
        stock_shortage = true,
        stopped = true,
    }

    Runtime.WORKSHOP_WINDMILL_SETUP_TASKS = {
        chase = true,
        packing = true,
        rollers = true,
        ink = true,
        feeder = true,
        register = true,
    }

    Runtime.WORKSHOP_WINDMILL_SETUP_ACTIONS = {
        align = true,
        square = true,
        tighten = true,
        layer = true,
        smooth = true,
        clamp = true,
        left_down = true,
        left_up = true,
        right_down = true,
        right_up = true,
        key_1 = true,
        key_2 = true,
        key_3 = true,
        ductor = true,
        prepare = true,
        suction_down = true,
        suction_up = true,
        air_down = true,
        air_up = true,
        test = true,
        left = true,
        right = true,
        up = true,
        down = true,
    }

    Runtime.WORKSHOP_WINDMILL_SERVICE_STEPS = {
        idle = true,
        lockout_disconnect = true,
        lockout_key = true,
        lockout_tag = true,
        task = true,
    }
end

return Component
