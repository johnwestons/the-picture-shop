-- Smoke-test dependency wiring.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.runSmoke(startupTextureBytes, Sound)
        if not Runtime.Smoke.requested() then return end
        if #Runtime.state.assetErrors == 0 then
            Runtime.startGame(Runtime.Save.newGame(1), "smoke")
            if os.getenv("PICTURE_SHOP_SMOKE_FOCUS")=="warehouse-condition" then
                Runtime.state.warehouse.condition=require("src.warehouse_condition").new("story",42)
                local review=os.getenv("PICTURE_SHOP_RESTORATION_REVIEW")
                local c=Runtime.state.warehouse.condition
                if review=="worn-on" then c.powerConnected,c.breakerRepaired=true,true end
                if review=="clean-off" then
                    c.powerConnected,c.breakerRepaired,c.repainted,c.lightsOn=true,true,true,false
                    c.cleaned.west,c.cleaned.center,c.cleaned.east=true,true,true
                end
                local stage,lighting
                if type(review)=="string" then
                    stage,lighting=review:match("^stage([0-4])%-(on)$")
                    if not stage then stage,lighting=review:match("^stage([0-4])%-(off)$") end
                end
                if stage then
                    local number=tonumber(stage)
                    c.cleaned.west,c.cleaned.center,c.cleaned.east=number>=1,number>=2,number>=3
                    c.repainted=number>=4
                    c.powerConnected,c.breakerRepaired=lighting=="on",lighting=="on"
                    c.lightsOn=lighting=="on"
                end
            end
            -- Install the active world assets/state used by placement and render checks.
            Runtime.World.update(0, 0, 0, Runtime.Assets, Runtime.state)
            -- Make the render fixture independent of the live seasonal arrival
            -- cadence, then walk the visitor to reception using normal navigation.
            if os.getenv("PICTURE_SHOP_SMOKE_FOCUS")~="warehouse-condition" then
                local customer = Runtime.World.customer
                customer:reset(true, 0)
                customer.timer = 0
                local employeeContext = Runtime.World.employeeContext(Runtime.state, Runtime.Assets)
                for _ = 1, 120 do
                    if customer.state == "waiting" then break end
                    customer:update(0.5, Runtime.World.player, false, 0.5, employeeContext)
                end
            end
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
        if os.getenv("PICTURE_SHOP_SMOKE_FOCUS")=="warehouse-condition"
            and os.getenv("PICTURE_SHOP_RESTORATION_REVIEW")=="footprints" then
            local prints=require("src.warehouse_footprints")
            local player=Runtime.World.player
            local now=love.timer.getTime()
            player.x,player.y=112,383
            prints.update(Runtime.state,player,nil,now)
            player.x=199
            prints.update(Runtime.state,player,nil,now+.1)
        end
        if Runtime.spriteLabActive then Runtime.SpriteMotionLab.enter(Runtime.CharacterAssets) end
    end
end

return Component
