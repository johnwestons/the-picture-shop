-- Bound document archives without deleting stock, debts or unfinished work.
local H={LIMIT=100}
local function trim(rows,limit,eligible,removed)
    if type(rows)~='table' or #rows<=limit then return false end
    local excess=#rows-limit
    local kept={}
    for _,row in ipairs(rows) do
        if excess>0 and (not eligible or eligible(row)) then
            excess=excess-1
            if removed then removed(row) end
        else kept[#kept+1]=row end
    end
    local changed=#kept~=#rows
    for i=#rows,1,-1 do rows[i]=nil end
    for i,row in ipairs(kept) do rows[i]=row end
    return changed
end
H.trim=trim
local function int(n)return type(n)=='number' and n==n and n%1==0 and n>=0 and n<=1e15 end
function H.valid(state)
    if type(state)~='table' or state.jobs~=nil and type(state.jobs)~='table' then return false end
    local retired=state and state.jobs and state.jobs.retired
    if retired==nil then return true end
    if type(retired)~='table' or not int(retired.completed) or not int(retired.paymentCents)
        or type(retired.relationships)~='table' or #retired.relationships>H.LIMIT then return false end
    local seen,count={},0
    for i,row in pairs(retired.relationships) do
        if not int(i) or i<1 or i>#retired.relationships or type(row)~='table'
            or type(row.company)~='string' or #row.company>256 or seen[row.company] or not int(row.count) then return false end
        seen[row.company]=true;count=count+1
    end
    return count==#retired.relationships
end
function H.relationship(state,company)
    for _,row in ipairs(state.jobs and state.jobs.retired and state.jobs.retired.relationships or {}) do
        if row.company==company then return row.count end
    end
    return 0
end
local function retireJob(jobs,job)
    jobs.retired=jobs.retired or {completed=0,paymentCents=0,relationships={}}
    local summary=jobs.retired
    summary.completed=summary.completed+1
    summary.paymentCents=summary.paymentCents+math.max(0,math.floor((job.paymentAmount or 0)*100+.5))
    local rows=summary.relationships
    for _,row in ipairs(rows) do if row.company==job.company then row.count=row.count+1;return end end
    rows[#rows+1]={company=tostring(job.company or ''):sub(1,256),count=1}
    trim(rows,H.LIMIT)
end
local function deliveryJobIds(state)
    local ids={}
    local function manifest(run)
        for _,stop in ipairs(run and run.stops or {}) do
            for _,id in ipairs(stop.jobIds or {}) do ids[id]=true end
        end
    end
    manifest(state.employment and state.employment.companyTruck and state.employment.companyTruck.deliveryRun)
    local trip=state.home and state.home.commute
    manifest(trip and trip.deliveryRun)
    for _,part in pairs(trip and trip.participants or {}) do manifest(part.deliveryRun) end
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        for _,item in ipairs(worker.schedule and worker.schedule.items or {}) do if item.jobId then ids[item.jobId]=true end end
    end
    for _,item in ipairs(state.employment and state.employment.teamSchedule and state.employment.teamSchedule.items or {}) do
        if item.jobId then ids[item.jobId]=true end
    end
    return ids
end
local function returningTruck(delivery)
    local route=delivery and delivery.returnRoute
    return route and route.vehicle and route.vehicle.phase~='offmap'
end
local function completedSafe(job,ids)
    return not ids[job.id] and not (job.customerCase and job.customerCase.status=='open')
        and not returningTruck(job.delivery) and not returningTruck(job.pickup and job.pickup.roadDelivery)
end
function H.canAcceptJob(state)
    local ids=deliveryJobIds(state)
    local reserved=#(state.jobs and state.jobs.active or {})
    for _,job in ipairs(state.jobs and state.jobs.completed or {}) do
        if not completedSafe(job,ids) then reserved=reserved+1 end
    end
    return reserved<H.LIMIT
end
local function orderSafe(order)
    if order.status~='received' then return false end
    for _,pallet in ipairs(order.pallets or {}) do if pallet.location~='none' then return false end end
    return true
end
local function promotionSafe(row)
    return row.responseOutcome~='no_response'
        and not (row.responseOutcome=='thank_you' and row.couponUsedAtHours==nil)
end
function H.reservePromotion(state)
    local rows=state.clientEmails and state.clientEmails.sentPromotions or {}
    trim(rows,H.LIMIT-1,promotionSafe)
    return #rows<H.LIMIT
end
function H.emails(state)
    local emails=state.clientEmails
    if not emails then return end
    local function informational(row)return not row.job end
    trim(emails.inbox,H.LIMIT,informational)
    trim(emails.pending,H.LIMIT,informational)
    trim(emails.archive,H.LIMIT)
    trim(emails.sentPromotions,H.LIMIT,promotionSafe)
end
function H.canRequestEmailJob(state)
    local count=0
    local emails=state.clientEmails or {}
    for _,rows in ipairs({emails.inbox or {},emails.pending or {}}) do
        for _,row in ipairs(rows) do if row.job then count=count+1 end end
    end
    return count<H.LIMIT
end
function H.procurement(state,reserve)
    local procurement=state.procurement
    if not procurement then return true end
    local limit=H.LIMIT-(reserve and 1 or 0)
    local removed={}
    local returning={}
    if #(procurement.orders or {})>limit then
        for _,shipment in ipairs(procurement.shipments or {}) do
            if returningTruck(shipment.delivery) then returning[shipment.id]=true end
        end
    end
    trim(procurement.orders,limit,function(row)return orderSafe(row) and not returning[row.shipmentId] end,
        function(row)removed[row.id]=true end)
    for _,shipment in ipairs(next(removed) and procurement.shipments or {}) do
        if shipment.orderIds then
            local ids={};for _,id in ipairs(shipment.orderIds) do if not removed[id] then ids[#ids+1]=id end end
            shipment.orderIds=ids
        end
    end
    trim(procurement.shipments,limit,function(shipment)
        return #(shipment.orderIds or {})==0 and shipment.status=='received' and not returningTruck(shipment.delivery)
    end)
    return #(procurement.orders or {})<H.LIMIT and #(procurement.shipments or {})<H.LIMIT
end
function H.bills(state)
    local rows=state.bills and state.bills.ledger
    if not rows then return end
    trim(rows,H.LIMIT,function(row)return row.status=='paid' end)
    -- Recurring bills must still accrue when every retained invoice is unpaid.
    -- Roll up old debts of the same kind, retaining amount and earliest due date.
    while #rows>H.LIMIT do
        local found={};local first,second
        for i,row in ipairs(rows) do
            local kind=row.kind or 'operating'
            if found[kind] then first,second=found[kind],i;break end
            found[kind]=i
        end
        if not first then break end
        local a,b=rows[first],rows[second]
        a.total=a.total+b.total
        a.consolidatedCount=(a.consolidatedCount or 1)+(b.consolidatedCount or 1)
        a.charges={{id='earlier_unpaid',label='Earlier unpaid charges ('..a.consolidatedCount..' invoices)',amount=a.total}}
        a.dueOnDay=math.min(a.dueOnDay or a.issuedOnDay or 0,b.dueOnDay or b.issuedOnDay or 0)
        a.reference=nil
        table.remove(rows,second)
    end
end
function H.enforce(state)
    local jobs=state.jobs
    if jobs then
        if #(jobs.completed or {})>H.LIMIT then
            local ids=deliveryJobIds(state)
            trim(jobs.completed,H.LIMIT,function(job)return completedSafe(job,ids) end,function(job)retireJob(jobs,job) end)
        end
        trim(jobs.declined,H.LIMIT)
    end
    H.procurement(state)
    H.bills(state)
    H.emails(state)
    if state.receipts then require('src.receipt_book').ensure(state) end
end
return H
