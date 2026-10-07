-- Warehouse, bills, and credit presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawWarehouse(state,pointerX,pointerY,assets)
        local view=Runtime.ComputerScreen.warehouseView(state)
        Runtime.panel({x=82,y=190,width=770,height=408},{0.04,0.065,0.08,1},{0.43,0.61,0.58,1})
        local backdrop=assets and assets.images and assets.images.critterNetMenu
        if backdrop then
            love.graphics.setColor(1,1,1,0.06)
            love.graphics.draw(backdrop,82,190,0,770/backdrop:getWidth(),408/backdrop:getHeight())
        end
        love.graphics.setColor(0.94,0.83,0.34,1)
        love.graphics.print("CRITTERNET / WAREHOUSE IMPROVEMENTS",100,202)
        love.graphics.setColor(0.72,0.84,0.82,1)
        love.graphics.print("Each expansion: four construction stages, one game day per stage.",100,224)
        local function control(rect,text,enabled)
            local hovered=pointerX and pointerY and Runtime.contains(rect,pointerX,pointerY)
            Runtime.panel(rect,enabled and (hovered and {0.18,0.38,0.37,1} or {0.10,0.25,0.25,1}) or {0.10,0.13,0.14,1},
                enabled and {0.42,0.72,0.64,1} or {0.28,0.35,0.34,1},3,1)
            love.graphics.setColor(enabled and {0.93,0.96,0.88,1} or {0.49,0.55,0.53,1})
            love.graphics.printf(text,rect.x+5,rect.y+13,rect.width-10,"center")
        end
        for bi,bay in ipairs(view.bays) do
            local x=90+(bi-1)*380
            Runtime.panel({x=x,y=244,width=372,height=224},{0.04,0.08,0.10,0.97},{0.27,0.46,0.45,1},3,1)
            love.graphics.setColor(0.91,0.93,0.87,1)
            love.graphics.print((bi==1 and "LEFT" or "RIGHT").." EXPANSION BAY",x+14,256)
            for oi,option in ipairs(bay.options) do
                control(Runtime.warehouseOptionRect(bi,oi),option.name.."  /  "..(option.available and Runtime.money(option.price) or "NOT READY YET"),
                    view.enabled and option.available and bay.status=="locked" and not view.pending)
            end
            local phase=bay.status=="locked" and "Unpurchased / black area"
                or bay.status=="complete" and "Ready: "..(Runtime.Upgrades.catalog(bay.optionId).name)
                or bay.phase=="building" and ("Building / stage "..bay.stage.." of 4")
                or "Ordered / "..tostring(bay.phase or bay.status):gsub("_"," ")
            love.graphics.setColor(0.64,0.82,0.72,1)
            love.graphics.printf(phase,x+12,441,348,"center")
        end
        Runtime.panel({x=90,y=480,width=752,height=64},{0.08,0.13,0.15,0.98},{0.45,0.61,0.55,1},3,1)
        love.graphics.setColor(0.95,0.81,0.35,1)
        love.graphics.print("FORKLIFT / "..Runtime.money(view.forklift.price),104,490)
        love.graphics.setColor(0.74,0.84,0.79,1)
        love.graphics.print("Raise forks for upper shelves and two-high pallet stacks.",104,518)
        control(Runtime.WAREHOUSE_FORKLIFT,view.forkliftOwned and "OWNED" or "REVIEW PURCHASE",
            view.enabled and not view.forkliftOwned and not view.pending)
        love.graphics.setColor(0.96,0.77,0.38,1)
        love.graphics.printf(view.message or "Shelves: 10 spaces. Lower 5 use a jack or forklift; upper 5 require a forklift.",100,555,736,"left")
        love.graphics.setColor(0.69,0.78,0.78,1)
        love.graphics.printf(view.pending and "Waiting for the host to confirm your purchase."
            or not view.enabled and "Purchasing is not enabled in this build."
            or "Review a choice to confirm its cost. The raccoon mechanic calls before construction.",100,578,736,"left")
        local choice=view.confirmation
        if not choice then return end
        local product=Runtime.Upgrades.catalog(choice.optionId or "forklift")
        love.graphics.setColor(0,0,0,0.88);love.graphics.rectangle("fill",82,190,770,408)
        Runtime.panel({x=178,y=242,width=584,height=324},{0.045,0.09,0.11,1},{0.61,0.76,0.61,1},5,2)
        love.graphics.setColor(0.97,0.84,0.35,1)
        love.graphics.printf("CONFIRM "..product.name:upper(),204,265,532,"center")
        love.graphics.setColor(0.92,0.96,0.91,1)
        love.graphics.printf("Host catalog price: "..Runtime.money(product.price),204,300,532,"center")
        love.graphics.setColor(0.72,0.85,0.82,1)
        love.graphics.printf(choice.kind=="buy_forklift"
            and "One warehouse forklift. Operate it to lift, lower and transfer actual pallets."
            or ((choice.bayId=="front_left" and "Left" or "Right").." expansion bay. Construction takes 4 game days after the mechanic arrives; one full day for each stage."),
            208,336,524,"left")
        if choice.optionId=="storage" then
            love.graphics.setColor(0.97,0.74,0.33,1)
            love.graphics.printf("2 rows x 5 columns. Only the lower five slots work with a pallet jack. You must operate a forklift to use the upper five.",208,388,524,"left")
        end
        if choice.warningRequired then
            control(Runtime.WAREHOUSE_ACK,(choice.confirmUpperRows and "[X]" or "[ ]").." I understand: the upper 5 shelves need a forklift.",not view.pending)
        end
        if view.message then
            love.graphics.setColor(0.96,0.72,0.41,1)
            love.graphics.printf(view.message,208,486,524,"center")
        end
        control(Runtime.WAREHOUSE_CANCEL,"CANCEL",not view.pending)
        control(Runtime.WAREHOUSE_CONFIRM,"CONFIRM "..Runtime.money(product.price),not view.pending and (state.money or 0)>=product.price
            and (not choice.warningRequired or choice.confirmUpperRows))
    end

    function Runtime.drawBills(state, pointerX, pointerY)
        local charges, monthlyTotal = Runtime.BusinessCalendar.monthlyCharges()
        local balance,_,wages = Runtime.BusinessCalendar.amountDue(state)
        local accrued=state.employment and Runtime.Payroll.total(state,Runtime.BusinessCalendar.absoluteHours(state),true)/100 or 0
        local weekly=0
        for _,w in ipairs(state.employment and state.employment.staff or {}) do
            if w.status=="employed" and not w.terminationRequested then weekly=weekly+require("src.employment_contracts").weeklyEstimate(w.contract) end
        end
        local claimTotal = 0
        for _, invoice in ipairs(state.bills and state.bills.ledger or {}) do
            if invoice.status == "unpaid" and invoice.kind == "spoil_claim" then
                claimTotal = claimTotal + (invoice.total or 0)
            end
        end
        Runtime.panel({ x = 82, y = 190, width = 770, height = 408 },
            { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.print("OPERATING BILLS, CLAIMS & PAYROLL", 108, 214)
        love.graphics.setColor(0.76, 0.83, 0.84)
        love.graphics.print(Runtime.BusinessCalendar.dateText(state), 108, 242)
        love.graphics.print("Monthly shop invoices. Wages: agreed 1-4 week cycle, Monday 09:00.", 108, 266)

        love.graphics.setColor(0.16, 0.22, 0.24)
        love.graphics.rectangle("fill", 108, 302, 470, 28)
        love.graphics.setColor(0.86, 0.89, 0.88)
        love.graphics.print("EXPENSE", 122, 310)
        love.graphics.print("FLAT MONTHLY RATE", 408, 310)
        for index, charge in ipairs(charges) do
            local y = 330 + (index - 1) * 34
            love.graphics.setColor(index % 2 == 0 and 0.085 or 0.105, 0.12, 0.14, 1)
            love.graphics.rectangle("fill", 108, y, 470, 32)
            love.graphics.setColor(0.78, 0.84, 0.84)
            love.graphics.print(charge.label, 122, y + 9)
            love.graphics.setColor(0.95, 0.84, 0.30)
            love.graphics.printf(Runtime.money(charge.amount), 402, y + 9, 150, "right")
        end
        love.graphics.setColor(0.72, 0.79, 0.80)
        love.graphics.print("Normal monthly total", 122, 478)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(Runtime.money(monthlyTotal), 402, 478, 150, "right")
        love.graphics.setColor(claimTotal > 0 and 0.92 or 0.72, claimTotal > 0 and 0.48 or 0.79, 0.44)
        love.graphics.print("Customer stock replacement claims", 122, 510)
        love.graphics.printf(Runtime.money(claimTotal), 402, 510, 150, "right")
        love.graphics.setColor(.78,.84,.84,1)
        love.graphics.print("Employee wages currently due",122,534)
        love.graphics.printf(Runtime.money(wages),402,534,150,"right")
        love.graphics.print("Wages earned, not yet due",122,556)
        love.graphics.printf(Runtime.money(math.max(0,accrued-wages)),402,556,150,"right")
        love.graphics.print("Estimated staff pay / week",122,578)
        love.graphics.printf(Runtime.money(weekly),402,578,150,"right")

        Runtime.panel({ x = 604, y = 302, width = 204, height = 188 },
            { 0.08, 0.10, 0.11, 1 }, { 0.31, 0.48, 0.49, 1 })
        love.graphics.setColor(0.72, 0.79, 0.80)
        love.graphics.printf("TOTAL CURRENTLY DUE", 620, 330, 172, "center")
        love.graphics.setColor(balance > 0 and 0.96 or 0.54, balance > 0 and 0.48 or 0.84, balance > 0 and 0.30 or 0.65)
        love.graphics.printf(Runtime.money(balance), 620, 370, 172, "center")
        love.graphics.setColor(0.58, 0.66, 0.67)
        love.graphics.printf(balance > 0 and "Includes due wages. Unpaid balances carry forward." or "All currently due bills and wages are paid.",
            620, 410, 172, "center")

        local ownerOnly=Runtime.dependencies.remoteCommand~=nil and wages>0
        local payable = not ownerOnly and balance > 0
            and math.floor((state.money or 0)*100+1e-7)>=math.floor(balance*100+.5+1e-7)
        local hovered = payable and pointerX and Runtime.contains(Runtime.PAY_BILLS, pointerX, pointerY)
        local payLabel = ownerOnly and "OWNER PAYS WAGES"
            or balance <= 0 and "NO BALANCE DUE"
            or payable and "PAY BILLS & WAGES" or "INSUFFICIENT CASH"
        Runtime.drawComputerButton(Runtime.PAY_BILLS, payLabel,
            payable and (hovered and "primaryHover" or "primary") or "disabled")
    end

    function Runtime.drawCredit(state, pointerX, pointerY)
        local profile = Runtime.Credit.profile(state)
        local quotes = Runtime.Credit.machineQuotes(state, Runtime.ComputerScreen.creditChannel)
        local loans = Runtime.Credit.loanRows(state)
        Runtime.panel({ x = 82, y = 190, width = 770, height = 408 },
            { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.print("CRITTER CREDIT PROFILE", 98, 202)

        Runtime.panel({ x = 98, y = 230, width = 350, height = 50 },
            { 0.08, 0.11, 0.13, 1 }, { 0.30, 0.48, 0.49, 1 })
        love.graphics.setColor(0.74, 0.83, 0.83)
        love.graphics.print("CREDIT SCORE", 112, 239)
        love.graphics.setColor(profile.score < 580 and { 0.95, 0.55, 0.40, 1 }
            or profile.score < 680 and { 0.96, 0.79, 0.38, 1 }
            or { 0.47, 0.86, 0.63, 1 })
        love.graphics.print(string.format("%d  /  %s", profile.score, profile.tier:upper()), 228, 236)
        love.graphics.setColor(0.65, 0.74, 0.75)
        love.graphics.print(string.format("Offers: %.2f%% APR  •  %d%% down  •  %d months",
            profile.apr, profile.downPercent, profile.termMonths), 112, 258)

        Runtime.panel({ x = 462, y = 230, width = 366, height = 50 },
            { 0.08, 0.11, 0.13, 1 }, { 0.30, 0.48, 0.49, 1 })
        love.graphics.setColor(0.74, 0.83, 0.83)
        love.graphics.print("OPEN MACHINE CREDIT", 476, 239)
        love.graphics.setColor(0.95, 0.84, 0.30)
        love.graphics.printf(Runtime.money(profile.totalBalance), 680, 237, 132, "right")
        love.graphics.setColor(0.65, 0.74, 0.75)
        love.graphics.print(string.format("%d of %d accounts  •  scheduled %s / month",
            profile.openLoans, Runtime.Credit.MAX_OPEN_LOANS, Runtime.money(profile.monthlyDue)), 476, 258)

        love.graphics.setColor(0.68, 0.83, 0.84)
        love.graphics.print("MACHINE FINANCING", 102, 283)
        for _, option in ipairs({
            { id = "online", rect = Runtime.CREDIT_CHANNEL_ONLINE, label = "ONLINE" },
            { id = "dealer", rect = Runtime.CREDIT_CHANNEL_DEALER, label = "DEALER" },
        }) do
            local selected = Runtime.ComputerScreen.creditChannel == option.id
            local hovered = pointerX and Runtime.contains(option.rect, pointerX, pointerY)
            Runtime.drawComputerButton(option.rect, option.label,
                selected and (hovered and "primaryHover" or "primary")
                    or hovered and "hover" or "secondary")
        end
        love.graphics.setColor(0.80, 0.89, 0.87, 1)
        love.graphics.print("YOUR MACHINE LOANS", 466, 283)
        for index, quote in ipairs(quotes) do
            local rect = Runtime.creditMachineRect(index)
            local action = Runtime.creditMachineActionRect(index)
            Runtime.panel(rect, { 0.065, 0.085, 0.10, 1 }, { 0.22, 0.37, 0.40, 1 })
            love.graphics.setColor(0.91, 0.94, 0.92)
            love.graphics.printf(quote.name, rect.x + 10, rect.y + 8, 238, "left")
            local red, green, blue = Runtime.conditionColor(quote.condition)
            love.graphics.setColor(red, green, blue)
            love.graphics.print(string.format("%s used  •  %.0f%% condition  •  %s",
                quote.channel == "dealer" and "Dealer" or "Online", quote.condition, Runtime.money(quote.price)),
                rect.x + 10, rect.y + 27)
            love.graphics.setColor(0.72, 0.81, 0.81)
            love.graphics.printf(string.format("Down %s  •  loan %s",
                Runtime.money(quote.downPayment), Runtime.money(quote.principal)),
                rect.x + 10, rect.y + 46, 242, "left")
            love.graphics.printf(string.format("%d mo  •  %.2f%% APR",
                quote.termMonths, quote.apr), rect.x + 10, rect.y + 60, 242, "left")
            local hovered = quote.eligible and pointerX and Runtime.contains(action, pointerX, pointerY)
            Runtime.drawComputerButton(action,
                quote.eligible and ("REVIEW\n" .. Runtime.money(quote.monthlyPayment) .. "/mo")
                    or "SAVE TO\nAPPLY",
                quote.eligible and (hovered and "primaryHover" or "primary") or "disabled")
        end

        local visibleLoans = 0
        for _, loan in ipairs(loans) do
            if loan.status == "active" or loan.status == "defaulted" then
                visibleLoans = visibleLoans + 1
                if visibleLoans > 3 then break end
                local rect = Runtime.creditLoanRect(visibleLoans)
                local action = Runtime.creditLoanActionRect(visibleLoans)
                Runtime.panel(rect, { 0.065, 0.085, 0.10, 1 }, { 0.22, 0.37, 0.40, 1 })
                love.graphics.setColor(0.91, 0.94, 0.92)
                love.graphics.printf(loan.id .. "  " .. loan.machineName, rect.x + 10, rect.y + 8, 245, "left")
                love.graphics.setColor(0.68, 0.77, 0.77)
                love.graphics.printf(string.format("Balance %s  •  %.2f%% APR  •  %d month term",
                    Runtime.money(loan.balance), loan.aprBasisPoints / 100, loan.termMonths), rect.x + 10, rect.y + 28, 340, "left")
                local dueLabel = loan.installmentsDue > 0
                    and ("DUE " .. Runtime.money(loan.amountDue + loan.feesDue))
                    or ("NEXT " .. Runtime.money(loan.monthlyPayment) .. " payment")
                local ready = loan.installmentsDue > 0 and (state.money or 0) >= loan.amountDue + loan.feesDue
                local hovered = ready and pointerX and Runtime.contains(action, pointerX, pointerY)
                Runtime.drawComputerButton(action,
                    ready and ("PAY " .. Runtime.money(loan.amountDue + loan.feesDue))
                        or loan.installmentsDue > 0 and "NEED CASH" or "NOT DUE",
                    ready and (hovered and "primaryHover" or "primary") or "disabled")
                love.graphics.setColor(0.68, 0.77, 0.77)
                love.graphics.print(dueLabel, rect.x + 10, rect.y + 53)
            end
        end
        if visibleLoans == 0 then
            love.graphics.setColor(0.58, 0.66, 0.67)
            love.graphics.printf("No open machine loans.", 478, 370, 330, "center")
        end

        local latest = profile.history[#profile.history]
        love.graphics.setColor(0.61, 0.70, 0.71)
        love.graphics.printf(latest and ("LATEST CREDIT UPDATE: " .. latest.reason .. "  (" ..
            (latest.delta >= 0 and "+" or "") .. latest.delta .. ", score " .. latest.score .. ")")
            or "Pay monthly shop bills and loan installments on time to build credit. Late accounts are reported after 30 days.",
            100, 566, 730, "left")

        local choice = Runtime.ComputerScreen.creditConfirmation
        if choice then
            local quote = Runtime.Credit.machineQuotes(state, choice.channel)[choice.offerIndex]
            if quote then
                love.graphics.setColor(0.01, 0.02, 0.03, 0.82)
                love.graphics.rectangle("fill", 82, 190, 770, 408)
                Runtime.panel(Runtime.CREDIT_CONFIRM_PANEL, { 0.07, 0.09, 0.11, 1 }, { 0.48, 0.68, 0.63, 1 })
                love.graphics.setColor(0.95, 0.84, 0.30)
                love.graphics.print("REVIEW MACHINE FINANCING", 176, 321)
                love.graphics.setColor(0.89, 0.93, 0.91)
                love.graphics.print(string.format("%s  •  %s used listing at %s", quote.name,
                    choice.channel == "dealer" and "dealer" or "online", Runtime.money(quote.price)), 176, 350)
                love.graphics.setColor(0.72, 0.82, 0.81)
                love.graphics.print("Down payment due today: " .. Runtime.money(quote.downPayment), 176, 377)
                love.graphics.print(string.format("Amount financed: %s  •  fixed APR: %.2f%%  •  term: %d months",
                    Runtime.money(quote.principal), quote.apr, quote.termMonths), 176, 401)
                love.graphics.print("Monthly payment: " .. Runtime.money(quote.monthlyPayment) ..
                    "  •  estimated total interest: " .. Runtime.money(math.max(0,
                        quote.monthlyPayment * quote.termMonths - quote.principal)), 176, 425)
                love.graphics.setColor(0.62, 0.72, 0.72)
                love.graphics.print("Late fees may apply after 15 days; late payments affect credit after 30 days.", 176, 447)
                local signHover = pointerX and Runtime.contains(Runtime.CREDIT_SIGN, pointerX, pointerY)
                local cancelHover = pointerX and Runtime.contains(Runtime.CREDIT_CANCEL, pointerX, pointerY)
                Runtime.drawComputerButton(Runtime.CREDIT_SIGN, "SIGN & ORDER",
                    signHover and "primaryHover" or "primary")
                Runtime.drawComputerButton(Runtime.CREDIT_CANCEL, "CANCEL",
                    cancelHover and "dangerHover" or "danger")
            end
        end
    end
end

return Component
