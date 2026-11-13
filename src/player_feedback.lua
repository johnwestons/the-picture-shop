local Feedback = {}
Feedback.__index = Feedback
local Notifications=require('src.notifications')
local Tutorial=require('src.tutorial')
local StoryGuide=require('src.story_restoration_guide')
local function updateTutorial(feedback)
    local state=feedback.context.state
    if require('src.warehouse_condition').openForBusiness(state) then Tutorial.update(feedback)
    else StoryGuide.update(feedback) end
end

local MENU_SCREENS = { title = true, lan = true, direct = true, asset_error = true }
local NOTICE_LIMIT = 3
local NOTICE_SECONDS = 6
local CASH_SECONDS = 1.05
local CASH_FEEDBACK_THRESHOLD = 1.00
local CASH_CHANGE_EPSILON = 0.005

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
        previousPaper = 0,
        previousStatusMessage = nil,
        statusText = nil,
        statusTimer = 0,
        customerState = nil,
        vendorState = nil,
        callId = nil,
        emailState = {},
        cashDelta = 0,
        cashTimer = 0,
        pendingCashDelta = 0,
        notices = {},
    }, Feedback)
end

function Feedback:seed()
    local state, world = self.context.state, self.context.world
    self.previousMoney = tonumber(state.money) or 0
    self.previousPaper = tonumber(state.inventory and state.inventory.paper) or 0
    self.previousStatusMessage = state.message
    self.statusText = type(state.message)=='string' and state.message or nil
    self.statusTimer = self.statusText and 5 or 0
    self.customerState = world and world.customer and world.customer.state or nil
    self.vendorState = world and world.vendor and world.vendor.state or nil
    local call = currentCall(state)
    self.callId = call and tostring(call.id) or nil
    self.emailState = emailStates(state)
    self.cashDelta, self.cashTimer, self.pendingCashDelta = 0, 0, 0
    self.notices = {}
    self.tutorialStep=nil
    self.initialized = true
end

