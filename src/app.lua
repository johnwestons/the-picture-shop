local Assets = require("src.assets")
local AssetErrorScreen = require("src.screens.asset_error_screen")
local BayDoor = require("src.bay_door")
local BusinessCalendar = require("src.business_calendar")
local CharacterAssets = require("src.character_assets")
local ComputerScreen = require("src.screens.computer_screen")
local Config = require("src.config")
local Controller = require("src.controller")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local Hud = require("src.screens.hud")
local Input = require("src.input")
local Ui = require("src.screens.ui")
local JobOfferScreen = require("src.screens.job_offer_screen")
local JobService = require("src.job_service")
local Jobs = require("src.jobs")
local Machine = require("src.machine")
local MachineFleet = require("src.machine_fleet")
local MachineMaintenance = require("src.machine_maintenance")
local MobileControls = require("src.mobile_controls")
local Navigation = require("src.navigation")
local Procurement = require("src.procurement")
local Wrapper = require("src.wrapper")
local MachineScreen = require("src.screens.machine_screen")
local PalletJack = require("src.pallet_jack")
local PalletState = require("src.pallet_state")
local PalletLogistics = require("src.pallet_logistics")
local PlateService = require("src.plate_service")
local PressScreen = require("src.screens.press_screen")
local Receiving = require("src.receiving")
local Save = require("src.save")
local Shop = require("src.shop")
local Smoke = require("src.smoke")
local SpriteMotionLab = require("src.screens.sprite_motion_lab")
local State = require("src.state")
local TitleScreen = require("src.screens.title_screen")
local Technician = require("src.technician")
local Truck = require("src.truck")
local TruckInventoryScreen = require("src.screens.truck_inventory_screen")
local VendorScreen = require("src.screens.vendor_screen")
local Viewport = require("src.viewport")
local World = require("src.world")
local WorldRenderer = require("src.world_renderer")
local Windmill = require("src.windmill")
local WindmillPlacement = require("src.windmill_placement")

local App = {}
local state = State.new()
local spriteLabActive = false
local mobileControls = nil
local controller = nil

local function cameraTransformsUi()
    return App.mobileCamera and App.mobileCamera:isEnabled() and state.screen ~= "world"
end

local function cameraViewKey()
    if state.screen == "machine" then return "machine:" .. tostring(state.machineType or "unknown") end
    return tostring(state.screen)
end

local function toPointerCoordinates(x, y)
    local gameX, gameY = Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight)
    if cameraTransformsUi() then return App.mobileCamera:screenToWorld(gameX, gameY) end
    return gameX, gameY
end

local function saveCurrent()
    if not state.activeSlot then return false end
    return Save.save(state.activeSlot, state, World.snapshot())
end

local function startGame(payload, mode)
    State.applySave(state, payload)
    World.load(payload.player)
    if mode == "new" then saveCurrent() end
    if payload.recovered then
        state.message = "Recovered this shop from its last valid " .. tostring(payload.recoverySource) .. " copy."
    end
end

local function returnToTitle()
    saveCurrent()
    state.screen = "title"
    TitleScreen.enter(startGame)
end

local inputContext = {
    state = state,
    assets = Assets,
    computerScreen = ComputerScreen,
    hud = Hud,
    world = World,
    shop = Shop,
    jobOfferScreen = JobOfferScreen,
    jobService = JobService,
    machine = Machine,
    wrapper = Wrapper,
    machineScreen = MachineScreen,
    truckInventoryScreen = TruckInventoryScreen,
    vendorScreen = VendorScreen,
    pressScreen = PressScreen,
    windmill = Windmill,
    title = TitleScreen,
    saveCurrent = saveCurrent,
    returnToTitle = returnToTitle,
}

local function pointerPosition()
    if controller and controller:isActive() and state.screen ~= "world" then
        return controller:pointer()
    end
    if mobileControls and mobileControls:isEnabled() then
        local x, y = mobileControls:pointer()
        if x and y then
            if cameraTransformsUi() then return App.mobileCamera:screenToWorld(x, y) end
            return x, y
        end
    end
    local x, y = love.mouse.getPosition()
    return toPointerCoordinates(x, y)
end

local function dispatchGameMousePressed(gameX, gameY, button)
    if state.screen == "asset_error" then return end
    if button == 1 then Ui.notePress(gameX, gameY) end
    return Input.mousepressed(gameX, gameY, button, inputContext)
end

local function dispatchGameMouseReleased(gameX, gameY, button)
    return Input.mousereleased(gameX, gameY, button, inputContext)
end

local function dispatchMousePressed(x, y, button)
    if state.screen == "asset_error" then return end
    local gameX, gameY = toPointerCoordinates(x, y)
    if button == 1 then Ui.notePress(gameX, gameY) end
    return Input.mousepressed(gameX, gameY, button, inputContext)
