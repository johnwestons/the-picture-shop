-- First join frames can render before the simulation notices the new scene.
-- Exercise real GPU ownership and the actual ready-event handler in that gap.
local C=require('src.commute.runtime')
local Schema=require('src.save_schema')
local Loading=require('src.commute.tests.loading_test_support')
local Test={}
function Test.run(context,check)
    local R=context.appRuntime
    local oldPlayer=R.World.snapshot()
    local oldDrain,oldResident=R.multiplayer.drainEvents,R.multiplayer.residentId
    local oldIsClient=R.multiplayer.isClient
    local oldError=R.showConnectionError
    local function drawLoading(label)
        local printf=love.graphics.printf;local loading=false
        love.graphics.printf=function(text,...)
            if text=='Preparing your ride…' then loading=true end
            return printf(text,...)
        end
        local okay,reason=xpcall(function()C.draw(R)end,debug.traceback)
        love.graphics.printf=printf
        check(label..'_first_frame_is_loading',okay and loading,reason)
    end
    local function ready(state,spawn)
        R.multiplayer.isClient=function()return true end
        R.multiplayer.residentId='owner'
        R.multiplayer.drainEvents=function()return {{type='ready',state=state,spawn=spawn}} end
        R.handleMultiplayerEvents()
        R.multiplayer.drainEvents=oldDrain
    end
    local function validIcon(label)
        local image,quad=R._commute.renderer.bikeArt:resolve('parked',5)
        check(label..'_fresh_parked_icon_is_resident',image~=nil and quad~=nil
            and not R._commute.renderer.released)
        require('src.commute.cockpit').drawCondition(C.localPart(R).rider.bike,0,0,R._commute.renderer.bikeArt)
    end
    local okay,reason=xpcall(function()
        assert(R.startGame(assert(R.Save.newGame(3,{startMode='quick',townSeed=712345})),'smoke'))
        R.state.screen='world'
        assert(require('src.commute.free_travel').enter(R.state,R.World.player,C.world(R),nil,{R.World.player}))
        Loading.wait(R,check,'join_view_original')
        require('src.commute.tests.prediction_render_test').run(R,check)
        local snapshot=assert(Schema.snapshot(R.state));local spawn=R.World.snapshot()
        local oldView=R._commute;local oldRenderer=oldView.renderer
        -- A disconnect/rejoin need not pass through the main menu, and its
        -- snapshot can describe the very same town with a new session.
        R.state.screen='lan';R._storyOpening={time=0};R._grandOpening={time=0}
        ready(snapshot,spawn)
        check('join_view_same_town_releases_prior_session',oldRenderer.released
            and R._commute==nil and R._storyOpening==nil and R._grandOpening==nil)
        drawLoading('join_view_same_town')
        Loading.wait(R,check,'join_view_same_town')
        check('join_view_same_town_recreates_renderer',R._commute~=oldView
            and R._commute.renderer~=oldRenderer)
        validIcon('join_view_same_town')

        oldRenderer=R._commute.renderer
        assert(R.returnToTitle())
        check('join_view_menu_releases_renderer',oldRenderer.released and R._commute==nil)
        ready(snapshot,spawn)
        drawLoading('join_view_after_menu')
        Loading.wait(R,check,'join_view_after_menu')
        validIcon('join_view_after_menu')

        -- A new Story shop has a different generated town. Apply it between
        -- update and draw without a ready event to exercise the draw barrier.
        local payload=assert(R.Save.newGame(2,{startMode='story',townSeed=712346}))
        local host={state=payload.state,World={player=Schema.copy(spawn)}}
        host.World.player.homeResidentId='owner'
        assert(require('src.story_intro').spawn(host))
        local story=assert(Schema.snapshot(host.state))
        oldView=R._commute;oldRenderer=oldView.renderer
        assert(R.State.applySharedSnapshot(R.state,story))
        R.World.load(host.World.player);R.World.player.homeResidentId='owner'
        R.state.screen='world'
        drawLoading('join_view_new_story_town')
        check('join_view_new_story_town_releases_before_draw',oldRenderer.released
            and R._commute~=oldView and R._commute.renderer==nil
            and R._commute.world.townId==story.home.town.id)
        Loading.wait(R,check,'join_view_new_story_town')
        validIcon('join_view_new_story_town')
        oldView=R._commute;local rejected=false
        R.showConnectionError=function()rejected=true end
        ready({},spawn)
        check('join_view_rejected_snapshot_preserves_live_renderer',rejected
            and R._commute==oldView and not oldView.renderer.released)
        C.release(host)
        assert(R.returnToTitle())
    end,debug.traceback)
    R.multiplayer.drainEvents,R.multiplayer.residentId=oldDrain,oldResident
    R.multiplayer.isClient=oldIsClient
    R.showConnectionError=oldError
    R.World.load(oldPlayer)
    if not okay then C.release(R);error(reason,0) end
end
return Test
