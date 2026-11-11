-- Job list, artwork, and job detail presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local DeliveryTraffic=require("src.commute.delivery_traffic")
local BusinessCalendar=require("src.business_calendar")
local Fonts=require('src.screens.computer.fonts')
local Text=require('src.screens.typography')

local function trimLastCharacter(text)
    for index=#text,1,-1 do
        local byte=text:byte(index)
        if byte<128 or byte>=192 then return text:sub(1,index-1) end
    end
    return ""
end

function Component.install(Runtime)
    local function palletStatusText(status)
        return status == 'completed' and 'Complete' or Runtime.StatusLabels.get(status)
    end
    function Runtime.drawJobList(state, pointerX, pointerY)
        local originalFont = love.graphics.getFont()
        local active = Runtime.isJobDeskTab()
        Runtime.panel(Runtime.jobRect('LIST'), { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        local jobs, visible, page, maximumPage = Runtime.currentPageJobs(state)
        if #jobs == 0 then
            if active then love.graphics.setFont(Fonts.get('typewriter',15)) end
            love.graphics.setColor(0.58, 0.64, 0.66)
            local empty=Runtime.ComputerScreen.tab=="deliveries"
                and "No inbound deliveries are expected" or "No jobs in this view"
            love.graphics.printf(empty, Runtime.jobRect('LIST').x, Runtime.jobRect('LIST').y + 155, Runtime.jobRect('LIST').width, "center")
            love.graphics.setFont(originalFont)
        end
        local deliveryTab=Runtime.ComputerScreen.tab=="deliveries"
        local now=deliveryTab and BusinessCalendar.absoluteHours(state) or nil
        for row, job in ipairs(visible) do
            local rect = Runtime.jobRowRect(row)
            local selected = Runtime.ComputerScreen.selectedJobId == job.id
            local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
            local fill, border
            if selected then
                fill, border = { 0.08, 0.36, 0.38, 1 }, { 0.25, 0.72, 0.70, 1 }
            elseif hovered then
                fill, border = { 0.10, 0.18, 0.20, 1 }, { 0.26, 0.52, 0.55, 1 }
            else
                fill, border = { 0.075, 0.10, 0.12, 1 }, { 0.18, 0.33, 0.37, 1 }
            end
            Runtime.panel(rect, fill, border, 3, 1)
            if selected then
                love.graphics.setColor(0.53, 0.98, 0.84, 1)
                love.graphics.rectangle("fill", rect.x + 2, rect.y + 6, 2, rect.height - 12)
            end
            love.graphics.setColor(0.93, 0.94, 0.92)
            if active then
                love.graphics.setFont(originalFont)
                love.graphics.print(job.id, rect.x + 8, rect.y + 6)
                local companyX = rect.x + 16 + originalFont:getWidth(job.id)
                local companyFont = Fonts.get('typewriter', 14)
                love.graphics.setFont(companyFont)
                local company = tostring(job.company or job.vendor or 'Incoming shipment')
                local width = rect.x + rect.width - 8 - companyX
                local _, lines = companyFont:getWrap(company, width)
                if #lines > 2 then company = lines[1] .. '\n' .. Text.ellipsize(table.concat(lines, ' ', 2), width, companyFont) end
                love.graphics.printf(company, companyX, rect.y + 5, width, 'left')
            else
                love.graphics.print(job.id .. "  " .. tostring(job.company or job.vendor or "Incoming shipment"), rect.x + 8, rect.y + 6)
            end
            love.graphics.setColor(0.78, 0.86, 0.84)
            local progress=not deliveryTab and Runtime.JobFeedback.progress(state,job) or nil
            local base=deliveryTab and DeliveryTraffic.tracking(job.shipmentRecord or job,now,os.time())
                or progress and progress.stage or Runtime.StatusLabels.get(Runtime.displayStatus(job))
            local font = love.graphics.getFont()
            local subtitle = base
            local supplemental = progress and progress.alert or progress and progress.blocker
            local prefix = base .. " • "
            local maxWidth = rect.width - 18
            if supplemental and font:getWidth(prefix) < maxWidth then
                local available = maxWidth - font:getWidth(prefix)
                while #supplemental > 3 and font:getWidth(supplemental) > available do
                    supplemental = trimLastCharacter(supplemental)
                end
                subtitle = prefix .. supplemental
                if progress and (progress.alert or progress.blocker) and #supplemental < #tostring(progress.alert or progress.blocker) then
                    subtitle = subtitle .. "…"
                end
            end
            if deliveryTab then
                while #subtitle>3 and font:getWidth(subtitle)>maxWidth do
                    subtitle=trimLastCharacter(subtitle)
                end
                if subtitle~=base then subtitle=trimLastCharacter(subtitle).."…" end
            end
            love.graphics.print(active and Text.ellipsize(subtitle, maxWidth, font) or subtitle, rect.x + 8, rect.y + (active and 40 or 21))
            love.graphics.setFont(originalFont)
        end
        love.graphics.setColor(0.72, 0.80, 0.80)
        local previous, following = Runtime.jobRect('PREVIOUS'), Runtime.jobRect('NEXT')
        love.graphics.printf(string.format("Page %d / %d", page, maximumPage),
            previous.x + previous.width, previous.y + 8, following.x - previous.x - previous.width, "center")

        local function pageButton(rect, label, enabled)
            local hovered = enabled and pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, label,
                not enabled and "disabled" or hovered and "hover" or "secondary")
        end
        pageButton(Runtime.jobRect('PREVIOUS'), "PREV", page > 1)
        pageButton(Runtime.jobRect('NEXT'), "NEXT", page < maximumPage)
    end

    function Runtime.drawArtworkPreview(assets, job, x, y, size)
        local key = job and job.artwork and job.artwork.key or job and job.artworkKey or "flower"
        love.graphics.setColor(0.10, 0.14, 0.16)
        love.graphics.rectangle("fill", x, y, size, size, 3, 3)
        love.graphics.setColor(0.35, 0.56, 0.58)
        love.graphics.rectangle("line", x, y, size, size, 3, 3)
        local image = assets and assets.getArtwork and assets.getArtwork(key)
        if image then
            local imageWidth, imageHeight = image:getDimensions()
            local scale = math.min((size - 6) / imageWidth, (size - 6) / imageHeight)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, x + (size - imageWidth * scale) / 2,
                y + (size - imageHeight * scale) / 2, 0, scale, scale)
        end
        love.graphics.setColor(0.72, 0.79, 0.80)
        local name = job and job.artwork and (job.artwork.displayName or job.artwork.fileName) or key
        local active = Runtime.isJobDeskTab()
        love.graphics.printf((job and job.press and "CLIENT ART\n" or "JOB ART\n")
            .. string.upper(name or "artwork"),
            active and x - 4 or x - 31, y + size + 8, size + (active and 8 or 62), "center")
    end

    function Runtime.drawJobQualityPreview(job, rect)
        local preview = Runtime.Reputation.qualityPreview(job)
        if not preview then return end
        local accent = preview.rating <= 2 and { 1, 0.48, 0.40, 1 }
            or preview.rating == 3 and { 1, 0.79, 0.39, 1 }
            or { 0.53, 0.98, 0.84, 1 }
        love.graphics.setColor(0.075, 0.11, 0.12, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(accent)
        love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.rectangle("fill", rect.x + 1, rect.y + 5, 2, rect.height - 10)
        local factor = preview.offSpec and preview.spoiledSheets > 0
            and string.format("OFF-SPEC %d%%", math.floor(preview.spoilRate * 100 + 0.5))
            or preview.offSpec and "OFF-SPEC CUT"
            or preview.spoiledSheets > 0
                and string.format("SPOIL %d%%", math.floor(preview.spoilRate * 100 + 0.5))
            or preview.reworkSheets > 0
                and string.format("REWORK %s • DELIVERY COMPLETE", Runtime.commaNumber(preview.reworkSheets))
            or preview.qualityRequirementMet == false
                and string.format("BELOW CLIENT TARGET %d%%",
                    math.floor((preview.qualityStandard or 0) * 100 + 0.5))
            or preview.hasPrintQuality and preview.printQuality <= preview.edgeQuality
                and preview.printQuality < 0.999
                and string.format("PRINT QUALITY %d%%", math.floor(preview.printQuality * 100 + 0.5))
            or preview.edgeQuality < 0.999
                and string.format("CUT EDGE %d%%", math.floor(preview.edgeQuality * 100 + 0.5))
            or preview.hasPrintQuality and "CLEAN CUTS + PRINT"
            or "CLEAN RUN"
        love.graphics.setColor(0.70, 0.80, 0.80, 1)
        love.graphics.printf(string.upper(preview.label) .. " • " .. factor,
            rect.x + 8, rect.y + 20, rect.width - 14, "left")
        local status = job.inspection and job.inspection.status
        local inspectionText = status == "passed" and "QC PASS"
            or status == "held" and "QC HOLD"
            or status == "rework_in_progress" and "REWORK"
            or "QC REQUIRED"
        love.graphics.setColor(0.72, 0.82, 0.82, 1)
        love.graphics.printf(string.format("%s • %d/5", inspectionText, preview.rating),
            rect.x + 8, rect.y + 3, rect.width - 14, "left")
    end

    function Runtime.drawDeliveryTrackerDetail(state,selected,twelveHourTime)
        local detail = Runtime.jobRect('DETAIL')
        Runtime.panel(detail,{0.065,0.08,0.10,1},{0.23,0.35,0.38,1})
        if not selected then
            local previousFont=love.graphics.getFont()
            love.graphics.setFont(Fonts.get('typewriter',15))
            love.graphics.setColor(0.58,0.64,0.66)
            love.graphics.printf("Select an inbound delivery to see its expected arrival and current location.",
                detail.x+28,detail.y+150,detail.width-56,"center")
            love.graphics.setFont(previousFont)
            return
        end
        local record=selected.shipmentRecord or selected
        local delivery=record.delivery or selected.delivery or {}
        local route=delivery.route or {}
        local nowHours=BusinessCalendar.absoluteHours(state)
        local epoch=os.time()
        local position=DeliveryTraffic.tracking(record,nowHours,epoch)
        local expected=tonumber(route.arrivalAtHours or delivery.expectedAtHours or delivery.readyAtHours)
        twelveHourTime=twelveHourTime~=false
        local scheduled=expected and BusinessCalendar.dateTimeTextAtHours(expected,twelveHourTime)
            or "Waiting for a confirmed dispatch window"
        local liveEta
        local vehicle=route.vehicle
        if vehicle and vehicle.phase=="at_bay" then liveEta="Arrived at the warehouse loading bay"
        elseif vehicle and vehicle.phase=="waiting_bay" then liveEta="At the shop; loading bay is occupied"
        elseif vehicle and route.arrivedAtEpoch then
            local seconds=route.arrivedAtEpoch-epoch
            if seconds<=0 then liveEta="Delayed · truck is still on the town route"
            elseif seconds<60 then liveEta="About 1 minute"
            else liveEta=string.format("About %d minutes",math.ceil(seconds/60)) end
        end

        local originalFont = love.graphics.getFont()
        local labelFont,valueFont = Fonts.get('sans',13),Fonts.get('typewriter',15)
        local x,width = detail.x+20,detail.width-40
        love.graphics.setFont(labelFont)
        love.graphics.setColor(0.96,0.84,0.30,1)
        love.graphics.print('INBOUND DELIVERY TRACKER',x,detail.y+16)
        love.graphics.setColor(0.88,0.93,0.91,1)
        local idText=tostring(selected.id)..'  ·  '
        love.graphics.print(idText,x,detail.y+42)
        love.graphics.setFont(valueFont)
        love.graphics.printf(tostring(selected.company or selected.vendor or 'Millhaven Freight'),
            x+labelFont:getWidth(idText),detail.y+42,width-labelFont:getWidth(idText),'left')
        local y=detail.y+78
        local function field(label,value,color)
            love.graphics.setFont(labelFont)
            love.graphics.setColor(0.55,0.80,0.81,1)
            love.graphics.print(label,x,y)
            y=y+17
            love.graphics.setFont(valueFont)
            love.graphics.setColor(color or {0.90,0.94,0.92,1})
            value=tostring(value)
            love.graphics.printf(value,x,y,width,'left')
            local _,lines=valueFont:getWrap(value,width)
            y=y+math.max(1,#lines)*valueFont:getHeight()+10
        end
        field('CURRENT LOCATION',position,{0.45,0.92,0.72,1})
        field('EXPECTED ARRIVAL IN MILLHAVEN',scheduled)
        if liveEta then field('LIVE TRAVEL ESTIMATE',liveEta) end
        field('ROUTE',tostring(route.originCity or 'Millhaven')..' · '
            ..tostring(route.originLocation or 'Freight Yard')..' to The Picture Shop warehouse')
        local contents={}
        if selected.orders then
            if #selected.orders==0 then
                contents[1]=selected.productName or 'Supply shipment'
            else
                for index,order in ipairs(selected.orders) do
                    if index>3 then break end
                    contents[#contents+1]=tostring(order.id)..' · '..tostring(order.productName or 'Supplies')
                end
                if #selected.orders>3 then
                    contents[#contents+1]=string.format('and %d more order%s',#selected.orders-3,
                        #selected.orders==4 and '' or 's')
                end
            end
        else
            local count=#(selected.pallets or {})
            contents[1]=selected.stockSpec and selected.stockSpec.description
                or string.format('Customer paper shipment · %d pallet%s',count,count==1 and '' or 's')
        end
        love.graphics.setFont(labelFont)
        love.graphics.setColor(0.55,0.80,0.81,1)
        love.graphics.print('SHIPMENT CONTENTS',x,y)
        y=y+17
        love.graphics.setFont(valueFont)
        love.graphics.setColor(0.84,0.89,0.88,1)
        for _,content in ipairs(contents) do
            love.graphics.printf(content,x,y,width,'left')
            local _,lines=valueFont:getWrap(content,width)
            y=y+math.max(1,#lines)*valueFont:getHeight()+3
        end
        love.graphics.setFont(originalFont)
    end

    function Runtime.detailRows(selected, state)
        local details = selected.details or {}
        local rows = {
            { text = string.format("Parent: %g × %g in",
                selected.sourceSize.width, selected.sourceSize.height), width = 310 },
            { text = string.format("Finished: %g × %g in",
                selected.finishedSize.width, selected.finishedSize.height), width = 310 },
            { text = "Stock: " .. (selected.stockSpec and selected.stockSpec.description
                or details.stockDescription or "Customer supplied"), width = 310 },
            { text = "Packaging: " .. Runtime.ComputerScreen.packagingText(selected), width = 310 },
        }
        local progress = Runtime.JobFeedback.progress(state, selected)
        if progress then
            rows[#rows + 1] = { text = string.format("Progress: %s • %s / %s good sheets",
                progress.stage, Runtime.commaNumber(progress.goodSheets), Runtime.commaNumber(progress.targetSheets))
                .. (progress.alert and " • STAFF ALERT" or ""),
                width = Runtime.jobRect('DETAIL').width - 40 }
        else
            rows[#rows + 1] = { text = "Client: " .. tostring(selected.clientTemperament or "standard")
                .. " • Reputation tier: " .. tostring(selected.reputationTier or "legacy"), width = 310 }
        end
        if (selected.spoiledSheets or 0) > 0 then
            rows[#rows + 1] = { text = string.format("Cutting waste: %s sheets • $%d redo/replacement charges",
                Runtime.commaNumber(selected.spoiledSheets), selected.spoilCost or 0), width = Runtime.jobRect('DETAIL').width - 40 }
            rows[#rows + 1] = { text = string.format("Replacement stock: %d skid%s • %s sheets delivered or inbound",
                selected.replacementSkids or 0, (selected.replacementSkids or 0) == 1 and "" or "s",
                Runtime.commaNumber(selected.replacementSheets or 0)), width = Runtime.jobRect('DETAIL').width - 40 }
        end
        if selected.press then
            local actual = selected.press.actual or {}
            rows[#rows + 1] = {
                text = string.format("Print: %s target • %s supplied • %d imp • %d spoil",
                    Runtime.commaNumber(selected.quote.orderedCopies or selected.press.orderedQuantity
                        or selected.quote.totalSheets),
                    Runtime.commaNumber(selected.quote.suppliedSheets or selected.quote.totalSheets),
                    actual.impressions or 0, actual.spoilage or 0),
                width = Runtime.jobRect('DETAIL').width - 40,
            }
            rows[#rows + 1] = {
                text = string.format("Inks (%d): %s", selected.press.colors or 1,
                    table.concat(selected.press.colorSequence or { "Black" }, " → ")),
                width = Runtime.jobRect('DETAIL').width - 40,
            }
        end
        for _, row in ipairs(rows) do
            row.label, row.value = row.text:match("^([^:]+:%s*)(.*)$")
        end
        return rows
    end

    function Runtime.ComputerScreen.jobDetailLayout(selected, state)
        local active = Runtime.ComputerScreen.tab == 'active' or Runtime.ComputerScreen.tab == 'completed'
        local font = active and Fonts.get('typewriter', 15) or love.graphics.getFont()
        local palletFont = active and Fonts.get('typewriter', 14) or font
        local labelFont = active and Fonts.get('sans', 13) or font
        local y = Runtime.jobRect('DETAIL').y + (active and 86 or 96)
        local titleY = Runtime.jobRect('DETAIL').y + 18
        local _, titleLines = labelFont:getWrap(tostring(selected.id or '') .. '  •  ' .. tostring(selected.company or ''), Runtime.jobRect('DETAIL').width - 40)
        local statusY = titleY + (active and math.max(26, #titleLines * labelFont:getHeight() + 8) or 26)
        local progress = Runtime.JobFeedback.progress(state, selected)
        local statusText = Runtime.StatusLabels.get(selected.status) .. (progress and ('  •  ' .. progress.stage) or '')
        local _, statusLines = font:getWrap(statusText, 310)
        local inboundY = statusY + (active and math.max(22, #statusLines * font:getHeight() + 6) or 22)
        local artY = active and math.max(Runtime.jobRect('DETAIL').y + 34, titleY + #titleLines * labelFont:getHeight() + 4)
            or Runtime.jobRect('DETAIL').y + 34
        if active then
            local _, inboundLines = font:getWrap(Runtime.JobService.deliverySummary(selected,state), 310 - labelFont:getWidth('Inbound: '))
            y = math.max(y, inboundY + #inboundLines * font:getHeight() + 6)
        end
        local rows = Runtime.detailRows(selected, state)
        for _, row in ipairs(rows) do
            if active and y >= artY + 102 then row.width = Runtime.jobRect('DETAIL').width - 40 end
            local labelWidth = row.label and labelFont:getWidth(row.label) or 0
            local valueWidth = math.max(1, row.width - labelWidth)
            local _, wrapped = font:getWrap(row.value or row.text, valueWidth)
            row.y = y
            row.height = math.max(1, #wrapped) * font:getHeight()
            row.labelWidth = labelWidth
            y = y + row.height + (active and 1 or 4)
        end
        local valueY = y + 1
        local valueLines = active and (selected.labor or selected.quote.employeeBudget) and 2 or 1
        local tableY = valueY + font:getHeight() * valueLines + 3
        local palletCount = #(selected.pallets or {})
        local palletRowHeight = palletCount >= 3 and 24 or 28
        if active then
            for _, pallet in ipairs(selected.pallets or {}) do
                local _, lines = palletFont:getWrap(palletStatusText(pallet.status), 94)
                palletRowHeight = math.max(palletRowHeight, #lines * palletFont:getHeight() + 6)
            end
        end
        local layout = {
            rows = rows,
            valueFont = font,
            palletFont = palletFont,
            labelFont = labelFont,
            titleY = titleY, statusY = statusY, inboundY = inboundY, statusText = statusText, artY = artY,
            valueY = valueY,
            tableY = tableY,
            palletRowHeight = palletRowHeight,
            textBottom = y,
            tableBottom = tableY + 30 + palletCount * palletRowHeight,
            actionTop = Runtime.ComputerScreen.tab == "completed" and Runtime.jobRect('JOB_PROMO').y or Runtime.jobRect('COMPLETE').y,
        }
        if active then
            layout.viewTop = Runtime.jobRect('DETAIL').y + 10
            layout.viewBottom = layout.actionTop - 8
            layout.scrollMax = math.max(0, layout.tableBottom + 4 - layout.viewBottom)
            if layout.scrollMax > 0 then
                layout.viewBottom = layout.viewBottom - 34
                layout.scrollMax = math.max(0, layout.tableBottom + 4 - layout.viewBottom)
            end
            if Runtime.ComputerScreen.jobScrollId ~= selected.id then
                Runtime.ComputerScreen.jobScrollId = selected.id
                Runtime.ComputerScreen.jobScroll = 0
            end
            layout.scroll = math.max(0, math.min(layout.scrollMax, Runtime.ComputerScreen.jobScroll or 0))
            Runtime.ComputerScreen.jobScroll = layout.scroll
        end
        return layout
    end

    function Runtime.ComputerScreen.scrollJobDetail(state, direction)
        if Runtime.ComputerScreen.tab ~= 'active' and Runtime.ComputerScreen.tab ~= 'completed' then return false end
        local selected = Runtime.findJob(Runtime.jobsForTab(state, Runtime.ComputerScreen.tab), Runtime.ComputerScreen.selectedJobId)
        if not selected or Runtime.isPurchaseOrder(selected) then return false end
        local layout = Runtime.ComputerScreen.jobDetailLayout(selected, state)
        if layout.scrollMax <= 0 then return false end
        Runtime.ComputerScreen.jobScroll = math.max(0, math.min(layout.scrollMax, layout.scroll + direction * 80))
        return true
    end

    function Runtime.jobScrollButtons()
        local detail = Runtime.jobRect('DETAIL')
        local y = Runtime.jobRect('COMPLETE').y - 38
        return {x=detail.x+18,y=y,width=64,height=28}, {x=detail.x+88,y=y,width=64,height=28}
    end

    function Runtime.jobScrollPointer(state, x, y)
        if Runtime.ComputerScreen.tab ~= 'active' and Runtime.ComputerScreen.tab ~= 'completed' then return nil end
        local up, down = Runtime.jobScrollButtons()
        local direction = Runtime.contains(up,x,y) and -1 or Runtime.contains(down,x,y) and 1
        if direction and Runtime.ComputerScreen.scrollJobDetail(state,direction) then return {action='job_scroll'} end
    end

    function Runtime.drawDetail(state, pointerX, pointerY, assets, twelveHourTime)
        Runtime.panel(Runtime.jobRect('DETAIL'), { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
        local selected = Runtime.findJob(Runtime.jobsForTab(state, Runtime.ComputerScreen.tab), Runtime.ComputerScreen.selectedJobId)
        if not selected then
            local previousFont=love.graphics.getFont()
            if Runtime.isJobDeskTab() then love.graphics.setFont(Fonts.get('typewriter',15)) end
            love.graphics.setColor(0.58, 0.64, 0.66)
            local prompt=Runtime.ComputerScreen.tab=="deliveries"
                and "Select a shipment to view its tracker." or "Select a job to view its ticket and pallet progress."
            love.graphics.printf(prompt,
                Runtime.jobRect('DETAIL').x + 24, Runtime.jobRect('DETAIL').y + 145, Runtime.jobRect('DETAIL').width - 48, "center")
            love.graphics.setFont(previousFont)
            return
        end
        if Runtime.ComputerScreen.tab=="deliveries" then
            Runtime.drawDeliveryTrackerDetail(state,selected,twelveHourTime)
            return
        end
        if Runtime.isPurchaseOrder(selected) then
            local delivery = selected.delivery or {}
            local pallet = selected.pallets and selected.pallets[1] or {}
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print(selected.id .. "  •  PURCHASE ORDER", Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 18)
            love.graphics.setColor(0.72, 0.79, 0.80)
            love.graphics.print(Runtime.StatusLabels.get(Runtime.displayStatus(selected)), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 44)
            love.graphics.print("Vendor: " .. tostring(selected.vendor), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 82)
            love.graphics.print("Product: " .. tostring(selected.productName), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 112)
            love.graphics.print("Purchase price: " .. Runtime.money(selected.price), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 142)
            love.graphics.print("Order state: " .. Runtime.StatusLabels.get(selected.status), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 182)
            love.graphics.print("Delivery state: " .. Runtime.StatusLabels.get(delivery.status), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 212)
            love.graphics.print("Pallet state: " .. Runtime.StatusLabels.get(pallet.status), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 242)
            love.graphics.print("Pallet location: " .. Runtime.StatusLabels.get(pallet.location), Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 272)
            local shipment=Runtime.Procurement.orderById(state,selected.shipmentId) or selected
            local location=require('src.commute.delivery_traffic').tracking(shipment,
                require('src.business_calendar').absoluteHours(state),os.time())
            love.graphics.setColor(0.45,0.88,0.69)
            love.graphics.printf("Live truck location: "..location,
                Runtime.jobRect('DETAIL').x+20,Runtime.jobRect('DETAIL').y+300,Runtime.jobRect('DETAIL').width-40,'left')
            love.graphics.setColor(0.55, 0.63, 0.65)
            love.graphics.printf("Purchase orders are paid when placed. Received supplies appear in Inventory.",
                Runtime.jobRect('DETAIL').x + 20, Runtime.jobRect('DETAIL').y + 326, Runtime.jobRect('DETAIL').width - 40, "left")
            return
        end
        local active = Runtime.ComputerScreen.tab == 'active' or Runtime.ComputerScreen.tab == 'completed'
        local originalFont = love.graphics.getFont()
        local layout = Runtime.ComputerScreen.jobDetailLayout(selected, state)
        if active then
            love.graphics.push('all')
            local left, top = love.graphics.transformPoint(Runtime.jobRect('DETAIL').x + 8, layout.viewTop)
            local right, bottom = love.graphics.transformPoint(Runtime.jobRect('DETAIL').x + Runtime.jobRect('DETAIL').width - 8, layout.viewBottom)
            love.graphics.intersectScissor(left, top, right - left, bottom - top)
            love.graphics.translate(0, -layout.scroll)
        end
        love.graphics.setFont(layout.labelFont)
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.printf(selected.id .. "  •  " .. selected.company, Runtime.jobRect('DETAIL').x + 20, layout.titleY, Runtime.jobRect('DETAIL').width - 40, 'left')
        love.graphics.setColor(0.72, 0.79, 0.80)
        love.graphics.setFont(layout.valueFont)
        love.graphics.printf(layout.statusText, Runtime.jobRect('DETAIL').x + 20, layout.statusY, active and 310 or 400, 'left')
        local function field(label, value, x, y, width)
            love.graphics.setFont(layout.labelFont)
            love.graphics.setColor(0.55, 0.80, 0.81, 1)
            love.graphics.print(label, x, y)
            local labelWidth = layout.labelFont:getWidth(label)
            love.graphics.setFont(layout.valueFont)
            love.graphics.setColor(0.88, 0.92, 0.92, 1)
            love.graphics.printf(tostring(value), x + labelWidth, y, width - labelWidth, 'left')
        end
        if active then
            field('Inbound: ', Runtime.JobService.deliverySummary(selected, state),
                Runtime.jobRect('DETAIL').x + 20, layout.inboundY, 310)
        else
            love.graphics.printf('Inbound: ' .. Runtime.JobService.deliverySummary(selected, state),
                Runtime.jobRect('DETAIL').x + 20, layout.inboundY, 310, 'left')
        end
        for _, row in ipairs(layout.rows) do
            local rowX = Runtime.jobRect('DETAIL').x + 20
            if row.label then
                love.graphics.setFont(layout.labelFont)
                love.graphics.setColor(0.55, 0.80, 0.81, 1)
                love.graphics.print(row.label, rowX, row.y)
                love.graphics.setColor(0.88, 0.92, 0.92, 1)
                love.graphics.setFont(layout.valueFont)
                love.graphics.printf(row.value, rowX + row.labelWidth, row.y,
                    math.max(1, row.width - row.labelWidth), "left")
            else
                love.graphics.setFont(layout.valueFont)
                love.graphics.setColor(0.88, 0.92, 0.92, 1)
                love.graphics.printf(row.text, rowX, row.y, row.width, "left")
            end
        end
        if active then
            field('Job value: ', Runtime.money(selected.quote.totalPrice), Runtime.jobRect('DETAIL').x + 20, layout.valueY, 200)
            if selected.labor or selected.quote.employeeBudget then
                field(selected.labor and 'Staff wages: ' or 'Staff budget: ',
                    Runtime.money(selected.labor and selected.labor.wageCents/100 or selected.quote.employeeBudget.laborCost),
                    Runtime.jobRect('DETAIL').x + 20, layout.valueY + layout.valueFont:getHeight(), 398)
            else
                field('Required lifts: ', selected.quote.totalLifts, Runtime.jobRect('DETAIL').x + 218, layout.valueY, 200)
            end
        else
        local valueText="Job value: "..Runtime.money(selected.quote.totalPrice)
        if selected.labor then valueText=valueText.." | Staff wages: "..Runtime.money(selected.labor.wageCents/100)
        elseif selected.quote.employeeBudget then valueText=valueText.." | Staff budget: "..Runtime.money(selected.quote.employeeBudget.laborCost) end
        love.graphics.printf(valueText, Runtime.jobRect('DETAIL').x + 20, layout.valueY, Runtime.jobRect('DETAIL').width - 40, "left")
        if not selected.labor and not selected.quote.employeeBudget then
            love.graphics.print("Required lifts: " .. selected.quote.totalLifts, Runtime.jobRect('DETAIL').x + 190, layout.valueY)
        end
        end
        love.graphics.setFont(originalFont)
        Runtime.drawArtworkPreview(assets, selected, Runtime.jobRect('DETAIL').x + 350, layout.artY, 70)

        love.graphics.setFont(layout.labelFont)
        love.graphics.setColor(0.16, 0.22, 0.24)
        love.graphics.rectangle("fill", Runtime.jobRect('DETAIL').x + 18, layout.tableY, Runtime.jobRect('DETAIL').width - 36, 26)
        love.graphics.setColor(0.85, 0.88, 0.87)
        love.graphics.print("PALLET", Runtime.jobRect('DETAIL').x + 28, layout.tableY + 7)
        love.graphics.print(selected.press and "GOOD / TARGET" or "REMAINING", Runtime.jobRect('DETAIL').x + 132, layout.tableY + 7)
        love.graphics.print("LIFTS", Runtime.jobRect('DETAIL').x + 270, layout.tableY + 7)
        love.graphics.print("STATE", Runtime.jobRect('DETAIL').x + (active and 324 or 340), layout.tableY + 7)
        for index, pallet in ipairs(selected.pallets or {}) do
            love.graphics.setFont(layout.palletFont)
            local y = layout.tableY + 30 + (index - 1) * layout.palletRowHeight
            love.graphics.setColor(0.12, 0.15, 0.17)
            love.graphics.rectangle("fill", Runtime.jobRect('DETAIL').x + 18, y, Runtime.jobRect('DETAIL').width - 36,
                layout.palletRowHeight - 3)
            love.graphics.setColor(0.78, 0.83, 0.83)
            love.graphics.print(tostring(pallet.number), Runtime.jobRect('DETAIL').x + 48, y + 7)
            if selected.press then
                love.graphics.print(string.format("%s / %s",
                    Runtime.commaNumber(pallet.press and pallet.press.goodSheets or 0),
                    Runtime.commaNumber(pallet.requestedCopies or pallet.initialSheets)), Runtime.jobRect('DETAIL').x + 136, y + 7)
            else
                love.graphics.print(Runtime.commaNumber(pallet.remainingSheets), Runtime.jobRect('DETAIL').x + 153, y + 7)
            end
            love.graphics.print(string.format("%d/%d", pallet.completedLifts, pallet.requiredLifts), Runtime.jobRect('DETAIL').x + 274, y + 7)
            if active then
                love.graphics.printf(palletStatusText(pallet.status), Runtime.jobRect('DETAIL').x + 324, y + 5, 94, 'left')
            else
                love.graphics.print(Runtime.StatusLabels.get(pallet.status), Runtime.jobRect('DETAIL').x + 340, y + 7)
            end
        end

        if active then
            love.graphics.pop()
            if layout.scrollMax > 0 then
                local up, down = Runtime.jobScrollButtons()
                Runtime.drawComputerButton(up, 'UP', layout.scroll > 0 and 'secondary' or 'disabled')
                Runtime.drawComputerButton(down, 'DOWN', layout.scroll < layout.scrollMax and 'secondary' or 'disabled')
                love.graphics.setColor(0.72, 0.79, 0.80)
                love.graphics.print(layout.scroll == layout.scrollMax and 'End of job details' or 'More job details below', down.x + down.width + 10, down.y + 7)
            end
        end
        love.graphics.setFont(originalFont)

        local qualityReady = Runtime.completionReady(selected)
            or selected.status == "ready_for_pickup"
            or selected.status == "pickup_in_progress"
            or selected.status == "completed"
        if qualityReady then
            local rect = Runtime.ComputerScreen.tab == "completed"
                and { x = Runtime.jobRect('DETAIL').x + 18, y = Runtime.jobRect('JOB_PROMO').y - 6,
                    width = 200, height = Runtime.jobRect('JOB_PROMO').height + 6 }
                or { x = Runtime.jobRect('DETAIL').x + 18, y = Runtime.jobRect('COMPLETE').y - 6,
                    width = 158, height = Runtime.jobRect('COMPLETE').height + 6 }
            Runtime.drawJobQualityPreview(selected, rect)
        end

        if Runtime.ComputerScreen.tab == "completed" then
            local sent = Runtime.promotionSentForJob(state, selected)
            local hovered = not sent and pointerX and Runtime.contains(Runtime.jobRect('JOB_PROMO'), pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.jobRect('JOB_PROMO'),
                sent and "10% PROMO SENT" or "EMAIL 10% PROMO",
                sent and "disabled" or hovered and "primaryHover" or "primary")
            return
        end
        if Runtime.ComputerScreen.tab ~= "active" then return end
        local ready = Runtime.completionReady(selected)
        local inspection = selected.inspection or {}
        local buttonLabel = ready and (inspection.status == "passed" and "SCHEDULE CUSTOMER PICKUP"
            or inspection.status == "held" and "REWORK AFFECTED PALLETS"
            or "INSPECT FINISHED JOB") or "PRODUCTION NOT COMPLETE"
        if selected.status == "ready_for_pickup" and inspection.status == "passed"
            and selected.pickup and selected.pickup.status == "awaiting_schedule" then
            if selected.outboundDelivery and selected.outboundDelivery.transport == "customer" then
                Runtime.drawComputerButton(Runtime.jobRect('COMPLETE'), "CLIENT PICKUP QUEUED", "disabled")
                return
            end
            local mode=selected.pickup.driverMode or 'employee'
            local employeeHover=pointerX and Runtime.contains(Runtime.jobRect('PICKUP_EMPLOYEE'),pointerX,pointerY)
            local playerHover=pointerX and Runtime.contains(Runtime.jobRect('PICKUP_PLAYER'),pointerX,pointerY)
            Runtime.drawComputerButton(Runtime.jobRect('PICKUP_EMPLOYEE'),
                mode=='employee' and 'EMPLOYEE ✓' or 'EMPLOYEE',
                employeeHover and 'primaryHover' or mode=='employee' and 'primary' or 'secondary')
            Runtime.drawComputerButton(Runtime.jobRect('PICKUP_PLAYER'),
                mode=='player' and 'I WILL DELIVER ✓' or 'I WILL DELIVER',
                playerHover and 'primaryHover' or mode=='player' and 'primary' or 'secondary')
            return
        elseif selected.status == "ready_for_pickup" then buttonLabel = "DELIVERY IN PROGRESS"
        elseif selected.status == "pickup_in_progress" then buttonLabel = "PICKUP IN PROGRESS"
        elseif selected.status == "completed" then buttonLabel = "PAID AND COMPLETED" end
        if ready and inspection.status == 'passed' and selected.status == 'in_production' then
            if selected.outboundDelivery and selected.outboundDelivery.transport == "customer" then
                local hovered=pointerX and Runtime.contains(Runtime.jobRect('COMPLETE'),pointerX,pointerY)
                Runtime.drawComputerButton(Runtime.jobRect('COMPLETE'),"SCHEDULE CUSTOMER PICKUP",
                    hovered and "primaryHover" or "primary")
                return
            end
            local employeeHover=pointerX and Runtime.contains(Runtime.jobRect('PICKUP_EMPLOYEE'),pointerX,pointerY)
            local playerHover=pointerX and Runtime.contains(Runtime.jobRect('PICKUP_PLAYER'),pointerX,pointerY)
            Runtime.drawComputerButton(Runtime.jobRect('PICKUP_EMPLOYEE'),'EMPLOYEE DRIVER',
                employeeHover and 'primaryHover' or 'primary')
            Runtime.drawComputerButton(Runtime.jobRect('PICKUP_PLAYER'),'I WILL DELIVER',
                playerHover and 'primaryHover' or 'secondary')
            return
        end
        local hovered = ready and pointerX and Runtime.contains(Runtime.jobRect('COMPLETE'), pointerX, pointerY)
        Runtime.drawComputerButton(Runtime.jobRect('COMPLETE'), buttonLabel,
            not ready and "disabled" or hovered and "primaryHover" or "primary")
    end
end

return Component
