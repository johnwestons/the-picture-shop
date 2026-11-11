-- Customer ratings and recent review history for the shop computer.
local Component = {}

local function drawPaw(x, y, active)
    love.graphics.setColor(active and { 0.98, 0.79, 0.30, 1 } or { 0.28, 0.37, 0.39, 1 })
    love.graphics.circle("fill", x + 4, y + 7, 2.5)
    love.graphics.circle("fill", x + 8, y + 3.5, 2.5)
    love.graphics.circle("fill", x + 13, y + 3.5, 2.5)
    love.graphics.circle("fill", x + 17, y + 7, 2.5)
    love.graphics.ellipse("fill", x + 10.5, y + 11, 5.5, 4.5)
end

local function drawPaws(x, y, rating)
    for index = 1, 5 do drawPaw(x + (index - 1) * 22, y, index <= rating) end
end

function Component.install(Runtime)
    function Runtime.drawReviews(state, pointerX, pointerY, twelveHourTime)
        local panel = { x = 110, y = 190, width = 738, height = 394 }
        Runtime.panel(panel, { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        love.graphics.setColor(0.96, 0.84, 0.30, 1)
        local originalFont = love.graphics.getFont()
        local typewriter = require('src.screens.computer.fonts').get('typewriter', 14)
        love.graphics.print("CUSTOMER RATINGS & REVIEWS", panel.x + 22, panel.y + 16)

        local reputation = Runtime.Reputation.ensure(state)
        local average = Runtime.Reputation.averageRating(reputation)
        love.graphics.setColor(0.72, 0.80, 0.80, 1)
        if average then
            love.graphics.printf(string.format("%.1f / 5 paws  •  %d customer review%s",
                average, reputation.ratingCount, reputation.ratingCount == 1 and "" or "s"),
                panel.x + 22, panel.y + 48, 430, "left")
            drawPaws(panel.x + 22, panel.y + 72, math.floor(average + 0.5))
        else
            love.graphics.setFont(typewriter)
            love.graphics.printf("Reviews appear after customers pick up completed orders.",
                panel.x + 22, panel.y + 51, 470, "left")
            love.graphics.setFont(originalFont)
        end

        local leadChange = math.floor((Runtime.Reputation.demandMultiplier(state) - 1) * 100 + 0.5)
        local leadLabel = leadChange > 0 and string.format("+%d%%", leadChange)
            or string.format("%d%%", leadChange)
        local demand = { x = panel.x + 492, y = panel.y + 42, width = 236, height = 64 }
        Runtime.panel(demand, { 0.07, 0.12, 0.14, 1 }, { 0.25, 0.43, 0.45, 1 }, 4, 1)
        love.graphics.setColor(0.53, 0.98, 0.84, 1)
        love.graphics.printf("RATING EFFECT " .. leadLabel, demand.x + 8, demand.y + 9,
            demand.width - 16, "center")
        love.graphics.setColor(0.72, 0.80, 0.80, 1)
        love.graphics.printf("on inbound customer leads", demand.x + 8, demand.y + 33,
            demand.width - 16, "center")

        local reviews = reputation.reviews or {}
        if #reviews == 0 then
            love.graphics.setColor(0.58, 0.64, 0.66, 1)
            love.graphics.setFont(typewriter)
            love.graphics.printf("No customer reviews yet. Complete an order and have the customer pick it up.",
                panel.x + 24, panel.y + 222, panel.width - 48, "center")
            love.graphics.setFont(originalFont)
            return
        end

        local visibleCount = math.min(6, #reviews)
        for row = 1, visibleCount do
            local review = reviews[#reviews - row + 1]
            local rect = { x = panel.x + 16, y = panel.y + 124 + (row - 1) * 40,
                width = panel.width - 32, height = 37 }
            Runtime.panel(rect, { 0.075, 0.10, 0.12, 1 }, { 0.18, 0.33, 0.37, 1 }, 3, 1)
            love.graphics.setColor(0.92, 0.94, 0.92, 1)
            local customer = tostring(review.customer or "Customer")
            love.graphics.print(customer, rect.x + 10, rect.y + 4)
            love.graphics.setColor(0.60, 0.72, 0.72, 1)
            local when = Runtime.BusinessCalendar.dateTimeTextAtHours(review.gameHours, twelveHourTime)
            love.graphics.printf(tostring(review.jobId or "JOB") .. " • " .. when,
                rect.x + 250, rect.y + 4, rect.width - 375, "right")
            drawPaws(rect.x + rect.width - 112, rect.y + 8, review.rating or 0)
            love.graphics.setColor(0.78, 0.86, 0.84, 1)
            love.graphics.setFont(typewriter)
            love.graphics.printf(tostring(review.text or "The customer left no written comment."),
                rect.x + 10, rect.y + 21, rect.width - 20, "left")
            love.graphics.setFont(originalFont)
        end
        love.graphics.setColor(0.55, 0.68, 0.68, 1)
        love.graphics.printf("Quality, delivery timing, and driver service affect ratings.",
            panel.x + 16, panel.y + 370, panel.width - 32, "center")
    end
end

return Component
