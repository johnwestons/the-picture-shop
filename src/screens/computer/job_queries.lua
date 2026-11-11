-- Office jobs, deliveries, email selection, and remote intents.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.remoteAction(kind, args)
        args = args or {}
        args.kind = kind
        Runtime.dependencies.remoteCommand(args)
        return { action = "remote_pending" }
    end

    function Runtime.markEmailRead(state, email)
        if not email or email.unread ~= true or email.awaitingReply or email.archiveRecord then return false end
        if Runtime.dependencies.remoteCommand then
            Runtime.dependencies.remoteCommand({ kind = "mark_email_read", id = email.id })
        else
            Runtime.JobService.markEmailRead(state, email.id)
        end
        return true
    end

    function Runtime.machineBuyRect(index)
        return { x = Runtime.MACHINE_OFFER.x + Runtime.MACHINE_OFFER.width - 100,
            y = Runtime.MACHINE_OFFER.y + (index - 1) * (Runtime.MACHINE_OFFER.height + Runtime.MACHINE_OFFER.gap) + 5,
            width = 88, height = 40 }
    end

    function Runtime.machineSellRect(index)
        return { x = Runtime.OWNED_MACHINE.x + Runtime.OWNED_MACHINE.width - 88,
            y = Runtime.OWNED_MACHINE.y + (index - 1) * (Runtime.OWNED_MACHINE.height + Runtime.OWNED_MACHINE.gap) + 13,
            width = 76, height = 36 }
    end

    function Runtime.ComputerScreen.ownedMachinePage(state)
        local owned = Runtime.MachineFleet.owned(state)
        local pages = math.max(1, math.ceil(#owned / Runtime.ComputerScreen.machinePageSize))
        Runtime.ComputerScreen.machinePage = math.max(1, math.min(Runtime.ComputerScreen.machinePage or 1, pages))
        return owned, pages
    end

    function Runtime.isPurchaseOrder(item)
        return item and item.vendor ~= nil and item.productName ~= nil
    end

    function Runtime.displayStatus(item)
        if Runtime.isPurchaseOrder(item) then
            return item.delivery and item.delivery.status or item.status
        end
        if item and Runtime.ComputerScreen.tab == "active"
            and Runtime.completionReady(item) then
            return "ready_to_ship"
        end
        return item and item.status
    end

    function Runtime.deliveries(state)
        local result = {}
        for _, job in ipairs(state.jobs.active or {}) do
            local delivery=job.delivery or {}
            if job.status == "awaiting_delivery" and delivery.status~="received" then
                result[#result + 1] = job
            end
        end
        local procurement = Runtime.Procurement.ensure(state)
        local ordersByShipment={}
        for _,order in ipairs(procurement.orders or {}) do
            local list=ordersByShipment[order.shipmentId]
            if not list then list={};ordersByShipment[order.shipmentId]=list end
            list[#list+1]=order
        end
        for _, shipment in ipairs(procurement.shipments or {}) do
            local delivery=shipment.delivery or {}
            if shipment.status=="awaiting_delivery" and delivery.status~="received" then
                local orders,companies,products={},{},{}
                local company
                for _,order in ipairs(ordersByShipment[shipment.id] or {}) do
                    orders[#orders+1]=order
                    local name=order.productName or order.item or "Supplies"
                    if not products[name] then products[name]=true end
                    local vendor=order.company or order.vendor
                    if vendor and vendor~="" then companies[vendor]=true end
                end
                local productNames={}
                for name in pairs(products) do productNames[#productNames+1]=name end
                table.sort(productNames)
                for name in pairs(companies) do
                    if not company then company=name
                    elseif company~=name then company="Millhaven Freight";break end
                end
                company=delivery.route and delivery.route.originCompany or company or "Millhaven Freight"
                local description=#productNames==0 and "Supply shipment"
                    or table.concat(productNames," · ")
                if #description>64 then description=description:sub(1,61).."..." end
                result[#result+1]={id=shipment.id,shipmentId=shipment.id,shipmentRecord=shipment,
                    orderIds=shipment.orderIds,orders=orders,company=company,vendor=company,
                    productName=description,status=shipment.status,delivery=delivery}
            end
        end
        local function arrival(item)
            local delivery=item.delivery or {}
            local route=delivery.route or {}
            return tonumber(route.arrivalAtHours or delivery.expectedAtHours or delivery.readyAtHours)
                or math.huge
        end
        table.sort(result,function(a,b)
            local at,bt=arrival(a),arrival(b)
            if at~=bt then return at<bt end
            return tostring(a.id)<tostring(b.id)
        end)
        return result
    end

    -- Keep the older per-job/per-order projection for callers that use it to
    -- display operational delivery records. The DELIVERIES tab itself uses
    -- one tracker row per inbound truck shipment.
    function Runtime.ComputerScreen.deliveryRows(state)
        local rows={}
        for _,job in ipairs(state.jobs.active or {}) do
            if job.status=="awaiting_delivery" or job.status=="ready_for_pickup"
                or job.status=="pickup_in_progress" then rows[#rows+1]=job end
        end
        local procurement=Runtime.Procurement.ensure(state)
        for _,order in ipairs(procurement.orders or {}) do rows[#rows+1]=order end
        return rows
    end
    function Runtime.ComputerScreen.statusLabel(status) return Runtime.StatusLabels.get(status) end

    function Runtime.jobsForTab(state, tab)
        if tab == "active" then return state.jobs.active or {} end
        if tab == "completed" then return state.jobs.completed or {} end
        if tab == "deliveries" then return Runtime.deliveries(state) end
        return {}
    end

    function Runtime.findJob(jobs, id)
        for _, job in ipairs(jobs) do
            if job.id == id then return job end
        end
        return nil
    end

    function Runtime.inboxForTab(state)
        if Runtime.ComputerScreen.tab == "estimating" then return Runtime.JobService.estimateInbox(state) end
        if Runtime.ComputerScreen.tab == "email" and Runtime.ComputerScreen.emailFolder == "archive" then
            return Runtime.JobService.archiveInbox(state)
        end
        return Runtime.JobService.generalInbox(state)
    end

    function Runtime.tabUnreadCount(state, tabId)
        local inbox
        if tabId == "email" then inbox = Runtime.JobService.generalInbox(state)
        elseif tabId == "estimating" then inbox = Runtime.JobService.estimateInbox(state)
        else return 0 end
        local count = 0
        for _, email in ipairs(inbox) do
            if email.unread == true and not email.awaitingReply and not email.archiveRecord then
                count = count + 1
            end
        end
        return count
    end

    function Runtime.emailPageSize()
        return Runtime.EMAIL_PAGE_SIZE
    end

    function Runtime.emailRowY()
        return Runtime.ComputerScreen.tab == "email" and 252 or 238
    end

    function Runtime.selectedEmail(state)
        for _, email in ipairs(Runtime.inboxForTab(state)) do
            if email.id == Runtime.ComputerScreen.selectedEmailId then return email end
        end
    end

    function Runtime.promotionSentForJob(state, job)
        if not job then return false end
        if job.promotionSent then return true end
        for _, promotion in ipairs((state.clientEmails and state.clientEmails.sentPromotions) or {}) do
            if promotion.sourceJobId == job.id then return true end
        end
        return false
    end

    function Runtime.resetQuoteText(state)
        local email = Runtime.selectedEmail(state)
        local terms=email and email.job and Runtime.JobService.quoteTerms(state,email.job)
        local base = terms and terms.recommendedPrice
        Runtime.ComputerScreen.quoteText = base and tostring(math.floor(base)) or ""
        Runtime.ComputerScreen.quoteFocused = false
        Runtime.ComputerScreen.quoteReplaceOnType = true
        local deliveryTerms=email and email.job and Runtime.JobService.deliveryQuoteTerms(email.job)
        Runtime.ComputerScreen.deliveryQuoteText = deliveryTerms
            and tostring(math.floor(deliveryTerms.recommendedPrice)) or ""
        Runtime.ComputerScreen.deliveryQuoteFocused = false
        Runtime.ComputerScreen.deliveryQuoteReplaceOnType = true
        Runtime.ComputerScreen.includeDeliveryQuote = deliveryTerms ~= nil
    end

    function Runtime.currentPageJobs(state)
        local jobs = Runtime.jobsForTab(state, Runtime.ComputerScreen.tab)
        local page = Runtime.ComputerScreen.pages[Runtime.ComputerScreen.tab] or 1
        local maximumPage = math.max(1, math.ceil(#jobs / Runtime.jobsPerPage()))
        page = math.min(math.max(1, page), maximumPage)
        Runtime.ComputerScreen.pages[Runtime.ComputerScreen.tab] = page
        local visible = {}
        local first = (page - 1) * Runtime.jobsPerPage() + 1
        for index = first, math.min(#jobs, first + Runtime.jobsPerPage() - 1) do
            visible[#visible + 1] = jobs[index]
        end
        return jobs, visible, page, maximumPage
    end

    function Runtime.ensureSelection(state)
        local jobs = Runtime.jobsForTab(state, Runtime.ComputerScreen.tab)
        if not Runtime.findJob(jobs, Runtime.ComputerScreen.selectedJobId) then
            Runtime.ComputerScreen.selectedJobId = jobs[1] and jobs[1].id or nil
        end
    end
end

return Component
