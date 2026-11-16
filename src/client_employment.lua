-- Credential-bound human employment. The host owns applications and signed
-- terms; an applicant accepts an explicit offer before any wages can accrue.
local Contracts=require('src.employment_contracts')
local Calendar=require('src.business_calendar')
local Employment={}
local statuses={applied=true,offered=true,employed=true,declined=true}
local function int(n,lo,hi)
    return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi
end
local function hour(n) return type(n)=='number' and n==n and n>=0 and n<1e12 end
function Employment.valid(resident)
    local job=resident.job
    if job==nil then return true end
    if type(job)~='table' or not statuses[job.status] or not int(job.revision,1,1e12)
        or type(job.clockedIn)~='boolean' or job.clockedIn and not hour(job.clockedAtHours)
        or not job.clockedIn and job.clockedAtHours~=nil then return false end
    if job.offer~=nil and (type(job.offer)~='table'
        or not Contracts.validTerms(job.offer.terms)
        or not Contracts.hasOpenHours(job.offer.terms)
        or job.offer.revision~=job.revision) then return false end
    if job.contract~=nil and not Contracts.valid(job.contract) then return false end
    if job.status=='offered' and not job.offer or job.status=='employed' and not job.contract
        or job.status~='employed' and job.clockedIn then return false end
    return true
end
local function own(state,player,id)
    local resident=state.home and state.home.residents and state.home.residents[id]
    if not resident or not resident.clientSlot then return nil end
    if player.id~=1 and player.homeResidentId~=id then return nil end
    return resident
end
function Employment.command(state,intent,player)
    local resident=own(state,player,intent.residentId)
    if not resident then return false,'Choose your own client application.' end
    local function accepted(message)
        resident.revision=resident.revision+1
        state.home.revision=state.home.revision+1
        return true,message
    end
    local job=resident.job
    if intent.kind=='player_job_apply' then
        if player.id==1 or player.sceneId~='warehouse' then
            return false,'Visit the Picture Shop office to apply.'
        end
        if job and job.status~='declined' then return false,'Your application is already on file.' end
        resident.job={status='applied',revision=job and job.revision+1 or 1,clockedIn=false}
        return accepted('Application sent. The host can review it in Player Jobs.')
    end
    if not job or not int(intent.expectedRevision,1,1e12)
        or intent.expectedRevision~=job.revision then
        return false,'The application changed. Review it again.'
    end
    if intent.kind=='player_job_decline' then
        if player.id~=1 or (job.status~='applied' and job.status~='offered') then
            return false,'Only the host can decline an open application.'
        end
        job.status='declined';job.offer=nil;job.revision=job.revision+1
        return accepted('Client application declined.')
    end
    if intent.kind=='player_job_offer' then
        if player.id~=1 or job.status=='declined' then return false,'Only the host can offer an open position.' end
        if job.clockedIn then return false,'Wait until the client clocks out before changing terms.' end
        local terms=Contracts.terms(intent.wageCents,intent.days,intent.startHour,intent.endHour,1,'cutter')
        if not Contracts.validTerms(terms) or not Contracts.hasOpenHours(terms) then
            return false,'Choose a 4–12 hour shift with working hours.'
        end
        job.revision=job.revision+1
        job.offer={terms=terms,revision=job.revision}
        resident.wageProposal=nil
        if job.status~='employed' then job.status='offered' end
        return accepted('Job terms offered. The client can accept on the office PC.')
    end
    if intent.kind=='player_job_accept' then
        if player.id==1 or not job.offer then return false,'The client must accept the pending offer.' end
        local offer=job.offer
        local now=Calendar.absoluteHours(state)
        local revision=job.contract and job.contract.revision+1 or 1
        job.contract={role='cutter',wageCents=offer.terms.wageCents,
            days=offer.terms.days,startHour=offer.terms.startHour,
            endHour=offer.terms.endHour,payWeeks=1,revision=revision,
            startDay=math.floor(now/24),signedAtHours=now}
        job.status='employed';job.offer=nil;job.revision=job.revision+1
        resident.wageCents=job.contract.wageCents
        resident.wageProposal=nil
        return accepted('Job accepted. Clock in during your scheduled hours to earn pay.')
    end
    if intent.kind=='player_clock_in' then
        if player.id==1 or job.status~='employed' or job.offer
            or player.sceneId~='warehouse'
            or job.clockedIn then return false,'Clock in at the Picture Shop during your shift.' end
        local now=Calendar.absoluteHours(state)
        if not Contracts.onShift(job.contract,now) then return false,'Your agreed shift is not in progress.' end
        job.clockedIn=true;job.clockedAtHours=now;job.revision=job.revision+1
        return accepted('Clocked in. Work time is now being paid.')
    end
    if intent.kind=='player_clock_out' then
        if player.id==1 or not job.clockedIn then return false,'You are not clocked in.' end
        job.clockedIn=false;job.clockedAtHours=nil;job.revision=job.revision+1
        return accepted('Clocked out.')
    end
    return false,'Unknown client employment action.'
end
function Employment.worked(contract,first,last)
    if not contract or last<=first then return 0 end
    local total=0
    for day=math.max(0,math.floor(first/24)-1),math.floor(last/24) do
        local a,b=Contracts.shiftBounds(contract,day)
        if a and day>=contract.startDay then total=total+math.max(0,math.min(last,b)-math.max(first,a)) end
    end
    return total
end
return Employment
