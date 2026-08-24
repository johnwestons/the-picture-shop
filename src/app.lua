local Assets = require("src.assets")
local AssetErrorScreen = require("src.screens.asset_error_screen")
local BayDoor = require("src.bay_door")
local CharacterAssets = require("src.character_assets")
local ComputerScreen = require("src.screens.computer_screen")
local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local Hud = require("src.screens.hud")
local Input = require("src.input")
local JobOfferScreen = require("src.screens.job_offer_screen")
local JobService = require("src.job_service")
local Jobs = require("src.jobs")
local Machine = require("src.machine")
local Navigation = require("src.navigation")
local Procurement = require("src.procurement")
local Wrapper = require("src.wrapper")
local MachineScreen = require("src.screens.machine_screen")
local PalletJack = require("src.pallet_jack")
local PalletState = require("src.pallet_state")
local PalletLogistics = require("src.pallet_logistics")
local Receiving = require("src.receiving")
local Save = require("src.save")
local Shop = require("src.shop")
local Smoke = require("src.smoke")
local State = require("src.state")
local TitleScreen = require("src.screens.title_screen")
local Truck = require("src.truck")
local TruckInventoryScreen = require("src.screens.truck_inventory_screen")
local VendorScreen = require("src.screens.vendor_screen")
local Viewport = require("src.viewport")
local World = require("src.world")

local App = {}
local state = State.new()

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
    title = TitleScreen,
    saveCurrent = saveCurrent,
    returnToTitle = returnToTitle,
}

function App.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    if Smoke.requested() then love.filesystem.setIdentity("the-picture-shop-smoke") end
    Assets.load()
    CharacterAssets.load()
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
            characterAssets = CharacterAssets,
            wrapper = Wrapper,
            computerScreen = ComputerScreen,
            Customer = Customer,
            config = Config,
            CutterPlacement = CutterPlacement,
            CutterZones = CutterZones,
            machine = Machine,
            machineScreen = MachineScreen,
            Navigation = Navigation,
            PalletJack = PalletJack,
            PalletState = PalletState,
            PalletLogistics = PalletLogistics,
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
            Truck = Truck,
            truckInventoryScreen = TruckInventoryScreen,
            vendorScreen = VendorScreen,
            world = World,
            startupTextureBytes = startupTextureBytes,
        })
    end
end

function App.update(dt)
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
        if state.machineType == "skid_wrapper" then
            local previousStep = Wrapper.step
            Wrapper.update(dt, state)
            if previousStep ~= "finished" and Wrapper.step == "finished" then saveCurrent() end
            return
        end
        local previousStep = Machine.step
        Machine.update(dt, state)
        if previousStep ~= "finished" and Machine.step == "finished" then saveCurrent() end
    end
end

function App.draw()
    love.graphics.clear(0.04, 0.05, 0.07)
    Viewport.beginDraw(Config.baseWidth, Config.baseHeight)
    local desiredPack = state.screen == "title" and "menu"
        or state.screen == "machine"
            and (state.machineType == "skid_wrapper" and "wrapper" or "cutter") or nil
    if not Assets.activatePack(desiredPack) then
        local _, failures = Assets.assertHealthy()
        state.assetErrors = AssetErrorScreen.normalize(failures)
        state.screen = "asset_error"
        state.message = "A screen asset pack could not be loaded."
    end
    if state.screen == "asset_error" then
        CharacterAssets.retainCharacters({})
        AssetErrorScreen.draw(state.assetErrors)
    elseif state.screen == "title" then
        CharacterAssets.retainCharacters({})
        local mouseX, mouseY = love.mouse.getPosition()
        mouseX, mouseY = Viewport.toGame(mouseX, mouseY, Config.baseWidth, Config.baseHeight)
        TitleScreen.draw(Assets, mouseX, mouseY)
    else
        local mouseX, mouseY = love.mouse.getPosition()
        mouseX, mouseY = Viewport.toGame(mouseX, mouseY, Config.baseWidth, Config.baseHeight)
        World.draw(Assets, CharacterAssets, state,
            state.screen == "world" and mouseX or nil,
            state.screen == "world" and mouseY or nil)
        if state.screen == "world" then
            Hud.draw(state, World.prompt(), Assets, mouseX, mouseY)
        elseif state.screen == "computer" then
            ComputerScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "machine" then
            MachineScreen.draw(state, Assets, mouseX, mouseY)
        elseif state.screen == "job_offer" then
            JobOfferScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "truck_inventory" then
            TruckInventoryScreen.draw(state, World, Assets, mouseX, mouseY)
        elseif state.screen == "vendor" then
            VendorScreen.draw(state, Assets, mouseX, mouseY)
        end
    end
    Viewport.endDraw()
    Smoke.drawn()
end

function App.keypressed(key)
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

function App.mousepressed(x, y, button)
    if state.screen == "asset_error" then return end
    local gameX, gameY = Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight)
    Input.mousepressed(gameX, gameY, button, inputContext)
end

function App.mousereleased(x, y, button)
    local gameX, gameY = Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight)
    Input.mousereleased(gameX, gameY, button, inputContext)
end

function App.mousemoved(x, y)
    local gameX, gameY = Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight)
    Input.mousemoved(gameX, gameY, inputContext)
end

function App.quit()
    saveCurrent()
end

return App
