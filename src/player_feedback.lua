local Feedback = {}
Feedback.__index = Feedback

local MENU_SCREENS = { title = true, lan = true, direct = true, asset_error = true }
local NOTICE_LIMIT = 3
local NOTICE_SECONDS = 2.35
local CASH_SECONDS = 1.05

local function currentCall(state)
    local call = state.workPhone and state.workPhone.incoming
    if type(call) ~= "table" or call.direction == "outgoing" then return nil end
    return call
end

local function emailStates(state)
    local seen = {}
    for _, email in ipairs(state.clientEmails and state.clientEmails.inbox or {}) do
        if email.id ~= nil then
            seen[tostring(email.id)] = {
                receivedAtHours = tonumber(email.receivedAtHours),
                subject = email.subject,
                unread = email.unread == true,
            }
        end
    end
    return seen
end

function Feedback.new(context)
    assert(type(context) == "table" and type(context.state) == "table",
        "player feedback requires shop state")
    return setmetatable({
        context = context,
        initialized = false,
        previousScreen = nil,
        previousMoney = 0,
        customerState = nil,
        vendorState = nil,
        callId = nil,
        emailState = {},
        cashDelta = 0,
        cashTimer = 0,
        notices = {},
    }, Feedback)
end

function Feedback:seed()
    local state, world = self.context.state, self.context.world
    self.previousMoney = tonumber(state.money) or 0
    self.customerState = world and world.customer and world.customer.state or nil
    self.vendorState = world and world.vendor and world.vendor.state or nil
    local call = currentCall(state)
    self.callId = call and tostring(call.id) or nil
    self.emailState = emailStates(state)
    self.cashDelta, self.cashTimer = 0, 0
    self.notices = {}
    self.initialized = true
end

function Feedback:enqueue(kind, title, detail)
    if #self.notices >= NOTICE_LIMIT then table.remove(self.notices, 1) end
    self.notices[#self.notices + 1] = {
        kind = kind,
        title = title,
        detail = tostring(detail or ""),
        remaining = NOTICE_SECONDS,
    }
end

local function updateEmails(self, state)
    local newest, added = nil, 0
    for _, email in ipairs(state.clientEmails and state.clientEmails.inbox or {}) do
        local id = email.id ~= nil and tostring(email.id) or nil
        if id then
            local previous = self.emailState[id]
            local receivedAtHours = tonumber(email.receivedAtHours)
            if not previous or (email.unread == true
                and (receivedAtHours ~= previous.receivedAtHours
                    or email.subject ~= previous.subject))
            then
                newest, added = email, added + 1
            end
            self.emailState[id] = {
                receivedAtHours = receivedAtHours,
                subject = email.subject,
                unread = email.unread == true,
            }
        end
    end
    if added == 1 then
        local title = "NEW EMAIL"
        if type(newest.job) == "table" or newest.estimateRequest then
            title = "NEW JOB REQUEST"
        elseif newest.noticeKind == "client_estimate_accepted" then
            title = "JOB AWARDED"
        end
        self:enqueue("email", title, newest.subject or "A new message arrived.")
    elseif added > 1 then
        self:enqueue("email", "NEW EMAILS", string.format("%d new messages. Latest: %s",
            added, tostring(newest and newest.subject or "New message")))
    end
end

local function updatePhone(self, state)
    local call = currentCall(state)
    local callId = call and tostring(call.id) or nil
    if call and call.answered ~= true and callId ~= self.callId then
        self:enqueue("phone", "INCOMING CALL", call.caller or "The work phone is ringing.")
        local playSound = self.context.playSound
        if type(playSound) == "function" then
            playSound("ui_confirm", { cooldown = 0.5, volume = 0.38 })
        end
    end
    self.callId = callId
end

local function updateVisitors(self, world)
    local customer = world and world.customer
    local vendor = world and world.vendor
    local customerState = customer and customer.state or nil
    local vendorState = vendor and vendor.state or nil
    if customerState == "entering" and self.customerState ~= "entering" then
        self:enqueue("customer", "CUSTOMER ARRIVING", "A client is walking in to reception.")
    end
    if vendorState == "entering" and self.vendorState ~= "entering" then
        self:enqueue("supplier", "SUPPLIER ARRIVING", "A supplier is walking in to reception.")
    end
    self.customerState, self.vendorState = customerState, vendorState
end

function Feedback:update(dt)
    local state, world = self.context.state, self.context.world
    local screen = state.screen
    if not self.initialized or MENU_SCREENS[screen]
        or (MENU_SCREENS[self.previousScreen] and not MENU_SCREENS[screen])
    then
        self:seed()
        self.previousScreen = screen
        return
    end

    dt = math.max(0, tonumber(dt) or 0)
    self.cashTimer = math.max(0, self.cashTimer - dt)
    if self.notices[1] then
        self.notices[1].remaining = self.notices[1].remaining - dt
        if self.notices[1].remaining <= 0 then table.remove(self.notices, 1) end
    end

    local money = tonumber(state.money) or 0
    local delta = money - self.previousMoney
    if math.abs(delta) >= 0.005 then
        self.cashDelta = delta
        self.cashTimer = CASH_SECONDS
    end
    self.previousMoney = money

    updateEmails(self, state)
    updatePhone(self, state)
    updateVisitors(self, world)
    self.previousScreen = screen
end

function Feedback:cashEffect()
    return self.cashDelta, self.cashTimer, CASH_SECONDS
end

local function fitText(text, width)
    text = tostring(text or "")
    local font = love.graphics.getFont()
    if font:getWidth(text) <= width then return text end
    while #text > 1 and font:getWidth(text .. "…") > width do
        text = text:sub(1, -2)
    end
    return text .. "…"
end

function Feedback:drawToast(bounds, screen)
    local notice = self.notices[1]
    if not notice then return end
    bounds = bounds or { left = 0, right = 960 }
    local width, height = 300, 46
    local x = (bounds.left + bounds.right - width) / 2
    local y = screen == "world" and 124 or 78
    local elapsed = NOTICE_SECONDS - notice.remaining
    local alpha = math.min(1, elapsed / 0.14, notice.remaining / 0.3)
    local accents = {
        email = { 0.38, 0.83, 0.91 },
        phone = { 0.98, 0.75, 0.34 },
        customer = { 0.97, 0.80, 0.42 },
        supplier = { 0.57, 0.82, 0.61 },
    }
    local accent = accents[notice.kind] or { 0.72, 0.82, 0.84 }

    love.graphics.push("all")
    love.graphics.setColor(0.035, 0.055, 0.065, 0.94 * alpha)
    love.graphics.rectangle("fill", x, y, width, height, 6, 6)
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.9 * alpha)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x, y, width, height, 6, 6)
    love.graphics.rectangle("fill", x + 8, y + 8, 3, height - 16, 1, 1)
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.16 * alpha)
    love.graphics.circle("fill", x + 31, y + height / 2, 12)
    love.graphics.setColor(accent[1], accent[2], accent[3], alpha)
    love.graphics.printf(notice.kind == "email" and "@"
        or notice.kind == "phone" and "!"
        or notice.kind == "customer" and "C" or "S", x + 19, y + 15, 24, "center")
    love.graphics.setColor(0.96, 0.97, 0.92, alpha)
    love.graphics.print(fitText(notice.title, 236), x + 51, y + 6)
    love.graphics.setColor(0.72, 0.81, 0.82, alpha)
    love.graphics.print(fitText(notice.detail, 236), x + 51, y + 24)
    love.graphics.pop()
end

return Feedback
