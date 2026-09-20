local Config = require("src.config")
local JobService = require("src.job_service")
local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")
local JobOfferScreen = { activeJobId = nil }

local PANEL = { x = 100, y = 32, width = 760, height = 610 }
local BUTTONS = {
    back = { x = 714, y = 44, width = 126, height = 40 },
    accept = { x = 536, y = 566, width = 250, height = 48 },
}

local contains, commaNumber, money = Ui.contains, Ui.commaNumber, Ui.money

local function sizeText(size)
    return string.format("%g × %g inches", size.width, size.height)
end

local function line(label, value, x, y)
    love.graphics.setColor(0.28, 0.30, 0.31)
    love.graphics.print(label, x, y)
    love.graphics.setColor(0.08, 0.09, 0.10)
    love.graphics.print(value, x + 122, y)
end

local function button(action, label, pointerX, pointerY)
    local rect = BUTTONS[action]
    local hovered = pointerX and pointerY and contains(rect, pointerX, pointerY)
    love.graphics.setColor(hovered and 0.18 or 0.12, hovered and 0.55 or 0.43, 0.28)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    love.graphics.setColor(0.98, 0.98, 0.96)
    love.graphics.printf(label, rect.x, rect.y + 15, rect.width, "center")
end

local function drawArtworkPreview(assets, job, x, y, size)
    local key = job and job.artwork and job.artwork.key or job and job.artworkKey or "flower"
    love.graphics.setColor(0.78, 0.76, 0.68)
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)
    love.graphics.setColor(0.14, 0.17, 0.18)
    love.graphics.rectangle("line", x, y, size, size, 3, 3)
    love.graphics.setColor(0.28, 0.30, 0.31)
    love.graphics.printf(job and job.press and "CLIENT ART FILE" or "JOB ART", x - 42, y - 20, size + 84, "center")
    local image = assets and assets.getArtwork and assets.getArtwork(key)
    if image then
        local imageWidth, imageHeight = image:getDimensions()
        local scale = math.min((size - 8) / imageWidth, (size - 8) / imageHeight)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, x + (size - imageWidth * scale) / 2,
            y + (size - imageHeight * scale) / 2, 0, scale, scale)
    end
    love.graphics.setColor(0.08, 0.09, 0.10)
    local name = job and job.artwork and (job.artwork.displayName or job.artwork.fileName) or key
    love.graphics.printf(string.upper(name or "artwork"), x - 42, y + size + 6,
        size + 84, "center")
end

function JobOfferScreen.hitTest(x, y)
    if contains(BUTTONS.back, x, y) then return "back" end
    if contains(BUTTONS.accept, x, y) then return "accept" end
    return nil
end

function JobOfferScreen.enter(job)
    JobOfferScreen.activeJobId = job and job.id or nil
end

function JobOfferScreen.wantsTextInput() return false end
function JobOfferScreen.keypressed() return false end
function JobOfferScreen.textinput() return false end

