-- Smoke-test dependency wiring.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.runSmoke(startupTextureBytes, Sound)
        if not Runtime.Smoke.requested() then return end
        if #Runtime.state.assetErrors == 0 then
            Runtime.startGame(Runtime.Save.newGame(1), "smoke")
            -- Advance the transient visitor to reception so the smoke render
            -- includes the customer sprite and depth-sorting path.
            Runtime.World.update(10, 0, 0, Runtime.Assets, Runtime.state)
        end
        Runtime.Smoke.start({
            appRuntime = Runtime,
            assets = Runtime.Assets,
            assetErrorScreen = Runtime.AssetErrorScreen,
            BayDoor = Runtime.RuntimeDependencies.BayDoor,
            businessCalendar = Runtime.BusinessCalendar,
            characterAssets = Runtime.CharacterAssets,
            wrapper = Runtime.Wrapper,
            computerScreen = Runtime.ComputerScreen,
            workPhone = Runtime.WorkPhone,
            workPhoneScreen = Runtime.WorkPhoneScreen,
            Customer = Runtime.Customer,
            config = Runtime.Config,
            CutterPlacement = Runtime.RuntimeDependencies.CutterPlacement,
            CutterZones = Runtime.RuntimeDependencies.CutterZones,
            machine = Runtime.Machine,
            serviceNetworkBeforeMachine = Runtime.serviceNetworkBeforeMachine,
            machineFleet = Runtime.MachineFleet,
            machineMaintenance = Runtime.MachineMaintenance,
            machineScreen = Runtime.MachineScreen,
            Navigation = Runtime.RuntimeDependencies.Navigation,
            PalletJack = Runtime.PalletJack,
            PalletState = Runtime.PalletState,
            PalletLogistics = Runtime.PalletLogistics,
            PaperWork = Runtime.PaperWork,
            plateService = Runtime.PlateService,
            pressScreen = Runtime.PressScreen,
            Receiving = Runtime.Receiving,
            procurement = Runtime.Procurement,
            jobs = Runtime.Jobs,
            jobOfferScreen = Runtime.JobOfferScreen,
            jobService = Runtime.JobService,
            input = Runtime.Input,
            inputContext = Runtime.inputContext,
            save = Runtime.Save,
            SaveEditor = require("src.save_editor"),
            Settings = Runtime.Settings,
            shop = Runtime.Shop,
            state = Runtime.state,
            State = Runtime.State,
            title = Runtime.TitleScreen,
            Technician = Runtime.Technician,
            Truck = Runtime.Truck,
            truckInventoryScreen = Runtime.RuntimeDependencies.TruckInventoryScreen,
            vendorScreen = Runtime.VendorScreen,
            palletWorkOrderScreen = Runtime.inputContext.palletWorkOrderScreen,
            world = Runtime.World,
            app = Runtime.App,
            worldRenderer = Runtime.WorldRenderer,
            windmill = Runtime.Windmill,
            createWorkshopAuthority = Runtime.createWorkshopAuthority,
            windmillNetworkView = Runtime.windmillView,
            wrapperNetworkView = Runtime.wrapperSnapshotView,
            windmillLiveNetworkView = function() return Runtime.windmillView(Runtime.activeWindmillRemote) end,
            WindmillPlacement = Runtime.RuntimeDependencies.WindmillPlacement,
            startupTextureBytes = startupTextureBytes,
            Sound = Sound,
        })
        if Runtime.spriteLabActive then Runtime.SpriteMotionLab.enter(Runtime.CharacterAssets) end
    end
end

return Component
