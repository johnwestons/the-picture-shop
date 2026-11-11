-- Human-worker wage agreement on the shared office computer.
local Payroll=require('src.guest_payroll')
local Component={}
local previous={x=116,y=520,width=114,height=32}
local nextPage={x=724,y=520,width=114,height=32}
local function rowRect(index)
    local y=264+(index-1)*84
    return {y=y,minus={x=570,y=y+31,width=36,height=34},plus={x=610,y=y+31,width=36,height=34},
        propose={x=652,y=y+31,width=88,height=34},accept={x=746,y=y+31,width=102,height=34}}
end
local function entries(state)
    local rows={}
    for id,resident in pairs(state.home and state.home.residents or {}) do
        if id~='owner' then rows[#rows+1]={id=id,resident=resident} end
    end
    table.sort(rows,function(a,b)
        local aOn,bOn=a.resident.activePlayerId~=nil,b.resident.activePlayerId~=nil
        if aOn~=bOn then return aOn end
        return tonumber(a.id:match('%d+$'))<tonumber(b.id:match('%d+$'))
    end)
    return rows
end
function Component.install(Runtime)
    local page,drafts=1,{}
    local function localId() return Runtime.dependencies.localPlayerId or 1 end
    local function active(row)
        return row.resident.activePlayerId~=nil and (localId()==1 or localId()==row.resident.activePlayerId)
    end
    function Runtime.ComputerScreen.playerWageControlCenter(name,index)
        local rect=name=='previous' and previous or name=='next' and nextPage or rowRect(index or 1)[name]
        return rect.x+rect.width/2,rect.y+rect.height/2+30
    end
    function Runtime.playerWagesMousepressed(state,x,y)
        local rows=entries(state);local maxPage=math.max(1,math.ceil(#rows/3))
        page=math.min(page,maxPage)
        if Runtime.contains(previous,x,y) then page=math.max(1,page-1);return {action='player_wage_page'} end
        if Runtime.contains(nextPage,x,y) then page=math.min(maxPage,page+1);return {action='player_wage_page'} end
        for visible=1,3 do
            local row=rows[(page-1)*3+visible]
            if row then
                local resident=row.resident;local rect=rowRect(visible)
                local draft=drafts[row.id] or resident.wageCents or Payroll.DEFAULT_WAGE_CENTS
                if Runtime.contains(rect.minus,x,y) then
                    drafts[row.id]=math.max(Payroll.MIN_WAGE_CENTS,draft-100)
                    return {action='player_wage_draft'}
                elseif Runtime.contains(rect.plus,x,y) then
                    drafts[row.id]=math.min(Payroll.MAX_WAGE_CENTS,draft+100)
                    return {action='player_wage_draft'}
                end
                local intent
                if Runtime.contains(rect.propose,x,y) then
                    intent={kind='player_wage_propose',residentId=row.id,
                        expectedRevision=resident.wageRevision or 0,wageCents=draft}
                elseif Runtime.contains(rect.accept,x,y) then
                    intent={kind='player_wage_accept',residentId=row.id,
                        expectedRevision=resident.wageRevision or 0}
                end
                if intent then
                    if not active(row) then
                        state.message='Both players must be connected to negotiate this wage.'
                        return {action='blocked'}
                    end
                    local normalized,reason=Runtime.OfficeIntent.normalize(intent)
                    if not normalized then state.message=reason;return {action='blocked'} end
                    local command=Runtime.dependencies.remoteCommand or Runtime.dependencies.warehouseCommand
                    local okay,code,message
                    if command then okay,code,message=command(normalized)
                    else
                        okay,message=Payroll.command(state,normalized,{id=localId(),homeResidentId=row.id},
                            {{id=resident.activePlayerId,homeResidentId=row.id}})
                    end
                    state.message=message or code or (okay and 'Wage request sent to the host.' or 'Wage request failed.')
                    return {action=okay and 'player_wage_changed' or 'blocked'}
                end
            end
        end
    end
    function Runtime.drawPlayerWages(state,pointerX,pointerY)
        local rows=entries(state);local maxPage=math.max(1,math.ceil(#rows/3))
        page=math.min(page,maxPage)
        Runtime.panel({x=110,y=190,width=738,height=364},{.045,.075,.09,1},{.28,.48,.48,1})
        local function label(value,x,y,width,color)
            love.graphics.setColor(unpack(color or {.85,.92,.87,1}))
            love.graphics.printf(value,x,y,width,'left')
        end
        local function button(rect,title,enabled)
            local hover=pointerX and pointerY and Runtime.contains(rect,pointerX,pointerY)
            Runtime.drawComputerButton(rect,title,enabled and (hover and 'primaryHover' or 'primary') or 'disabled')
        end
        label('PLAYER WAGES',124,210,712,{1,.86,.41,1})
        label('Connected guests earn shop-time wages, even while riding. Host cash pays them automatically.',124,237,712)
        if #rows==0 then label('No player has joined this shop yet. New guests start at $1.00 per hour.',124,320,712) end
        for visible=1,3 do
            local row=rows[(page-1)*3+visible]
            if row then
                local resident=row.resident;local rect=rowRect(visible)
                local draft=drafts[row.id] or resident.wageCents or Payroll.DEFAULT_WAGE_CENTS
                local paid=resident.wagePaidCents or 0
                local earned=resident.wageEarnedCents or 0
                local due=math.max(0,math.floor(earned+1e-6)-paid)
                local online=resident.activePlayerId~=nil
                love.graphics.setColor(.09,.15,.17,1)
                love.graphics.rectangle('fill',116,rect.y,722,82,4,4)
                label((resident.name or row.id)..(online and '  /  CONNECTED' or '  /  OFFLINE'),128,rect.y+7,424,
                    online and {.58,.94,.72,1} or {.65,.72,.72,1})
                label(string.format('Agreed $%.2f/hr   |   Earned $%.2f   |   Paid $%.2f   |   Owed $%.2f',
                    (resident.wageCents or Payroll.DEFAULT_WAGE_CENTS)/100,earned/100,paid/100,due/100),128,rect.y+32,438)
                local proposal=resident.wageProposal
                label(proposal and string.format('Offer $%.2f/hr from %s',proposal.wageCents/100,
                    proposal.fromPlayerId==1 and 'host' or 'guest') or 'No pending offer',128,rect.y+61,438)
                local allowed=active(row)
                button(rect.minus,'-',allowed and draft>Payroll.MIN_WAGE_CENTS)
                button(rect.plus,'+',allowed and draft<Payroll.MAX_WAGE_CENTS)
                label(string.format('$%.2f',draft/100),653,rect.y+7,186,{.96,.85,.51,1})
                button(rect.propose,'OFFER',allowed and draft~=(resident.wageCents or Payroll.DEFAULT_WAGE_CENTS))
                button(rect.accept,'ACCEPT',allowed and proposal~=nil and proposal.fromPlayerId~=localId())
            end
        end
        button(previous,'PREVIOUS',page>1)
        label(string.format('%d / %d',page,maxPage),432,528,100)
        button(nextPage,'NEXT',page<maxPage)
    end
end
return Component
