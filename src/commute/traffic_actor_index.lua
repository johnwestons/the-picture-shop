-- Per-simulation spatial index for active road users. Array queries retain
-- actor order; streaming queries avoid building temporary result arrays.
local Index={CELL_SIZE=32,MIN_ACTORS=16}

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end

local function cell(value,size)
    return math.floor(value/size)
end

local function cellKey(x,z)
    return x..':'..z
end

local function removeRecord(buckets,record)
    local key=cellKey(record.cellX,record.cellZ)
    local bucket=buckets[key]
    if not bucket then return end
    for index=#bucket,1,-1 do
        if bucket[index]==record then
            table.remove(bucket,index)
            break
        end
    end
    if #bucket==0 then buckets[key]=nil end
end

local function insertRecord(buckets,record,cellSize)
    record.cellX,record.cellZ=cell(record.actor.x,cellSize),cell(record.actor.z,cellSize)
    local key=cellKey(record.cellX,record.cellZ)
    local bucket=buckets[key]
    if not bucket then bucket={};buckets[key]=bucket end
    bucket[#bucket+1]=record
end

function Index.shouldUse(actorCount)
    return finite(actorCount) and actorCount>=Index.MIN_ACTORS
end

function Index.new(entries,cellSize)
    local size=finite(cellSize) and cellSize>0 and cellSize or Index.CELL_SIZE
    local result=setmetatable({cellSize=size,buckets={},
        records=setmetatable({}, {__mode='k'}),count=0},{__index=Index})
    for order,entry in ipairs(entries or {}) do
        local actor=type(entry)=='table' and (entry.actor or entry)
        if type(actor)=='table' and finite(actor.x) and finite(actor.z)
            and not result.records[actor] then
            local record={actor=actor,entry=entry,order=order}
            result.records[actor]=record
            result.count=result.count+1
            insertRecord(result.buckets,record,size)
        end
    end
    return result
end

function Index:add(entry)
    local actor=type(entry)=='table' and (entry.actor or entry)
    if type(actor)~='table' or not finite(actor.x) or not finite(actor.z) then return false end
    local record=self.records[actor]
    if record then record.entry=entry;return false end
    record={actor=actor,entry=entry,order=self.count+1}
    self.records[actor]=record
    self.count=self.count+1
    insertRecord(self.buckets,record,self.cellSize)
    return true
end

function Index:update(actor,entry)
    local record=self.records[actor]
    if not record then return self:add(entry or actor) end
    if not finite(actor.x) or not finite(actor.z) then return false end
    local nextX,nextZ=cell(actor.x,self.cellSize),cell(actor.z,self.cellSize)
    if record.cellX==nextX and record.cellZ==nextZ then return false end
    removeRecord(self.buckets,record)
    insertRecord(self.buckets,record,self.cellSize)
    return true
end

function Index:contains(actor)
    return self.records[actor]~=nil
end

function Index:forEachBox(minX,minZ,maxX,maxZ,callback)
    if not finite(minX) or not finite(minZ) or not finite(maxX) or not finite(maxZ)
        or type(callback)~='function' then return false end
    local size=self.cellSize
    local firstX,lastX=cell(minX,size),cell(maxX,size)
    local firstZ,lastZ=cell(minZ,size),cell(maxZ,size)
    for ix=firstX,lastX do
        for iz=firstZ,lastZ do
            for _,record in ipairs(self.buckets[cellKey(ix,iz)] or {}) do
                local actor=record.actor
                if actor.x>=minX and actor.x<=maxX and actor.z>=minZ and actor.z<=maxZ
                    and callback(record.entry,record.order,actor)==false then return false end
            end
        end
    end
    return true
end

function Index:forEachOrientedBox(centerX,centerZ,heading,halfLength,halfWidth,callback)
    if not finite(centerX) or not finite(centerZ) or not finite(heading)
        or not finite(halfLength) or not finite(halfWidth) or type(callback)~='function' then
        return false
    end
    halfLength,halfWidth=math.max(0,halfLength),math.max(0,halfWidth)
    local fx,fz=math.cos(heading),math.sin(heading)
    local nx,nz=-fz,fx
    local xExtent=math.abs(fx)*halfLength+math.abs(nx)*halfWidth
    local zExtent=math.abs(fz)*halfLength+math.abs(nz)*halfWidth
    local size,halfCell=self.cellSize,self.cellSize*.5
    local firstX,lastX=cell(centerX-xExtent,size),cell(centerX+xExtent,size)
    local firstZ,lastZ=cell(centerZ-zExtent,size),cell(centerZ+zExtent,size)
    local forwardCellRadius=halfCell*(math.abs(fx)+math.abs(fz))
    local lateralCellRadius=halfCell*(math.abs(nx)+math.abs(nz))
    for ix=firstX,lastX do
        for iz=firstZ,lastZ do
            local cellCenterX=(ix+.5)*size
            local cellCenterZ=(iz+.5)*size
            local dx,dz=cellCenterX-centerX,cellCenterZ-centerZ
            local overlaps=math.abs(dx)<=xExtent+halfCell and math.abs(dz)<=zExtent+halfCell
                and math.abs(dx*fx+dz*fz)<=halfLength+forwardCellRadius
                and math.abs(dx*nx+dz*nz)<=halfWidth+lateralCellRadius
            if overlaps then
                for _,record in ipairs(self.buckets[cellKey(ix,iz)] or {}) do
                    local actor=record.actor
                    local actorX,actorZ=actor.x-centerX,actor.z-centerZ
                    if math.abs(actorX*fx+actorZ*fz)<=halfLength
                        and math.abs(actorX*nx+actorZ*nz)<=halfWidth
                        and callback(record.entry,record.order,actor)==false then return false end
                end
            end
        end
    end
    return true
end

function Index:forEachCircle(x,z,radius,callback)
    if not finite(x) or not finite(z) or not finite(radius) or type(callback)~='function' then
        return false
    end
    radius=math.max(0,radius)
    local radius2=radius*radius
    return self:forEachBox(x-radius,z-radius,x+radius,z+radius,function(entry,order,actor)
        if (actor.x-x)^2+(actor.z-z)^2<=radius2 then
            return callback(entry,order,actor)
        end
    end)
end

local function collect(self,minX,minZ,maxX,maxZ,centerX,centerZ,radius)
    local result={}
    local radius2=radius and radius*radius
    self:forEachBox(minX,minZ,maxX,maxZ,function(entry,order,actor)
        if not radius2 or (actor.x-centerX)^2+(actor.z-centerZ)^2<=radius2 then
            result[#result+1]={entry=entry,order=order}
        end
    end)
    table.sort(result,function(a,b)return a.order<b.order end)
    local entries={}
    for index,item in ipairs(result) do entries[index]=item.entry end
    return entries
end

function Index:queryCircle(x,z,radius)
    if not finite(x) or not finite(z) or not finite(radius) then return {} end
    radius=math.max(0,radius)
    return collect(self,x-radius,z-radius,x+radius,z+radius,x,z,radius)
end

function Index:queryBox(minX,minZ,maxX,maxZ)
    return collect(self,minX,minZ,maxX,maxZ)
end

return Index
