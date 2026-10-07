-- Application dependencies and live session state.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.RuntimeDependencies = {}
    Runtime.Assets = require("src.assets")
    Runtime.RuntimeDependencies.AcceptanceHostBootstrap = require("src.acceptance_host_bootstrap")
    Runtime.AssetErrorScreen = require("src.screens.asset_error_screen")
    Runtime.RuntimeDependencies.BayDoor = require("src.bay_door")
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.CharacterAssets = require("src.character_assets")
    Runtime.ComputerScreen = require("src.screens.computer_screen")
    Runtime.Employees = require("src.employees")
    Runtime.employmentSaveClock = 0
    Runtime.Config = require("src.config")
    Runtime.Controller = require("src.controller")
    Runtime.RuntimeDependencies.CutterMaintenanceAuthority = require("src.cutter_maintenance_authority")
    Runtime.RuntimeDependencies.CutterPlacement = require("src.cutter_placement")
    Runtime.RuntimeDependencies.CutterZones = require("src.cutter_zones")
    Runtime.Customer = require("src.customer")
    Runtime.CryptoNative = require("src.net.crypto_native")
    Runtime.RuntimeDependencies.DirectConnection = require("src.net.direct_connection")
    Runtime.DirectIpv4Runtime = {
        Host = require("src.net.direct_ipv4_host"),
        Listener = require("src.net.direct_ipv4_listener"),
        hosts = {},
        pending = nil,
    }
    Runtime.RuntimeDependencies.DirectCompositeTransport = require("src.net.transport_direct_composite")
    Runtime.DirectScreen = require("src.screens.direct_screen")
    Runtime.RuntimeDependencies.Hud = require("src.screens.hud")
    Runtime.Input = require("src.input")
    Runtime.Ui = require("src.screens.ui")
    Runtime.JobOfferScreen = require("src.screens.job_offer_screen")
    Runtime.LanScreen = require("src.screens.lan_screen")
    Runtime.RuntimeDependencies.PalletWorkOrderScreen = require("src.screens.pallet_work_order_screen")
    Runtime.JobService = require("src.job_service")
    Runtime.Jobs = require("src.jobs")
    Runtime.RuntimeDependencies.LanDiscovery = require("src.net.lan_discovery")
    Runtime.RuntimeDependencies.LanReconnect = require("src.net.lan_reconnect")
    Runtime.LanAddress = require("src.net.address")
    Runtime.Machine = require("src.machine")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.MachineResource = require("src.machine_resource_id")
    Runtime.MachineMaintenance = require("src.machine_maintenance")
    Runtime.RuntimeDependencies.MachineRelocationAuthority = require("src.machine_relocation_authority")
    Runtime.MobileControls = require("src.mobile_controls")
    Runtime.MultiplayerHud = require("src.screens.multiplayer_hud")
    Runtime.HighFiveUi = require("src.screens.high_five_ui")
    Runtime.MultiplayerSession = require("src.net.session")
    Runtime.RuntimeDependencies.Navigation = require("src.navigation")
    Runtime.OptionsScreen = require("src.screens.options_screen")
    Runtime.Procurement = require("src.procurement")
    Runtime.Wrapper = require("src.wrapper")
    Runtime.RuntimeDependencies.WrapperMaintenanceAuthority = require("src.wrapper_maintenance_authority")
    Runtime.MachineScreen = require("src.screens.machine_screen")
    Runtime.PalletJack = require("src.pallet_jack")
    Runtime.RuntimeDependencies.PlacementGrid = require("src.placement_grid")
    Runtime.PalletState = require("src.pallet_state")
    Runtime.PalletLogistics = require("src.pallet_logistics")
    Runtime.PaperWork = require("src.paper_work")
    Runtime.PlateService = require("src.plate_service")
    Runtime.PressSetupGames = require("src.press_setup_games")
    Runtime.PressScreen = require("src.screens.press_screen")
    Runtime.Receiving = require("src.receiving")
    Runtime.Save = require("src.save")
    Runtime.SaveSchema = require("src.save_schema")
    Runtime.Settings = require("src.settings")
    Runtime.Shop = require("src.shop")
    Runtime.Smoke = require("src.smoke")
    Runtime.SpriteMotionLab = require("src.screens.sprite_motion_lab")
    Runtime.State = require("src.state")
    Runtime.TitleScreen = require("src.screens.title_screen")
    Runtime.Technician = require("src.technician")
    Runtime.Truck = require("src.truck")
    Runtime.RuntimeDependencies.TruckAuthority = require("src.truck_authority")
    Runtime.RuntimeDependencies.TruckInventoryScreen = require("src.screens.truck_inventory_screen")
    Runtime.VendorScreen = require("src.screens.vendor_screen")
    Runtime.RuntimeDependencies.VendorAuthority = require("src.vendor_authority")
    Runtime.Viewport = require("src.viewport")
    Runtime.World = require("src.world")
    Runtime.WorldRenderer = require("src.world_renderer")
    Runtime.Windmill = require("src.windmill")
    Runtime.RuntimeDependencies.WindmillPlacement = require("src.windmill_placement")
    Runtime.WorkPhone = require("src.work_phone")
    Runtime.RuntimeDependencies.PhoneAuthority = require("src.phone_authority")
    Runtime.RuntimeDependencies.OfficeAuthority = require("src.office_authority")
    Runtime.WorkPhoneScreen = require("src.screens.work_phone_screen")
    Runtime.WorkshopAuthority = require("src.workshop_authority")
    Runtime.WorkshopRemoteScreen = require("src.screens.workshop_remote_screen")
    Runtime.Forklift = require("src.forklift")
    Runtime.RuntimeDependencies.WarehouseAuthority = require("src.warehouse_authority")
    Runtime.RuntimeDependencies.WarehouseControls = require("src.screens.warehouse_controls")

    Runtime.App = {}
    Runtime.state = Runtime.State.new()
    Runtime.acceptanceHostPlan = nil
    Runtime.acceptanceHostRelocationSignature = nil
    Runtime.spriteLabActive = false
    Runtime.mobileControls = nil
    Runtime.controller = nil
    Runtime.multiplayer = Runtime.MultiplayerSession.new()
    Runtime.App.multiplayerFocusGrace = require("src.net.focus_grace").new({
        clock = function()
            if love and love.timer and love.timer.getTime then return love.timer.getTime() end
            return os.time()
        end,
        timeoutSeconds = 120,
    })
    Runtime.lanDiscovery = Runtime.RuntimeDependencies.LanDiscovery.new()
    Runtime.lanReconnect = Runtime.RuntimeDependencies.LanReconnect.new()
    Runtime.lanReconnectArmed = false
    Runtime.workshopAuthority = nil
    Runtime.localWorkshopLease = nil
    Runtime.localWorkshopRequestId = 0
    Runtime.activeCutterRemote = nil
    Runtime.cutterMaintenanceAuthority = nil
    Runtime.activeWrapperRemote = nil
    Runtime.wrapperMaintenanceAuthority = nil
    Runtime.activeWindmillRemote = nil
    Runtime.machineRemoteSessions = {}
    Runtime.directConnection = nil
    Runtime.pendingDirectSession = nil
    Runtime.directHostComposite = nil
    Runtime.directHostInvitationGeneration = 0
    Runtime.lastDirectSlot = 1
    Runtime.serviceNetworkBeforeMachine = nil
    Runtime.warehouseControls = nil
    Runtime.warehousePendingIntent = nil
    Runtime.warehouseSaveClock = 0

    Runtime.MachineFleet.setSaleGuard(function(currentState, item)
        local placementKey = item and Runtime.MachineFleet.definitions[item.modelId]
            and Runtime.MachineFleet.definitions[item.modelId].placementKey
        if item and item.status == "installed" and placementKey
            and currentState and currentState[placementKey]
            and currentState[placementKey].moving
        then
            return false, "Place the moving machine before listing it for sale."
        end
        local windmillLeaseActive = Runtime.workshopAuthority
            and Runtime.workshopAuthority:leaseForResource("windmill") ~= nil
        if windmillLeaseActive and item and item.modelId == "heidelberg_10x15"
            and item.status == "installed"
        then
            return false, "Close the active Windmill console before listing the press for sale."
        end
        local cutterLeaseActive = Runtime.workshopAuthority
            and Runtime.workshopAuthority:leaseForResource("cutter") ~= nil
        if item and Runtime.Employees.reservation(currentState,item.id) then
            return false,"Pause the employee's assignment before selling this machine."
        end
        local wrapperLeaseActive = Runtime.workshopAuthority
            and Runtime.workshopAuthority:leaseForResource("skid_wrapper") ~= nil
        if wrapperLeaseActive and item and item.modelId == "skid_wrapper"
            and item.status == "installed"
        then
            return false, "Close the active skid-wrapper console before listing it for sale."
        end
        return Runtime.Machine.validateSale(item, cutterLeaseActive)
    end)
end

return Component
