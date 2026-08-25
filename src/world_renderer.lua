local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local PalletJack = require("src.pallet_jack")
local PalletLogistics = require("src.pallet_logistics")
local MachineFleet = require("src.machine_fleet")
local PlacementGrid = require("src.placement_grid")
local Wrapper = require("src.wrapper")
local WrapperPlacement = require("src.wrapper_placement")
local WindmillPlacement = require("src.windmill_placement")
local Technician = require("src.technician")

local Renderer = {}
local World
local checkerShader

local function drawWallVentFan(assets)
    local image = assets.get("wallVentFan")
    if not image then return end
    local frame = math.floor(love.timer.getTime() * Config.wallVentFan.framesPerSecond)
        % Config.wallVentFan.frameCount + 1
    local sprite = assets.getQuad("wallVentFan" .. frame)
    if not sprite then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, Config.wallVentFan.x, Config.wallVentFan.y, 0,
        Config.wallVentFan.drawScale, Config.wallVentFan.drawScale,
        sprite.width / 2, sprite.height / 2)
end

local function drawPalletJack(assets, state)
    local frame, loaded, palletFrame = PalletJack.frame(state, Config.palletJack)
    local carried = loaded and PalletJack.carriedItem(state, Config.palletJack) or nil
    local vendorLoad = carried and carried.vendor
    local boxedLoad = carried and not vendorLoad and carried.pallet.packaging == "boxed"
    local flatWrappedLoad = carried and not vendorLoad and not boxedLoad and carried.pallet.wrapped
    -- Always draw the smaller empty jack first. Every carried pallet is a
    -- separate depth layer afterward, so pallet size stays unchanged and the
    -- load can never slip underneath the forks/body.
    local imageName = "palletJack"
    local quadName = imageName .. frame
    local image, sprite = assets.get(imageName), assets.getQuad(quadName)
    if not image or not sprite then return end
    local jack = state.palletJack
    local scale = Config.palletJack.drawScale
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, jack.x, jack.y, 0, scale, scale,
        sprite.width / 2, sprite.height * 0.88)

    if carried then
        local productImage = assets.get(vendorLoad and "vendorProductPallets"
            or (boxedLoad and "boxedPaperPalletStages"
                or (flatWrappedLoad and "wrappedPalletStages" or "loadedPaperPalletDirections")))
        local productSprite
        if vendorLoad then
            productSprite = assets.getQuad(
                "vendorProductPallet" .. tostring(carried.pallet.assetRow or 1) .. "_" .. palletFrame)
        elseif boxedLoad then
            productSprite = assets.getQuad(
                "boxedPaperPalletStage" .. (carried.pallet.wrapped and 5 or 1) .. "_" .. palletFrame)
        elseif flatWrappedLoad then
            productSprite = assets.getQuad("wrappedPalletStage3")
        else
            productSprite = assets.getQuad("loadedPaperPallet" .. palletFrame)
        end
        if productImage and productSprite then
            local productScale = Config.palletLogistics.drawScale * (flatWrappedLoad and 0.5 or 1)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(productImage, productSprite.quad, jack.x, jack.y - 3, 0,
                productScale, productScale,
                productSprite.width / 2, productSprite.height * 0.92)
        end
    end
end

function Renderer.palletVisual(item)
    local boxed = not item.vendor and item.pallet.packaging == "boxed"
    local stage = 1
    if boxed then
        if item.pallet.wrapped then stage = 5 end
        if Wrapper.pallet == item.pallet and Wrapper.step == "wrapping" then
            stage = math.max(1, math.min(5, math.floor(Wrapper.filmHeight() * 4) + 1))
        end
    end
    local flatWrapped = not item.vendor and not boxed and item.pallet.wrapped
    local imageName = item.vendor and "vendorProductPallets"
        or (boxed and "boxedPaperPalletStages"
            or (flatWrapped and "wrappedPalletStages" or "loadedPaperPalletDirections"))
    local frame = PalletLogistics.directionFrame(item.pallet)
    local spriteName = item.vendor and ("vendorProductPallet" .. tostring(item.pallet.assetRow or 1) .. "_" .. frame)
        or (boxed and ("boxedPaperPalletStage" .. stage .. "_" .. frame)
            or (flatWrapped and "wrappedPalletStage3" or ("loadedPaperPallet" .. frame)))
    return imageName, spriteName,
        Config.palletLogistics.drawScale * (flatWrapped and 0.5 or 1), flatWrapped
