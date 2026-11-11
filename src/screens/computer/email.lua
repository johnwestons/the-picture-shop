-- Email and estimating presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawEmail(state, pointerX, pointerY, assets)
        local estimating = Runtime.ComputerScreen.tab == "estimating"
        local inbox = Runtime.inboxForTab(state)
        Runtime.panel({ x = 110, y = 190, width = 288, height = 394 },
            { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        Runtime.panel({ x = 410, y = 190, width = 438, height = 394 },
            { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.print(estimating and "JOB ESTIMATING" or "EMAIL INBOX", 124, 202)
        if not estimating then
            local function folderButton(rect, label, active)
                local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
                Runtime.drawComputerButton(rect, label, active
                    and (hovered and "primaryHover" or "primary")
                    or (hovered and "hover" or "secondary"))
            end
            folderButton(Runtime.EMAIL_FOLDER_INBOX, "INBOX", Runtime.ComputerScreen.emailFolder ~= "archive")
            folderButton(Runtime.EMAIL_FOLDER_ARCHIVE, "ARCHIVE BOX", Runtime.ComputerScreen.emailFolder == "archive")
        else
            local mailFrame = 13 + math.floor(love.timer.getTime() * 1.4) % 2
            Runtime.drawCritterNetSprite(assets, mailFrame, 302, 188, 80, 54, 0.92)
        end
        if Runtime.ComputerScreen.promoJobId then
            local source = Runtime.findJob(state.jobs.completed or {}, Runtime.ComputerScreen.promoJobId)
            love.graphics.setColor(0.66, 0.74, 0.75)
            love.graphics.printf("Promotion composer open for a completed client.", 122, 252, 264, "center")
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print("NEW RETURNING-CLIENT PROMOTION", 434, 212)
            love.graphics.setColor(0.76, 0.83, 0.84)
            love.graphics.print("TO: " .. tostring(source and source.company or "--"), 434, 246)
            love.graphics.printf(source and source.press
                and "We'd like to offer you 10% off your next custom printing job."
                or "We'd like to offer you 10% off your next paper-cutting job.",
                434, 278, 392, "left")
            love.graphics.setColor(0.58, 0.67, 0.68)
            love.graphics.print("ADD A PERSONAL NOTE — OPTIONAL", 434, 320)
            Runtime.panel(Runtime.PROMO_INPUT, { 0.045, 0.085, 0.10, 1 },
                Runtime.ComputerScreen.promoFocused and { 0.32, 0.78, 0.73, 1 }
                    or { 0.20, 0.34, 0.39, 1 }, 3, 1)
            love.graphics.setColor(0.88, 0.91, 0.89)
            local note = Runtime.ComputerScreen.promoText
            if note == "" then note = "Write a personal note to your client (optional)." end
            note = note .. (Runtime.ComputerScreen.promoFocused and "_" or "")
            local input = Runtime.PROMO_INPUT
            local font = love.graphics.getFont()
            local _, lines = font:getWrap(note, input.width - 20)
            local lineHeight = font:getHeight() * font:getLineHeight()
            local visibleLines = math.max(1, math.floor((input.height - 20) / lineHeight))
            local firstLine = math.max(1, #lines - visibleLines + 1)
            local textX, textY = input.x + 10, input.y + 10
            local previousScissorX, previousScissorY, previousScissorWidth, previousScissorHeight = love.graphics.getScissor()
            love.graphics.setScissor(input.x + 1, input.y + 1, input.width - 2, input.height - 2)
            if firstLine > 1 then
                love.graphics.print("…", textX, textY)
                textY = textY + lineHeight
                firstLine = math.max(1, #lines - visibleLines + 2)
            end
            for index = firstLine, #lines do
                love.graphics.print(lines[index], textX, textY)
                textY = textY + lineHeight
            end
            if previousScissorX then
                love.graphics.setScissor(previousScissorX, previousScissorY,
                    previousScissorWidth, previousScissorHeight)
            else
                love.graphics.setScissor()
            end
            love.graphics.setColor(0.58, 0.67, 0.68)
            love.graphics.print("Your note is included in the offer.",434,468)
            love.graphics.printf(string.format("%d/600",#Runtime.ComputerScreen.promoText),
                766,468,60,"right")
            local function promoButton(rect, label, green)
                local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
                Runtime.drawComputerButton(rect, label, green
                    and (hovered and "primaryHover" or "primary")
                    or (hovered and "dangerHover" or "danger"))
            end
            promoButton(Runtime.EMAIL_DECLINE, "CANCEL", false)
            promoButton(Runtime.PROMO, "SEND 10% OFFER", true)
            return
        end
        if #inbox == 0 then
            love.graphics.setColor(0.58, 0.66, 0.67)
            local originalFont=love.graphics.getFont()
            love.graphics.setFont(require('src.screens.computer.fonts').get('typewriter',14))
            love.graphics.printf(not estimating and Runtime.ComputerScreen.emailFolder == "archive"
                and "No archived emails yet. Archive a message from your inbox to keep it here."
                or estimating
                and "No estimates need attention. Walk-in clients email their written details after the counter visit."
                or "No new receipts, notices, or client messages.",
                122, 332, 264, "center")
            love.graphics.setFont(originalFont)
            return
        end
        local selected
        local pageSize = Runtime.emailPageSize()
        local rowY = Runtime.emailRowY()
        local maximumEmailPage = math.max(1, math.ceil(#inbox / pageSize))
        Runtime.ComputerScreen.emailPage = math.max(1, math.min(Runtime.ComputerScreen.emailPage or 1, maximumEmailPage))
        local firstEmail = (Runtime.ComputerScreen.emailPage - 1) * pageSize + 1
        for row = 1, pageSize do
            local email = inbox[firstEmail + row - 1]
            if not email then break end
            local rect = { x = 116, y = rowY + (row - 1) * 54, width = 282, height = 46 }
            if email.id == Runtime.ComputerScreen.selectedEmailId then selected = email end
            local active = email.id == Runtime.ComputerScreen.selectedEmailId
            local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.panel(rect,
                active and { 0.08, 0.27, 0.30, 1 }
                    or hovered and { 0.075, 0.17, 0.20, 1 }
                    or { 0.055, 0.085, 0.11, 1 },
                active and { 0.25, 0.68, 0.68, 1 }
                    or hovered and { 0.23, 0.47, 0.54, 1 }
                    or { 0.15, 0.27, 0.33, 1 }, 3, active and 2 or 1)
            love.graphics.setColor(active and 0.98 or 0.89, active and 0.99 or 0.93,
                active and 0.94 or 0.92)
            local originalFont=love.graphics.getFont()
            love.graphics.setFont(require('src.screens.computer.fonts').get('typewriter',13))
            love.graphics.print(email.sender, rect.x + 8, rect.y + 7)
            if email.awaitingReply or email.archiveRecord then love.graphics.setColor(0.96, 0.78, 0.35)
            elseif active then love.graphics.setColor(0.72, 0.91, 0.88)
            else love.graphics.setColor(0.65, 0.77, 0.80) end
            love.graphics.print(email.awaitingReply and "SENT · WAITING FOR REPLY"
                or email.archiveRecord and email.archiveStatus or email.subject,
                rect.x + 8, rect.y + 24)
            love.graphics.setFont(originalFont)
        end
        local function emailPageButton(rect, label, enabled)
            local hovered = enabled and pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, label,
                not enabled and "disabled" or hovered and "hover" or "secondary")
        end
        emailPageButton(Runtime.EMAIL_PREVIOUS, "<", Runtime.ComputerScreen.emailPage > 1)
        emailPageButton(Runtime.EMAIL_NEXT, ">", Runtime.ComputerScreen.emailPage < maximumEmailPage)
        love.graphics.setColor(0.55, 0.63, 0.65)
        love.graphics.printf(string.format("%d/%d", Runtime.ComputerScreen.emailPage, maximumEmailPage),
            206, 556, 100, "center")
        if not selected and not Runtime.ComputerScreen.emailSelectionRequired then selected = inbox[1] end
        if not selected and Runtime.ComputerScreen.emailSelectionRequired then
            love.graphics.setColor(0.58, 0.66, 0.67)
            love.graphics.printf("Select an email to view its details.",
                454, 350, 352, "center")
            return
        end
        if not selected then return end
        love.graphics.setColor(0.96, 0.84, 0.30)
        local originalFont=love.graphics.getFont()
        love.graphics.setFont(require('src.screens.computer.fonts').get('typewriter',14))
        love.graphics.print("FROM: " .. selected.sender, 434, 212)
        love.graphics.setColor(0.72, 0.79, 0.80)
        love.graphics.print("SUBJECT: " .. selected.subject, 434, 238)
        if selected.estimateRequest and selected.job then
            local font=love.graphics.getFont()
            local _,lines=font:getWrap(selected.body,392)
            local lineHeight=font:getHeight()*font:getLineHeight()
            for index=1,math.min(3,#lines) do
                love.graphics.print(lines[index],434,270+(index-1)*lineHeight)
            end
            if #lines>3 then love.graphics.print("…",810,270+2*lineHeight) end
        else
            love.graphics.printf(selected.body, 434, 270, 392, "left")
        end
        love.graphics.setFont(originalFont)
        if selected.estimateRequest and selected.job then
            love.graphics.setColor(0.48, 0.78, 0.68)
            love.graphics.print("ARRIVAL IF ACCEPTED:", 434, 328)
            love.graphics.setColor(0.91, 0.93, 0.87)
            love.graphics.printf(Runtime.JobService.expectedStockArrivalText(state, selected.job),
                588, 328, 238, "right")
        end
        if selected.awaitingReply then
            local remaining = math.max(0, math.ceil((tonumber(selected.expiresAtHours) or 0)
                - Runtime.BusinessCalendar.absoluteHours(state)))
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print("ESTIMATE SENT", 434, 350)
            love.graphics.setColor(0.86, 0.90, 0.88)
            love.graphics.print("Job: " .. tostring(selected.sourceJobId or "--"), 434, 382)
            love.graphics.print("Amount: " .. Runtime.money(selected.quotedPrice or 0), 434, 408)
            love.graphics.print(string.format("Expires in: %d hour%s", remaining,
                remaining == 1 and "" or "s"), 434, 434)
            love.graphics.setColor(0.58, 0.67, 0.68)
            love.graphics.printf("The client usually replies within a few hours. Cancel this estimate if you no longer want to wait.",
                434, 478, 392, "left")
            local deleteHover = pointerX and Runtime.contains(Runtime.EMAIL_DELETE, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.EMAIL_DELETE, "CANCEL ESTIMATE",
                deleteHover and "dangerHover" or "danger")
            return
        end
        if selected.noticeKind == "customer_case" or selected.noticeKind == "customer_case_resolved" then
            local job = Runtime.findJob(state.jobs and state.jobs.completed or {}, selected.sourceJobId)
            local customerCase = job and job.customerCase
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print(customerCase and customerCase.status == "open"
                and "CUSTOMER CASE • ACTION NEEDED" or "CUSTOMER CASE • RESOLVED", 434, 392)
            love.graphics.setColor(0.78, 0.86, 0.84)
            love.graphics.printf("Job: " .. tostring(selected.sourceJobId or "--"), 434, 420, 392, "left")
            if customerCase and customerCase.status == "open" then
                local creditHover = pointerX and Runtime.contains(Runtime.EMAIL_ACCEPT, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.EMAIL_ACCEPT, "OFFER 10% ACCOUNT CREDIT",
                    creditHover and "primaryHover" or "primary")
                local apologyHover = pointerX and Runtime.contains(Runtime.EMAIL_DECLINE, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.EMAIL_DECLINE, "APOLOGIZE + EXPLAIN",
                    apologyHover and "hover" or "secondary")
                local declineHover = pointerX and Runtime.contains(Runtime.EMAIL_DELETE, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.EMAIL_DELETE, "DECLINE RESPONSIBILITY",
                    declineHover and "dangerHover" or "danger")
            else
                love.graphics.setColor(0.72, 0.82, 0.82)
                love.graphics.printf(selected.body, 434, 446, 392, "left")
                local archiveHover = pointerX and Runtime.contains(Runtime.EMAIL_DECLINE, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.EMAIL_DECLINE, "ARCHIVE CASE",
                    archiveHover and "hover" or "secondary")
                local deleteHover = pointerX and Runtime.contains(Runtime.EMAIL_DELETE, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.EMAIL_DELETE, "DELETE EMAIL",
                    deleteHover and "dangerHover" or "danger")
            end
            return
        end
        if selected.serviceNotice then
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print("BLADE EXCHANGE UPDATE", 434, 392)
            love.graphics.setColor(0.66, 0.75, 0.76)
            love.graphics.printf("This is an update from Mara Mouse, the cutter blade exchange courier.",
                434, 424, 392, "left")
            local hovered = pointerX and Runtime.contains(Runtime.EMAIL_DECLINE, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.EMAIL_DECLINE, "ARCHIVE NOTICE",
                hovered and "hover" or "secondary")
            local deleteHover = pointerX and Runtime.contains(Runtime.EMAIL_DELETE, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.EMAIL_DELETE, "DELETE EMAIL",
                deleteHover and "dangerHover" or "danger")
            return
        end
        if selected.archiveRecord then
            local heading = "ARCHIVED EMAIL"
            if selected.response == "estimate_sent" then heading = "ESTIMATE SENT"
            elseif selected.response == "accepted" or selected.response == "quote_accepted" then heading = "ESTIMATE ACCEPTED"
            elseif selected.response == "declined" or selected.response == "quote_rejected" then heading = "ESTIMATE DECLINED"
            elseif selected.noticeKind == "service_notice" then heading = "SERVICE NOTICE"
            elseif selected.orderId then heading = "ORDER EMAIL" end
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print(heading, 434, 392)
            if selected.jobId then
                love.graphics.setColor(0.72, 0.79, 0.80)
                love.graphics.print("Job: " .. selected.jobId, 434, 420)
            elseif selected.orderId then
                love.graphics.setColor(0.72, 0.79, 0.80)
                love.graphics.print("Order: " .. selected.orderId, 434, 420)
            end
            if selected.quotedPrice then
                love.graphics.setColor(0.54, 0.84, 0.65)
                love.graphics.print("Estimate: " .. Runtime.money(selected.quotedPrice), 434, 446)
            elseif selected.total then
                love.graphics.setColor(0.54, 0.84, 0.65)
                love.graphics.print("Total paid: " .. Runtime.money(selected.total), 434, 446)
            end
            local deleteHover = pointerX and Runtime.contains(Runtime.EMAIL_DELETE, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.EMAIL_DELETE, "DELETE EMAIL",
                deleteHover and "dangerHover" or "danger")
            return
        end
        if not selected.job then
            if selected.applicationId then
                love.graphics.setColor(.96,.84,.30,1)
                love.graphics.print("RESUME / EMPLOYMENT THREAD",434,392)
                local hovered = pointerX and Runtime.contains(Runtime.EMAIL_ACCEPT, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.EMAIL_ACCEPT, "OPEN RESUME",
                    hovered and "primaryHover" or "primary")
            end
            local heading = selected.noticeKind == "receipt" and "ORDER RECEIPT"
                or selected.noticeKind == "salesman_confirmation" and "SALESMAN CONFIRMATION"
                or selected.noticeKind == "client_thanks" and "CLIENT REPLY"
                or selected.noticeKind == "client_estimate_accepted" and "ESTIMATE ACCEPTED"
                or selected.noticeKind == "client_estimate_declined" and "ESTIMATE DECLINED"
                or (selected.applicationId and "" or "EMAIL NOTICE")
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print(heading, 434, 392)
            if selected.orderId then
                love.graphics.setColor(0.72, 0.79, 0.80)
                love.graphics.print("Order: " .. selected.orderId, 434, 420)
            end
            if selected.total then
                love.graphics.setColor(0.54, 0.84, 0.65)
                love.graphics.print("Total paid: " .. Runtime.money(selected.total), 434, 446)
            end
            local hovered = pointerX and Runtime.contains(Runtime.EMAIL_DECLINE, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.EMAIL_DECLINE, "ARCHIVE EMAIL",
                hovered and "hover" or "secondary")
            local deleteHover = pointerX and Runtime.contains(Runtime.EMAIL_DELETE, pointerX, pointerY)
            Runtime.drawComputerButton(Runtime.EMAIL_DELETE, "DELETE EMAIL",
                deleteHover and "dangerHover" or "danger")
            return
        end
        local job = selected.job
        love.graphics.setColor(0.86, 0.89, 0.88)
        love.graphics.print("PROPOSED JOB  " .. job.id, 434, 350)
        love.graphics.print(string.format("Sheets: %g × %g in → %g × %g in",
            job.sourceSize.width, job.sourceSize.height, job.finishedSize.width, job.finishedSize.height), 434, 372)
        local stockSource = job.press and job.stockSpec and job.stockSpec.suppliedBy == "house"
            and "HOUSE PAPER" or "CUSTOMER STOCK"
        local paperText = job.stockSpec and job.stockSpec.description
            or job.details and job.details.stockDescription or "Customer supplied"
        love.graphics.printf((job.press and (stockSource .. " — ") or "Paper: ") .. paperText, 434, 394,
            job.press and 292 or 392, "left")
        if job.press then
            love.graphics.printf(string.format("Order: %s good / %s supplied",
                Runtime.commaNumber(job.quote.orderedCopies or job.press.orderedQuantity),
                Runtime.commaNumber(job.quote.suppliedSheets or job.quote.totalSheets)), 434, 414, 392, "left")
            love.graphics.printf(string.format("Press: %d color%s • %s", job.press.colors or 1,
                (job.press.colors or 1) == 1 and "" or "s",
                table.concat(job.press.colorSequence or { "Black" }, " → ")), 434, 434, 292, "left")
            Runtime.drawArtworkPreview(assets, job, 766, 354, 48)
        else
            love.graphics.print(string.format("%d pallet%s · %s sheets · %s, wrapped",
                job.quote.palletCount, job.quote.palletCount == 1 and "" or "s",
                Runtime.commaNumber(job.quote.totalSheets),job.packaging=="boxed" and "Boxed" or "Flat"), 434, 414)
        end
        local terms = Runtime.JobService.quoteTerms(state, job, tonumber(Runtime.ComputerScreen.quoteText))
        local deliveryRequested = job.outboundDelivery and job.outboundDelivery.requested == true
        local deliveryTerms = deliveryRequested
            and Runtime.JobService.deliveryQuoteTerms(job,
                tonumber(Runtime.ComputerScreen.deliveryQuoteText)) or nil
        if terms and terms.employeeBudget and not job.press then
            love.graphics.setColor(.67,.78,.69,1)
            love.graphics.printf(string.format("Cutter labor budget %s at %s/hr",Runtime.money(terms.employeeBudget.laborCost),Runtime.money(terms.employeeBudget.wagePerHour)),434,426,392,"left")
        end
        if deliveryRequested then
            local included = Runtime.ComputerScreen.includeDeliveryQuote == true
            local hovered = pointerX and Runtime.contains(Runtime.EMAIL_DELIVERY_TOGGLE, pointerX, pointerY)
            Runtime.panel(Runtime.EMAIL_DELIVERY_TOGGLE,
                included and { 0.07, 0.22, 0.18, 1 } or { 0.07, 0.09, 0.11, 1 },
                hovered and { 0.39, 0.70, 0.57, 1 } or { 0.20, 0.38, 0.34, 1 }, 3, 1)
            love.graphics.setColor(included and 0.74 or 0.70, included and 0.91 or 0.77,
                included and 0.77 or 0.78)
            love.graphics.print(included and "[✓] OFFER SHOP DELIVERY" or "[ ] CLIENT ARRANGES TRANSPORT",
                Runtime.EMAIL_DELIVERY_TOGGLE.x + 9, Runtime.EMAIL_DELIVERY_TOGGLE.y + 3)
            love.graphics.setColor(0.68, 0.76, 0.76)
            love.graphics.printf(included and "Client can accept or decline this fee separately"
                or "No delivery fee will be quoted", 620, Runtime.EMAIL_DELIVERY_TOGGLE.y + 3, 198, "right")
        else
            love.graphics.setColor(0.68, 0.76, 0.76)
            love.graphics.print("CLIENT ARRANGES TRANSPORT", 434, 446)
        end

        love.graphics.setColor(0.58, 0.78, 0.72)
        love.graphics.print(selected.discountedTotal and "PRODUCTION · COUPON" or "PRODUCTION",
            Runtime.EMAIL_QUOTE_INPUT.x, 464)
        love.graphics.setColor(0.58, 0.67, 0.68)
        love.graphics.printf("Rec. " .. Runtime.money(terms and terms.recommendedPrice or job.quote.totalPrice),
            Runtime.EMAIL_QUOTE_INPUT.x + 90, 464, Runtime.EMAIL_QUOTE_INPUT.width - 90, "right")
        Runtime.panel(Runtime.EMAIL_QUOTE_INPUT, { 0.045, 0.085, 0.10, 1 },
            Runtime.ComputerScreen.quoteFocused and { 0.32, 0.78, 0.73, 1 }
                or { 0.20, 0.34, 0.39, 1 }, 3, 1)
        love.graphics.setColor(0.96, 0.96, 0.92)
        love.graphics.print("$", Runtime.EMAIL_QUOTE_INPUT.x + 8, Runtime.EMAIL_QUOTE_INPUT.y + 11)
        love.graphics.printf(Runtime.ComputerScreen.quoteText .. (Runtime.ComputerScreen.quoteFocused and "_" or ""),
            Runtime.EMAIL_QUOTE_INPUT.x + 25, Runtime.EMAIL_QUOTE_INPUT.y + 11,
            Runtime.EMAIL_QUOTE_INPUT.width - 32, "right")

        if deliveryRequested then
            love.graphics.setColor(0.58, 0.78, 0.72)
            love.graphics.print("DELIVERY", Runtime.EMAIL_DELIVERY_QUOTE_INPUT.x, 464)
            love.graphics.setColor(0.58, 0.67, 0.68)
            love.graphics.printf("Rec. " .. Runtime.money(deliveryTerms and deliveryTerms.recommendedPrice or 0),
                Runtime.EMAIL_DELIVERY_QUOTE_INPUT.x + 90, 464,
                Runtime.EMAIL_DELIVERY_QUOTE_INPUT.width - 90, "right")
            Runtime.panel(Runtime.EMAIL_DELIVERY_QUOTE_INPUT,
                Runtime.ComputerScreen.includeDeliveryQuote and { 0.045, 0.085, 0.10, 1 }
                    or { 0.07, 0.08, 0.09, 1 },
                Runtime.ComputerScreen.deliveryQuoteFocused and { 0.32, 0.78, 0.73, 1 }
                    or { 0.20, 0.34, 0.39, 1 }, 3, 1)
            love.graphics.setColor(Runtime.ComputerScreen.includeDeliveryQuote and 0.96 or 0.48,
                Runtime.ComputerScreen.includeDeliveryQuote and 0.96 or 0.53,
                Runtime.ComputerScreen.includeDeliveryQuote and 0.92 or 0.54)
            love.graphics.print("$", Runtime.EMAIL_DELIVERY_QUOTE_INPUT.x + 8,
                Runtime.EMAIL_DELIVERY_QUOTE_INPUT.y + 11)
            love.graphics.printf(Runtime.ComputerScreen.deliveryQuoteText
                .. (Runtime.ComputerScreen.deliveryQuoteFocused and "_" or ""),
                Runtime.EMAIL_DELIVERY_QUOTE_INPUT.x + 25, Runtime.EMAIL_DELIVERY_QUOTE_INPUT.y + 11,
                Runtime.EMAIL_DELIVERY_QUOTE_INPUT.width - 32, "right")
        end
        love.graphics.setColor(0.64, 0.72, 0.73)
        local deliverySummary = Runtime.ComputerScreen.includeDeliveryQuote and deliveryTerms
            and ("Quoted total if both accepted: " .. Runtime.money(terms.amount + deliveryTerms.amount))
            or deliveryRequested and "Client will arrange its own transportation"
            or "This client arranges its own transportation"
        love.graphics.printf(deliverySummary, 434, 521, 392, "center")

        local function responseButton(rect, label, green)
            local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, label, green
                and (hovered and "primaryHover" or "primary")
                or (hovered and "dangerHover" or "danger"))
        end
        responseButton(Runtime.EMAIL_ESTIMATE_DECLINE, "DECLINE REQUEST", false)
        responseButton(Runtime.EMAIL_ESTIMATE_SEND, "SEND ESTIMATE", true)
        if terms and terms.employeeBudget and terms.amount<terms.recommendedPrice then
            love.graphics.setColor(.98,.71,.35,1)
            love.graphics.printf("Below staff cost target",434,592,190,"left")
        end
        love.graphics.setColor(0.58, 0.67, 0.68)
        love.graphics.printf("The client replies within 3 days.", 630, 592, 196, "center")
    end
end

return Component
