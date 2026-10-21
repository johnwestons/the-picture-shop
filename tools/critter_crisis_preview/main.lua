-- Preview the actual game modules without reading or writing shop saves.
local Games=require('src.breakroom_games')
local Crisis=require('src.critter_crisis')
local Screen=require('src.screens.critter_crisis_screen')
local Frontier=require('src.screens.frontier_arcade')
local runtime={state={roomGameBay='front_left',breakroomGames=Games.defaultState()},
    World={player={id=1,sceneId='front_left',x=860,y=436}},
    multiplayer={isClient=function()return false end},
    Config={baseWidth=960,baseHeight=678},App={officeFitsScreen=function()return true end}}
runtime.state.breakroomGames.bays.front_left.critter_kombat=true
local paused=false
local function point(x,y)
    local w,h=love.graphics.getDimensions();local scale=math.min(w/960,h/678)
    return (x-(w-960*scale)/2)/scale,(y-(h-678*scale)/2)/scale
end
runtime.Viewport={toGame=point}
function love.load()
    Screen.enter()
    love.window.setTitle('Critter Crisis | 7: Two Players Here | 2: LAN | 4: Range / 5: Last Stand / 6: Train Attack')
    local review=os.getenv('CRITTER_PREVIEW_REVIEW')
    if review then
        local module=os.getenv('CRITTER_PHONE_REVIEW') and 'mobile_review' or os.getenv('CRITTER_COOP_REVIEW') and 'coop_review' or 'review'
        require('tools.critter_crisis_preview.'..module).run(runtime,Screen,Crisis,Frontier,review)
        love.event.quit()
    end
end
function love.update(dt)
    if not paused then
        Screen.update(dt,runtime)
        local x,y,buttons=Screen.controls(runtime)
        local arcade=Screen.arcadeInputs(runtime)
        Crisis.update(dt,function(id,session)
            if arcade then
                return require('src.critter_crisis_actions').seat(arcade,id==0,session.roundId)
            end
            return {x=x,y=y,buttons=buttons}
        end)
    end
end
function love.draw()
    local w,h=love.graphics.getDimensions();local scale=math.min(w/960,h/678)
    love.graphics.clear(.01,.015,.025,1);love.graphics.push('all')
    love.graphics.translate((w-960*scale)/2,(h-678*scale)/2);love.graphics.scale(scale)
    Screen.draw(runtime)
    if paused and not Frontier.active() then
        love.graphics.setColor(0,0,0,.8);love.graphics.rectangle('fill',250,282,460,70)
        love.graphics.setColor(1,1,1);love.graphics.printf('PAUSED - P TO RESUME',250,300,460,'center')
    end
    love.graphics.pop()
end
function love.keypressed(key)
    if key=='p' and not Frontier.active() then paused=not paused;return end
    if Screen.keypressed(runtime,key)=='back' then love.event.quit() end
end
function love.keyreleased(key) Screen.keyreleased(key) end
function love.mousepressed(x,y,button,istouch)
    if istouch then return end
    x,y=point(x,y)
    if Screen.mousepressed(runtime,x,y,button)=='back' then love.event.quit() end
end
function love.mousereleased(_,_,button,istouch) if not istouch then Screen.mousereleased(button) end end
function love.mousemoved(x,y,_,_,istouch) if not istouch then x,y=point(x,y);Screen.mousemoved(runtime,x,y) end end
function love.touchpressed(id,x,y) Screen.touchpressed(runtime,id,x,y) end
function love.touchmoved(id,x,y) Screen.touchmoved(runtime,id,x,y) end
function love.touchreleased(id) Screen.touchreleased(id) end
function love.gamepadpressed(pad,button) Screen.gamepadpressed(runtime,pad,button) end
function love.gamepadreleased(pad,button) Screen.gamepadreleased(pad,button) end
function love.gamepadaxis(pad,axis,value) Screen.gamepadaxis(runtime,pad,axis,value) end
function love.focus(focused)
    Screen.focus(focused)
    if not focused then paused=not Frontier.active();Screen.mousereleased();Screen.keyreleased('space') end
end