end

local function drawPallet(assets, item)
    local imageName, spriteName, scale = Renderer.palletVisual(item)
    local image = assets.get(imageName)
    local sprite = assets.getQuad(spriteName)
    if not image or not sprite then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, item.x, item.y, 0, scale, scale,
        sprite.width / 2, sprite.height * 0.92)
    love.graphics.setColor(0.12, 0.24, 0.34, 0.95)
    love.graphics.rectangle("fill", item.x - 22, item.y - 15, 44, 12)
    love.graphics.setColor(0.92, 0.96, 0.94)
    love.graphics.printf(item.vendor and "STOCK" or ("P" .. tostring(item.pallet.number)), item.x - 25, item.y - 14, 50, "center")
end

local function drawPalletTooltip(state, mouseX, mouseY)
    local hovered = PalletLogistics.hovered(state, mouseX, mouseY)
    if not hovered and state then
        local carried = PalletJack.carriedItem(state, Config.palletJack)
        if carried and mouseX >= carried.x - 58 and mouseX <= carried.x + 58
            and mouseY >= carried.y - 92 and mouseY <= carried.y + 12
        then
            hovered = carried
        end
    end
    local tooltip = PalletLogistics.tooltip(hovered)
    if not tooltip then return end
    local width, height = 390, 86
    local x = math.min(Config.baseWidth - width - 12, mouseX + 16)
    local y = math.min(Config.baseHeight - height - 12, mouseY + 16)
    love.graphics.setColor(0.025, 0.04, 0.055, 0.96)
    love.graphics.rectangle("fill", x, y, width, height, 4, 4)
    love.graphics.setColor(0.42, 0.70, 0.76)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, width, height, 4, 4)
    love.graphics.setColor(0.96, 0.84, 0.30)
    love.graphics.print(tooltip.title, x + 12, y + 9)
    love.graphics.setColor(0.84, 0.90, 0.91)
    love.graphics.print(tooltip.line1, x + 12, y + 29)
    love.graphics.print(tooltip.line2, x + 12, y + 47)
    love.graphics.print(tooltip.line3, x + 12, y + 65)
end

