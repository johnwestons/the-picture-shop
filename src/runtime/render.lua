-- World, screen, and overlay rendering.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.App.draw()
        Runtime.CharacterAssets.beginFrame()
        love.graphics.clear(0.04, 0.05, 0.07)
        local viewBounds = Runtime.syncCamera()
        if Runtime.mobileControls then Runtime.mobileControls:setBounds(viewBounds) end
        local mobileWorld = Runtime.App.cameraTransformsWorld()
        local mobileUi = Runtime.App.cameraTransformsUi()
        Runtime.Viewport.beginDraw(Runtime.Config.baseWidth, Runtime.Config.baseHeight, not (mobileWorld or mobileUi), Runtime.App.officeFitsScreen())
        if Runtime.spriteLabActive then
            Runtime.SpriteMotionLab.draw(Runtime.CharacterAssets)
            Runtime.CharacterAssets.endFrame()
            Runtime.Viewport.endDraw()
            Runtime.Smoke.drawn()
            return
        end
        Runtime.WorldRenderer.beginFrame()
        local desiredPack = (Runtime.state.screen == "title" or Runtime.state.screen == "lan"
            or Runtime.state.screen == "direct") and "menu"
            or Runtime.state.screen == "machine"
                and (Runtime.state.machineType == "skid_wrapper" and "wrapper" or "cutter")
            or Runtime.state.screen == "workshop_remote" and Runtime.WorkshopRemoteScreen.requiredAssetPack()
            or Runtime.state.screen == "press" and "press" or nil
        -- Options uses procedural UI. Keep the underlying screen's textures
        -- pinned instead of decoding the large title art and evicting the machine.
        if Runtime.state.screen == "options" then desiredPack = Runtime.Assets.activePackName() end
        if not Runtime.Assets.activatePack(desiredPack) then
            local _, failures = Runtime.Assets.assertHealthy()
            Runtime.state.assetErrors = Runtime.AssetErrorScreen.normalize(failures)
            Runtime.state.screen = "asset_error"
            Runtime.state.message = "A screen asset pack could not be loaded."
        end
        if mobileUi then Runtime.App.mobileCamera:beginDraw() end
        if Runtime.state.screen == "asset_error" then
            Runtime.CharacterAssets.retainCharacters({}, true)
            Runtime.AssetErrorScreen.draw(Runtime.state.assetErrors)
        elseif Runtime.state.screen == "title" then
            Runtime.CharacterAssets.retainCharacters({}, true)
            local mouseX, mouseY = Runtime.pointerPosition()
            Runtime.TitleScreen.draw(Runtime.Assets, mouseX, mouseY)
        elseif Runtime.state.screen == "lan" then
            Runtime.CharacterAssets.retainCharacters({}, true)
            Runtime.LanScreen.draw()
        elseif Runtime.state.screen == "direct" then
            Runtime.CharacterAssets.retainCharacters({}, true)
            Runtime.DirectScreen.draw()
        elseif Runtime.state.screen == "options" then
            Runtime.CharacterAssets.retainCharacters({}, true)
            local mouseX, mouseY = Runtime.pointerPosition()
            Runtime.OptionsScreen.draw(mouseX, mouseY)
        else
            local mouseX, mouseY = Runtime.pointerPosition()
            if mobileWorld then
                local worldX, worldY = Runtime.App.mobileCamera:screenToWorld(mouseX, mouseY)
                Runtime.App.mobileCamera:beginDraw()
                Runtime.World.draw(Runtime.Assets, Runtime.CharacterAssets, Runtime.state, worldX, worldY, Runtime.multiplayer:remotePlayers())
                Runtime.App.mobileCamera:endDraw()
            else
                Runtime.World.draw(Runtime.Assets, Runtime.CharacterAssets, Runtime.state,
                    Runtime.state.screen == "world" and mouseX or nil,
                    Runtime.state.screen == "world" and mouseY or nil,
                    Runtime.multiplayer:remotePlayers())
            end
            if Runtime.state.screen == "world" then
                Runtime.RuntimeDependencies.Hud.draw(Runtime.state, Runtime.World.prompt(), Runtime.Assets, mouseX, mouseY,
                    Runtime.mobileControls and Runtime.mobileControls:isEnabled(), Runtime.controller and Runtime.controller:isActive(), viewBounds,
                    Runtime.App.settings and Runtime.App.settings.followPlayerCamera,
                    Runtime.App.settings and Runtime.App.settings.twelveHourTime)
                Runtime.MultiplayerHud.draw(Runtime.multiplayerHudInfo())
                Runtime.HighFiveUi.draw(Runtime.multiplayer:highFiveInfo())
            elseif Runtime.state.screen == "computer" then
                Runtime.ComputerScreen.draw(Runtime.state, mouseX, mouseY, Runtime.Assets,
                    Runtime.App.settings and Runtime.App.settings.twelveHourTime)
            elseif Runtime.state.screen == "shop_rooms" then
                require("src.shop_room_controls").draw(Runtime)
            elseif Runtime.state.screen == "air_hockey" then
                require("src.screens.air_hockey_screen").draw(Runtime)
            elseif Runtime.state.screen == "critter_kombat" then
                require("src.screens.critter_kombat_screen").draw(Runtime)
            elseif Runtime.state.screen == "shop_clock" then
                require("src.screens.shop_clock").draw(Runtime.state,mouseX,mouseY,
                    Runtime.App.settings and Runtime.App.settings.twelveHourTime)
            elseif Runtime.state.screen == "work_phone" then
                Runtime.WorkPhoneScreen.draw(Runtime.state, mouseX, mouseY, Runtime.Assets)
            elseif Runtime.state.screen == "machine" then
                Runtime.MachineScreen.draw(Runtime.state, Runtime.Assets, mouseX, mouseY)
            elseif Runtime.state.screen == "press" then
                Runtime.PressScreen.draw(Runtime.state, Runtime.Assets, mouseX, mouseY)
            elseif Runtime.state.screen == "job_offer" then
                Runtime.JobOfferScreen.draw(Runtime.state, mouseX, mouseY, Runtime.Assets)
            elseif Runtime.state.screen == "workshop_remote" then
                Runtime.WorkshopRemoteScreen.draw(Runtime.state, mouseX, mouseY, Runtime.Assets)
            elseif Runtime.state.screen == "truck_inventory" then
                Runtime.RuntimeDependencies.TruckInventoryScreen.draw(Runtime.state, Runtime.World, Runtime.Assets, mouseX, mouseY)
            elseif Runtime.state.screen == "vendor" then
                Runtime.VendorScreen.draw(Runtime.state, Runtime.Assets, mouseX, mouseY)
            elseif Runtime.state.screen == "pallet_work_order" then
                Runtime.RuntimeDependencies.PalletWorkOrderScreen.draw(Runtime.state, Runtime.Assets, mouseX, mouseY)
            end
            Runtime.warehouseControls:draw(Runtime.Assets)
        end
        if Runtime.state.screen ~= "options" and Runtime.state.screen ~= "asset_error"
            and Runtime.state.screen ~= "critter_kombat" then
            local optionsX, optionsY = Runtime.pointerPosition()
            local accessScreen, accessBounds = Runtime.optionsAccessLayout()
            Runtime.OptionsScreen.drawAccessButton(optionsX, optionsY, accessScreen, accessBounds, Runtime.Assets)
        end
        Runtime.Ui.drawPressFeedback()
        if Runtime.controller then Runtime.controller:draw() end
        if mobileUi then Runtime.App.mobileCamera:endDraw() end
        if Runtime.mobileControls then Runtime.mobileControls:draw() end
        Runtime.WorldRenderer.endFrame()
        Runtime.CharacterAssets.endFrame()
        Runtime.Viewport.endDraw()
        Runtime.Smoke.drawn()
    end
end

return Component
