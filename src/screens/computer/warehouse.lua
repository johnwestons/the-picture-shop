-- Warehouse purchases and confirmation actions.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.warehouseEnabled()
        return Runtime.dependencies.warehouseEnabled == true
            or (type(Runtime.dependencies.warehouseEnabled) == "function" and Runtime.dependencies.warehouseEnabled() == true)
    end

    function Runtime.warehouseOptionAvailable(bayId,optionId)
        return Runtime.dependencies.warehouseFirstStorageOnly~=true
            or (bayId=="front_left" and optionId=="storage")
    end

    function Runtime.visibleTabs()
        local result = {}
        for _,tab in ipairs(Runtime.TABS) do
            if tab.id ~= "warehouse" or Runtime.warehouseEnabled() then result[#result+1] = tab end
        end
        return result
    end

    function Runtime.warehouseOptionRect(bayIndex,optionIndex)
        return {x=96+(bayIndex-1)*380,y=280+(optionIndex-1)*51,width=360,height=43}
    end

    Runtime.WAREHOUSE_PAGE_SWITCH={x=690,y=202,width=148,height=28}
    local function productFor(choice)
        if choice.kind=="buy_breakroom_fixture" then return Runtime.BreakroomGames.CATALOG[choice.fixtureId] end
        return Runtime.Upgrades.catalog(choice.optionId or "forklift")
    end

    function Runtime.ComputerScreen.configureWarehouse(options)
        options=options or {}
        Runtime.dependencies.warehouseEnabled=options.enabled==true
        Runtime.dependencies.warehouseCommand=options.command
        Runtime.dependencies.warehouseFirstStorageOnly=options.firstStorageOnly==true
        if options.requestPrefix then Runtime.warehouseRequestPrefix=options.requestPrefix end
        if not Runtime.warehouseEnabled() and Runtime.ComputerScreen.tab=="warehouse" then Runtime.ComputerScreen.tab="active" end
        Runtime.ComputerScreen.warehouseConfirmation,Runtime.ComputerScreen.warehousePending=nil,false
        Runtime.ComputerScreen.warehouseGamesPage=false
    end

    function Runtime.ComputerScreen.configureGameClock(options)
        options=options or {}
        Runtime.dependencies.getGameClockSpeed=options.getSpeed
        Runtime.dependencies.canChangeGameClockSpeed=options.canChange
        Runtime.dependencies.setGameClockSpeed=options.setSpeed
    end

    function Runtime.ComputerScreen.gameClockSpeed()
        if Runtime.dependencies.getGameClockSpeed then
            return Runtime.dependencies.getGameClockSpeed()
        end
        return 1
    end

    function Runtime.ComputerScreen.canChangeGameClockSpeed()
        if Runtime.dependencies.canChangeGameClockSpeed then
            return Runtime.dependencies.canChangeGameClockSpeed()==true
        end
        return Runtime.dependencies.remoteCommand==nil
    end

    function Runtime.ComputerScreen.warehouseEnabled() return Runtime.warehouseEnabled() end

    function Runtime.ComputerScreen.resolveWarehouse(accepted,message)
        Runtime.ComputerScreen.warehousePending=false
        if accepted then Runtime.ComputerScreen.warehouseConfirmation=nil end
        Runtime.ComputerScreen.warehouseMessage=message or (accepted and "Purchase confirmed by the host." or "The purchase was not completed.")
    end

    function Runtime.ComputerScreen.warehouseButtonCenter(bayId,optionId)
        local rect
        if bayId=="forklift" then rect=Runtime.WAREHOUSE_FORKLIFT
        elseif bayId=="confirm" then rect=Runtime.WAREHOUSE_CONFIRM
        elseif bayId=="cancel" then rect=Runtime.WAREHOUSE_CANCEL
        elseif bayId=="acknowledge" then rect=Runtime.WAREHOUSE_ACK
        else
            for bi,bay in ipairs(Runtime.WAREHOUSE_BAYS) do for oi,option in ipairs(Runtime.WAREHOUSE_OPTIONS) do
                if bayId==bay and optionId==option then rect=Runtime.warehouseOptionRect(bi,oi) end
            end end
        end
        if rect then return rect.x+rect.width/2,rect.y+rect.height/2 end
    end

    function Runtime.ComputerScreen.warehouseView(state)
        local warehouse=state.warehouse or Runtime.Upgrades.defaultState()
        local result={enabled=Runtime.warehouseEnabled(),forkliftOwned=warehouse.forkliftOwned==true,
            forklift=Runtime.Upgrades.catalog("forklift"),bays={},confirmation=Runtime.ComputerScreen.warehouseConfirmation,
            pending=Runtime.ComputerScreen.warehousePending,message=Runtime.ComputerScreen.warehouseMessage,
            gamesPage=Runtime.ComputerScreen.warehouseGamesPage}
        for _,bayId in ipairs(Runtime.WAREHOUSE_BAYS) do
            local bay=warehouse.bays and warehouse.bays[bayId] or {status="locked"}
            local project
            for _,candidate in ipairs(warehouse.projects or {}) do if candidate.id==bay.projectId then project=candidate end end
            local options={Runtime.Upgrades.catalog("floor"),Runtime.Upgrades.catalog("storage"),Runtime.Upgrades.catalog("breakroom")}
            for index,option in ipairs(options) do
                option.available=Runtime.warehouseOptionAvailable(bayId,Runtime.WAREHOUSE_OPTIONS[index])
            end
            local owned={}
            for _,fixtureId in ipairs(Runtime.BreakroomGames.ORDER) do
                owned[fixtureId]=Runtime.BreakroomGames.owns(state,bayId,fixtureId)
            end
            result.bays[#result.bays+1]={id=bayId,status=bay.status,optionId=bay.optionId,owned=owned,
                phase=project and project.phase,stage=project and project.stage or 0,options={
                    options[1],options[2],options[3]}}
        end
        return result
    end

    function Runtime.warehouseMousepressed(state,x,y)
        if not Runtime.warehouseEnabled() then return {action="blocked",reason="warehouse_disabled"} end
        if Runtime.ComputerScreen.warehousePending then return {action="blocked",reason="waiting"} end
        local choice=Runtime.ComputerScreen.warehouseConfirmation
        if choice then
            if Runtime.contains(Runtime.WAREHOUSE_CANCEL,x,y) then Runtime.ComputerScreen.warehouseConfirmation=nil;return {action="warehouse_cancelled"} end
            if Runtime.contains(Runtime.WAREHOUSE_ACK,x,y) and choice.warningRequired then
                choice.confirmUpperRows=not choice.confirmUpperRows
                return {action="warehouse_warning_acknowledged"}
            end
            if not Runtime.contains(Runtime.WAREHOUSE_CONFIRM,x,y) then return nil end
            if choice.kind=="buy_upgrade" and not Runtime.warehouseOptionAvailable(choice.bayId,choice.optionId) then
                Runtime.ComputerScreen.warehouseMessage="This expansion is not ready in this build. Choose the left storage bay."
                return {action="blocked",reason="warehouse_not_ready"}
            end
            if choice.warningRequired and choice.confirmUpperRows~=true then
                Runtime.ComputerScreen.warehouseMessage="Acknowledge the forklift requirement before buying these shelves."
                return {action="blocked",reason="forklift_warning_required"}
            end
            local product=productFor(choice)
            if (state.money or 0)<product.price then
                Runtime.ComputerScreen.warehouseMessage="Not enough money for this purchase."
                return {action="blocked",reason="insufficient_funds"}
            end
            local intent={kind=choice.kind,bayId=choice.bayId,optionId=choice.optionId,
                fixtureId=choice.fixtureId,requestId=choice.requestId}
            if choice.kind=="buy_upgrade" then intent.confirmUpperRows=choice.confirmUpperRows==true end
            local normalized,errorMessage=Runtime.OfficeIntent.normalize(intent)
            if not normalized then Runtime.ComputerScreen.warehouseMessage=errorMessage;return {action="blocked"} end
            local command=Runtime.dependencies.remoteCommand or Runtime.dependencies.warehouseCommand
            if type(command)~="function" then
                Runtime.ComputerScreen.warehouseMessage="Warehouse purchasing is not connected to the host."
                return {action="blocked",reason="warehouse_unwired"}
            end
            Runtime.ComputerScreen.warehousePending=true
            local called,accepted,code,message=pcall(command,normalized)
            if not called or accepted==false then
                Runtime.ComputerScreen.resolveWarehouse(false,called and (message or code) or "The purchase could not be sent.")
                return {action="blocked"}
            end
            if not Runtime.dependencies.remoteCommand and accepted==true then
                Runtime.ComputerScreen.resolveWarehouse(true,message)
                return {action="warehouse_purchased",hostSaved=true}
            end
            return {action="remote_pending"}
        end
        if Runtime.contains(Runtime.WAREHOUSE_PAGE_SWITCH,x,y) then
            Runtime.ComputerScreen.warehouseGamesPage=not Runtime.ComputerScreen.warehouseGamesPage
            Runtime.ComputerScreen.warehouseMessage=nil
            return {action="warehouse_page_changed"}
        end
        local view=Runtime.ComputerScreen.warehouseView(state)
        local kind,bayId,optionId,fixtureId
        for bi,bay in ipairs(view.bays) do
            local choices=view.gamesPage and Runtime.BreakroomGames.ORDER or Runtime.WAREHOUSE_OPTIONS
            for oi,option in ipairs(choices) do
                if Runtime.contains(Runtime.warehouseOptionRect(bi,oi),x,y) then
                    if view.gamesPage then
                        if bay.status=="complete" and bay.optionId=="breakroom" and not bay.owned[option] then
                            kind,bayId,fixtureId="buy_breakroom_fixture",bay.id,option
                        end
                    elseif bay.status=="locked" then
                        if not Runtime.warehouseOptionAvailable(bay.id,option) then
                            Runtime.ComputerScreen.warehouseMessage="This expansion is not ready in this build. Choose the left storage bay."
                            return {action="blocked",reason="warehouse_not_ready"}
                        end
                        kind,bayId,optionId="buy_upgrade",bay.id,option
                    end
                end
            end
        end
        if not view.gamesPage and Runtime.contains(Runtime.WAREHOUSE_FORKLIFT,x,y)
            and not view.forkliftOwned then kind="buy_forklift" end
        if not kind then return nil end
        Runtime.ComputerScreen.warehouseRequestNumber=Runtime.ComputerScreen.warehouseRequestNumber+1
        local warehouse=state.warehouse or Runtime.Upgrades.defaultState()
        local receiptCount=#(warehouse.receipts or {})+#(state.breakroomGames and state.breakroomGames.receipts or {})
        Runtime.warehouseRequestPrefix=tostring(Runtime.warehouseRequestPrefix
            or ("WH-"..os.time().."-"..math.random(1,99999999))):gsub("[^%w_.%-]","-"):sub(1,40)
        local identifier=string.format("%s-%d-%d",Runtime.warehouseRequestPrefix,receiptCount,Runtime.ComputerScreen.warehouseRequestNumber)
        Runtime.ComputerScreen.warehouseConfirmation={kind=kind,bayId=bayId,optionId=optionId,
            fixtureId=fixtureId,requestId=identifier,
            warningRequired=optionId=="storage" and Runtime.Upgrades.catalog("storage").upperRowRequiresForklift
                and not view.forkliftOwned,confirmUpperRows=false}
        Runtime.ComputerScreen.warehouseMessage=nil
        return {action="warehouse_confirmation"}
    end
end

return Component
