-- Inbox views, response labels, archiving, and deletion.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.JobService.emailInbox(state)
        local result = {}
        for _, notice in ipairs(Runtime.MachineFleet.serviceInbox(state)) do result[#result + 1] = notice end
        for _, email in ipairs(Runtime.ensureEmails(state).inbox) do result[#result + 1] = email end
        return result
    end

    function Runtime.JobService.estimateInbox(state)
        local result = {}
        local emails = Runtime.ensureEmails(state)
        for _, email in ipairs(emails.inbox) do
            if email.job or email.estimateRequest
                or email.noticeKind == "client_estimate_accepted"
                or email.noticeKind == "client_estimate_declined"
            then
                result[#result + 1] = email
            end
        end
        -- Keep sent estimates visible as "waiting" records without exposing their
        -- hidden response times.
        for _, email in ipairs(emails.pending) do
            if email.estimateReply then
                email.awaitingReply = true
                result[#result + 1] = email
            end
        end
        return result
    end

    function Runtime.archiveResponseLabel(email)
        if email.response == "estimate_sent" then return "ESTIMATE SENT" end
        if email.response == "accepted" or email.response == "quote_accepted" then return "ACCEPTED" end
        if email.response == "declined" or email.response == "quote_rejected" then return "DECLINED" end
        if email.noticeKind == "service_notice" then return "SERVICE NOTICE" end
        return "ARCHIVED"
    end

    function Runtime.archivedEmailBody(email)
        if type(email.body) == "string" and email.body ~= "" then return email.body end
        if email.response == "estimate_sent" then
            return string.format("A $%d estimate was sent for %s. The client reply is pending.",
                math.floor(tonumber(email.quotedPrice) or 0), tostring(email.jobId or "this job"))
        elseif email.response == "accepted" or email.response == "quote_accepted" then
            return "The estimate was accepted for " .. tostring(email.jobId or "this job") .. "."
        elseif email.response == "declined" or email.response == "quote_rejected" then
            return "The estimate was declined for " .. tostring(email.jobId or "this job") .. "."
        end
        return "This email was moved to the Archive Box."
    end

    function Runtime.JobService.archiveInbox(state)
        local result = {}
        local archive = Runtime.ensureEmails(state).archive
        for index = #archive, 1, -1 do
            local email = archive[index]
            result[#result + 1] = {
                id = email.id,
                sender = email.sender,
                subject = email.subject,
                body = Runtime.archivedEmailBody(email),
                noticeKind = email.noticeKind,
                orderId = email.orderId,
                total = email.total,
                jobId = email.jobId,
                quotedPrice = email.quotedPrice,
                response = email.response,
                archiveStatus = Runtime.archiveResponseLabel(email),
                archiveRecord = true,
            }
        end
        return result
    end

    function Runtime.JobService.markEmailRead(state, emailId)
        local emails = Runtime.ensureEmails(state)
        for _, email in ipairs(emails.inbox) do
            if email.id == emailId then
                email.unread = false
                return true, email
            end
        end
        for _, notice in ipairs(Runtime.MachineFleet.serviceInbox(state)) do
            if notice.id == emailId then
                notice.unread = false
                return true, notice
            end
        end
        return false
    end

    function Runtime.JobService.generalInbox(state)
        local result = {}
        for _, notice in ipairs(Runtime.MachineFleet.serviceInbox(state)) do result[#result + 1] = notice end
        for _, email in ipairs(Runtime.ensureEmails(state).inbox) do
            if not email.job and not email.estimateRequest
                and email.noticeKind ~= "client_estimate_accepted"
                and email.noticeKind ~= "client_estimate_declined"
            then
                result[#result + 1] = email
            end
        end
        return result
    end

    function Runtime.emailById(state, emailId)
        for index, email in ipairs(Runtime.ensureEmails(state).inbox) do
            if email.id == emailId then return email, index end
        end
    end

    function Runtime.JobService.respondToEmail(state, emailId, response, timestamp)
        local email, index = Runtime.emailById(state, emailId)
        if not email then return false, "email request was not found" end
        local succeeded, result
        if response == "accepted" then
            succeeded, result = Runtime.JobService.acceptOffer(state, email.job, timestamp)
        elseif response == "declined" then
            succeeded, result = Runtime.JobService.declineOffer(state, email.job, timestamp)
        else
            return false, "email response must be accepted or declined"
        end
        if not succeeded then return false, result end
        table.remove(state.clientEmails.inbox, index)
        state.clientEmails.archive[#state.clientEmails.archive + 1] = {
            id = email.id, sender = email.sender, subject = email.subject,
            body = email.body,
            jobId = email.job.id, response = response,
            respondedAtHours = Runtime.BusinessCalendar.absoluteHours(state),
        }
        return true, email.job
    end

    function Runtime.JobService.dismissInboxNotice(state, emailId)
        return Runtime.Inbox.dismissNotice(state, emailId)
    end

    function Runtime.JobService.archiveServiceNotice(state, noticeId)
        local notice = Runtime.MachineFleet.dismissServiceNotice(state, noticeId)
        if not notice then return false, "service notice was not found" end
        local emails = Runtime.ensureEmails(state)
        emails.archive[#emails.archive + 1] = {
            id = notice.id,
            sender = notice.sender,
            subject = notice.subject,
            body = notice.body,
            response = "archived",
            noticeKind = "service_notice",
            respondedAtHours = Runtime.BusinessCalendar.absoluteHours(state),
        }
        return true, notice
    end

    function Runtime.JobService.deleteEmail(state, emailId)
        local emails = Runtime.ensureEmails(state)
        for index, email in ipairs(emails.inbox) do
            if email.id == emailId then
                table.remove(emails.inbox, index)
                return true, email
            end
        end
        for index, email in ipairs(emails.pending) do
            if email.id == emailId then
                table.remove(emails.pending, index)
                if email.estimateReply and email.sourceJobId then
                    for archiveIndex = #emails.archive, 1, -1 do
                        local archived = emails.archive[archiveIndex]
                        if archived.jobId == email.sourceJobId and archived.response == "estimate_sent" then
                            table.remove(emails.archive, archiveIndex)
                        end
                    end
                end
                return true, email
            end
        end
        for index, email in ipairs(emails.archive) do
            if email.id == emailId then
                return true, table.remove(emails.archive, index)
            end
        end
        local notice = Runtime.MachineFleet.dismissServiceNotice(state, emailId)
        if notice then return true, notice end
        return false, "email was not found"
    end
end

return Component