end

local function dispatchMouseReleased(x, y, button)
    local gameX, gameY = toPointerCoordinates(x, y)
    return Input.mousereleased(gameX, gameY, button, inputContext)
end

local function dispatchMouseMoved(x, y)
    local gameX, gameY = toPointerCoordinates(x, y)
    return Input.mousemoved(gameX, gameY, inputContext)
end

local function wantsTextInput()
    if state.screen == "job_offer" and JobOfferScreen.wantsTextInput then
        return JobOfferScreen.wantsTextInput()
    elseif state.screen == "computer" and ComputerScreen.wantsTextInput then
        return ComputerScreen.wantsTextInput()
    elseif state.screen == "machine" and MachineScreen.wantsTextInput then
        return MachineScreen.wantsTextInput()
    end
    return false
end

local function syncMobileKeyboard()
    if mobileControls and mobileControls:isEnabled() and love.keyboard.setTextInput then
        love.keyboard.setTextInput(wantsTextInput())
    end
end

local function primaryMobileAction()
    if state.cutter and state.cutter.moving or state.wrapper and state.wrapper.moving
        or state.windmill and state.windmill.moving
    then
        return "e", "PLACE"
    end
    local selected = World.getInteraction()
    if not selected then return "e", "USE" end
    local labels = {
        customer = "QUOTE", computer = "PC", vendor = "TALK", loadingBayDoor = "DOOR",
        truckCargoDoor = "TRUCK", cutter = "CUTTER", skidWrapper = "WRAP",
        windmill = "PRESS", palletJack = state.palletJack and state.palletJack.operating and "LIFT" or "DRIVE",
    }
    return "e", labels[selected.kind] or "USE"
end

