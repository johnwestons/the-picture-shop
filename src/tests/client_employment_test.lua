local State=require('src.state')
local Home=require('src.home')
local Residents=require('src.home_residents')
local Employment=require('src.client_employment')
local Payroll=require('src.guest_payroll')
local Calendar=require('src.business_calendar')
local Config=require('src.config')
local Test={}

function Test.run(_,check)
    local state=State.new()
    state.home=assert(Home.new({apartmentId='corner'}))
    state.calendar.elapsed=10/24*Config.businessCalendar.secondsPerDay
    state.money=100
    local host={id=1,name='Host',sceneId='warehouse'}
    local guest={id=2,name='Worker',sceneId='warehouse'}
    local id=assert(Residents.bind(state,guest,string.rep('b',64),{host}))
    local resident=state.home.residents[id]
    local private=state.home.clientHomes[id]
    local initial=private.balanceCents
    local idle=Payroll.advance(state,{guest},10,11)
    check('client_job_no_wages_before_application',not idle and resident.wageEarnedCents==0)
    local applied=Employment.command(state,{kind='player_job_apply',residentId=id},guest)
    check('client_job_applies_at_shop',applied and resident.job.status=='applied')
    local offered=Employment.command(state,{kind='player_job_offer',residentId=id,
        expectedRevision=resident.job.revision,wageCents=2000,days=127,startHour=9,endHour=17},host)
    check('client_job_host_offers_shift',offered and resident.job.status=='offered')
    local accepted=Employment.command(state,{kind='player_job_accept',residentId=id,
        expectedRevision=resident.job.revision},guest)
    check('client_job_accepts_host_terms',accepted and resident.job.status=='employed'
        and resident.job.contract.wageCents==2000)
    local clocked=Employment.command(state,{kind='player_clock_in',residentId=id,
        expectedRevision=resident.job.revision},guest)
    local first=Calendar.absoluteHours(state)
    local earned=Payroll.advance(state,{guest},first,first+1)
    check('client_job_clocked_shift_pays_private_apartment',clocked and earned
        and resident.wagePaidCents==2000 and private.balanceCents==initial+2000
        and state.money==80,
        string.format('clocked=%s earned=%s hours=%s paid=%s balance=%s initial=%s cash=%s',
            tostring(clocked),tostring(earned),tostring(first),tostring(resident.wagePaidCents),
            tostring(private.balanceCents),tostring(initial),tostring(state.money)))
    local out=Employment.command(state,{kind='player_clock_out',residentId=id,
        expectedRevision=resident.job.revision},guest)
    check('client_job_clock_out_stops_wages',out and not resident.job.clockedIn
        and not Payroll.advance(state,{guest},first+1,first+2))
end

return Test
