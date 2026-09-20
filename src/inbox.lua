local BusinessCalendar = require("src.business_calendar")

local Inbox = {}

function Inbox.ensure(state)
    state.clientEmails = type(state.clientEmails) == "table" and state.clientEmails or {}
    local emails = state.clientEmails
    emails.nextEmailId = math.max(1, math.floor(tonumber(emails.nextEmailId) or 1))
    emails.nextPromotionId = math.max(1, math.floor(tonumber(emails.nextPromotionId) or 1))
    emails.pending = type(emails.pending) == "table" and emails.pending or {}
    emails.inbox = type(emails.inbox) == "table" and emails.inbox or {}
    emails.archive = type(emails.archive) == "table" and emails.archive or {}
    emails.sentPromotions = type(emails.sentPromotions) == "table" and emails.sentPromotions or {}
    return emails
end

function Inbox.addNotice(state, notice, delayHours)
    local emails = Inbox.ensure(state)
    local now = BusinessCalendar.absoluteHours(state)
    notice = {
        id = tostring(notice.id),
        sender = tostring(notice.sender),
        subject = tostring(notice.subject),
        body = tostring(notice.body),
        noticeKind = tostring(notice.noticeKind or "notice"),
        sourceJobId = notice.sourceJobId,
        orderId = notice.orderId,
        total = tonumber(notice.total),
        standardPrice = tonumber(notice.standardPrice),
        discountAmount = tonumber(notice.discountAmount),
        discountedTotal = tonumber(notice.discountedTotal),
        readyAtHours = now + math.max(0, tonumber(delayHours) or 0),
    }
    if notice.readyAtHours then notice.readyAtHours = math.max(now, tonumber(notice.readyAtHours) or now) end
    if notice.readyAtHours <= now then
        notice.receivedAtHours = now
        emails.inbox[#emails.inbox + 1] = notice
    else
        emails.pending[#emails.pending + 1] = notice
    end
    return notice
end

function Inbox.dismissNotice(state, noticeId)
    local emails = Inbox.ensure(state)
    for index, notice in ipairs(emails.inbox) do
        if notice.id == noticeId and not notice.job then
            table.remove(emails.inbox, index)
            emails.archive[#emails.archive + 1] = {
                id = notice.id,
                sender = notice.sender,
                subject = notice.subject,
                response = "archived",
                noticeKind = notice.noticeKind,
                orderId = notice.orderId,
                total = notice.total,
                respondedAtHours = BusinessCalendar.absoluteHours(state),
            }
            return notice
        end
    end
end

return Inbox
