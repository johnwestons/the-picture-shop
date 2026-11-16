-- Human-worker wage agreement on the shared office computer.
local Payroll=require('src.guest_payroll')
local Component={}
local previous={x=116,y=520,width=114,height=32}
local nextPage={x=724,y=520,width=114,height=32}
local shifts={
    {label='M-F 09-17',days=31,startHour=9,endHour=17},
    {label='M-F 12-20',days=31,startHour=12,endHour=20},
    {label='M-F 06-14',days=31,startHour=6,endHour=14},
    {label='M-F 16-00',days=31,startHour=16,endHour=0},
    {label='M/W/F 09-17',days=21,startHour=9,endHour=17},
    {label='T/Th 09-17',days=10,startHour=9,endHour=17},
}
local function rowRect(index)
    local y=264+(index-1)*84
    return {y=y,minus={x=570,y=y+31,width=36,height=34},plus={x=610,y=y+31,width=36,height=34},
        propose={x=652,y=y+31,width=88,height=34},accept={x=746,y=y+31,width=102,height=34},
        shift={x=470,y=y+54,width=176,height=26}}
end
local function entries(state)
    local rows={}
    for id,resident in pairs(state.home and state.home.residents or {}) do
        if id~='owner' and resident.clientSlot then rows[#rows+1]={id=id,resident=resident} end
    end
    table.sort(rows,function(a,b)
        local aOn,bOn=a.resident.activePlayerId~=nil,b.resident.activePlayerId~=nil
        if aOn~=bOn then return aOn end
        return tonumber(a.id:match('%d+$'))<tonumber(b.id:match('%d+$'))
    end)
    return rows
end
function Component.install(Runtime)
    local page,drafts,shiftDrafts=1,{},{}
    local function localId() return Runtime.dependencies.localPlayerId or 1 end
    local function active(row)
        return row.resident.activePlayerId~=nil and (localId()==1 or localId()==row.resident.activePlayerId)
    end
    local function shiftFor(row)
        local selected=shiftDrafts[row.id]
        if selected then return shifts[selected] end
        local contract=row.resident.job and (row.resident.job.offer and row.resident.job.offer.terms
            or row.resident.job.contract)
        for index,shift in ipairs(shifts) do
            if contract and contract.days==shift.days and contract.startHour==shift.startHour
                and contract.endHour==shift.endHour then return shift end
        end
        return shifts[1]
    end
    local function shiftIndex(row)
        local current=shiftFor(row)
        for index,shift in ipairs(shifts) do if shift==current then return index end end
        return 1
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
                local job=resident.job
                local draft=drafts[row.id] or math.max(1000,resident.wageCents or Payroll.DEFAULT_WAGE_CENTS)
                if Runtime.contains(rect.shift,x,y) and localId()==1 and job then
                    shiftDrafts[row.id]=shiftIndex(row)%#shifts+1
                    return {action='player_job_shift_draft'}
                end
                if Runtime.contains(rect.minus,x,y) then
                    drafts[row.id]=math.max(1000,draft-100)
                    return {action='player_wage_draft'}
                elseif Runtime.contains(rect.plus,x,y) then
                    drafts[row.id]=math.min(Payroll.MAX_WAGE_CENTS,draft+100)
                    return {action='player_wage_draft'}
                end
                local intent
                if Runtime.contains(rect.propose,x,y) then
                    if localId()==1 and job and job.status~='declined' then
                        local shift=shiftFor(row)
                        intent={kind='player_job_offer',residentId=row.id,
                            expectedRevision=job.revision,wageCents=draft,
                            days=shift.days,startHour=shift.startHour,endHour=shift.endHour}
                    elseif job and job.status=='employed' then
                        intent={kind='player_wage_propose',residentId=row.id,
                            expectedRevision=resident.wageRevision or 0,wageCents=draft}
                    end
                elseif Runtime.contains(rect.accept,x,y) then
                    if localId()==1 and job and (job.status=='applied' or job.status=='offered') then
                        intent={kind='player_job_decline',residentId=row.id,expectedRevision=job.revision}
                    elseif localId()~=1 and (not job or job.status=='declined') then
                        intent={kind='player_job_apply',residentId=row.id}
                    elseif localId()~=1 and job and job.offer then
                        intent={kind='player_job_accept',residentId=row.id,expectedRevision=job.revision}
                    elseif resident.wageProposal and resident.wageProposal.fromPlayerId~=localId() then
                        intent={kind='player_wage_accept',residentId=row.id,
                            expectedRevision=resident.wageRevision or 0}
                    elseif localId()~=1 and job and job.status=='employed' then
                        intent={kind=job.clockedIn and 'player_clock_out' or 'player_clock_in',
                            residentId=row.id,expectedRevision=job.revision}
                    end
                end
                if intent then
                    if localId()~=1 and not active(row) then
                        state.message='Only your own client record can be changed.'
                        return {action='blocked'}
                    end
                    local normalized,reason=Runtime.OfficeIntent.normalize(intent)
                    if not normalized then state.message=reason;return {action='blocked'} end
                    local command=Runtime.dependencies.remoteCommand or Runtime.dependencies.warehouseCommand
                    local okay,code,message
                    if command then okay,code,message=command(normalized)
                    else
                        local actor={id=localId(),homeResidentId=row.id,sceneId='warehouse'}
                        if intent.kind:match('^player_job_') or intent.kind:match('^player_clock_') then
                            okay,message=require('src.client_employment').command(state,normalized,actor)
                        else
                            okay,message=Payroll.command(state,normalized,actor,
                                {{id=resident.activePlayerId,homeResidentId=row.id}})
                        end
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
        label('PLAYER JOBS',124,210,712,{1,.86,.41,1})
        label('Clients apply here. The host offers hours and pay; accepted workers clock in on shift.',124,237,712)
        if #rows==0 then label('No client has joined this shop yet.',124,320,712) end
        for visible=1,3 do
            local row=rows[(page-1)*3+visible]
            if row then
                local resident=row.resident;local rect=rowRect(visible)
                local job=resident.job
                local draft=drafts[row.id] or math.max(1000,resident.wageCents or Payroll.DEFAULT_WAGE_CENTS)
                local paid=resident.wagePaidCents or 0
                local earned=resident.wageEarnedCents or 0
                local due=math.max(0,math.floor(earned+1e-6)-paid)
                local online=resident.activePlayerId~=nil
                love.graphics.setColor(.09,.15,.17,1)
                love.graphics.rectangle('fill',116,rect.y,722,82,4,4)
                label((resident.name or row.id)..' / '..(job and job.status:upper() or 'NOT APPLIED')
                    ..(online and '  /  ONLINE' or '  /  OFFLINE'),128,rect.y+7,340,
                    online and {.58,.94,.72,1} or {.65,.72,.72,1})
                label(string.format('Agreed $%.2f/hr   |   Earned $%.2f   |   Paid $%.2f   |   Owed $%.2f',
                    (resident.wageCents or Payroll.DEFAULT_WAGE_CENTS)/100,earned/100,paid/100,due/100),128,rect.y+32,438)
                local proposal=resident.wageProposal
                local terms=job and job.offer and job.offer.terms or job and job.contract
                label(terms and string.format('Shift %s  /  %s',shiftFor(row).label,
                    job.clockedIn and 'CLOCKED IN' or job.offer and 'OFFER PENDING' or 'CLOCKED OUT')
                    or proposal and string.format('Wage offer $%.2f/hr',proposal.wageCents/100)
                    or 'No signed shift',128,rect.y+61,340)
                local host=localId()==1
                local allowed=active(row)
                button(rect.minus,'-',host and job~=nil or allowed and job and job.status=='employed')
                button(rect.plus,'+',host and job~=nil or allowed and job and job.status=='employed')
                label(string.format('$%.2f',draft/100),653,rect.y+7,186,{.96,.85,.51,1})
                button(rect.shift,'SHIFT '..shiftFor(row).label,host and job~=nil)
                button(rect.propose,host and 'OFFER' or 'WAGE',
                    host and job~=nil and job.status~='declined'
                    or allowed and job and job.status=='employed')
                local acceptLabel=host and job and (job.status=='applied' or job.status=='offered') and 'DECLINE'
                    or not host and (not job or job.status=='declined') and 'APPLY'
                    or not host and job and job.offer and 'ACCEPT'
                    or proposal and proposal.fromPlayerId~=localId() and 'ACCEPT'
                    or not host and job and job.status=='employed'
                        and (job.clockedIn and 'CLOCK OUT' or 'CLOCK IN')
                    or 'ACCEPT'
                button(rect.accept,acceptLabel,
                    host and job and (job.status=='applied' or job.status=='offered')
                    or not host and allowed and (not job or job.status=='declined'
                        or job.offer~=nil or job.status=='employed')
                    or host and proposal~=nil and proposal.fromPlayerId~=1)
            end
        end
        button(previous,'PREVIOUS',page>1)
        label(string.format('%d / %d',page,maxPage),432,528,100)
        button(nextPage,'NEXT',page<maxPage)
    end
end
return Component
