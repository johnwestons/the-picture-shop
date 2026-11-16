-- Host-owned wages for connected human workers. The credential-bound resident,
-- never the temporary network slot, owns the rate and cumulative paid amount.
local Finance=require('src.household_finances')
local Employment=require('src.client_employment')
local Payroll={DEFAULT_WAGE_CENTS=2000,MIN_WAGE_CENTS=100,MAX_WAGE_CENTS=10000}
local function integer(value,low,high)
    return type(value)=='number' and value==math.floor(value) and value>=low and value<=high
end
local function finite(value,low,high)
    return type(value)=='number' and value==value and value>=low and value<=high
end
function Payroll.ensure(resident)
    -- Repair the earlier $1 placeholder without changing signed or pending terms.
    local job=resident.job
    if resident.wageCents==nil then
        resident.wageCents=job and job.contract and job.contract.wageCents or Payroll.DEFAULT_WAGE_CENTS
    elseif resident.wageCents==100 and (resident.wageRevision or 0)==0
        and not (job and (job.status=='employed' or job.offer)) then
        resident.wageCents=Payroll.DEFAULT_WAGE_CENTS
    end
    if resident.wageEarnedCents==nil then resident.wageEarnedCents=0 end
    if resident.wagePaidCents==nil then resident.wagePaidCents=0 end
    if resident.wageRevision==nil then resident.wageRevision=0 end
    return resident
end
function Payroll.valid(resident)
    if resident.wageCents==nil and resident.wageEarnedCents==nil
        and resident.wagePaidCents==nil and resident.wageRevision==nil
        and resident.wageProposal==nil then return true end -- older saves
    if not integer(resident.wageCents,Payroll.MIN_WAGE_CENTS,Payroll.MAX_WAGE_CENTS)
        or not finite(resident.wageEarnedCents,0,1e12)
        or not integer(resident.wagePaidCents,0,1e12)
        or resident.wagePaidCents>math.floor(resident.wageEarnedCents+1e-6)
        or not integer(resident.wageRevision,0,1e12) then return false end
    local proposal=resident.wageProposal
    return proposal==nil or type(proposal)=='table'
        and integer(proposal.wageCents,Payroll.MIN_WAGE_CENTS,Payroll.MAX_WAGE_CENTS)
        and integer(proposal.fromPlayerId,1,4)
        and proposal.revision==resident.wageRevision
end
function Payroll.totalOwed(state)
    local total=0
    for id,resident in pairs(state.home and state.home.residents or {}) do
        if id~='owner' and resident.wageEarnedCents~=nil then
            total=total+math.max(0,math.floor(resident.wageEarnedCents+1e-6)-(resident.wagePaidCents or 0))
        end
    end
    return total
end
function Payroll.advance(state,players,first,last)
    if not state.home or not state.home.residents then return false end
    local changed=false
    if last>first then
        for _,player in ipairs(players or {}) do
            if player.id and player.id>1 and player.homeResidentId then
                local resident=state.home.residents[player.homeResidentId]
                if resident and resident.activePlayerId==player.id then
                    local job=resident.job
                    local paidShift=job and job.status=='employed' and job.clockedIn
                        and (player.sceneId=='warehouse' or player.sceneId=='front_left'
                            or player.sceneId=='front_right')
                    local worked=paidShift and Employment.worked(job.contract,
                        math.max(first,player.homeJoinedAtHours or first,job.clockedAtHours or first),last) or 0
                    if worked>0 then
                        Payroll.ensure(resident)
                        local earned=math.min(1e12-resident.wageEarnedCents,worked*resident.wageCents)
                        if earned>0 then
                            resident.wageEarnedCents=resident.wageEarnedCents+earned
                            Finance.record(state,'wages',earned)
                            changed=true
                        end
                    end
                    if job and job.clockedIn and (not paidShift
                        or not require('src.employment_contracts').onShift(job.contract,last)) then
                        job.clockedIn=false;job.clockedAtHours=nil;job.revision=job.revision+1
                        changed=true
                    end
                end
            end
        end
    end
    -- Funds can arrive after a guest leaves. Keep their earned obligation in
    -- the host save and settle it when shop cash is available.
    local cash=math.max(0,math.floor((state.money or 0)*100+1e-7))
    for id,resident in pairs(state.home.residents) do
        if id~='owner' and resident.wageEarnedCents~=nil then
            Payroll.ensure(resident)
            local owed=math.max(0,math.floor(resident.wageEarnedCents+1e-6)-resident.wagePaidCents)
            local household=state.home.clientHomes and state.home.clientHomes[id]
            local paid=math.min(owed,cash,household and 1e12-household.balanceCents or 1e12)
            if paid>0 then
                resident.wagePaidCents=resident.wagePaidCents+paid
                state.money=math.max(0,state.money-paid/100)
                if household then
                    household.balanceCents=household.balanceCents+paid
                    household.revision=household.revision+1
                    state.home.revision=state.home.revision+1
                end
                cash=cash-paid;changed=true
            end
        end
    end
    return changed
end
function Payroll.command(state,intent,player,players)
    local resident=state.home and state.home.residents and state.home.residents[intent.residentId]
    if not resident or not resident.credentialHash then return false,'Choose a connected player.' end
    local guestId=resident.activePlayerId
    local present=false
    for _,connected in ipairs(players or {}) do
        if connected.id==guestId and connected.homeResidentId==intent.residentId then present=true end
    end
    if not present or not guestId or (player.id~=1 and player.id~=guestId) then
        return false,'Both the host and that player must be connected.'
    end
    if not resident.job or resident.job.status~='employed' then
        return false,'Agree to a job contract before changing wages.'
    end
    if resident.job.offer then return false,'Resolve the pending job terms first.' end
    Payroll.ensure(resident)
    if intent.expectedRevision~=resident.wageRevision then
        return false,'The wage offer changed. Review it again.'
    end
    if intent.kind=='player_wage_propose' then
        if not integer(intent.wageCents,Payroll.MIN_WAGE_CENTS,Payroll.MAX_WAGE_CENTS) then
            return false,'Choose a wage from $1 to $100 per hour.'
        end
        if resident.job and resident.job.status=='employed' and intent.wageCents<1000 then
            return false,'Signed job wages must be at least $10 per hour.'
        end
        if intent.wageCents==resident.wageCents then return false,'That is already the agreed hourly wage.' end
        resident.wageRevision=resident.wageRevision+1
        resident.wageProposal={wageCents=intent.wageCents,fromPlayerId=player.id,revision=resident.wageRevision}
        return true,string.format('Offered $%.2f/hour. The other player must accept.',intent.wageCents/100)
    end
    if intent.kind=='player_wage_accept' then
        local proposal=resident.wageProposal
        if not proposal or proposal.fromPlayerId==player.id then
            return false,'The other player must make an offer first.'
        end
        resident.wageCents=proposal.wageCents
        if resident.job and resident.job.contract then
            resident.job.contract.wageCents=proposal.wageCents
            resident.job.contract.revision=resident.job.contract.revision+1
        end
        resident.wageRevision=resident.wageRevision+1
        resident.wageProposal=nil
        return true,string.format('Agreed wage is now $%.2f/hour.',resident.wageCents/100)
    end
    return false,'Unknown player wage action.'
end
return Payroll