local function extraMobileActions()
    local actions = {}
    if state.cutter and state.cutter.moving or state.wrapper and state.wrapper.moving
        or state.windmill and state.windmill.moving
    then
        actions[#actions + 1] = { key = "q", label = "TURN" }
        return actions
    end
    if state.palletJack and state.palletJack.operating then
        actions[#actions + 1] = { key = "f", label = "PARK" }
        local selected = World.getInteraction()
        local canRelocate = selected and (selected.kind == "cutter"
            or selected.kind == "skidWrapper" or selected.kind == "windmill")
        if not canRelocate then
            canRelocate = World.cutterNearby and World.cutterNearby(state)
                or World.wrapperNearby and World.wrapperNearby(state)
                or World.windmillNearby and World.windmillNearby(state)
        end
        if canRelocate then actions[#actions + 1] = { key = "m", label = "MOVE" } end
    end
    return actions
end

function App.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    mobileControls = MobileControls.new({
        toGame = function(x, y) return Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight) end,
        pressKey = function(key) Input.keypressed(key, inputContext) end,
        releaseKey = function(key) Input.keyreleased(key, inputContext) end,
        pressPointer = dispatchMousePressed,
        movePointer = dispatchMouseMoved,
        releasePointer = dispatchMouseReleased,
        gameplayActive = function() return state.screen == "world" end,
        gestureActive = function()
            return App.mobileCamera and App.mobileCamera:isEnabled() and not spriteLabActive
        end,
        primaryAction = primaryMobileAction,
        extraActions = extraMobileActions,
        afterInput = syncMobileKeyboard,
        beginGesture = function(x, y, distance)
            if App.mobileCamera then App.mobileCamera:beginGesture(x, y, distance) end
        end,
        updateGesture = function(x, y, distance)
            if App.mobileCamera then App.mobileCamera:updateGesture(x, y, distance) end
        end,
        endGesture = function()
            if App.mobileCamera then App.mobileCamera:endGesture() end
        end,
    })
    App.mobileCamera = require("src.mobile_camera").new({
        enabled = mobileControls:isEnabled(),
        baseWidth = Config.baseWidth,
        baseHeight = Config.baseHeight,
    })
    controller = Controller.new({
        pressKey = function(key) Input.keypressed(key, inputContext) end,
        releaseKey = function(key) Input.keyreleased(key, inputContext) end,
        pressPointer = dispatchGameMousePressed,
        releasePointer = dispatchGameMouseReleased,
        screenInfo = function() return state.screen, state.machineType end,
        worldMenuAction = returnToTitle,
    })
    Input.setMobileMovementProvider(function()
        if mobileControls then return mobileControls:movement() end
        return 0, 0
    end)
    if Smoke.requested() then love.filesystem.setIdentity("the-picture-shop-smoke") end
    Assets.load()
    CharacterAssets.load()
    spriteLabActive = Smoke.spriteLabRequested()
    local startupTextureBytes = Assets.textureBytes() + CharacterAssets.textureBytes()
    local assetsHealthy, assetFailures = Assets.assertHealthy()
    local charactersHealthy, characterFailures = CharacterAssets.assertHealthy()
    state.assetErrors = AssetErrorScreen.normalize(
        assetsHealthy and nil or assetFailures,
        charactersHealthy and nil or characterFailures)
    if #state.assetErrors == 0 then
        World.load()
        TitleScreen.enter(startGame)
    else
        state.screen = "asset_error"
        state.message = string.format("Startup stopped: %d required asset error(s).", #state.assetErrors)
    end
    Machine.setOutputResolver(function(targetState, pallet)
        return World.findCutterOutput(targetState, Assets, pallet and pallet.id)
    end)

    if Smoke.requested() then
        if #state.assetErrors == 0 then
            startGame(Save.newGame(1), "smoke")
            -- Advance the transient visitor to reception so the smoke render
            -- includes the customer sprite and depth-sorting path.
            World.update(10, 0, 0, Assets, state)
        end
        Smoke.start({
            assets = Assets,
            assetErrorScreen = AssetErrorScreen,
            BayDoor = BayDoor,
            businessCalendar = BusinessCalendar,
            characterAssets = CharacterAssets,
            wrapper = Wrapper,
            computerScreen = ComputerScreen,
            Customer = Customer,
            config = Config,
            CutterPlacement = CutterPlacement,
            CutterZones = CutterZones,
            machine = Machine,
            machineFleet = MachineFleet,
            machineMaintenance = MachineMaintenance,
            machineScreen = MachineScreen,
            Navigation = Navigation,
            PalletJack = PalletJack,
            PalletState = PalletState,
            PalletLogistics = PalletLogistics,
            plateService = PlateService,
            pressScreen = PressScreen,
            Receiving = Receiving,
            procurement = Procurement,
            jobs = Jobs,
            jobOfferScreen = JobOfferScreen,
            jobService = JobService,
            input = Input,
            inputContext = inputContext,
            save = Save,
            shop = Shop,
            state = state,
            State = State,
            title = TitleScreen,
            Technician = Technician,
            Truck = Truck,
            truckInventoryScreen = TruckInventoryScreen,
            vendorScreen = VendorScreen,
            world = World,
            worldRenderer = WorldRenderer,
            windmill = Windmill,
            WindmillPlacement = WindmillPlacement,
            startupTextureBytes = startupTextureBytes,
        })
        if spriteLabActive then SpriteMotionLab.enter(CharacterAssets) end
    end
    print("[PICTURE SHOP] Startup complete")
end

function App.update(dt)
    if controller then controller:update(dt) end
    if spriteLabActive then SpriteMotionLab.update(dt, CharacterAssets); return end
    if state.screen ~= "title" and state.screen ~= "asset_error" then
        local calendarChanged = BusinessCalendar.update(state, dt)
        local emailArrived = JobService.updateClientEmails(state)
        local technicianChanged = MachineMaintenance.updateTechnician(state)
        if calendarChanged or emailArrived or technicianChanged then saveCurrent() end
    end
    if state.screen == "asset_error" then
        return
    elseif state.screen == "title" then
        TitleScreen.update(dt)
    elseif state.screen == "world" then
        local directionX, directionY = Input.movement()
        if World.update(dt, directionX, directionY, Assets, state) then saveCurrent() end
        Wrapper.update(dt, state)
    elseif state.screen == "truck_inventory" then
        if World.update(dt, 0, 0, Assets, state) then saveCurrent() end
    elseif state.screen == "machine" then
        MachineScreen.update(dt)
        if state.machineType == "skid_wrapper" then
            local previousStep = Wrapper.step
            Wrapper.update(dt, state)
            if previousStep ~= "finished" and Wrapper.step == "finished" then saveCurrent() end
            return
        end
        local previousStep = Machine.step
        Machine.update(dt, state)
        if previousStep ~= "finished" and Machine.step == "finished" then saveCurrent() end
    elseif state.screen == "press" then
        PressScreen.update(dt, state)
        if Windmill.update(dt, state) then saveCurrent() end
    end
end

function App.draw()
    love.graphics.clear(0.04, 0.05, 0.07)
    local viewBounds = Viewport.gameBounds(Config.baseWidth, Config.baseHeight)
    if mobileControls then mobileControls:setBounds(viewBounds) end
    if App.mobileCamera then App.mobileCamera:setViewport(viewBounds.width, viewBounds.height) end
    local mobileCameraActive = App.mobileCamera and App.mobileCamera:isEnabled()
    if mobileCameraActive then App.mobileCamera:selectView(cameraViewKey(), state.screen == "world") end
    local mobileWorld = state.screen == "world" and mobileCameraActive
    local mobileUi = state.screen ~= "world" and mobileCameraActive
    Viewport.beginDraw(Config.baseWidth, Config.baseHeight, not mobileCameraActive)
    if spriteLabActive then
        SpriteMotionLab.draw(CharacterAssets)
        Viewport.endDraw()
        Smoke.drawn()
        return
    end
    local desiredPack = state.screen == "title" and "menu"
        or state.screen == "machine"
            and (state.machineType == "skid_wrapper" and "wrapper" or "cutter") or nil
    if not Assets.activatePack(desiredPack) then
        local _, failures = Assets.assertHealthy()
        state.assetErrors = AssetErrorScreen.normalize(failures)
        state.screen = "asset_error"
        state.message = "A screen asset pack could not be loaded."
    end
    if mobileUi then App.mobileCamera:beginDraw() end
    if state.screen == "asset_error" then
        CharacterAssets.retainCharacters({})
        AssetErrorScreen.draw(state.assetErrors)
    elseif state.screen == "title" then
        CharacterAssets.retainCharacters({})
        local mouseX, mouseY = pointerPosition()
        TitleScreen.draw(Assets, mouseX, mouseY)
    else
        local mouseX, mouseY = pointerPosition()
        if mobileWorld then
            local worldX, worldY = App.mobileCamera:screenToWorld(mouseX, mouseY)
            App.mobileCamera:beginDraw()
            World.draw(Assets, CharacterAssets, state, worldX, worldY)
            App.mobileCamera:endDraw()
        else
            World.draw(Assets, CharacterAssets, state,
                state.screen == "world" and mouseX or nil,
                state.screen == "world" and mouseY or nil)
        end
        if state.screen == "world" then
            Hud.draw(state, World.prompt(), Assets, mouseX, mouseY,
                mobileControls and mobileControls:isEnabled(), controller and controller:isActive(), viewBounds)
        elseif state.screen == "computer" then
            ComputerScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "machine" then
            MachineScreen.draw(state, Assets, mouseX, mouseY)
        elseif state.screen == "press" then
            PressScreen.draw(state, Assets, mouseX, mouseY)
        elseif state.screen == "job_offer" then
            JobOfferScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "truck_inventory" then
            TruckInventoryScreen.draw(state, World, Assets, mouseX, mouseY)
        elseif state.screen == "vendor" then
            VendorScreen.draw(state, Assets, mouseX, mouseY)
        end
    end
    Ui.drawPressFeedback()
    if controller then controller:draw() end
    if mobileUi then App.mobileCamera:endDraw() end
    if mobileControls then mobileControls:draw() end
    Viewport.endDraw()
    Smoke.drawn()
end

function App.keypressed(key)
    if spriteLabActive then SpriteMotionLab.keypressed(key, CharacterAssets); return end
    if state.screen == "asset_error" then
        if key == "escape" or key == "q" then love.event.quit() end
        return
    end
    Input.keypressed(key, inputContext)
end

function App.keyreleased(key)
    Input.keyreleased(key, inputContext)
end

function App.textinput(text)
    Input.textinput(text, inputContext)
end

function App.mousepressed(x, y, button, isTouch)
    if mobileControls and mobileControls:ignoreSyntheticMouse(isTouch) then return end
    return dispatchMousePressed(x, y, button)
end

function App.mousereleased(x, y, button, isTouch)
    if mobileControls and mobileControls:ignoreSyntheticMouse(isTouch) then return end
    return dispatchMouseReleased(x, y, button)
end

function App.mousemoved(x, y, _, _, isTouch)
    if mobileControls and mobileControls:ignoreSyntheticMouse(isTouch) then return end
    return dispatchMouseMoved(x, y)
end

function App.wheelmoved(x, y)
    Input.wheelmoved(x, y, inputContext)
end

function App.touchpressed(id, x, y)
    if mobileControls then return mobileControls:touchpressed(id, x, y) end
end

function App.touchmoved(id, x, y, dx, dy)
    if mobileControls then return mobileControls:touchmoved(id, x, y, dx, dy) end
end

function App.touchreleased(id, x, y)
    if mobileControls then return mobileControls:touchreleased(id, x, y) end
end

function App.gamepadpressed(joystick, button)
    if controller then return controller:gamepadpressed(joystick, button) end
end

function App.gamepadreleased(joystick, button)
    if controller then return controller:gamepadreleased(joystick, button) end
end

function App.focus(focused)
    if not focused and mobileControls then
        mobileControls:cancelAll()
        saveCurrent()
    end
    if not focused and controller then controller:cancelAll() end
end

function App.quit()
    if not spriteLabActive then saveCurrent() end
end

return App
