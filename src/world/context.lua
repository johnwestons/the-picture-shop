-- World dependencies, actors, and shared world state.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.Config = require("src.config")
    Runtime.BayDoor = require("src.bay_door")
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.CutterPlacement = require("src.cutter_placement")
    Runtime.CutterZones = require("src.cutter_zones")
    Runtime.CutterStaging = require("src.cutter_staging")
    Runtime.StagingAreas = require("src.staging_areas")
    Runtime.Customer = require("src.customer")
    Runtime.Interaction = require("src.interaction")
    Runtime.JobService = require("src.job_service")
    Runtime.Machine = require("src.machine")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.MachinePose = require("src.machine_pose")
    Runtime.MachineTransport = require("src.machine_transport")
    Runtime.MultiplayerCapabilities = require("src.multiplayer_capabilities")
    Runtime.Navigation = require("src.navigation")
    Runtime.PlacementGrid = require("src.placement_grid")
    Runtime.Footprint = require("src.floor_footprint")
    Runtime.PalletLogistics = require("src.pallet_logistics")
    Runtime.PalletJack = require("src.pallet_jack")
    Runtime.PlayerController = require("src.player_controller")
    Runtime.Procurement = require("src.procurement")
    Runtime.Truck = require("src.truck")
    Runtime.MachineResource = require("src.machine_resource_id")
    Runtime.Technician = require("src.technician")
    Runtime.WrapperPlacement = require("src.wrapper_placement")
    Runtime.Wrapper = require("src.wrapper")
    Runtime.WorldRenderer = require("src.world_renderer")
    Runtime.Windmill = require("src.windmill")
    Runtime.WindmillPlacement = require("src.windmill_placement")
    Runtime.Forklift = require("src.forklift")
    Runtime.WarehouseGameplay = require("src.warehouse_gameplay")
    Runtime.WarehouseLayout = require("src.warehouse_layout")
    Runtime.WarehouseConstruction = require("src.warehouse_construction")
    Runtime.Employees = require("src.employees")
    Runtime.EmployeeAI = require("src.employee_ai")

    Runtime.World = {
        player = {
            id = nil,
            character = Runtime.Config.player.character,
            x = Runtime.Config.player.spawnX,
            y = Runtime.Config.player.spawnY,
            speed = Runtime.Config.player.speed,
            moving = false,
            facing = 1,
            velocityX = 0,
            velocityY = 0,
            animationDistance = 0,
            idleClock = 0,
            interactionClock = 0,
        },
        bayDoor = Runtime.BayDoor.new(Runtime.Config.loadingBay),
        truck = Runtime.Truck.new(Runtime.Config.truck),
        customer = Runtime.Customer.new(Runtime.Config.customer),
        vendor = Runtime.Customer.new(Runtime.Config.vendor),
        selectedInteraction = nil,
        placementSelection = nil,
    }
end

return Component