local function drawTruck(assets, state)
    if not World.truck:isVisible() then return end
    local machineDelivery = World.truck.mode == "machine_delivery"
    local truckImage, cargoImage, cargoSprite
    if machineDelivery then
        local loaded = MachineFleet.remainingOnTruck(state, World.truck.jobId) > 0
        truckImage = assets.get(loaded and "machineFlatbedLoaded" or "machineFlatbedEmpty")
        if not truckImage then return end
    else
        truckImage = assets.get("deliveryTruck")
        cargoImage = assets.get("truckCargoDoor")
        cargoSprite = assets.getQuad("truckCargoDoor" .. World.truck:cargoFrame())
        if not truckImage or not cargoImage or not cargoSprite then return end
    end

    local aperture = {}
    for _, point in ipairs(Config.truck.aperture) do
        aperture[#aperture + 1] = point.x
        aperture[#aperture + 1] = point.y
    end
    love.graphics.stencil(function()
        love.graphics.polygon("fill", unpack(aperture))
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    local transform = World.truck:transform()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(
        truckImage,
        transform.x,
        transform.y,
        0,
        transform.scale,
        transform.scale,
        Config.truck.frameSize / 2,
        Config.truck.frameSize * 0.84
    )
    if not machineDelivery then
        love.graphics.draw(
            cargoImage,
            cargoSprite.quad,
            transform.x,
            transform.y,
            0,
            transform.scale,
            transform.scale,
            Config.truck.frameSize / 2,
            Config.truck.frameSize * 0.84
        )
    end
    love.graphics.setStencilTest()
end

local function drawBayDoor(assets)
    local image = assets.get("loadingBayDoor")
    local sprite = assets.getQuad("loadingBayDoor" .. World.bayDoor:frame())
    local warehouse = assets.get("warehouse")
    if not image or not sprite or not warehouse then return end
    local scaleX = Config.baseWidth / warehouse:getWidth()
    local scaleY = Config.baseHeight / warehouse:getHeight()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(
        image,
        sprite.quad,
        Config.loadingBay.sourceX * scaleX,
        Config.loadingBay.sourceY * scaleY,
        0,
        scaleX,
        scaleY
    )
end

local function drawBackground(assets)
    local background = assets.get("warehouse")
    if background then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            background,
            0,
            0,
            0,
            Config.baseWidth / background:getWidth(),
            Config.baseHeight / background:getHeight()
        )
        return
    end

    love.graphics.setColor(0.33, 0.35, 0.34)
    love.graphics.polygon("fill", 80, 115, 480, 55, 880, 115, 480, 620)
end

local function drawCutter(assets, state, placement)
    local cutter = placement or CutterPlacement.ensure(state, Config.cutterPlacement)
    local image = assets.get("polarDirections")
    local frame = placement and (placement.frame or 1)
        or CutterPlacement.frame(state, Config.cutterPlacement)
    local sprite = assets.getQuad("polarDirection" .. frame)
    if image and sprite then
        local scale = Config.cutterPlacement.drawScale
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            image,
            sprite.quad,
            cutter.x,
            cutter.y,
            0,
            scale,
            scale,
            sprite.width / 2,
            sprite.height * 0.96
        )
        return
    end

    love.graphics.setColor(0.36, 0.39, 0.43)
    love.graphics.rectangle(
        "fill",
        cutter.x - 58,
        cutter.y - 55,
        116,
        55
    )
end

local function drawWrapper(assets, state, placement)
    local wrapper = placement or WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local image = assets.get("skidWrapperDirections")
    local directions = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }
    local frame = placement and (directions[placement.direction] or placement.frame or 1)
        or WrapperPlacement.frame(state, Config.wrapperPlacement)
    local sprite = assets.getQuad("skidWrapperDirection" .. frame)
    if not image or not sprite then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, wrapper.x, wrapper.y, 0,
        Config.wrapperPlacement.drawScale, Config.wrapperPlacement.drawScale,
        sprite.width / 2, sprite.height * 0.94)
end

local function drawWindmill(assets, state, placement)
    local item = placement or WindmillPlacement.ensure(state, Config.windmillPlacement)
    local image = assets.get("windmillDirections")
    local frame = placement and (placement.frame or 1)
        or WindmillPlacement.frame(state, Config.windmillPlacement)
    local sprite = assets.getQuad("windmillDirection" .. frame)
    if not image or not sprite then return end
    if not checkerShader then
        checkerShader = love.graphics.newShader([[
            vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_coords) {
                vec4 px = Texel(texture, uv);
                float spread = max(max(abs(px.r-px.g), abs(px.g-px.b)), abs(px.r-px.b));
                if (px.r > 0.86 && px.g > 0.86 && px.b > 0.86 && spread < 0.018) discard;
                return px * color;
            }
        ]])
    end
    love.graphics.setShader(checkerShader)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, item.x, item.y, 0,
        Config.windmillPlacement.drawScale, Config.windmillPlacement.drawScale,
        sprite.width / 2, sprite.height * 0.94)
    love.graphics.setShader()
end

local function drawPlayer(assets)
    local player = World.player
    local action = player.moving and "walk" or "idle"
    -- Generated walk frames 1 and 6 contain doubled silhouettes. Loop the
    -- four clean poses forward and back for a stable six-step walk cycle.
    local walkFrames = { 2, 3, 4, 5, 4, 3 }
    local frameCount = action == "walk" and #walkFrames or 2
    local rate = action == "walk" and 9 or 2
    local frame = math.floor(player.animationClock * rate) % frameCount + 1
    if action == "walk" then frame = walkFrames[frame] end
    local quad, cellWidth, cellHeight = assets.getRabbitFrame(action, frame)
    local image = assets.get("rabbit")


    if image and quad then
        local scaleX = Config.player.drawScale * player.facing
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            image,
            quad,
            player.x,
            player.y,
            0,
            scaleX,
            Config.player.drawScale,
            cellWidth / 2,
            cellHeight * 0.94
        )
        return
    end

    love.graphics.setColor(0.75, 0.58, 0.42)
    love.graphics.rectangle("fill", player.x - 9, player.y - 38, 18, 28)
    love.graphics.rectangle("fill", player.x - 13, player.y - 56, 9, 18)
    love.graphics.rectangle("fill", player.x + 4, player.y - 56, 9, 18)
    love.graphics.setColor(0.25, 0.46, 0.62)
    love.graphics.rectangle("fill", player.x - 13, player.y - 10, 26, 18)
