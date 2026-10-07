-- Job list, artwork, and job detail presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawJobList(state, pointerX, pointerY)
        Runtime.panel(Runtime.LIST, { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        local jobs, visible, page, maximumPage = Runtime.currentPageJobs(state)
        if #jobs == 0 then
            love.graphics.setColor(0.58, 0.64, 0.66)
            love.graphics.printf("No jobs in this view", Runtime.LIST.x, Runtime.LIST.y + 155, Runtime.LIST.width, "center")
        end
        for row, job in ipairs(visible) do
            local rect = { x = Runtime.LIST.x + 8, y = Runtime.LIST.y + 14 + (row - 1) * Runtime.ROW_HEIGHT,
                width = Runtime.LIST.width - 16, height = 38 }
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
            love.graphics.print(job.id .. "  " .. job.company, rect.x + 8, rect.y + 6)
            love.graphics.setColor(0.78, 0.86, 0.84)
            love.graphics.print(Runtime.StatusLabels.get(Runtime.displayStatus(job)), rect.x + 8, rect.y + 21)
        end
        love.graphics.setColor(0.72, 0.80, 0.80)
        love.graphics.printf(string.format("Page %d / %d", page, maximumPage), 168, 578, 138, "center")

        local function pageButton(rect, label, enabled)
            local hovered = enabled and pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, label,
                not enabled and "disabled" or hovered and "hover" or "secondary")
        end
        pageButton(Runtime.PREVIOUS, "PREV", page > 1)
        pageButton(Runtime.NEXT, "NEXT", page < maximumPage)
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
        love.graphics.printf((job and job.press and "CLIENT ART\n" or "JOB ART\n")
            .. string.upper(name or "artwork"),
            x - 31, y + size + 8, size + 62, "center")
    end

    function Runtime.detailRows(selected)
        local details = selected.details or {}
        local rows = {
            { text = string.format("Parent: %g × %g in",
                selected.sourceSize.width, selected.sourceSize.height), width = 310 },
            { text = string.format("Finished: %g × %g in",
                selected.finishedSize.width, selected.finishedSize.height), width = 310 },
            { text = "Stock: " .. (selected.stockSpec and selected.stockSpec.description
                or details.stockDescription or "Customer supplied"), width = 310 },
            { text = "Packaging: " .. Runtime.ComputerScreen.packagingText(selected), width = 310 },
            { text = "Client: " .. tostring(selected.clientTemperament or "standard")
                .. " • Reputation tier: " .. tostring(selected.reputationTier or "legacy"), width = 310 },
        }
        if (selected.spoiledSheets or 0) > 0 then
            rows[#rows + 1] = { text = string.format("Cutting waste: %s sheets • $%d redo/replacement charges",
                Runtime.commaNumber(selected.spoiledSheets), selected.spoilCost or 0), width = Runtime.DETAIL.width - 40 }
            rows[#rows + 1] = { text = string.format("Replacement stock: %d skid%s • %s sheets delivered or inbound",
                selected.replacementSkids or 0, (selected.replacementSkids or 0) == 1 and "" or "s",
                Runtime.commaNumber(selected.replacementSheets or 0)), width = Runtime.DETAIL.width - 40 }
        end
        if selected.press then
            local actual = selected.press.actual or {}
            rows[#rows + 1] = {
                text = string.format("Print: %s target • %s supplied • %d imp • %d spoil",
                    Runtime.commaNumber(selected.quote.orderedCopies or selected.press.orderedQuantity
                        or selected.quote.totalSheets),
                    Runtime.commaNumber(selected.quote.suppliedSheets or selected.quote.totalSheets),
                    actual.impressions or 0, actual.spoilage or 0),
                width = Runtime.DETAIL.width - 40,
            }
            rows[#rows + 1] = {
                text = string.format("Inks (%d): %s", selected.press.colors or 1,
                    table.concat(selected.press.colorSequence or { "Black" }, " → ")),
                width = Runtime.DETAIL.width - 40,
            }
        end
        for _, row in ipairs(rows) do
            row.label, row.value = row.text:match("^([^:]+:%s*)(.*)$")
        end
        return rows
    end

    function Runtime.ComputerScreen.jobDetailLayout(selected)
        local font = love.graphics.getFont()
        local y = Runtime.DETAIL.y + 96
        local rows = Runtime.detailRows(selected)
        for _, row in ipairs(rows) do
            local labelWidth = row.label and font:getWidth(row.label) or 0
            local valueWidth = math.max(1, row.width - labelWidth)
            local _, wrapped = font:getWrap(row.value or row.text, valueWidth)
            row.y = y
            row.height = math.max(1, #wrapped) * font:getHeight()
            row.labelWidth = labelWidth
            y = y + row.height + 4
        end
        local valueY = y + 1
        local tableY = valueY + font:getHeight() + 3
        local palletCount = #(selected.pallets or {})
        local palletRowHeight = palletCount >= 3 and 24 or 28
        return {
            rows = rows,
            valueY = valueY,
            tableY = tableY,
            palletRowHeight = palletRowHeight,
            textBottom = y,
            tableBottom = tableY + 30 + palletCount * palletRowHeight,
            actionTop = Runtime.ComputerScreen.tab == "completed" and Runtime.JOB_PROMO.y or Runtime.COMPLETE.y,
        }
    end

    function Runtime.drawDetail(state, pointerX, pointerY, assets)
        Runtime.panel(Runtime.DETAIL, { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
        local selected = Runtime.findJob(Runtime.jobsForTab(state, Runtime.ComputerScreen.tab), Runtime.ComputerScreen.selectedJobId)
        if not selected then
            love.graphics.setColor(0.58, 0.64, 0.66)
            love.graphics.printf("Select a job to view its ticket and pallet progress.",
                Runtime.DETAIL.x + 24, Runtime.DETAIL.y + 145, Runtime.DETAIL.width - 48, "center")
            return
        end
        if Runtime.isPurchaseOrder(selected) then
            local delivery = selected.delivery or {}
            local pallet = selected.pallets and selected.pallets[1] or {}
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print(selected.id .. "  •  PURCHASE ORDER", Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 18)
            love.graphics.setColor(0.72, 0.79, 0.80)
            love.graphics.print(Runtime.StatusLabels.get(Runtime.displayStatus(selected)), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 44)
            love.graphics.print("Vendor: " .. tostring(selected.vendor), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 82)
            love.graphics.print("Product: " .. tostring(selected.productName), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 112)
            love.graphics.print("Purchase price: " .. Runtime.money(selected.price), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 142)
            love.graphics.print("Order state: " .. Runtime.StatusLabels.get(selected.status), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 182)
            love.graphics.print("Delivery state: " .. Runtime.StatusLabels.get(delivery.status), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 212)
            love.graphics.print("Pallet state: " .. Runtime.StatusLabels.get(pallet.status), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 242)
            love.graphics.print("Pallet location: " .. Runtime.StatusLabels.get(pallet.location), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 272)
            love.graphics.setColor(0.55, 0.63, 0.65)
            love.graphics.printf("Purchase orders are paid when placed. Received supplies appear in Inventory.",
                Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 326, Runtime.DETAIL.width - 40, "left")
            return
        end
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print(selected.id .. "  •  " .. selected.company, Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 18)
        love.graphics.setColor(0.72, 0.79, 0.80)
        love.graphics.print(Runtime.StatusLabels.get(selected.status), Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 44)
        love.graphics.printf("Inbound: " .. Runtime.JobService.deliverySummary(selected, state),
            Runtime.DETAIL.x + 20, Runtime.DETAIL.y + 66, 310, "left")
        local layout = Runtime.ComputerScreen.jobDetailLayout(selected)
        for _, row in ipairs(layout.rows) do
            local rowX = Runtime.DETAIL.x + 20
            if row.label then
                love.graphics.setColor(0.55, 0.80, 0.81, 1)
                love.graphics.print(row.label, rowX, row.y)
                love.graphics.setColor(0.88, 0.92, 0.92, 1)
                love.graphics.printf(row.value, rowX + row.labelWidth, row.y,
                    math.max(1, row.width - row.labelWidth), "left")
            else
                love.graphics.setColor(0.88, 0.92, 0.92, 1)
                love.graphics.printf(row.text, rowX, row.y, row.width, "left")
            end
        end
        local valueText="Job value: "..Runtime.money(selected.quote.totalPrice)
        if selected.labor then valueText=valueText.." | Staff wages: "..Runtime.money(selected.labor.wageCents/100)
        elseif selected.quote.employeeBudget then valueText=valueText.." | Staff budget: "..Runtime.money(selected.quote.employeeBudget.laborCost) end
        love.graphics.printf(valueText, Runtime.DETAIL.x + 20, layout.valueY, Runtime.DETAIL.width - 40, "left")
        if not selected.labor and not selected.quote.employeeBudget then
            love.graphics.print("Required lifts: " .. selected.quote.totalLifts, Runtime.DETAIL.x + 190, layout.valueY)
        end
        Runtime.drawArtworkPreview(assets, selected, Runtime.DETAIL.x + 350, Runtime.DETAIL.y + 34, 70)

        love.graphics.setColor(0.16, 0.22, 0.24)
        love.graphics.rectangle("fill", Runtime.DETAIL.x + 18, layout.tableY, Runtime.DETAIL.width - 36, 26)
        love.graphics.setColor(0.85, 0.88, 0.87)
        love.graphics.print("PALLET", Runtime.DETAIL.x + 28, layout.tableY + 7)
        love.graphics.print(selected.press and "GOOD / TARGET" or "REMAINING", Runtime.DETAIL.x + 132, layout.tableY + 7)
        love.graphics.print("LIFTS", Runtime.DETAIL.x + 270, layout.tableY + 7)
        love.graphics.print("STATE", Runtime.DETAIL.x + 340, layout.tableY + 7)
        for index, pallet in ipairs(selected.pallets or {}) do
            local y = layout.tableY + 30 + (index - 1) * layout.palletRowHeight
            love.graphics.setColor(0.12, 0.15, 0.17)
            love.graphics.rectangle("fill", Runtime.DETAIL.x + 18, y, Runtime.DETAIL.width - 36,
                layout.palletRowHeight - 3)
            love.graphics.setColor(0.78, 0.83, 0.83)
            love.graphics.print(tostring(pallet.number), Runtime.DETAIL.x + 48, y + 7)
            if selected.press then
                love.graphics.print(string.format("%s / %s",
                    Runtime.commaNumber(pallet.press and pallet.press.goodSheets or 0),
                    Runtime.commaNumber(pallet.requestedCopies or pallet.initialSheets)), Runtime.DETAIL.x + 136, y + 7)
            else
                love.graphics.print(Runtime.commaNumber(pallet.remainingSheets), Runtime.DETAIL.x + 153, y + 7)
            end
            love.graphics.print(string.format("%d/%d", pallet.completedLifts, pallet.requiredLifts), Runtime.DETAIL.x + 274, y + 7)
            love.graphics.print(Runtime.StatusLabels.get(pallet.status), Runtime.DETAIL.x + 340, y + 7)
        end

        if Runtime.ComputerScreen.tab == "completed" then
            local sent = Runtime.promotionSentForJob(state, selected)
            local hovered = not sent and pointerX and Runtime.contains(Runtime.JOB_PROMO, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.JOB_PROMO,
                sent and "10% PROMO SENT" or "EMAIL 10% PROMO",
                sent and "disabled" or hovered and "primaryHover" or "primary")
            return
        end
        if Runtime.ComputerScreen.tab ~= "active" then return end
        local ready = Runtime.completionReady(selected)
        local hovered = ready and pointerX and Runtime.contains(Runtime.COMPLETE, pointerX, pointerY)
        local buttonLabel = ready and "SCHEDULE CUSTOMER PICKUP" or "PRODUCTION NOT COMPLETE"
        if selected.status == "ready_for_pickup" then buttonLabel = "PICKUP AWAITING TRUCK"
        elseif selected.status == "pickup_in_progress" then buttonLabel = "PICKUP IN PROGRESS"
        elseif selected.status == "completed" then buttonLabel = "PAID AND COMPLETED" end
        Runtime.drawComputerButton(Runtime.COMPLETE, buttonLabel,
            not ready and "disabled" or hovered and "primaryHover" or "primary")
    end
end

return Component
