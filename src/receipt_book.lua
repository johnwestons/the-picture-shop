-- Host-owned business documents. Copy facts at settlement so a later change to
-- a job, catalog price, delivery manifest or signature screen cannot alter them.
local Book={}
local kinds={delivery=true,job=true,purchase=true,bill=true,payout=true}
local statuses={paid=true,unpaid=true,received=true}
local function copy(v)
    if type(v)~='table' then return v end
    local r={};for k,item in pairs(v) do r[k]=copy(item) end;return r
end
local function number(n)return type(n)=='number' and n==n and n>=0 and n<=1e12 end
local function text(v,limit)return type(v)=='string' and #v<=limit end
local function clipped(value,limit)
    value=tostring(value or '')
    while value:byte(limit+1) and value:byte(limit+1)>=128 and value:byte(limit+1)<=191 do limit=limit-1 end
    return value:sub(1,limit)
end
function Book.new()return {version=1,nextId=1,entries={}}end
function Book.valid(book)
    if book==nil then return true end -- Pre-archive saves migrate without fabricated signatures.
    if type(book)~='table' or book.version~=1 or not number(book.nextId) or book.nextId%1~=0
        or book.nextId<1 or type(book.entries)~='table' then return false end
    local ids,sources,count={},{},0
    for key in pairs(book) do if key~='version' and key~='nextId' and key~='entries' then return false end end
    local fields={id=true,source=true,kind=true,title=true,party=true,account=true,status=true,amountCents=true,
        atHours=true,paidAtHours=true,details=true,signature=true,signedBy=true}
    for i,row in pairs(book.entries) do
        count=count+1
        if type(i)~='number' or i%1~=0 or i<1 or i>#book.entries or type(row)~='table' then return false end
        for key in pairs(row) do if not fields[key] then return false end end
        if not number(row.id) or row.id%1~=0 or row.id<1 or row.id>=book.nextId or ids[row.id]
            or not text(row.source,160) or sources[row.source] or not kinds[row.kind] or not statuses[row.status]
            or not text(row.title,120) or not text(row.party,120) or not text(row.account,60)
            or not text(row.details,2400) or not number(row.amountCents) or row.amountCents%1~=0
            or not number(row.atHours) or row.atHours>24000100
            or row.paidAtHours~=nil and (not number(row.paidAtHours) or row.paidAtHours>24000100)
            or row.signedBy~=nil and not text(row.signedBy,80)
            or row.signature~=nil and not require('src.receipt_signature').valid(row.signature) then return false end
        ids[row.id],sources[row.source]=true,true
    end
    return count==#book.entries
end
function Book.ensure(state)
    if not state.receipts then state.receipts=Book.new() end
    return state.receipts
