-- Reception, office, vendor, and truck presentation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawCustomer(pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("CLIENT", 142, 150)
        love.graphics.printf(tostring(view.company or "Waiting customer"), 260, 150, 500, "left")
        love.graphics.print("JOB", 142, 184)
        love.graphics.printf(tostring(view.jobId or "Pending ticket"), 260, 184, 500, "left")
        love.graphics.print("WORK", 142, 218)
        local source = view.sourceSize or {}
        local finished = view.finishedSize or {}
        local description = string.format("%gx%g stock to %gx%g finished · %s · %s",
            tonumber(source.width) or 0, tonumber(source.height) or 0,
            tonumber(finished.width) or 0, tonumber(finished.height) or 0,
            tostring(view.stock or "customer stock"),
            view.packaging == "boxed" and "boxed" or "flat pallet")
        love.graphics.printf(description, 260, 218, 500, "left")
        love.graphics.print("DELIVERY", 142, 288)
        love.graphics.printf(tostring(view.delivery or "Host-calculated service"), 260, 288, 500, "left")
        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.rectangle("fill", 142, 354, 676, 128, 4, 4)
        love.graphics.setColor(0.94, 0.91, 0.79)
        love.graphics.printf("Review the sample work now. The client will email the complete written specifications before your shop prepares a price.",
            170, 382, 620, "center")
        Runtime.button(Runtime.CONFIRM, "REQUEST EMAIL DETAILS", pointerX, pointerY, not Runtime.Screen.waiting, true)
    end

    function Runtime.drawComputer(state, pointerX, pointerY)
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print(string.format("CASH  $%d", math.floor(tonumber(state.money) or 0)), 142, 136)
        love.graphics.print(string.format("A/R  $%d", math.floor(tonumber(state.accountsReceivable) or 0)), 350, 136)
        love.graphics.print("ACTIVE JOBS — select one to inspect pickup readiness", 142, 158)
        local jobs = Runtime.activeJobs(state)
        if #jobs == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("No active jobs are in the host shop.", Runtime.ROW_X, Runtime.ROW_Y + 30, Runtime.ROW_W, "center")
        end
        for index, job in ipairs(jobs) do
            local rect = Runtime.rowRect(index)
            local selected = job.id == Runtime.Screen.selectedJobId
            love.graphics.setColor(selected and 0.91 or 0.79, selected and 0.72 or 0.78,
                selected and 0.24 or 0.73)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
            love.graphics.setColor(0.08, 0.10, 0.11)
            love.graphics.print(tostring(job.id), rect.x + 14, rect.y + 9)
            love.graphics.printf(tostring(job.company or "Client"), rect.x + 110, rect.y + 9, 280, "left")
            love.graphics.printf(Runtime.JobService.completionReady(job) and "READY" or tostring(job.status or "ACTIVE"),
                rect.x + 470, rect.y + 9, 184, "right")
        end
        Runtime.button(Runtime.CONFIRM, "REQUEST PICKUP", pointerX, pointerY,
            not Runtime.Screen.waiting and Runtime.Screen.selectedJobId ~= nil, true)
    end

    function Runtime.drawVendor(pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print(tostring(view.categoryName or "VENDOR CATALOG"), 142, 132)
        love.graphics.printf(tostring(view.salesman or "Supplier representative"),
            420, 132, 398, "right")
        love.graphics.print(string.format("HOST SHOP CASH  $%d",
            math.max(0, math.floor(tonumber(view.cash) or 0))), 142, 154)
        local rows = Runtime.vendorRows()
        for index, item in ipairs(rows) do
            local rect = Runtime.rowRect(index)
            local affordable = item.available == true
                and (tonumber(view.cash) or 0) >= (tonumber(item.price) or math.huge)
            love.graphics.setColor(0.79, 0.78, 0.73)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
            love.graphics.setColor(0.08, 0.10, 0.11)
            love.graphics.print(tostring(item.name or item.id), rect.x + 14, rect.y + 7)
            love.graphics.setColor(0.24, 0.28, 0.29)
            love.graphics.print(tostring(item.detail or "Host-verified purchase"),
                rect.x + 14, rect.y + 26)
            Runtime.button(Runtime.vendorBuyRect(index), item.available == true
                and string.format("BUY $%d", tonumber(item.price) or 0) or "LOCKED",
                pointerX, pointerY, not Runtime.Screen.waiting and affordable, true)
        end
        if #rows == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("This vendor has no active listings.", Runtime.ROW_X, Runtime.ROW_Y + 30,
                Runtime.ROW_W, "center")
        end
        Runtime.button(Runtime.CONFIRM, "NO THANKS", pointerX, pointerY, not Runtime.Screen.waiting, false)
    end

    function Runtime.drawTruck(pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        local pickup = view.mode == "pickup"
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print(tostring(view.manifestId or "TRUCK MANIFEST"), 142, 132)
        love.graphics.printf(tostring(view.title or "Truck manifest"), 420, 132, 398, "right")
        love.graphics.print(string.format("%d ITEM(S) REMAIN · PAGE %d / %d",
            math.max(0, tonumber(view.remaining) or 0), tonumber(view.page) or 1,
            tonumber(view.pageCount) or 1), 142, 154)
        for index, item in ipairs(view.items or {}) do
            local rect = Runtime.rowRect(index)
            love.graphics.setColor(item.available == true and 0.79 or 0.68,
                item.available == true and 0.78 or 0.72, 0.73)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
            love.graphics.setColor(0.08, 0.10, 0.11)
            love.graphics.print(tostring(item.label or "Manifest item"), rect.x + 14, rect.y + 7)
            love.graphics.setColor(0.24, 0.28, 0.29)
            love.graphics.print(tostring(item.detail or "Host-owned cargo"), rect.x + 14, rect.y + 26)
            Runtime.button(Runtime.vendorBuyRect(index), item.available == true
                and (pickup and "LOAD" or "UNLOAD") or "DONE",
                pointerX, pointerY, not Runtime.Screen.waiting and item.available == true, true)
        end
        Runtime.button(Runtime.TRUCK_PREVIOUS, "PREVIOUS", pointerX, pointerY,
            not Runtime.Screen.waiting and (tonumber(view.page) or 1) > 1, false)
        Runtime.button(Runtime.TRUCK_NEXT, "NEXT", pointerX, pointerY,
            not Runtime.Screen.waiting and (tonumber(view.page) or 1) < (tonumber(view.pageCount) or 1), false)
        Runtime.button(Runtime.CONFIRM, view.mode == "machine_delivery" and "RELEASE FLATBED" or "CLOSE CARGO",
            pointerX, pointerY, not Runtime.Screen.waiting and view.canClose == true, true)
    end
end

return Component
