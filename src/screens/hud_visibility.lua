-- Local presentation preferences; neither HUD nor camera locks enter game saves.
local Ui=require('src.screens.ui')
local Visibility={}
local font
function Visibility.isVisible(R)
    return not (R.App and R.App.settings and R.App.settings.hudVisible==false)
end
function Visibility.canLockCamera(R)
    local view=R._commute;local camera=view and view.camera
    return R.state.screen=='world' and R.World.player.sceneId=='commute'
        and camera~=nil and view.renderer~=nil and not view.loading and not view.mechanicOffer
        and (camera.firstPerson==true or camera.outsideMode~='follow')
end
function Visibility.cameraLocked(R)
    return R._commute and R._commute.cameraLocked==true and Visibility.canLockCamera(R) or false
end
function Visibility.setVisible(R,shown)
    R.App.settings.hudVisible=shown~=false
    if not shown then
        require('src.home_activity_controls').hideHud()
        if R._commute then
            R._commute.mapOpen=false
            require('src.commute.runtime').cancelCameraLook(R)
        end
    end
    require('src.settings').save(R.App.settings)
    return true
end
function Visibility.toggle(R) return Visibility.setVisible(R,not Visibility.isVisible(R)) end
function Visibility.toggleCameraLock(R)
    if not Visibility.canLockCamera(R) then return false end
    R._commute.cameraLocked=not R._commute.cameraLocked
    require('src.commute.runtime').cancelCameraLook(R)
    return true
end
function Visibility.buttons(R)
    if R.state.screen~='world' then return {} end
    local _,bounds=R.optionsAccessLayout()
    local right=bounds and bounds.right or R.Config.baseWidth
    local mobile=R.mobileControls and R.mobileControls:isEnabled()
    local buttons={{id='hud',x=right-272,y=58,width=128,height=32,
        label=(Visibility.isVisible(R) and 'HIDE HUD' or 'SHOW HUD')..(mobile and '' or ' [F9]')}}
    if Visibility.canLockCamera(R) then
        buttons[#buttons+1]={id='lock',x=right-140,y=58,width=122,height=32,
            label=(Visibility.cameraLocked(R) and 'UNLOCK' or 'LOCK CAM')..(mobile and '' or ' [F8]')}
    end
    return buttons
end
function Visibility.pointer(R,x,y,button)
    if button~=1 then return false end
    for _,b in ipairs(Visibility.buttons(R)) do
        if Ui.contains(b,x,y) then
            return b.id=='hud' and Visibility.toggle(R) or Visibility.toggleCameraLock(R)
        end
    end
    return false
end
function Visibility.keypressed(R,key)
    if R.state.screen~='world' then return false end
    if key=='f9' then return Visibility.toggle(R) end
    if key=='f8' then return Visibility.toggleCameraLock(R) end
    return false
end
function Visibility.draw(R)
    local g=love.graphics;font=font or g.newFont(12)
    g.push('all');g.setShader();g.setFont(font)
    for _,b in ipairs(Visibility.buttons(R)) do
        local locked=b.id=='lock' and Visibility.cameraLocked(R)
        Ui.panel(b,{.055,.09,.095,.94},locked and {.91,.75,.37,1} or {.43,.53,.51,1},5,1)
        g.setColor(locked and 1 or .94,locked and .86 or .95,locked and .51 or .89,1)
        g.printf(b.label,b.x,b.y+(b.height-font:getHeight())/2,b.width,'center')
    end
    g.pop()
end
return Visibility
