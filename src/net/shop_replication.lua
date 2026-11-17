-- Keep live shop state independent of the size of the document archive.
-- The host owns these records; paging changes only their network presentation.
local Codec=require('src.net.codec')
local R={PAGE_ROWS=32,PAGE_BYTES=24000,PART_BYTES=24000}
R.collections={
    receipts={'receipts','entries'}, completed={'jobs','completed'}, declined={'jobs','declined'},
    emailArchive={'clientEmails','archive'}, promotions={'clientEmails','sentPromotions'},
    calls={'workPhone','history'}, invoices={'bills','ledger'},
}
R.order={'receipts','completed','declined','emailArchive','promotions','calls','invoices'}
R.limits={maxBytes=1024*1024,maxDepth=28,maxEntries=65536,maxStringBytes=128*1024,maxNumberBytes=32}
local function shallow(t)
    local out={};for k,v in pairs(t or {}) do out[k]=v end;return out
end
function R.copy(v)
    if type(v)~='table' then return v end
    local out={};for k,item in pairs(v) do out[k]=R.copy(item) end;return out
end
function R.equal(a,b)
    if a==b then return true end
    if type(a)~='table' or type(b)~='table' then return false end
    for k,v in pairs(a) do if not R.equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function R.project(state)
    local live=shallow(state)
    local history={}
    for name,path in pairs(R.collections) do
        local parent=state[path[1]]
        history[name]=type(parent)=='table' and parent[path[2]] or {}
        if name=='receipts' and #history[name]>require('src.receipt_book').MAX_ENTRIES then
            history[name]=require('src.receipt_book').normalize(parent).entries
        end
        if parent then
            if live[path[1]]==parent then live[path[1]]=shallow(parent) end
            live[path[1]][path[2]]={}
        end
    end
    return live,history
end
-- Persistent copy-on-write patches keep a distinct baseline for each peer.
-- A joining worker can therefore start from a newer state than other workers.
function R.diff(old,new)
    local operations={}
    local function visit(a,b,path)
        if a==b then return end
        for k,v in pairs(b) do
            if v~=a[k] then
                local child=shallow(path);child[#child+1]=k
                if type(v)=='table' and type(a[k])=='table' then visit(a[k],v,child)
                else operations[#operations+1]={path=child,value=v} end
            end
        end
        for k in pairs(a) do if b[k]==nil then
            local child=shallow(path);child[#child+1]=k
            operations[#operations+1]={path=child,remove=true}
        end end
    end
    visit(old,new,{})
    if #operations>0 then return operations end
end
function R.apply(old,operations)
    if type(old)~='table' or type(operations)~='table' then return nil end
    local out=shallow(old)
    local owned={[out]=true}
    local count=0
    for index,op in pairs(operations) do
        count=count+1
        if type(index)~='number' or index%1~=0 or index<1 or index>#operations
            or type(op)~='table' or type(op.path)~='table' or #op.path<1 or #op.path>28
            or op.remove~=nil and op.remove~=true or op.remove==true and op.value~=nil
            or op.remove==nil and op.value==nil then return nil end
        for key in pairs(op) do if key~='path' and key~='value' and key~='remove' then return nil end end
        local target=out
        for i,key in ipairs(op.path) do
            if type(key)~='string' and (type(key)~='number' or key%1~=0 or key<1) then return nil end
            if i==#op.path then
                target[key]=op.remove and nil or R.copy(op.value)
            else
                if type(target[key])~='table' then return nil end
                if not owned[target[key]] then target[key]=shallow(target[key]);owned[target[key]]=true end
                target=target[key]
            end
        end
    end
    if count~=#operations then return nil end
    return out
end
function R.changed(operations)
    local result={}
    for _,op in ipairs(operations) do result[op.path[1]]=true end
    return result
end
function R.newHistorySender()
    return {collection=1,cursor={},sent={},totals={}}
end
-- At most one bounded page is prepared per update. Appends take priority;
-- the rolling scan also discovers edits, removals and reordered old records.
function R.nextHistory(sender,history)
    if sender.pending then return sender.pending end
    for _=1,#R.order do
        local name=R.order[sender.collection]
        sender.collection=sender.collection%#R.order+1
        local rows=history[name] or {}
        local sent=sender.sent[name] or {};sender.sent[name]=sent
        local start=sender.cursor[name] or 1
        if #sent<#rows then start=#sent+1 end
        if start>#rows then start=1 end
        local finish=math.min(#rows,start+R.PAGE_ROWS-1)
        local changed=sender.totals[name]~=#rows
        for i=start,finish do if not R.equal(sent[i],rows[i]) then changed=true;break end end
        sender.cursor[name]=finish>=#rows and 1 or finish+1
        if changed then
            local entries={}
            for i=start,finish do entries[#entries+1]=rows[i] end
            local data,err=Codec.encode(entries,R.limits)
            while (#entries>1) and (not data or #data>R.PAGE_BYTES) do
                table.remove(entries);finish=finish-1
                data,err=Codec.encode(entries,R.limits)
            end
            if not data then return nil,err end
            sender.pending={collection=name,start=start,total=#rows,data=data,offset=1,
                entries=R.copy(entries),finish=finish}
            return sender.pending
        end
    end
end
function R.advanceHistory(sender)
    local page=sender.pending
    page.offset=page.offset+R.PART_BYTES
    if page.offset<=#page.data then return end
    local rows=sender.sent[page.collection]
    for i,row in ipairs(page.entries) do rows[page.start+i-1]=row end
    for i=#rows,page.total+1,-1 do rows[i]=nil end
    sender.totals[page.collection]=page.total
    sender.cursor[page.collection]=page.finish>=page.total and 1 or page.finish+1
    sender.pending=nil
end
return R
