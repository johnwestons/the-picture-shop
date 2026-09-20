-- Shared local/guest controls; only the authenticated command callback mutates stock.
local Rack = require("src.screens.pallet_rack_screen")
local Ui = require("src.screens.ui")
local Controls = {}
Controls.__index = Controls
local rackOpenSerial = 0
local controlsSerial = 0

function Controls.new(context)
    controlsSerial=controlsSerial+1
    return setmetatable({ context=context, stackSerial=0,
        stackPrefix="STACK-"..tostring(os.time()).."-"..controlsSerial }, Controls)
end
function Controls:player()
    return self.context.player()
end
function Controls:ownsLift()
    local lift=self.context.state.forklift
    return lift and lift.operating and lift.operatorPlayerId==self:player().id
end
function Controls:openRack(id)
    local c=self.context
    id=id or c.world.warehouseNearRack(self:player(),c.state)
    if not id then c.state.message="Move to the storage rack loading area."; return false end
    rackOpenSerial=rackOpenSerial+1
    self.rack=Rack.new(id,{
        requestPrefix="RACK-"..tostring(self:player().id).."-"..tostring(os.time()).."-"..rackOpenSerial,
        context=function(state,rackId,row,column) return c.world.warehouseRackContext(self:player(),state,rackId,row,column) end,
        onIntent=function(request)
            request.kind,request.action=request.action,nil
            return c.command(request)
        end,
        onClose=function() c.state.screen="world" end,
    })
    c.state.screen="pallet_rack"
    return true
end
function Controls:resolve(intent,accepted,message)
    if self.rack and intent and intent.requestId then
        self.rack:resolve(intent.requestId,accepted,message)
    end
    if self.stackPending and intent and intent.requestId==self.stackPending.requestId then
        self.stackPending=nil
        if message then self.context.state.message=message end
    end
end
function Controls:reset(message)
    if self.rack and self.rack.pending then
        self.rack:resolve(self.rack.pending.requestId,false,message or "Warehouse control ended.")
    end
    self.stackPending=nil
    self.rack=nil
    if self.context.state.screen=="pallet_rack" then self.context.state.screen="world" end
end
function Controls:buttons()
    local c=self.context
    if c.state.screen~="world" and c.state.screen~="pallet_rack" then return {} end
    local lift=c.state.forklift
    local player=self:player()
    local near=lift and lift.owned and (player.x-lift.x)^2+(player.y-lift.y)^2<=100^2
    local owned=self:ownsLift()
    local rackId=c.world.warehouseNearRack(player,c.state)
    local specs={}
    if c.state.screen=="pallet_rack" then
        if owned then specs={{"g","LOWER",0},{"t","TRAVEL",0.08},{"u","UPPER",1}} end
    elseif owned then
        specs={{"e",lift.carriedPalletId and "DROP" or "PICK UP"},{"g","LOWER",0},
            {"t","TRAVEL",0.08},{"r","RAISE",1},{"v","PARK"},
            {"k",self.stackPending and "WAITING..." or lift.carriedPalletId and "STACK" or "TAKE TOP"}}
        if rackId then specs[#specs+1]={"h","SHELVES"} end
    else
        if near then specs[#specs+1]={"v","DRIVE FORKLIFT"} end
        if rackId then specs[#specs+1]={"h","SHELVES"} end
    end
    local result={}
    for i,spec in ipairs(specs) do
        local isRack=c.state.screen=="pallet_rack"
        result[i]={key=spec[1],label=spec[2],heightTarget=spec[3],
            x=isRack and (290+(i-1)*126) or (704+((i-1)%2)*120),
            y=isRack and 58 or (94+math.floor((i-1)/2)*48),width=114,height=44}
    end
    return result
end
function Controls:activate(key)
    local c=self.context
    if key=="h" then self:openRack(); return true end
    if key=="v" then c.command({kind=self:ownsLift() and "release" or "operate"}); return true end
    local height=({g=0,t=0.08,r=1,u=1})[key]
    if height~=nil then c.command({kind="set_height",height=height}); return true end
    if key=="k" then
        if self.stackPending then c.state.message="Waiting for the host to confirm the stack transfer.";return true end
        local candidate=c.world.warehouseStackCandidate and c.world.warehouseStackCandidate(c.state)
        if not candidate then
            c.state.message="Face a nearby matching skid to stack your load, or face a two-high stack to take its top. Raise forks fully."
            return true
        end
        self.stackSerial=self.stackSerial+1
        local request={kind=candidate.kind,palletId=candidate.palletId,supportPalletId=candidate.supportPalletId,
            vehicle="forklift",expectedRevision=c.state.storage and c.state.storage.revision or 0,
            requestId=self.stackPrefix.."-"..self:player().id.."-"..self.stackSerial}
        self.stackPending=request
        local accepted,message=c.command(request)
        if accepted~=nil then self:resolve(request,accepted,message) end
        return true
    end
    if key=="e" then
        if c.state.forklift.carriedPalletId then c.command({kind="drop"})
        else
            local id=c.world.warehouseCandidate(c.state)
            if id then c.command({kind="pickup",palletId=id})
            else c.state.message="Lower the forks and face a nearby skid to pick it up." end
        end
        return true
    end
end
function Controls:keypressed(key)
    local c=self.context
    for _,button in ipairs(self:buttons()) do if key==button.key then return self:activate(key) end end
    if c.state.screen=="pallet_rack" and self.rack then self.rack:keypressed(c.state,key); return true end
    -- Mounted workers cannot operate a second machine through its old hotkeys.
    if c.state.screen=="world" and self:ownsLift() and
        (key=="e" or key=="f" or key=="l" or key=="m" or key=="q" or key=="space") then return true end
    return false
end
function Controls:mousepressed(x,y,button)
    local c=self.context
    if button~=1 then return c.state.screen=="pallet_rack" end
    for _,item in ipairs(self:buttons()) do if Ui.contains(item,x,y) then return self:activate(item.key) end end
    if c.state.screen=="pallet_rack" and self.rack then self.rack:mousepressed(c.state,x,y,button); return true end
    -- A world tap must not bypass the mounted keyboard restriction and open
    -- another workstation. Vehicle actions remain on the explicit touch bar.
    if c.state.screen=="world" and self:ownsLift() then return true end
    return false
end
function Controls:draw(assets)
    local c=self.context
    if c.state.screen=="pallet_rack" and self.rack then self.rack:draw(c.state,nil,assets) end
    local buttons=self:buttons()
    for _,button in ipairs(buttons) do
        Ui.panel(button,{0.10,0.14,0.16,0.96},{0.8,0.65,0.25,1},4)
        love.graphics.setColor(1,0.9,0.65,1)
        love.graphics.printf(button.key:upper().."  "..button.label,button.x+3,button.y+15,button.width-6,"center")
    end
    if #buttons>0 and c.state.screen=="world" then
        love.graphics.setColor(1,0.86,0.5,1)
        love.graphics.printf(self:ownsLift() and "FORKLIFT  |  Stop before lifting" or "WAREHOUSE",704,76,234,"center")
    end
end
return Controls
