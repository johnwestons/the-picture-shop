local Config = require("src.config")
local BayDoor = require("src.bay_door")
local CutterPlacement = require("src.cutter_placement")
local Customer = require("src.customer")
local Interaction = require("src.interaction")
local Navigation = require("src.navigation")
local PalletLogistics = require("src.pallet_logistics")
local PalletJack = require("src.pallet_jack")
local Procurement = require("src.procurement")
local Truck = require("src.truck")
local WrapperPlacement = require("src.wrapper_placement")
local Wrapper = require("src.wrapper")

local World = {
    player = {
        x = Config.player.spawnX,
        y = Config.player.spawnY,
        speed = Config.player.speed,
        moving = false,
        facing = 1,
        animationClock = 0,
    },
    bayDoor = BayDoor.new(Config.loadingBay),
    truck = Truck.new(Config.truck),
    customer = Customer.new(Config.customer),
    vendor = Customer.new(Config.vendor),
    selectedInteraction = nil,
}

local function movementObstacles(state, excludeJack, inflate, excludeCutter, excludeWrapper)
    inflate = inflate or { x = 0, y = 0 }
    if type(inflate) == "number" then inflate = { x = inflate, y = inflate } end
    local obstacles = {}
    if not excludeCutter then
        local cutterObstacle = CutterPlacement.obstacle(state, Config.cutterPlacement)
        if cutterObstacle then obstacles[#obstacles + 1] = cutterObstacle end
    end
    if not excludeWrapper then
        local wrapperObstacle = WrapperPlacement.obstacle(state, Config.wrapperPlacement)
        if wrapperObstacle then obstacles[#obstacles + 1] = wrapperObstacle end
    end
    local customerObstacle = World.customer:getObstacle()
    if customerObstacle then obstacles[#obstacles + 1] = customerObstacle end
    local vendorObstacle = World.vendor:getObstacle()
    if vendorObstacle then obstacles[#obstacles + 1] = vendorObstacle end
    local bayObstacle = World.bayDoor:getObstacle()
    if bayObstacle then obstacles[#obstacles + 1] = bayObstacle end
    local truckObstacle = World.truck:getObstacle()
    if truckObstacle then obstacles[#obstacles + 1] = truckObstacle end
    for _, obstacle in ipairs(PalletLogistics.obstacles(state,
        Config.palletLogistics.collisionHalfWidth,
        Config.palletLogistics.collisionHalfHeight)) do
        obstacles[#obstacles + 1] = obstacle
    end
    if not excludeJack then
        local jackObstacle = PalletJack.obstacle(state, Config.palletJack)
        if jackObstacle then obstacles[#obstacles + 1] = jackObstacle end
    end
    if inflate.x > 0 or inflate.y > 0 then
        for _, obstacle in ipairs(obstacles) do
            if obstacle.halfWidth and obstacle.halfHeight then
                obstacle.halfWidth = obstacle.halfWidth + inflate.x
                obstacle.halfHeight = obstacle.halfHeight + inflate.y
            else
                obstacle.radius = obstacle.radius + math.max(inflate.x, inflate.y)
            end
        end
    end
    return obstacles
end

local function interactables()
    local targets = {
        computer = Config.interactables.computer,
    }
    local customerInteraction = World.customer:getInteraction()
    if customerInteraction then targets.customer = customerInteraction end
    local vendorInteraction = World.vendor:getInteraction()
    if vendorInteraction then
        vendorInteraction.prompt = "E: talk to the " .. Procurement.category(World._state and World._state.vendorCategory).name:lower() .. " salesman"
        targets.vendor = vendorInteraction
    end
    targets.loadingBayDoor = World.bayDoor:getInteraction()
    local truckInteraction = World.truck:getInteraction()
    if truckInteraction then targets.truckCargoDoor = truckInteraction end
    if World._state then
        targets.cutter = CutterPlacement.interaction(World.player, World._state, Config.cutterPlacement)
        targets.skidWrapper = WrapperPlacement.interaction(World.player, World._state, Config.wrapperPlacement)
        targets.palletJack = PalletJack.interaction(World.player, World._state, Config.palletJack)
    end
    return targets
end

function World.load(position)
    World.player.x = position and position.x or Config.player.spawnX
    World.player.y = position and position.y or Config.player.spawnY
    World.player.animationClock = 0
    World.bayDoor:reset()
    World.truck:reset()
    World.customer:reset()
    World.vendor:reset()
    World.selectedInteraction = nil
end

local function activeJobById(state, jobId)
    if not state or not state.jobs or type(state.jobs.active) ~= "table" then return nil end
    for _, job in ipairs(state.jobs.active) do
        if job.id == jobId then return job end
    end
    return nil
end

local function scheduleInboundTruck(state)
    if not state or World.truck.state ~= "absent" then return end
    local purchase = Procurement.nextInbound(state)
    if purchase then
        if World.truck:schedule(purchase.id, "vendor_delivery") then
            purchase.delivery.status = "scheduled"
            state.message = "Vendor delivery scheduled for " .. purchase.id .. "."
        end
        return
    end
    local activeJobs = state.jobs and state.jobs.active or {}
    for _, job in ipairs(activeJobs) do
        local deliveryStatus = job.delivery and job.delivery.status
        if job.status == "awaiting_delivery" and deliveryStatus ~= "received" then
            if World.truck:schedule(job.id, "delivery") then
                job.delivery = job.delivery or {}
                job.delivery.status = "scheduled"
                state.message = "Inbound truck scheduled for " .. job.id .. "."
            end
            return
        end
    end
end

local function updateTruck(dt, state)
    scheduleInboundTruck(state)
    local event = World.truck:update(dt, World.bayDoor.state)
    if not event then return end
    local job = activeJobById(state, World.truck.jobId)
    local purchase = Procurement.orderById(state, World.truck.jobId)
    if event == "request_bay_open" then
        if World.bayDoor.state == "closed" then World.bayDoor:open() end
        if state then state.message = "Delivery truck arrived. Opening the loading bay..." end
    elseif event == "backing_started" then
        if job and job.delivery then job.delivery.status = "backing" end
        if purchase and purchase.delivery then purchase.delivery.status = "backing" end
        if state then state.message = "The delivery truck is backing into the loading bay." end
    elseif event == "parked" then
        if job and job.delivery then job.delivery.status = "at_bay" end
        if purchase and purchase.delivery then purchase.delivery.status = "at_bay" end
        if state then state.message = "Truck parked. Open its rear cargo door to unload." end
    elseif event == "cargo_opened" then
        if state then state.message = "Truck cargo door open. Pallet inventory arrives in step seven." end
    elseif event == "cargo_closed" then
        local received = (job and job.delivery and job.delivery.status == "received")
            or (purchase and purchase.delivery and purchase.delivery.status == "received")
        if received and World.truck:depart() then
            if state then state.message = "Cargo secured. The empty truck is departing." end
        elseif state then
            state.message = "Truck cargo door closed."
        end
    elseif event == "departed" then
        if World.bayDoor.state == "open" then World.bayDoor:close() end
        if state then state.message = "The truck left. Closing the loading bay door..." end
    end
end

function World.update(dt, directionX, directionY, assets, state)
    World._state = state
    local player = World.player
    local jack = PalletJack.ensure(state, Config.palletJack)
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    if cutter.moving then
        CutterPlacement.move(state, directionX, directionY, dt, Config.cutterPlacement,
            function(nextX, nextY)
                local halfWidth = Config.cutterPlacement.collisionHalfWidth
                local halfHeight = Config.cutterPlacement.collisionHalfHeight
                local obstacles = movementObstacles(state, false,
                    { x = halfWidth, y = halfHeight }, true)
                if not Navigation.canMoveFrom(assets, cutter.x, cutter.y, nextX, nextY, obstacles) then
                    return false
                end
                local edgeOffsets = {
                    { x = -halfWidth, y = 0 }, { x = halfWidth, y = 0 },
                    { x = 0, y = -halfHeight }, { x = 0, y = halfHeight },
                }
                for _, offset in ipairs(edgeOffsets) do
                    if not Navigation.isWalkable(assets, nextX + offset.x, nextY + offset.y, {}) then
                        return false
                    end
                end
                return true
            end)
        player.x, player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
        player.moving = cutter.inMotion
        player.facing = player.x < cutter.x and 1 or -1
    elseif wrapper.moving then
        WrapperPlacement.move(state, directionX, directionY, dt, Config.wrapperPlacement,
            function(nextX, nextY)
                return Navigation.canMoveFrom(assets, wrapper.x, wrapper.y, nextX, nextY,
                    movementObstacles(state, false, {
                        x = Config.wrapperPlacement.collisionHalfWidth,
                        y = Config.wrapperPlacement.collisionHalfHeight,
                    }, false, true))
            end)
        player.x, player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement)
        player.moving = wrapper.inMotion
        player.facing = player.x < wrapper.x and 1 or -1
    elseif jack.operating then
        PalletJack.move(state, directionX, directionY, dt, Config.palletJack, function(nextX, nextY, loaded)
            local inflate = loaded and {
                x = Config.palletJack.loadedCollisionHalfWidth,
                y = Config.palletJack.loadedCollisionHalfHeight,
            } or {
                x = Config.palletJack.collisionHalfWidth,
                y = Config.palletJack.collisionHalfHeight,
            }
            return Navigation.canMoveFrom(assets, jack.x, jack.y, nextX, nextY,
                movementObstacles(state, true, inflate))
        end)
        player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
        player.moving = jack.moving
        player.facing = (jack.direction == "northeast" or jack.direction == "southeast") and 1 or -1
    else
        player.moving = directionX ~= 0 or directionY ~= 0
    end
    if player.moving and not jack.operating and not cutter.moving and not wrapper.moving then
        local length = math.sqrt(directionX * directionX + directionY * directionY)
        local nextX = player.x + directionX / length * player.speed * dt
        local nextY = player.y + directionY / length * player.speed * dt
        if Navigation.canMoveFrom(assets, player.x, player.y, nextX, nextY,
            movementObstacles(state, false))
        then
            player.x = nextX
            player.y = nextY
        end
        if directionX ~= 0 then player.facing = directionX < 0 and -1 or 1 end
    end

    player.animationClock = player.animationClock + dt
    local doorEvent = World.bayDoor:update(dt)
    if doorEvent == "opened" and state then
        state.message = "Loading bay door open. The parking lot is visible."
    elseif doorEvent == "closed" and state then
        state.message = "Loading bay door closed."
    end
    updateTruck(dt, state)
    PalletLogistics.update(state, dt, Config.palletLogistics.unloadDuration)
    local customerEvent = World.customer:update(dt, player)
    if customerEvent == "arrived" and state then
        state.message = "A customer is waiting at reception with a cutting job."
    elseif customerEvent == "timed_out" and state then
        state.message = "The client waited five minutes without being seen and is leaving."
    elseif customerEvent == "exited" and state then
        state.message = World.customer.decision == "timed_out"
            and "The client left after waiting five minutes."
            or (World.customer.decision == "accepted"
                and "The customer left after you accepted the job."
                or "The customer left after you declined the job.")
        -- Bring the next business client into the arrival queue after this
        -- visit so the configured roster is experienced during one session.
        World.customer:reset()
    end
    local category = Procurement.category(state and state.vendorCategory)
    World.vendor.character = category.character
    local vendorEvent = World.vendor:update(dt, player)
    if vendorEvent == "arrived" and state then
        state.message = category.salesman .. " is waiting at reception with the " .. category.name:lower() .. " catalog."
    elseif vendorEvent == "exited" and state then
        state.vendorCategory = state.vendorCategory % #Procurement.categories + 1
        World.vendor:reset()
        state.message = "The salesman left. Another supplier representative will visit soon."
    end
    World.selectedInteraction = Interaction.select(player, interactables())
end

local function drawPalletJack(assets, state)
    local frame, loaded = PalletJack.frame(state, Config.palletJack)
    local carried = loaded and PalletJack.carriedItem(state, Config.palletJack) or nil
    local vendorLoad = carried and carried.vendor
    local boxedLoad = carried and not vendorLoad and carried.pallet.packaging == "boxed"
    local imageName = loaded and not vendorLoad and not boxedLoad and "palletJackLoaded" or "palletJack"
    local quadName = imageName .. frame
    local image, sprite = assets.get(imageName), assets.getQuad(quadName)
    if not image or not sprite then return end
    local jack = state.palletJack
    local scale = Config.palletJack.drawScale
    if vendorLoad or boxedLoad then
        local productImage = assets.get(vendorLoad and "vendorProductPallets" or "boxedPaperPalletStages")
        local productSprite
        if vendorLoad then
            productSprite = assets.getQuad("vendorProductPallet" .. tostring(carried.pallet.assetRow or 1) .. "_" .. frame)
        else
            productSprite = assets.getQuad("boxedPaperPalletStage" .. (carried.pallet.wrapped and 5 or 1) .. "_" .. frame)
        end
        if productImage and productSprite then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(productImage, productSprite.quad, jack.x, jack.y - 3, 0,
                Config.palletLogistics.drawScale, Config.palletLogistics.drawScale,
                productSprite.width / 2, productSprite.height * 0.92)
        end
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, jack.x, jack.y, 0, scale, scale,
        sprite.width / 2, sprite.height * 0.88)
end

local function drawPallet(assets, item)
    local boxed = not item.vendor and item.pallet.packaging == "boxed"
    local stage = 1
    if boxed then
        if item.pallet.wrapped then stage = 5 end
        if Wrapper.pallet == item.pallet and Wrapper.step == "wrapping" then
            stage = math.max(1, math.min(5, math.floor(Wrapper.filmHeight() * 4) + 1))
        end
    end
    local imageName = item.vendor and "vendorProductPallets"
        or (boxed and "boxedPaperPalletStages" or "loadedPaperPalletDirections")
    local image = assets.get(imageName)
    local frame = PalletLogistics.directionFrame(item.pallet)
    local spriteName = item.vendor and ("vendorProductPallet" .. tostring(item.pallet.assetRow or 1) .. "_" .. frame)
        or (boxed and ("boxedPaperPalletStage" .. stage .. "_" .. frame) or ("loadedPaperPallet" .. frame))
    local sprite = assets.getQuad(spriteName)
    if not image or not sprite then return end
    local scale = Config.palletLogistics.drawScale
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, item.x, item.y, 0, scale, scale,
        sprite.width / 2, sprite.height * 0.92)
    -- `packaging` is the requested job outcome, not the pallet's current
    -- physical state. Only draw cartons after the wrapper has completed.
    if item.pallet.wrapped and not boxed then
        love.graphics.setColor(0.72, 0.90, 1.0, 0.22)
        love.graphics.polygon("fill", item.x - 43, item.y - 68, item.x + 43, item.y - 68,
            item.x + 48, item.y - 7, item.x - 48, item.y - 7)
        love.graphics.setColor(0.86, 0.96, 1.0, 0.55)
        for y = item.y - 60, item.y - 15, 12 do love.graphics.line(item.x - 42, y, item.x + 42, y) end
    end
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

local function drawTruck(assets)
    if not World.truck:isVisible() then return end
    local truckImage = assets.get("deliveryTruck")
    local cargoImage = assets.get("truckCargoDoor")
    local cargoSprite = assets.getQuad("truckCargoDoor" .. World.truck:cargoFrame())
    if not truckImage or not cargoImage or not cargoSprite then return end

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

local function drawCutter(assets, state)
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    local image = assets.get("polarDirections")
    local sprite = assets.getQuad("polarDirection" .. CutterPlacement.frame(state, Config.cutterPlacement))
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

local function drawWrapper(assets, state)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local image = assets.get("skidWrapperDirections")
    local sprite = assets.getQuad("skidWrapperDirection" .. WrapperPlacement.frame(state, Config.wrapperPlacement))
    if not image or not sprite then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, wrapper.x, wrapper.y, 0,
        Config.wrapperPlacement.drawScale, Config.wrapperPlacement.drawScale,
        sprite.width / 2, sprite.height * 0.94)
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

function World.draw(assets, characterAssets, state, mouseX, mouseY)
    drawBackground(assets)
    drawBayDoor(assets)
    drawTruck(assets)
    local jack = state and PalletJack.ensure(state, Config.palletJack)
    local cutter = state and CutterPlacement.ensure(state, Config.cutterPlacement)
    local wrapper = state and WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local actors = {
        { y = cutter.y, draw = function() drawCutter(assets, state) end },
        { y = wrapper.y, draw = function() drawWrapper(assets, state) end },
    }
    if jack and jack.operating then
        -- Separate depth entries keep the operator naturally behind or in
        -- front of the handle as the jack changes direction.
        actors[#actors + 1] = { y = jack.y, draw = function() drawPalletJack(assets, state) end }
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
    table.sort(actors, function(a, b) return a.y < b.y end)
    for _, actor in ipairs(actors) do actor.draw() end
    drawPalletTooltip(state, mouseX, mouseY)
end

function World.prompt()
    return Interaction.prompt(World.selectedInteraction)
end

function World.getInteraction()
    return World.selectedInteraction
end

function World.beginCustomerReview()
    return World.selectedInteraction
        and World.selectedInteraction.kind == "customer"
        and World.customer:beginReview()
        or false
end

function World.cancelCustomerReview(state)
    if not World.customer:cancelReview() then return false end
    if state then state.message = "The customer is still waiting whenever you are ready to review the job." end
    return true
end

function World.beginVendorReview()
    return World.selectedInteraction and World.selectedInteraction.kind == "vendor" and World.vendor:beginReview() or false
end

function World.cancelVendorReview(state)
    if not World.vendor:cancelReview() then return false end
    if state then state.message = "The salesperson is still waiting if you want to reopen the catalog." end
    return true
end

function World.resolveVendor(state)
    if not World.vendor:resolve("accepted") then return false end
    if state then state.message = "The supplier representative is heading out." end
    return true
end

function World.resolveCustomer(decision, state)
    if not World.customer:resolve(decision) then return false end
    if state then
        state.message = decision == "accepted"
            and "Job accepted. The customer is heading out."
            or "Job declined. The customer is heading out."
    end
    return true
end

function World.toggleBayDoor(state)
    if World.bayDoor.state == "open" and World.truck:blocksBayClosure() then
        if state then state.message = "The truck is occupying the bay. Keep the loading door open." end
        return false
    end
    if not World.bayDoor:toggle() then
        if state then state.message = "Wait for the loading bay door to finish moving." end
        return false
    end
    if state then
        state.message = World.bayDoor.state == "opening"
            and "Opening the loading bay door..."
            or "Closing the loading bay door..."
    end
    return true
end

function World.toggleTruckCargoDoor(state)
    if not World.truck:toggleCargoDoor() then
        if state then state.message = "Wait for the truck cargo door to finish moving." end
        return false
    end
    if state then
        state.message = World.truck.state == "cargo_opening"
            and "Opening the truck cargo door..."
            or "Closing the truck cargo door..."
    end
    return true
end

function World.openTruckInventory(state)
    if World.truck.state ~= "cargo_open" then return false end
    local job = activeJobById(state, World.truck.jobId)
    return job ~= nil or Procurement.orderById(state, World.truck.jobId) ~= nil
end

function World.unloadTruckPallet(state, palletId)
    if World.truck.state ~= "cargo_open" then
        if state then state.message = "Open the truck cargo door before unloading." end
        return false
    end
    local succeeded, pallet, remaining = PalletLogistics.unload(
        state,
        World.truck.jobId,
        palletId,
        Config.palletLogistics.spawnPoints,
        Config.palletLogistics.unloadOrigin
    )
    if state then
        state.message = succeeded
            and string.format("Unloaded %s. %d pallet(s) remain in the truck.", pallet.id, remaining)
            or tostring(pallet)
    end
    return succeeded, pallet, remaining
end

function World.closeTruckAfterUnload(state)
    if World.truck.state ~= "cargo_open" then return false end
    if PalletLogistics.remainingOnTruck(state, World.truck.jobId) > 0 then
        if state then state.message = "Unload every pallet before closing the cargo door." end
        return false
    end
    return World.toggleTruckCargoDoor(state)
end

function World.handlePalletJack(state, assets)
    local succeeded, action, pallet = PalletJack.use(state, Config.palletJack, function(x, y)
        return Navigation.isWalkable(assets, x, y,
            movementObstacles(state, true, {
                x = Config.palletJack.loadedCollisionHalfWidth,
                y = Config.palletJack.loadedCollisionHalfHeight,
            }))
    end)
    if not succeeded then
        if state then state.message = action == "blocked"
            and "There is not enough clear floor space to lower this pallet."
            or "The carried pallet could not be found." end
        return false
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if action == "mounted" then
        World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
        state.message = "Operating pallet jack. Drive with movement keys; E lifts or lowers pallets."
    elseif action == "lifted" then
        state.message = "Lifted " .. pallet.id .. ". Drive it to a clear warehouse position."
    elseif action == "lowered" then
        state.message = "Lowered " .. pallet.id .. " at its new warehouse position."
    else
        state.message = "Pallet jack parked."
    end
    return true, action, pallet
end

function World.parkPalletJack(state)
    if not PalletJack.park(state, Config.palletJack) then
        if state then state.message = "Lower the carried pallet before parking the jack." end
        return false
    end
    if state then state.message = "Pallet jack parked." end
    return true
end

local function cutterHasPaper(state)
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.location == "at_cutter" then return true end
        end
    end
    return false
end

function World.beginCutterMove(state)
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.operating then
        state.message = "Park the pallet jack before relocating the cutter."
        return false
    end
    if cutterHasPaper(state) then
        state.message = "Unload the paper and clear the cutting bed before relocating the cutter."
        return false
    end
    if not CutterPlacement.beginMove(state, Config.cutterPlacement) then return false end
    World.player.x, World.player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
    state.message = "Cutter relocation mode: move slowly, Q rotates, and E locks it in place."
    return true
end

function World.rotateCutter(state)
    local succeeded, direction = CutterPlacement.rotate(state, Config.cutterPlacement)
    if not succeeded then return false end
    if state.cutter.moving then
        World.player.x, World.player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
    end
    state.message = "Cutter rotated " .. direction .. "."
    return true
end

function World.placeCutter(state)
    if not CutterPlacement.place(state, Config.cutterPlacement) then return false end
    World.player.x, World.player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
    state.message = "Cutter locked in its new floor position."
    return true
end

function World.cutterSnapshot(state)
    return CutterPlacement.snapshot(state, Config.cutterPlacement)
end

function World.beginWrapperMove(state)
    if not Wrapper.canRelocate(state) then return false end
    if PalletJack.ensure(state, Config.palletJack).operating then
        state.message = "Park the pallet jack before relocating the skid wrapper."
        return false
    end
    if not WrapperPlacement.beginMove(state, Config.wrapperPlacement) then return false end
    World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement)
    state.message = "Wrapper relocation mode: move slowly, Q rotates, and E locks it in place."
    return true
end

function World.wrapperNearby(state)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local dx, dy = World.player.x - wrapper.x, World.player.y - wrapper.y
    return dx * dx + dy * dy <= Config.wrapperPlacement.interactionRadius ^ 2
end

function World.rotateWrapper(state)
    local succeeded, direction = WrapperPlacement.rotate(state, Config.wrapperPlacement)
    if not succeeded then return false end
    if state.wrapper.moving then World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement) end
    state.message = "Skid wrapper rotated " .. direction .. "."
    return true
end

function World.placeWrapper(state)
    if not WrapperPlacement.place(state, Config.wrapperPlacement) then return false end
    World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement)
    state.message = "Skid wrapper locked in its new floor position."
    return true
end

function World.wrapperSnapshot(state)
    return WrapperPlacement.snapshot(state, Config.wrapperPlacement)
end

function World.palletJackSnapshot(state)
    return PalletJack.snapshot(state, Config.palletJack)
end

function World.palletsSnapshot(state)
    return PalletLogistics.physicalPallets(state)
end

function World.palletTooltipAt(state, x, y)
    local hovered = PalletLogistics.hovered(state, x, y)
    if not hovered then
        local carried = PalletJack.carriedItem(state, Config.palletJack)
        if carried and x >= carried.x - 58 and x <= carried.x + 58
            and y >= carried.y - 92 and y <= carried.y + 12
        then hovered = carried end
    end
    return PalletLogistics.tooltip(hovered)
end

function World.bayDoorSnapshot()
    return World.bayDoor:snapshot()
end

function World.customerSnapshot()
    return World.customer:snapshot()
end

function World.truckSnapshot()
    return World.truck:snapshot()
end

function World.snapshot()
    return { x = World.player.x, y = World.player.y }
end

return World
