-- Asset loading and application initialization.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.App.load()
        Runtime.World.configureEmployees({players=function() return Runtime.multiplayer:remotePlayers() end,
            isNetworkClient=function() return Runtime.multiplayer:isClient() end,
            canClaim=function(machineId)
                local unit=Runtime.MachineFleet.byId(Runtime.state,machineId)
                local base=unit and (unit.modelId=="polar_115" and "cutter"
                    or unit.modelId=="skid_wrapper" and "skid_wrapper"
                    or unit.modelId=="heidelberg_10x15" and "windmill")
                if not base then return false end
                local playerUsing=(Runtime.state.screen=="machine" and Runtime.state.machineType==base
                    or Runtime.state.screen=="press" and base=="windmill")
                    and (Runtime.state.machineId==nil or Runtime.state.machineId==machineId)
                if playerUsing then return false end
                local resource=Runtime.MachineResource.forUnit(base,machineId)
                return not Runtime.workshopAuthority or (not Runtime.workshopAuthority:leaseForResource(base)
                    and not Runtime.workshopAuthority:leaseForResource(resource))
            end})
        Runtime.ComputerScreen.configureWarehouse({enabled=Runtime.Config.warehouse.enabled,
            firstStorageOnly=Runtime.Config.warehouse.firstStorageOnly,
            command=function(intent)
                if Runtime.multiplayer:isClient() then return false,"Use the host-authorized office screen." end
                if Runtime.multiplayer:isHost() then
                    local ok,message=Runtime.commandLocalWorkshop("office_action",{officeIntent=intent})
                    return ok,ok and "completed" or "blocked",message
                end
                return Runtime.RuntimeDependencies.OfficeAuthority.command({state=Runtime.state,world=Runtime.World,save=Runtime.saveCurrent,
                    warehouseEnabled=Runtime.Config.warehouse.enabled,
                    warehouseFirstStorageOnly=Runtime.Config.warehouse.firstStorageOnly})
                    .perform({},Runtime.warehousePlayer(),{officeIntent=intent})
            end})
        Runtime.ComputerScreen.configureGameClock({
            getSpeed=function() return Runtime.App.gameClockSpeed or 1 end,
            canChange=function() return not Runtime.multiplayer:isClient() end,
            setSpeed=function(speed) return Runtime.App.setGameClockSpeed(speed) end,
        })
        Runtime.ComputerScreen.configureRadio({
            isNetworkClient=function() return Runtime.multiplayer:isClient() end,
        })
        local Sound = require("src.sound")
        local acceptanceHost, acceptanceHostError = Runtime.RuntimeDependencies.AcceptanceHostBootstrap.plan({
            osName = love.system and love.system.getOS and love.system.getOS() or nil,
            getenv = os.getenv,
        })
        if acceptanceHostError then
            error("Acceptance host bootstrap refused: " .. acceptanceHostError)
        end
        if acceptanceHost and Runtime.Smoke.requested() then
            error("Acceptance host bootstrap cannot run at the same time as the smoke suite.")
        end
        Runtime.acceptanceHostPlan = acceptanceHost
        Runtime.acceptanceHostRelocationSignature = nil
        love.graphics.setDefaultFilter("nearest", "nearest")
        Runtime.App.settings = Runtime.Settings.load()
        Runtime.Settings.applyDisplay(Runtime.App.settings)
        Runtime.mobileControls = Runtime.MobileControls.new({
            layout = Runtime.App.settings.controlLayout,
            toGame = function(x, y)
                return Runtime.Viewport.toGame(x, y, Runtime.Config.baseWidth, Runtime.Config.baseHeight, Runtime.App.officeFitsScreen())
            end,
            pressKey = Runtime.dispatchKeyPressed,
            releaseKey = function(key) Runtime.Input.keyreleased(key, Runtime.inputContext) end,
            pressPointer = Runtime.dispatchMousePressed,
            movePointer = Runtime.dispatchMouseMoved,
            releasePointer = Runtime.dispatchMouseReleased,
            gameplayActive = function() return Runtime.state.screen == "world" end,
            gestureActive = function()
                return Runtime.App.mobileCamera and Runtime.App.mobileCamera:isEnabled() and not Runtime.spriteLabActive
                    and not Runtime.App.officeFitsScreen()
                    and not (Runtime.state.screen == "options" and Runtime.OptionsScreen.isControlsTab())
            end,
            primaryAction = Runtime.primaryMobileAction,
            extraActions = Runtime.extraMobileActions,
            afterInput = Runtime.syncMobileKeyboard,
            beginGesture = function(x, y, distance)
                Runtime.syncCamera()
                if Runtime.App.mobileCamera then Runtime.App.mobileCamera:beginGesture(x, y, distance) end
            end,
            updateGesture = function(x, y, distance)
                Runtime.syncCamera()
                if Runtime.App.mobileCamera then Runtime.App.mobileCamera:updateGesture(x, y, distance) end
            end,
            endGesture = function()
                if Runtime.App.mobileCamera then Runtime.App.mobileCamera:endGesture() end
            end,
        })
        Runtime.App.mobileCamera = require("src.mobile_camera").new({
            enabled = Runtime.mobileControls:isEnabled(),
            baseWidth = Runtime.Config.baseWidth,
            baseHeight = Runtime.Config.baseHeight,
            -- Player positions are foot anchors; focus on the stable body center.
            followOffsetY = -Runtime.Config.characterRendering.referenceHeight * Runtime.Config.player.drawScale / 2,
        })
        Runtime.controller = Runtime.Controller.new({
            pressKey = Runtime.dispatchKeyPressed,
            releaseKey = function(key) Runtime.Input.keyreleased(key, Runtime.inputContext) end,
            pressPointer = Runtime.dispatchGameMousePressed,
            releasePointer = Runtime.dispatchGameMouseReleased,
            screenInfo = function()
                return Runtime.state.screen, Runtime.state.machineType,
                    Runtime.state.screen == "title" and Runtime.TitleScreen.keyboardFocus ~= nil
            end,
            menuAction = Runtime.openOptions,
        })
        Runtime.Input.setMobileMovementProvider(function()
            if Runtime.mobileControls then return Runtime.mobileControls:movement() end
            return 0, 0
        end)
        if acceptanceHost then
            love.filesystem.setIdentity(acceptanceHost.identity)
        elseif Runtime.Smoke.requested() then
            local testIdentity = os.getenv("PICTURE_SHOP_TEST_IDENTITY")
            love.filesystem.setIdentity(testIdentity and testIdentity:match("^the%-picture%-shop%-test%-[%w%-]+$")
                and testIdentity or "the-picture-shop-smoke")
        end
        Runtime.Assets.load()
        Runtime.CharacterAssets.load()
        Runtime.spriteLabActive = Runtime.Smoke.spriteLabRequested()
        local startupTextureBytes = Runtime.Assets.textureBytes() + Runtime.CharacterAssets.textureBytes()
        local assetsHealthy, assetFailures = Runtime.Assets.assertHealthy()
        local charactersHealthy, characterFailures = Runtime.CharacterAssets.assertHealthy()
        Runtime.state.assetErrors = Runtime.AssetErrorScreen.normalize(
            assetsHealthy and nil or assetFailures,
            charactersHealthy and nil or characterFailures)
        if #Runtime.state.assetErrors == 0 then
            Runtime.World.load()
            Runtime.App.syncPlayerColorways()
            Runtime.TitleScreen.enter(Runtime.startGame, Runtime.openLocalPlay,
                Runtime.CryptoNative.productionReady == true and Runtime.openDirectPlay or nil)
        else
            Runtime.state.screen = "asset_error"
            Runtime.state.message = string.format("Startup stopped: %d required asset error(s).", #Runtime.state.assetErrors)
        end
        Runtime.Machine.setOutputResolver(function(targetState, pallet, machineId)
            return Runtime.World.findCutterOutput(targetState, Runtime.Assets, pallet and pallet.id,
                machineId or "MCH-0001")
        end)

        Runtime.runSmoke(startupTextureBytes, Sound)
        Runtime.App.sound = Sound.new({
            state = Runtime.state,
            world = Runtime.World,
            machine = Runtime.Machine,
            wrapper = Runtime.Wrapper,
            windmill = Runtime.Windmill,
        })
        local soundHealthy, soundErrors = Runtime.App.sound:initialize()
        Runtime.Settings.applyAudio(Runtime.App.settings, Runtime.App.sound)
        if Runtime.Smoke.requested() and not soundHealthy then
            error("Sound startup failed: " .. table.concat(soundErrors or {}, "; "))
        end
        if acceptanceHost then
            if #Runtime.state.assetErrors > 0 then
                error("Acceptance host bootstrap stopped because required assets failed validation.")
            end
            local hosted, hostError = Runtime.startLanHost(
                acceptanceHost.slot, acceptanceHost.playerName)
            if not hosted then
                error("Acceptance host bootstrap could not start LAN hosting: "
                    .. tostring(hostError))
            end
            if acceptanceHost.screen == "computer" then
                Runtime.ComputerScreen.enter(Runtime.state)
                Runtime.state.screen = "computer"
                print("[ACCEPTANCE HOST] SCREEN computer")
            end
            print(string.format("[ACCEPTANCE HOST] READY identity=%s slot=%d address=%s:%d",
                acceptanceHost.identity, acceptanceHost.slot,
                tostring(Runtime.multiplayer.localAddress or "unknown"),
                tonumber(Runtime.multiplayer.port) or 22122))
            io.flush()
        end
        print("[PICTURE SHOP] Startup complete")
    end
end

return Component
