-- Local player history. This is saved with the shop, not applied from peers.
local Notices={LIMIT=60}
local kinds={email=true,phone=true,customer=true,supplier=true,tutorial=true,calendar=true,shop=true}
local function integer(n,low,high)
    return type(n)=='number' and n==math.floor(n) and n>=low and n<=high
end
local function text(s,limit)return type(s)=='string' and #s<=limit end
function Notices.new()return {nextId=1,items={}}end
function Notices.normalize(value)
    if value==nil then return Notices.new() end
    if type(value)~='table' or not integer(value.nextId,1,1000000000)
        or type(value.items)~='table' or #value.items>Notices.LIMIT then return nil end
    local result,seen=Notices.new(),{}
    result.nextId=value.nextId
    for key in pairs(value.items) do if not integer(key,1,#value.items) then return nil end end
    for _,n in ipairs(value.items) do
        if type(n)~='table' or not integer(n.id,1,value.nextId-1) or seen[n.id]
            or not kinds[n.kind] or not text(n.title,120) or not text(n.detail,320)
            or not text(n.body,2400) or type(n.unread)~='boolean'
            or not integer(n.day,0,1000000000)
            or (n.key~=nil and not text(n.key,120)) then return nil end
        seen[n.id]=true
        result.items[#result.items+1]={id=n.id,kind=n.kind,title=n.title,detail=n.detail,
            body=n.body,unread=n.unread,day=n.day,key=n.key}
    end
    return result
end
function Notices.ensure(state)
    if not state.notifications then state.notifications=Notices.new() end
    return state.notifications
end
function Notices.find(state,id)
    for _,n in ipairs(Notices.ensure(state).items) do if n.id==id then return n end end
end
function Notices.findKey(state,key)
    for _,n in ipairs(Notices.ensure(state).items) do if n.key==key then return n end end
end
function Notices.add(state,kind,title,detail,body,key)
    local history=Notices.ensure(state)
    local previous=key and Notices.findKey(state,key)
    if previous then return previous,false end
    local n={id=history.nextId,kind=kind,title=tostring(title or ''):sub(1,120),
        detail=tostring(detail or ''):sub(1,320),body=tostring(body or detail or ''):sub(1,2400),
        unread=true,day=math.max(0,math.floor(state.calendar and state.calendar.totalDays or 0)),key=key}
    history.nextId=history.nextId+1
    history.items[#history.items+1]=n
    if #history.items>Notices.LIMIT then table.remove(history.items,1) end
    return n,true
end
function Notices.unread(state)
    local count=0;for _,n in ipairs(Notices.ensure(state).items) do if n.unread then count=count+1 end end
    return count
end
function Notices.read(state,id)
    local n=Notices.find(state,id)
    if n and n.unread then n.unread=false;return true end
    return false
end
return Notices