function Feedback:enqueue(kind, title, detail, body, key)
    local saved,added=Notifications.add(self.context.state,kind,title,detail,body,key)
    self.dirty=self.dirty or added
    -- Keep the currently visible instruction readable when several events
    -- arrive together. Every notice still remains in the saved history.
    if #self.notices >= NOTICE_LIMIT then table.remove(self.notices, 2) end
    local duration=(kind=='tutorial' or kind=='calendar') and 14 or NOTICE_SECONDS
    local notice = {
        id=saved.id,
        kind = kind,
        title = title,
        detail = tostring(detail or ""),
        remaining = duration,
        duration = duration,
    }
    if kind=='calendar' then table.insert(self.notices,1,notice)
    else self.notices[#self.notices+1]=notice end
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
        self:enqueue("email", title, newest.subject or "A new message arrived.",
            ('From: %s\n\n%s\n\nOpen EMAIL on the office computer to read the message and respond.'):format(
                tostring(newest.sender or 'Client'),type(newest.body)=='string' and newest.body or newest.subject or 'A new message arrived.'))
    elseif added > 1 then
        self:enqueue("email", "NEW EMAILS", string.format("%d new messages. Latest: %s",
            added, tostring(newest and newest.subject or "New message")),
            'Open EMAIL on the office computer to read your new messages. Select a message to see its details and available replies.')
    end
end

local function updatePhone(self, state)
    local call = currentCall(state)
    local callId = call and tostring(call.id) or nil
    if call and call.answered ~= true and callId ~= self.callId then
        self:enqueue("phone", "INCOMING CALL", call.caller or "The work phone is ringing.",
            ('%s\n\n%s\n\nWalk to the work phone and use it to answer. This notification records the call; check the phone for its current status.'):format(
                tostring(call.caller or 'Incoming caller'),tostring(call.subject or 'The work phone is ringing.')))
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
        self:enqueue("customer", "CUSTOMER ARRIVING", "A client is walking in to reception.",
            'Meet the client at reception and use the interaction prompt. Discuss the request, then look for their written job details in the office computer email.')
    end
    if vendorState == "entering" and self.vendorState ~= "entering" then
        self:enqueue("supplier", "SUPPLIER ARRIVING", "A supplier is walking in to reception.",
            'Meet the supplier at reception and use the interaction prompt to see what they offer. Review the price and delivery information before placing an order.')
    end
    self.customerState, self.vendorState = customerState, vendorState
end

local function updateWarehouseEvents(self,state)
    local paper=tonumber(state.inventory and state.inventory.paper) or 0
    if paper>self.previousPaper then
        local added=paper-self.previousPaper
        self:enqueue('supplier','PAPER RECEIVED',
            ('%d sheets added to shop stock.'):format(added),
            ('The warehouse received %d sheets of paper. Check Inventory on the shop computer for the updated count.'):format(added))
    end
    self.previousPaper=paper
    for _,job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.status=='ready_for_pickup' and job.id then
            local key='shop:ready:'..tostring(job.id)
            if not Notifications.findKey(state,key) then
                local customer=job.outboundDelivery and job.outboundDelivery.transport=='customer'
                self:enqueue('shop',customer and 'CUSTOMER PICKUP READY' or 'JOB READY FOR DELIVERY',
                    tostring(job.company or job.id)..' · '..tostring(job.id),
                    customer and 'The finished pallets are ready for the customer pickup truck.'
                        or 'The finished pallets are ready to load for delivery. Review the job desk or truck manifest.',key)
            end
        end
    end
end

function Feedback:update(dt)
    local state, world = self.context.state, self.context.world
    local screen = state.screen
    if not self.initialized or MENU_SCREENS[screen]
        or (MENU_SCREENS[self.previousScreen] and not MENU_SCREENS[screen])
    then
        self:seed()
        self.previousScreen = screen
        if not MENU_SCREENS[screen] then
            updateTutorial(self)
            require('src.business_notifications').update(self)
            updateWarehouseEvents(self,state)
        end
        local dirty=self.dirty;self.dirty=false;return dirty
    end

    dt = math.max(0, tonumber(dt) or 0)
    self.cashTimer = math.max(0, self.cashTimer - dt)
    self.statusTimer = math.max(0,(self.statusTimer or 0)-dt)
    if state.message~=self.previousStatusMessage then
        self.previousStatusMessage=state.message
        if type(state.message)=='string' and state.message~='' then
            self.statusText=state.message;self.statusTimer=5
        end
    end
    if self.notices[1] and screen~='notifications' and screen~='options' then
        self.notices[1].remaining = self.notices[1].remaining - dt
        if self.notices[1].remaining <= 0 then table.remove(self.notices, 1) end
    end

    local money = tonumber(state.money) or 0
    local delta = money - self.previousMoney
    if math.abs(delta) >= CASH_FEEDBACK_THRESHOLD then
        -- Keep meaningful purchases and payouts immediate. Discard any
        -- sub-dollar drift already accumulated before this distinct event.
        self.cashDelta = delta
        self.cashTimer = CASH_SECONDS
        self.pendingCashDelta = 0
    elseif math.abs(delta) >= CASH_CHANGE_EPSILON then
        self.pendingCashDelta = self.pendingCashDelta + delta
        if math.abs(self.pendingCashDelta) >= CASH_FEEDBACK_THRESHOLD then
            self.cashDelta = self.pendingCashDelta
            self.cashTimer = CASH_SECONDS
            self.pendingCashDelta = 0
        end
    end
    self.previousMoney = money

    updateEmails(self, state)
    updatePhone(self, state)
    updateVisitors(self, world)
    updateWarehouseEvents(self,state)
    if screen~='notifications' and screen~='options' then updateTutorial(self) end
    require('src.business_notifications').update(self)
    self.previousScreen = screen
    local dirty=self.dirty;self.dirty=false;return dirty
end

function Feedback:cashEffect()
    return self.cashDelta, self.cashTimer, CASH_SECONDS
end

local function fitText(text, width)
    return require('src.screens.typography').ellipsize(text,width)
end

function Feedback:toastRect(bounds,screen)
    bounds=bounds or {left=0,right=960}
    if screen=='commute' then
        local hud=require('src.commute.cockpit')
        local x=(bounds.left or 0)+hud.CARD_X+hud.CARD_WIDTH+8
        local baseWidth=require('src.config').baseWidth
        local mapWidth=math.min(370,math.max(300,baseWidth*.30))
        local width=math.min(380,(bounds.right or baseWidth)-mapWidth-30-x)
        if width<200 then x=(bounds.left or 0)+18;width=math.min(380,(bounds.right or 960)-x-18) end
        return {x=x,y=hud.CARD_Y+hud.CARD_HEIGHT+10,width=width,height=80}
    end
    return {x=((bounds.left or 0)+(bounds.right or 960)-380)/2,y=screen=='world' and 140 or 78,width=380,height=80}
end
function Feedback:toastHit(x,y,bounds,screen)
    local n=self.notices[1]
    return n and require('src.screens.ui').contains(self:toastRect(bounds,screen),x,y) and n.id or nil
end
function Feedback:drawToast(bounds, screen)
    local notice = self.notices[1]
    if not notice then return end
    local rect=self:toastRect(bounds,screen)
    local x,y,width,height=rect.x,rect.y,rect.width,rect.height
    local elapsed = (notice.duration or NOTICE_SECONDS) - notice.remaining
    local alpha = math.min(1, elapsed / 0.14, notice.remaining / 0.3)
    local accents = {
        email = { 0.38, 0.83, 0.91 },
        phone = { 0.98, 0.75, 0.34 },
        customer = { 0.97, 0.80, 0.42 },
        supplier = { 0.57, 0.82, 0.61 },
        tutorial = { .55, .92, .63 },
        calendar = { .98, .75, .34 },
        shop = { .55, .88, .68 },
    }
    local accent = accents[notice.kind] or { 0.72, 0.82, 0.84 }

    love.graphics.push("all")
    love.graphics.setFont(require('src.screens.typography').get(14))
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
        or notice.kind=='calendar' and '!' or notice.kind=='tutorial' and '?' or notice.kind == "customer" and "C" or "S", x + 19, y + 29, 24, "center")
    love.graphics.setColor(0.96, 0.97, 0.92, alpha)
    love.graphics.print(fitText(notice.title, width-64), x + 51, y + 9)
    love.graphics.setColor(0.72, 0.81, 0.82, alpha)
    love.graphics.print(fitText(notice.detail, width-64), x + 51, y + 30)
    love.graphics.setColor(.72,.89,.80,alpha)
    love.graphics.print('Tap / click to read more',x+51,y+54)
    love.graphics.pop()
end

return Feedback