function JobOfferScreen.buttonCenter(action)
    local rect = BUTTONS[action]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function JobOfferScreen.draw(state, pointerX, pointerY, assets)
    local job = state.currentOffer
    if job and JobOfferScreen.activeJobId ~= job.id then JobOfferScreen.enter(job) end
    love.graphics.setColor(0.01, 0.02, 0.03, 0.72)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)

    love.graphics.setColor(0.94, 0.92, 0.84)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 5, 5)
    love.graphics.setColor(0.17, 0.22, 0.25)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 5, 5)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, 66, 5, 5)
    love.graphics.setColor(0.97, 0.84, 0.30)
    love.graphics.printf(job and job.press and "CUSTOMER CUT + PRINT JOB TICKET" or "CUSTOMER CUTTING JOB TICKET",
        PANEL.x, PANEL.y + 14, PANEL.width, "center")
    love.graphics.setColor(0.84, 0.88, 0.88)
    love.graphics.printf("Review the sample job before asking for written specifications", PANEL.x, PANEL.y + 38, PANEL.width, "center")
    BackButton.draw(assets, BUTTONS.back, "BACK", pointerX, pointerY, false)

    if not job then
        love.graphics.setColor(0.58, 0.12, 0.12)
        love.graphics.printf("No valid job paperwork is available.", PANEL.x, 310, PANEL.width, "center")
        return
    end

    local details = job.details or {}
    line("Company", job.company, 136, 116)
    line("Job number", job.id, 136, 140)
    line("Parent sheet", sizeText(job.sourceSize), 136, 174)
    local finishedText = sizeText(job.finishedSize)
    if job.press then
        finishedText = finishedText .. string.format("  •  %d-color Windmill  •  %s",
            job.press.colors or 1, table.concat(job.press.colorSequence or { "Black" }, " then "))
    end
    line("Finished size", finishedText, 136, 198)
    line("Stock", job.stockSpec and job.stockSpec.description
        or details.stockDescription or "Customer-supplied paper", 136, 222)
    -- Keep the artwork in its own narrow column. Long artwork names can wrap
    -- beneath it without covering the job fields.
    drawArtworkPreview(assets, job, 738, 122, 76)
    line("Packaging", job.packaging == "boxed" and "Boxes on pallet, stretch-wrapped" or "Flat on pallet, stretch-wrapped", 136, 246)
    line("Stock arrival", job.remoteDelivery or JobService.deliverySummary(job), 136, 270)

    local tableX, tableY = 136, 294
    love.graphics.setColor(0.78, 0.76, 0.68)
    love.graphics.rectangle("fill", tableX, tableY, 688, 24)
    love.graphics.setColor(0.11, 0.12, 0.13)
    love.graphics.print("PALLET", tableX + 16, tableY + 5)
    if job.press then
        love.graphics.print("ORDERED", tableX + 130, tableY + 5)
        love.graphics.print("SUPPLIED", tableX + 270, tableY + 5)
        love.graphics.print("OVERAGE", tableX + 414, tableY + 5)
        love.graphics.print("LIFTS", tableX + 574, tableY + 5)
    else
        love.graphics.print("SHEETS", tableX + 178, tableY + 5)
        love.graphics.print("500-SHEET LIFTS", tableX + 342, tableY + 5)
        love.graphics.print("PRICE", tableX + 574, tableY + 5)
    end

    for index, pallet in ipairs(job.quote.pallets) do
        local rowY = tableY + 24 + (index - 1) * 24
        love.graphics.setColor(index % 2 == 0 and 0.88 or 0.91, 0.89, 0.82)
        love.graphics.rectangle("fill", tableX, rowY, 688, 24)
        love.graphics.setColor(0.10, 0.11, 0.12)
        love.graphics.print(tostring(pallet.number), tableX + 35, rowY + 5)
        if job.press then
            love.graphics.print(commaNumber(pallet.requestedCopies), tableX + 142, rowY + 5)
            love.graphics.print(commaNumber(pallet.sheetCount), tableX + 282, rowY + 5)
            love.graphics.print(commaNumber(pallet.spoilageAllowance), tableX + 432, rowY + 5)
            love.graphics.print(tostring(pallet.requiredLifts), tableX + 588, rowY + 5)
        else
            love.graphics.print(commaNumber(pallet.sheetCount), tableX + 188, rowY + 5)
            love.graphics.print(tostring(pallet.requiredLifts), tableX + 390, rowY + 5)
            love.graphics.print(money(pallet.price), tableX + 584, rowY + 5)
        end
    end

    love.graphics.setColor(0.12, 0.14, 0.15)
    local totalText = job.press
        and string.format("ORDER: %s good  •  SUPPLIED: %s  •  ALLOWANCE: %s",
            commaNumber(job.quote.orderedCopies), commaNumber(job.quote.suppliedSheets),
            commaNumber(job.quote.spoilageAllowance))
        or string.format("TOTAL: %d pallets  •  %s sheets  •  %d lifts", job.quote.palletCount,
            commaNumber(job.quote.totalSheets), job.quote.totalLifts)
    love.graphics.print(totalText, 136, 450)
    love.graphics.setColor(0.10, 0.39, 0.24)
    love.graphics.printf("PRICE AFTER WRITTEN DETAILS", 540, 450, 284, "right")

    line("Grain/handling", details.grainDirection or "Follow customer labels", 136, 474)
    line("Due", details.dueDate or "Standard turnaround", 136, 498)
    love.graphics.setColor(0.28, 0.30, 0.31)
    love.graphics.print("Notes", 136, 510)
    love.graphics.setColor(0.08, 0.09, 0.10)
    love.graphics.printf(details.notes or "", 258, 510, 260, "left")

    love.graphics.setColor(0.28, 0.30, 0.31)
    love.graphics.printf(string.format("%s client: %s The client will email the complete specifications. Build and send the estimate from the office computer after that message arrives.",
        string.upper(job.clientTemperament or "standard"), job.clientTemperamentNote or ""),
        136, 558, 360, "left")
    button("accept", "REQUEST EMAIL DETAILS", pointerX, pointerY)
    love.graphics.setColor(0.32, 0.34, 0.34)
    love.graphics.printf("No price or award is decided at the counter", PANEL.x, 628, PANEL.width, "center")
end

function JobOfferScreen.fromNetwork(view)
    if not view or not view.jobId then return nil end
    local quote={pallets=view.quoteRows or {},palletCount=#(view.quoteRows or {}),totalSheets=0,totalLifts=0,
        orderedCopies=0,suppliedSheets=0,spoilageAllowance=0}
    for _,row in ipairs(quote.pallets) do
        quote.totalSheets=quote.totalSheets+(row.sheetCount or 0)
        quote.totalLifts=quote.totalLifts+(row.requiredLifts or 0)
        quote.orderedCopies=quote.orderedCopies+(row.requestedCopies or 0)
        quote.suppliedSheets=quote.suppliedSheets+(row.sheetCount or 0)
        quote.spoilageAllowance=quote.spoilageAllowance+(row.spoilageAllowance or 0)
    end
    return {id=view.jobId,company=view.company,sourceSize=view.sourceSize,finishedSize=view.finishedSize,
        stockSpec={description=view.stock},packaging=view.packaging,remoteDelivery=view.delivery,
        artworkKey=view.artworkKey,artwork={key=view.artworkKey,displayName=view.artworkName},
        quote=quote,details={dueDate="Written details to follow",notes="Review the written specifications before estimating."},
        press=view.printJob and {colors=view.colorCount or 1,colorSequence={view.colorSequence or "see written specifications"}} or nil}
end

return JobOfferScreen
