-- Shopping cart, inventory, and supplier presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local VehicleDealer=require('src.vehicle_dealer')

function Component.install(Runtime)
    function Runtime.vehicleListingRect(index)
        local column=(index-1)%2
        local row=math.floor((index-1)/2)
        return {x=116+column*366,y=286+row*130,width=354,height=120}
    end
    function Runtime.vehicleListingBuyRect(index)
        local card=Runtime.vehicleListingRect(index)
        return {x=card.x+224,y=card.y+78,width=118,height=32}
    end

    function Runtime.ComputerScreen.resolveVehicle(accepted,message)
        Runtime.ComputerScreen.vehiclePending=false
        if accepted then Runtime.ComputerScreen.vehicleConfirmation=nil end
        Runtime.ComputerScreen.vehicleMessage=message or
            (accepted and 'Vehicle purchase confirmed.' or 'The vehicle purchase was not completed.')
    end

    function Runtime.vehicleDealerMousepressed(state,x,y)
        local screen=Runtime.ComputerScreen
        if screen.vehiclePending then return {action='blocked',reason='waiting'} end
        local choice=screen.vehicleConfirmation
        if choice then
            if Runtime.contains({x=208,y=504,width=180,height=42},x,y) then
                screen.vehicleConfirmation=nil;screen.vehicleMessage=nil
                return {action='vehicle_purchase_cancelled'}
            end
            if not Runtime.contains({x=572,y=504,width=194,height=42},x,y) then return nil end
            local listing=VehicleDealer.listing(choice.listingId)
            if not listing or VehicleDealer.owns(state,listing.model) then
                Runtime.ComputerScreen.resolveVehicle(false,'That vehicle listing is no longer available.')
                return {action='blocked',reason='product_changed'}
            end
            if (state.money or 0)<listing.price then
                screen.vehicleMessage='Not enough money for this vehicle.'
                return {action='blocked',reason='insufficient_funds'}
            end
            local intent,errorMessage=Runtime.OfficeIntent.normalize({kind='buy_vehicle',
                listingId=listing.id,requestId=choice.requestId})
            if not intent then screen.vehicleMessage=errorMessage;return {action='blocked'} end
            local command=Runtime.dependencies.remoteCommand or Runtime.dependencies.warehouseCommand
            if type(command)~='function' then
                screen.vehicleMessage='CritterNet vehicle purchasing is not connected to the shop.'
                return {action='blocked',reason='vehicle_dealer_unwired'}
            end
            local called,accepted,code,message=pcall(command,intent)
            if not called or accepted==false then
                Runtime.ComputerScreen.resolveVehicle(false,called and (message or code)
                    or 'The vehicle purchase could not be sent.')
                return {action='blocked'}
            end
            if Runtime.dependencies.remoteCommand then
                screen.vehiclePending=true
                screen.vehicleMessage='Waiting for the shop to confirm this purchase.'
                return {action='remote_pending'}
            end
            Runtime.ComputerScreen.resolveVehicle(true,message or 'Vehicle purchased. It is ready at the warehouse.')
            state.message=message or (listing.name..' purchased and delivered to the warehouse.')
            return {action='vehicle_purchased',hostSaved=true}
        end
        for index,listingId in ipairs(VehicleDealer.ORDER) do
            local listing=VehicleDealer.listing(listingId)
            if Runtime.contains(Runtime.vehicleListingBuyRect(index),x,y)
                and listing and not VehicleDealer.owns(state,listing.model) then
                screen.vehicleRequestNumber=(screen.vehicleRequestNumber or 0)+1
                local requestId=Runtime.nextFinanceRequestId(screen.vehicleRequestNumber)
                screen.vehicleConfirmation={listingId=listingId,requestId=requestId}
                screen.vehicleMessage=nil
                return {action='vehicle_purchase_review',listingId=listingId}
            end
        end
        return nil
    end

    function Runtime.drawCartButton(pointerX, pointerY)
        local total, count = Runtime.cartTotal()
        local hovered = pointerX and Runtime.contains(Runtime.CART_BUTTON, pointerX, pointerY)
        Runtime.drawComputerButton(Runtime.CART_BUTTON,
            string.format("CART %d • %s", count, Runtime.money(total)),
            hovered and "primaryHover" or "primary")
    end

    function Runtime.drawCart(state, pointerX, pointerY)
        Runtime.panel({ x = 110, y = 190, width = 738, height = 394 },
            { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        local total, count = Runtime.cartTotal()
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.print("ONLINE CART", 124, 208)
        love.graphics.setColor(0.70, 0.79, 0.80)
        love.graphics.printf("Review everything before checkout. A separate receipt is emailed for every order.",
            300, 208, 538, "right")
        local maximumPage = math.max(1, math.ceil(#Runtime.ComputerScreen.cart / Runtime.CART_PAGE_SIZE))
        Runtime.ComputerScreen.cartPage = math.max(1, math.min(Runtime.ComputerScreen.cartPage or 1, maximumPage))
        local first = (Runtime.ComputerScreen.cartPage - 1) * Runtime.CART_PAGE_SIZE + 1
        if #Runtime.ComputerScreen.cart == 0 then
            love.graphics.setColor(0.58, 0.66, 0.67)
            love.graphics.printf("Your cart is empty. Return to the store and add the items you need.",
                204, 350, 548, "center")
        end
        for visibleIndex = 1, Runtime.CART_PAGE_SIZE do
            local entry = Runtime.ComputerScreen.cart[first + visibleIndex - 1]
            if not entry then break end
            local y = 244 + (visibleIndex - 1) * 40
            love.graphics.setColor(visibleIndex % 2 == 0 and 0.085 or 0.105, 0.12, 0.14, 1)
            love.graphics.rectangle("fill", 116, y, 718, 36, 2, 2)
            love.graphics.setColor(0.86, 0.90, 0.88)
            love.graphics.printf(entry.name, 128, y + 10, 376, "left")
            love.graphics.setColor(0.63, 0.72, 0.73)
            love.graphics.printf("× " .. tostring(entry.quantity), 500, y + 10, 54, "right")
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.printf(Runtime.money(entry.price * entry.quantity), 566, y + 10, 140, "right")
            local remove = Runtime.cartRemoveRect(visibleIndex)
            local hovered = pointerX and Runtime.contains(remove, pointerX, pointerY)
            Runtime.drawComputerButton(remove, "REMOVE", hovered and "dangerHover" or "danger")
        end
        local function cartAction(rect, label, enabled, green)
            local hovered = enabled and pointerX and Runtime.contains(rect, pointerX, pointerY)
            local style = not enabled and "disabled"
                or green and (hovered and "primaryHover" or "primary")
                or hovered and "hover" or "secondary"
            Runtime.drawComputerButton(rect, label, style)
        end
        cartAction(Runtime.CART_BACK, "KEEP SHOPPING", true, false)
        cartAction(Runtime.CART_CLEAR, "CLEAR CART", count > 0, false)
        cartAction(Runtime.CART_PREVIOUS, "<", Runtime.ComputerScreen.cartPage > 1, false)
        cartAction(Runtime.CART_NEXT, ">", Runtime.ComputerScreen.cartPage < maximumPage, false)
        local affordable = count > 0 and (state.money or 0) >= total
        cartAction(Runtime.CART_CHECKOUT,
            count == 0 and "CART EMPTY" or affordable and ("CHECKOUT  " .. Runtime.money(total)) or "INSUFFICIENT CASH",
            affordable, true)
    end

    function Runtime.drawInventory(state)
        local inventory = state.inventory or {}
        love.graphics.setColor(0.73, 0.80, 0.81)
        love.graphics.print("PHYSICAL PALLET INVENTORY", 116, 202)
        local cards = {
            { label = "RAW PALLETS", value = inventory.rawPallets or 0, x = 116, color = { 0.37, 0.53, 0.63 } },
            { label = "IN PROCESS", value = inventory.inProcessPallets or 0, x = 358, color = { 0.73, 0.52, 0.20 } },
            { label = "FINISHED", value = inventory.finishedPallets or 0, x = 600, color = { 0.20, 0.57, 0.36 } },
        }
        for _, card in ipairs(cards) do
            Runtime.panel({ x = card.x, y = 234, width = 224, height = 112 },
                { card.color[1] * 0.30, card.color[2] * 0.30, card.color[3] * 0.30, 1 },
                { card.color[1], card.color[2], card.color[3], 1 })
            love.graphics.setColor(0.80, 0.85, 0.85)
            love.graphics.printf(card.label, card.x, 254, 224, "center")
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.printf(tostring(card.value), card.x, 292, 224, "center")
        end
        Runtime.panel({ x = 116, y = 360, width = 708, height = 224 },
            { 0.06, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
        love.graphics.setColor(0.73, 0.80, 0.81)
        love.graphics.print("SHOP STOCK", 128, 380)
        love.graphics.setColor(0.42, 0.73, 0.78)
        love.graphics.printf("Buy more through the WWW tab at www.thecritternet.com",
            404, 380, 404, "right")
        love.graphics.setColor(0.73, 0.80, 0.81)
        love.graphics.print("Loose starter sheets", 128, 414)
        love.graphics.print("Finished samples", 482, 414)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(Runtime.commaNumber(inventory.paper or 0), 318, 414, 110, "right")
        love.graphics.printf(Runtime.commaNumber(inventory.prints or 0), 680, 414, 110, "right")
        local rows = Runtime.Procurement.inventoryRows(state)
        local rowsPerColumn = math.max(1, math.ceil(#rows / 2))
        local rowSpacing = math.min(22, math.max(15, math.floor(116 / math.max(1, rowsPerColumn - 1))))
        local originalFont=love.graphics.getFont()
        love.graphics.setFont(require('src.screens.computer.fonts').get('typewriter',13))
        for index, item in ipairs(rows) do
            local column = math.floor((index - 1) / rowsPerColumn)
            local row = (index - 1) % rowsPerColumn
            local x, y = 128 + column * 354, 452 + row * rowSpacing
            love.graphics.setColor(row % 2 == 0 and 0.085 or 0.105, 0.12, 0.14, 1)
            love.graphics.rectangle("fill", x - 8, y - 4, 326, math.min(20,rowSpacing), 2, 2)
            love.graphics.setColor(0.73, 0.80, 0.81)
            love.graphics.print(item.label, x, y)
            love.graphics.setColor(0.95, 0.84, 0.30)
            love.graphics.printf(Runtime.commaNumber(item.quantity) .. " " .. item.unit, x + 190, y, 116, "right")
        end
        love.graphics.setFont(originalFont)
    end

    function Runtime.conditionColor(condition)
        if condition >= 75 then return 0.35, 0.78, 0.48 end
        if condition >= 55 then return 0.88, 0.70, 0.25 end
        return 0.90, 0.35, 0.24
    end

    function Runtime.drawCritterNetSprite(assets, frame, x, y, width, height, alpha)
        local image = assets and assets.images and assets.images.critterNetSprites
        local quad = assets and assets.quads and assets.quads["critterNetSprite" .. tostring(frame)]
        if not image or not quad then return end
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(image, quad.quad, x, y, 0, width / quad.width, height / quad.height)
    end

    function Runtime.drawCritterNetChrome(assets)
        local backdrop = assets and assets.images and assets.images.critterNetMenu
        if not backdrop then return end
        love.graphics.setColor(1, 1, 1, 0.90)
        love.graphics.draw(backdrop, Runtime.PANEL.x, Runtime.PANEL.y, 0,
            Runtime.PANEL.width / backdrop:getWidth(), Runtime.PANEL.height / backdrop:getHeight())

        local clock = love.timer.getTime()
        local frames = {
            active = 5 + math.floor(clock * 4) % 4,
            completed = 15,
            deliveries = 9 + math.floor(clock * 3) % 4,
            estimating = 13 + math.floor(clock * 2) % 2,
            calendar = 16,
            inventory = 5 + math.floor(clock * 4) % 4,
            www = 1 + math.floor(clock * 2.5) % 4,
            email = 13 + math.floor(clock * 2) % 2,
            bills = 15,
            credit = 16,
        }
        local frame = frames[Runtime.ComputerScreen.tab] or 5
        if Runtime.ComputerScreen.tab == 'active' then
            -- The atlas shifts the paw trio sideways between frames. Place each
            -- frame over the three fixed paws painted into the browser chrome.
            local positions = {
                [5] = {691,159}, [6] = {685,176},
                [7] = {693,179}, [8] = {708,172},
            }
            local placement = positions[frame]
            Runtime.drawCritterNetSprite(assets,frame,placement[1],58,placement[2],88,0.96)
        else
            Runtime.drawCritterNetSprite(assets,frame,696,52,46,31,0.96)
        end
    end

    function Runtime.drawWww(state, pointerX, pointerY, assets)
        Runtime.panel({ x = 110, y = 190, width = 738, height = 394 },
            { 0.035, 0.055, 0.075, 1 }, { 0.32, 0.56, 0.58, 1 })
        local site = Runtime.WWW_SITES[Runtime.ComputerScreen.wwwSite] or Runtime.WWW_SITES[1]
        -- The browser address bar above owns the URL; this is the site masthead.
        Runtime.panel({ x = 116, y = 198, width = 584, height = 32 },
            { 0.025, 0.15, 0.18, 1 }, { 0.31, 0.64, 0.65, 1 }, 3, 1)
        love.graphics.setColor(0.96, 0.94, 0.84, 1)
        love.graphics.print("CRITTERNET  /  " .. site.name, 130, 206)
        local animationTime = love.timer.getTime()
        local globeFrame = 1 + math.floor(animationTime * 2.5) % 4
        local pulseFrame = 5 + math.floor(animationTime * 4) % 4
        local modemFrame = 9 + math.floor(animationTime * 3) % 4
        Runtime.drawCritterNetSprite(assets, globeFrame, 400, 196, 58, 38, 1)
        Runtime.drawCritterNetSprite(assets, pulseFrame, 350, 492, 184, 122, 0.14)
        for index, website in ipairs(Runtime.WWW_SITES) do
            local rect = Runtime.wwwSiteRect(index)
            local selected = index == Runtime.ComputerScreen.wwwSite
            local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, website.short,
                selected and "primary" or hovered and "hover" or "secondary")
        end
        Runtime.drawCritterNetSprite(assets, modemFrame, 730, 536, 100, 60, 0.92)
        local siteChangeAge = animationTime - (Runtime.ComputerScreen.wwwSiteChangedAt or 0)
        if siteChangeAge < 0.70 then
            Runtime.drawCritterNetSprite(assets, siteChangeAge < 0.36 and 16 or 15,
                773, 244, 58, 39, 1)
        end
        local featuredSale = Runtime.Procurement.currentSale(state)
        if featuredSale then
            love.graphics.setColor(0.50, 0.94, 0.56, 1)
            love.graphics.printf(string.format("SALE %d%% OFF", featuredSale.percent), 492, 206, 194, "right")
        end
        if site.kind=='vehicles' then
            love.graphics.setColor(0.68,0.83,0.84)
            love.graphics.print('NEW AND USED WORK TRUCKS',116,274)
            for index,listingId in ipairs(VehicleDealer.ORDER) do
                local listing=VehicleDealer.listing(listingId)
                local card,buy=Runtime.vehicleListingRect(index),Runtime.vehicleListingBuyRect(index)
                local owned=VehicleDealer.owns(state,listing.model)
                local affordable=(state.money or 0)>=listing.price
                Runtime.panel(card,{0.06,0.09,0.12,1},{0.24,0.40,0.46,1})
                love.graphics.setColor(0.92,0.95,0.93)
                love.graphics.print(listing.name,card.x+12,card.y+8)
                love.graphics.setColor(0.93,0.78,0.36)
                love.graphics.print(Runtime.money(listing.price),card.x+12,card.y+31)
                love.graphics.setColor(0.62,0.73,0.75)
                love.graphics.printf(listing.description,card.x+12,card.y+53,210,'left')
                if listing.condition=='used' then
                    love.graphics.setColor(0.94,0.61,0.35)
                    love.graphics.print('Used • poor condition • service due',card.x+12,card.y+98)
                else
                    love.graphics.setColor(0.57,0.83,0.65)
                    love.graphics.print('New • inspected before delivery',card.x+12,card.y+98)
                end
                local hovered=pointerX and Runtime.contains(buy,pointerX,pointerY)
                Runtime.drawComputerButton(buy,owned and 'OWNED' or affordable and 'REVIEW'
                    or 'NOT ENOUGH',(owned or not affordable) and 'disabled'
                    or hovered and 'primaryHover' or 'primary')
            end
            local confirmation=Runtime.ComputerScreen.vehicleConfirmation
            if confirmation then
                local listing=VehicleDealer.listing(confirmation.listingId)
                if listing then
                    love.graphics.setColor(0,0,0,0.84)
                    love.graphics.rectangle('fill',116,270,722,298)
                    Runtime.panel({x=152,y=314,width=650,height=224},
                        {0.035,0.065,0.085,1},{0.56,0.74,0.69,1},4,2)
                    love.graphics.setColor(0.97,0.84,0.35,1)
                    love.graphics.printf('CONFIRM VEHICLE PURCHASE',174,332,606,'center')
                    love.graphics.setColor(0.92,0.95,0.93,1)
                    love.graphics.printf(listing.name..'  /  '..Runtime.money(listing.price),180,366,594,'center')
                    love.graphics.setColor(0.70,0.82,0.82,1)
                    love.graphics.printf(listing.condition=='used'
                        and 'This used truck arrives in poor condition, with body damage and every service interval overdue. Visit a town mechanic for repair and maintenance.'
                        or 'This new truck arrives with a clean maintenance record at the warehouse.',190,398,574,'center')
                    local message=Runtime.ComputerScreen.vehicleMessage
                    if message then
                        love.graphics.setColor(0.96,0.72,0.41,1)
                        love.graphics.printf(message,188,456,578,'center')
                    end
                    Runtime.drawComputerButton({x=208,y=504,width=180,height=42},'CANCEL',
                        pointerX and Runtime.contains({x=208,y=504,width=180,height=42},pointerX,pointerY)
                            and 'hover' or 'secondary')
                    Runtime.drawComputerButton({x=572,y=504,width=194,height=42},
                        Runtime.ComputerScreen.vehiclePending and 'WAITING…' or 'BUY '..Runtime.money(listing.price),
                        Runtime.ComputerScreen.vehiclePending and 'disabled'
                            or pointerX and Runtime.contains({x=572,y=504,width=194,height=42},pointerX,pointerY)
                                and 'primaryHover' or 'primary')
                end
            end
            if not confirmation and Runtime.ComputerScreen.vehicleMessage then
                love.graphics.setColor(0.57,0.83,0.65,1)
                love.graphics.printf(Runtime.ComputerScreen.vehicleMessage,116,550,722,'center')
            end
            return
        end
        if site.kind ~= "machines" then
            local category = Runtime.Procurement.category(site.categoryIndex)
            for index, item in ipairs(category.items) do
                local row, buy = Runtime.wwwProductRect(index), Runtime.retailBuyRect(index)
                local available = item.available ~= false and item.retailPrice ~= nil
                local price, regularPrice, salePercent = Runtime.Procurement.retailPrice(state, site.categoryIndex, index)
                local total = Runtime.cartTotal()
                local affordable = available and (state.money or 0) >= total + (price or 0)
                love.graphics.setColor(index % 2 == 0 and 0.075 or 0.095, 0.11, 0.17, 0.94)
                love.graphics.rectangle("fill", row.x, row.y, row.width, row.height, 2, 2)
                love.graphics.setColor(0.38, 0.78, 0.88, 1)
                love.graphics.printf(item.retailName or item.name, row.x + 14, row.y + 8, 430, "left")
                if (salePercent or 0) > 0 then love.graphics.setColor(0.50, 0.94, 0.56, 1)
                else love.graphics.setColor(0.66,0.72,0.72,1) end
                local originalFont=love.graphics.getFont()
                love.graphics.setFont(require('src.screens.computer.fonts').get('typewriter',13))
                love.graphics.print(available
                    and ((salePercent or 0) > 0
                        and string.format("%d%% SALE • regular %s • loading dock", salePercent, Runtime.money(regularPrice))
                        or string.format("Ships to loading dock • salesman bulk $%d",item.price))
                    or tostring(item.unavailableReason),row.x+14,row.y+29)
                love.graphics.setFont(originalFont)
                local hovered = affordable and pointerX and Runtime.contains(buy, pointerX, pointerY)
                Runtime.drawComputerButton(buy,
                    available and ((salePercent or 0) > 0 and ("SALE " .. Runtime.money(price))
                        or ("ADD "..Runtime.money(price))) or "OFFLINE",
                    not affordable and "disabled" or hovered and "primaryHover" or "primary")
            end
            return
        end
        love.graphics.setColor(0.68, 0.83, 0.84)
        love.graphics.print("MACHINE LISTINGS", Runtime.MACHINE_OFFER.x, 284)
        for index, offer in ipairs(Runtime.MachineFleet.offers("online")) do
            local y = Runtime.MACHINE_OFFER.y + (index - 1) * (Runtime.MACHINE_OFFER.height + Runtime.MACHINE_OFFER.gap)
            local buy = Runtime.machineBuyRect(index)
            Runtime.panel({ x = Runtime.MACHINE_OFFER.x, y = y, width = Runtime.MACHINE_OFFER.width, height = Runtime.MACHINE_OFFER.height },
                { 0.06, 0.09, 0.12, 1 }, { 0.24, 0.40, 0.46, 1 })
            love.graphics.setColor(0.92, 0.95, 0.93)
            local nameScale = math.min(1, (buy.x - Runtime.MACHINE_OFFER.x - 20)
                / math.max(1, love.graphics.getFont():getWidth(offer.name)))
            love.graphics.print(offer.name, Runtime.MACHINE_OFFER.x + 12, y + 5, 0, nameScale, nameScale)
            local red, green, blue = Runtime.conditionColor(offer.condition)
            love.graphics.setColor(red, green, blue)
            love.graphics.print(string.format("%s • %.0f%% condition", offer.conditionStatus, offer.condition),
                Runtime.MACHINE_OFFER.x + 12, y + 20)
            love.graphics.setColor(0.58, 0.67, 0.69)
            love.graphics.print("Inspected • flatbed delivery", Runtime.MACHINE_OFFER.x + 12, y + 36)
            local total = Runtime.cartTotal()
            local affordable = (state.money or 0) >= total + offer.price
            local canFinance = (state.money or 0) < offer.price
            local enabled = canFinance or affordable
            local hovered = enabled and pointerX and Runtime.contains(buy, pointerX, pointerY)
            Runtime.drawComputerButton(buy,
                canFinance and "FINANCE" or ("ADD " .. Runtime.money(offer.price)),
                not enabled and "disabled" or hovered and "primaryHover" or "primary")
        end

        love.graphics.setColor(0.63, 0.72, 0.74)
        love.graphics.print("YOUR MACHINES", Runtime.OWNED_MACHINE.x, 284)
        local owned, pages = Runtime.ComputerScreen.ownedMachinePage(state)
        if #owned == 0 then
            love.graphics.setColor(0.52, 0.60, 0.62)
            love.graphics.printf("No machines owned. Buy a unit to install it in the shop.",
                Runtime.OWNED_MACHINE.x, 356, Runtime.OWNED_MACHINE.width, "center")
        end
        for visibleIndex = 1, Runtime.ComputerScreen.machinePageSize do
            local item = owned[(Runtime.ComputerScreen.machinePage - 1) * Runtime.ComputerScreen.machinePageSize + visibleIndex]
            if item then
            local y = Runtime.OWNED_MACHINE.y + (visibleIndex - 1) * (Runtime.OWNED_MACHINE.height + Runtime.OWNED_MACHINE.gap)
            local sell = Runtime.machineSellRect(visibleIndex)
            local condition = Runtime.MachineFleet.condition(item)
            local weakest = Runtime.MachineFleet.weakestComponent(item)
            Runtime.panel({ x = Runtime.OWNED_MACHINE.x, y = y, width = Runtime.OWNED_MACHINE.width, height = Runtime.OWNED_MACHINE.height },
                { 0.065, 0.085, 0.10, 1 }, { 0.22, 0.34, 0.38, 1 })
            love.graphics.setColor(0.92, 0.95, 0.93)
            love.graphics.print(item.id .. "  " .. (Runtime.MachineFleet.definition(item.modelId).shortName),
                Runtime.OWNED_MACHINE.x + 10, y + 6)
            local red, green, blue = Runtime.conditionColor(condition)
            love.graphics.setColor(red, green, blue)
            love.graphics.print(string.format("%s %.1f%% • %s", Runtime.MachineFleet.conditionStatus(condition),
                condition, item.status:upper()), Runtime.OWNED_MACHINE.x + 10, y + 22)
            love.graphics.setColor(0.55, 0.64, 0.66)
            love.graphics.print(string.format("%s %.0f%% • %d cycles", weakest.label,
                weakest.value, item.cycles), Runtime.OWNED_MACHINE.x + 10, y + 39)
            local hovered = pointerX and Runtime.contains(sell, pointerX, pointerY)
            Runtime.drawComputerButton(sell,
                "SELL\n" .. Runtime.money(Runtime.MachineFleet.resaleValue(item, "online")),
                hovered and "dangerHover" or "danger")
            end
        end
        if pages > 1 then
            local previous, nextRect = Runtime.ComputerScreen.machinePreviousRect, Runtime.ComputerScreen.machineNextRect
            local previousHovered = Runtime.ComputerScreen.machinePage > 1 and pointerX
                and Runtime.contains(previous, pointerX, pointerY)
            local nextHovered = Runtime.ComputerScreen.machinePage < pages and pointerX
                and Runtime.contains(nextRect, pointerX, pointerY)
            Runtime.drawComputerButton(previous, "PREV", Runtime.ComputerScreen.machinePage <= 1
                and "disabled" or previousHovered and "hover" or "secondary")
            Runtime.drawComputerButton(nextRect, "NEXT", Runtime.ComputerScreen.machinePage >= pages
                and "disabled" or nextHovered and "hover" or "secondary")
            love.graphics.printf(string.format("%d / %d", Runtime.ComputerScreen.machinePage, pages),
                588, 554, 164, "center")
        end
        love.graphics.setColor(0.55, 0.68, 0.69)
        love.graphics.printf("Verified machines ship to your shop floor.",
            116, 550, 354, "center")
    end
end

return Component