end
function Book.add(state,data)
    local book=Book.ensure(state)
    local source=data.source or ('event:'..book.nextId)
    for _,row in ipairs(book.entries) do if row.source==source then return row,false end end
    local row={id=book.nextId,source=source,kind=data.kind or 'purchase',title=clipped(data.title or 'Receipt',120),
        party=clipped(data.party or 'Picture Shop',120),account=clipped(data.account or 'Shop',60),
        status=data.status or 'paid',amountCents=math.max(0,math.floor((data.amountCents or 0)+.5)),
        atHours=data.atHours or require('src.business_calendar').absoluteHours(state),
        details=clipped(data.details,2400),signedBy=data.signedBy and clipped(data.signedBy,80),signature=data.signature,
        paidAtHours=data.paidAtHours}
    book.nextId=book.nextId+1;book.entries[#book.entries+1]=row
    return row,true
end
function Book.expense(state,title,cents,party,account,details,source)
    return Book.add(state,{title=title,amountCents=cents,party=party,account=account,details=details,source=source})
end
function Book.invoice(state,invoice)
    local lines={}
    for _,line in ipairs(invoice.charges or {}) do
        lines[#lines+1]=('%s  $%.2f'):format(line.label or line.id or 'Charge',line.amount or 0)
    end
    local row=Book.add(state,{source='invoice:'..invoice.id,kind=invoice.kind=='operating_expense' and 'purchase' or 'bill',
        title=invoice.kind=='operating_expense' and (invoice.charges and invoice.charges[1] and invoice.charges[1].label or 'Company purchase') or 'Invoice '..invoice.id,
        status=invoice.status,amountCents=(invoice.total or 0)*100,atHours=(invoice.issuedOnDay or 0)*24,
        details=table.concat(lines,'\n')..(invoice.reference and ('\nReference: '..invoice.reference) or '')})
    if invoice.status=='paid' then row.status='paid';row.paidAtHours=(invoice.paidOnDay or 0)*24 end
    return row
end
function Book.job(state,job)
    local quote=job.quote or {}
    local production=quote.playerPrice or quote.totalPrice or 0
    local delivery=math.max(0,(quote.totalPrice or production)-production)
    local quantity=0
    for _,p in ipairs(job.pallets or {}) do
        if p.status~='spoiled_discarded' then
            quantity=quantity+(p.press and p.press.goodSheets or p.finishedSheets or p.sheetCount or p.remainingSheets or 0)
        end
    end
    local function dimensions(size)
        return size and ('%g x %g in'):format(size.width,size.height) or 'As ordered'
    end
    local stock=job.stockSpec and job.stockSpec.description or job.details and job.details.stockDescription
        or (type(job.paper)=='table' and (job.paper.name or job.paper.description) or job.paper) or 'Customer stock'
    return Book.add(state,{source='job:'..job.id,kind='job',title='Job payment '..job.id,party=job.company,
        amountCents=(job.paymentAmount or quote.totalPrice or 0)*100,atHours=job.completedAtHours,
        details=('%s\nJob: %s\nPaper: %s\nSheets: %s to %s\nPackaging: %s\nProduction: $%.2f\nDelivery: $%.2f\nFinished sheets: %d\nPayment received for completed work.')
            :format(job.title or job.description or (job.press and 'Printing, cutting and packing' or 'Cutting and packing'),
                job.id,stock,dimensions(job.sourceSize),dimensions(job.finishedSize),
                job.packaging or 'As ordered',production,delivery,quantity)})
end
function Book.delivery(state,receipt,signer,ink)
    return Book.add(state,{source='delivery:'..receipt.deliveryId,kind='delivery',title=receipt.document,
        party=receipt.supplier,status='received',amountCents=(receipt.declaredValue or 0)*100,signedBy=signer,signature=ink,
        details=('Delivery: %s\n%s\nQuantity: %s\nPallets: %s\nLocation: %s\n%s: $%.2f\nDelivery acknowledged; this is not an additional payment.')
            :format(receipt.deliveryId,receipt.shipment or '',receipt.quantity or '',receipt.palletCount or 0,
                receipt.location or 'Warehouse',receipt.amountLabel or 'Declared value',receipt.declaredValue or 0)})
end
function Book.normalize(value,state)
    if not Book.valid(value) then return nil end
    if value then return copy(value) end
    local temporary={receipts=Book.new(),calendar=state and state.calendar}
    if state then
        for _,invoice in ipairs(state.bills and state.bills.ledger or {}) do Book.invoice(temporary,invoice) end
        for _,job in ipairs(state.jobs and state.jobs.completed or {}) do Book.job(temporary,job) end
        for _,order in ipairs(state.procurement and state.procurement.orders or {}) do
            Book.add(temporary,{source='order:'..order.id,title='Supply order '..order.id,party=order.company,
                amountCents=(order.price or 0)*100,details=order.productName or 'Shop supplies',atHours=order.orderedAtHours or 0})
        end
        for _,order in ipairs(state.home and state.home.shopping and state.home.shopping.orders or {}) do
            local product=require('src.home_shop_catalog').PRODUCTS[order.productId]
            Book.add(temporary,{source='home-order:'..order.id,title='Home order #'..order.id,
                party='CritterNet Home Delivery',account='Household',amountCents=order.totalCents,
                details=('%d x %s\nDelivery fee: $%.2f'):format(order.quantity,product and product.name or order.productId,order.shippingCents/100),
                atHours=order.orderedAt})
        end
    end
    return temporary.receipts
end
function Book.list(state,kind)
    local result={}
    for _,row in ipairs(state.receipts and state.receipts.entries or {}) do
        if not kind or kind=='all' or row.kind==kind then result[#result+1]=row end
    end
    table.sort(result,function(a,b)return a.atHours>b.atHours or a.atHours==b.atHours and a.id>b.id end)
    return result
end
return Book
