-- Separate UI singletons, as on two devices; only the host owns the encounter.
local Devices={}
function Devices.new(runtime,phone)
    local isolated={
        ['src.critter_crisis_inputs']=true,['src.screens.critter_crisis_mobile']=true,
        ['src.screens.critter_crisis_coop']=true,['src.screens.critter_crisis_screen']=true,
    }
    local loaded={}
    local function load(name)
        if not isolated[name] then return require(name) end
        if loaded[name] then return loaded[name] end
        local chunk=assert(love.filesystem.load(name:gsub('%.','/')..'.lua'))
        setfenv(chunk,setmetatable({require=load},{__index=_G}));loaded[name]=chunk();return loaded[name]
    end
    runtime.mobileControls={isEnabled=function()return phone end}
    runtime.Config={baseWidth=960,baseHeight=678};runtime.Viewport={toGame=function(x,y)return x,y end}
    runtime.App={officeFitsScreen=function()return true end};runtime.state.roomGameBay='front_left'
    local d={runtime=runtime,screen=load('src.screens.critter_crisis_screen'),input=load('src.critter_crisis_inputs'),phone=phone}
    d.screen.enter()
    function d:tap(action)
        if self.phone then
            local point=({fire={840,610},cover={410,610},reload={610,610},restart={460,440},next={460,375}})[action]
            local id=newproxy();self.screen.touchpressed(self.runtime,id,unpack(point));self.screen.touchreleased(id)
        elseif action=='fire' then
            self.screen.mousepressed(self.runtime,480,300,1);self.screen.mousereleased(1)
        else local key=({reload='r',restart='return',next='return',cover='c'})[action];self.screen.keypressed(self.runtime,key);self.screen.keyreleased(key) end
    end
    return d
end
return Devices
