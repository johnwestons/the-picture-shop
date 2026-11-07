local Rider=require('src.commute.rider')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Test={}

function Test.run(check)
    local world={supportHeight=function()return 0 end,
        roads={nearest=function()return 0,{width=8}end,blocked=function()return false end}}
    local function distance(sprint)
        local rider=Rider.new(100,100,0)
        for _=1,120 do Rider.update(rider,{walkX=1,sprint=sprint},1/60,world) end
        return rider.ped.x-100
    end
    local walking,sprinting=distance(false),distance(true)
    check('on_foot_sprint_is_about_forty_percent_faster',sprinting>walking*1.35
        and sprinting<walking*1.65,('%0.2f / %0.2f'):format(walking,sprinting))
    local profile=Bindings.defaults()
    local hasSprint=false
    for _,button in ipairs(Touch.actionButtons(960,678,profile,
        {mounted=false,gearTransition=false,arrived=false,pedCrash=false},{mobile=true})) do
        if button.action=='boost' then
            hasSprint=button.label=='SPRINT' and button.x>480
                and Touch.actionAt(button.x,button.y,960,678,profile,
                    {mounted=false,gearTransition=false,arrived=false,pedCrash=false},{mobile=true})~=nil
        end
    end
    check('keyboard_shift_binding_and_mobile_sprint_button_are_available',profile.keyboard.boost=='lshift'
        and profile.touch.boost=='touch3' and hasSprint)
end

return Test