end

function Renderer.draw(world, assets, characterAssets, state, mouseX, mouseY)
    World = world
    drawBackground(assets)
    drawWallVentFan(assets)
    drawBayDoor(assets)
    drawTruck(assets, state)
    PlacementGrid.draw(World.placementGridSnapshot(state, assets))
    local visibleCharacters = {}
    if World.customer.visible then visibleCharacters[World.customer.character] = true end
    if World.vendor.visible then visibleCharacters[World.vendor.character] = true end
    characterAssets.retainCharacters(visibleCharacters)
    local jack = state and PalletJack.ensure(state, Config.palletJack)
    local cutter = state and CutterPlacement.ensure(state, Config.cutterPlacement)
    local wrapper = state and WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local windmill = state and WindmillPlacement.ensure(state, Config.windmillPlacement)
    local actors = {}
    if MachineFleet.isInstalled(state, "polar_115") then
        actors[#actors + 1] = { y = cutter.moving and jack.y or cutter.y,
            layer = cutter.moving and 2 or 0, draw = function() drawCutter(assets, state) end }
    end
    if MachineFleet.isInstalled(state, "skid_wrapper") then
        actors[#actors + 1] = { y = wrapper.moving and jack.y or wrapper.y,
            layer = wrapper.moving and 2 or 0, draw = function() drawWrapper(assets, state) end }
    end
    if MachineFleet.isInstalled(state, "heidelberg_10x15") then
        actors[#actors + 1] = { y = windmill.moving and jack.y or windmill.y,
            layer = windmill.moving and 2 or 0, draw = function() drawWindmill(assets, state) end }
    end
    for _, machine in ipairs(MachineFleet.owned(state)) do
        if machine.status == "stored" and machine.world then
            local storedMachine = machine
            if storedMachine.modelId == "polar_115" then
                actors[#actors + 1] = { y = storedMachine.world.y,
                    draw = function() drawCutter(assets, state, storedMachine.world) end }
            elseif storedMachine.modelId == "skid_wrapper" then
                actors[#actors + 1] = { y = storedMachine.world.y,
                    draw = function() drawWrapper(assets, state, storedMachine.world) end }
            elseif storedMachine.modelId == "heidelberg_10x15" then
                actors[#actors + 1] = { y = storedMachine.world.y,
                    draw = function() drawWindmill(assets, state, storedMachine.world) end }
            end
        end
    end
    if jack and jack.operating then
        -- Separate depth entries keep the operator naturally behind or in
        -- front of the handle as the jack changes direction.
        actors[#actors + 1] = { y = jack.y, layer = 1, draw = function() drawPalletJack(assets, state) end }
        actors[#actors + 1] = { y = World.player.y, draw = function() drawPlayer(assets) end }
    else
        actors[#actors + 1] = { y = World.player.y, draw = function() drawPlayer(assets) end }
        if jack then actors[#actors + 1] = { y = jack.y, draw = function() drawPalletJack(assets, state) end } end
    end
    for _, item in ipairs(PalletLogistics.physicalPallets(state)) do
        actors[#actors + 1] = { y = item.y, draw = function() drawPallet(assets, item) end }
    end
    if World.customer.visible then
        actors[#actors + 1] = {
            y = World.customer.y,
            draw = function() World.customer:draw(characterAssets) end,
        }
    end
    if World.vendor.visible then
        actors[#actors + 1] = { y = World.vendor.y, draw = function() World.vendor:draw(characterAssets) end }
    end
    local technician = state and Technician.ensure(state)
    if technician and technician.visible then
        actors[#actors + 1] = { y = technician.y, draw = function() Technician.draw(assets, state) end }
    end
    table.sort(actors, function(a, b)
        if a.y == b.y then return (a.layer or 0) < (b.layer or 0) end
        return a.y < b.y
    end)
    for _, actor in ipairs(actors) do actor.draw() end
    drawPalletTooltip(state, mouseX, mouseY)
end


return Renderer
