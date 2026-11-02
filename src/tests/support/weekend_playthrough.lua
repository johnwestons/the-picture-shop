-- A single household's Friday-to-Monday smoke journey. Advance the real
-- runtime in short steps and use the apartment controls for daily needs.
local Calendar=require('src.business_calendar')
local Layout=require('src.home_layouts')
local Activity=require('src.home_activity_controls')
local Sleep=require('src.home_sleep')
local Test={}
function Test.run(R,check)
    local state,host=R.state,R.World.player
    local owner=state.home.residents.owner
    local secondsPerHour=Calendar.secondsPerDay(state)/24
    local folder=os.getenv('PICTURE_SHOP_HOME_PREVIEW_DIR')
    local function hour() return Calendar.absoluteHours(state) end
    local function capture(name)
        if not folder then return end
        state.screen='world'
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{})
        require('src.screens.hud').draw(state,R.World.prompt(),R.Assets,nil,nil,false,false,nil,false,false,nil,'home',host)
        love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode('png')
        local file=assert(io.open(folder..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    local function advanceTo(target,label)
        assert(hour()<target+.00001,label..' started after its target time')
        for _=1,72 do
            local remaining=target-hour()
            if remaining<=.00001 then break end
            state.screen='world'
            R.App.update(math.min(1,remaining)*secondsPerHour)
        end
        check('weekend_playthrough_'..label,math.abs(hour()-target)<.001
            and state.home.weekend.phase=='home' and host.sceneId=='home',hour())
    end
    local function fixtureAction(name,kind,minutes,label)
        local fixture=assert(Layout.get(state).fixtures[name])
        host.x,host.y=Layout.toWorld(unpack(fixture.approach))
        local hoverX,hoverY=Layout.toWorld(fixture.x,fixture.y)
        state.screen='world'
        R.World.updateNetworkPlayer(0,0,0,R.Assets,state,hoverX,hoverY)
        check('weekend_playthrough_'..label..'_fixture',R.World.getInteraction()
            and R.World.getInteraction().kind=='homeActivity')
        assert(Activity.keypressed('e',R) and state.screen=='home_activity')
        Activity.keypressed('1',R)
        check('weekend_playthrough_'..label..'_started',owner.activity and owner.activity.kind==kind,state.message)
        R.App.update(secondsPerHour*minutes/60)
        check('weekend_playthrough_'..label..'_finished',not owner.activity,owner.activity and owner.activity.kind)
        Activity.keypressed('escape',R)
    end
    local function meal(label)
        state.screen='world';local before=state.home.inventory.pizza_slice or 0
        local hunger=owner.hunger
        assert(Activity.keypressed('h',R) and state.screen=='home_activity')
        check('weekend_playthrough_'..label..'_meal_selectable',require('src.tests.support.home_menu').choose(R,'pizza:floor'))
        check('weekend_playthrough_'..label..'_meal_started',owner.activity and owner.activity.kind=='pizza',state.message)
        R.App.update(secondsPerHour*10/60)
        check('weekend_playthrough_'..label..'_meal_fed_player',not owner.activity
            and owner.hunger>hunger and state.home.inventory.pizza_slice==before-1)
        Activity.keypressed('escape',R)
    end
    local function sleep(kind,label)
        state.screen='world'
        assert(Activity.keypressed('h',R));Activity.keypressed('t',R)
        assert(Activity.mode=='sleep')
        Activity.keypressed('1',R)
        check('weekend_playthrough_'..label..'_sleep_started',owner.activity and owner.activity.kind==kind
            and Sleep.status(state,{host}),state.message)
        local before=hour();local updates=0
        while owner.activity and updates<180 do R.App.update(.5);updates=updates+1 end
        check('weekend_playthrough_'..label..'_woke',not owner.activity and hour()>before+7.9
            and updates<180 and owner.energy>60,hour())
        Activity.keypressed('escape',R)
    end

    check('weekend_playthrough_friday_arrived',hour()<46 and state.home.weekend.phase=='home')
    advanceTo(46,'friday_night');capture('weekend-friday-night')
    sleep('sleepfloor','friday')
    advanceTo(57,'saturday_morning');meal('saturday_breakfast');capture('weekend-saturday-morning')
    advanceTo(60,'saturday_noon');local hygiene=owner.hygiene
    fixtureAction('bath','bathe',20,'saturday_bath')
    check('weekend_playthrough_bath_restored_hygiene',owner.hygiene>hygiene)
    advanceTo(66,'saturday_evening');local thirst=owner.thirst
    fixtureAction('sink','drink',2,'saturday_drink')
    check('weekend_playthrough_saturday_water_restored_thirst',owner.thirst>thirst)
    advanceTo(70,'saturday_night');sleep('sleepfloor','saturday')
    advanceTo(81,'sunday_morning');meal('sunday_breakfast');capture('weekend-sunday-morning')
    local homeDoor=require('src.home_travel').target(host,state)
    host.x,host.y=homeDoor.x,homeDoor.y
    check('weekend_runtime_no_sunday_return',not require('src.weekend_runtime').command(R,host,'request'))
    advanceTo(90,'sunday_evening');thirst=owner.thirst
    fixtureAction('sink','drink',2,'sunday_drink')
    check('weekend_playthrough_sunday_water_restored_thirst',owner.thirst>thirst)
    advanceTo(92,'sunday_night');capture('weekend-sunday-night')
    sleep('workfloor','sunday_to_monday')
    check('weekend_playthrough_monday_wake_reminder',state.home.weekend.returnReminderSent
        and math.abs(hour()-103)<.001)
    advanceTo(104,'monday_morning');meal('monday_breakfast')
    fixtureAction('sink','drink',2,'monday_drink')
    local ready=Sleep.readiness(state,{host})
    check('weekend_playthrough_monday_needs_ready',ready[1] and ready[1].ready
        and owner.hunger>=35 and owner.thirst>=35 and owner.hygiene>=35 and owner.energy>=35)
    capture('weekend-monday-ready')
    check('weekend_playthrough_stayed_home_until_return',state.home.weekend.phase=='home'
        and host.sceneId=='home' and #state.home.finance.history==1)
end
return Test
