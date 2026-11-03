-- Real App loading acceptance shared by the physical commute journeys.
local C=require('src.commute.runtime')
local Bindings=require('src.commute.bindings')
local Test={}
function Test.wait(R,check,prefix)
    local deadline=love.timer.getTime()+60
    -- Returning outdoors can reuse the complete resident terrain from the
    -- previous trip. Only a newly created renderer must show loading progress.
    local initialRenderer=R._commute and R._commute.renderer
    local initiallyReady=initialRenderer and initialRenderer:terrainReady()
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    local originalMovement,originalDrive=R.Input.movement,Bindings.drive
    local loadingFrames,progressSeen,blockedInput,blockedDraw=0,false,true,true
    local function drawProbe(loading)
        local view=R._commute;local renderer=view and view.renderer
        local originalDraw=renderer and renderer.draw
        local originalPrintf=love.graphics.printf
        local calls=0
        if renderer then renderer.draw=function(self,...)
            calls=calls+1
            assert(self:terrainReady(),'Exterior draw before permanent terrain was ready')
            return originalDraw(self,...)
        end end
        love.graphics.printf=function(text,...)
            if type(text)=='string' and text:match('Preparing the complete terrain: %d+%%')then progressSeen=true end
            return originalPrintf(text,...)
        end
        love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true})
        local okay,reason=xpcall(function()C.draw(R)end,debug.traceback)
        love.graphics.pop();love.graphics.printf=originalPrintf
        if renderer then renderer.draw=originalDraw end
        if not okay then error(reason,0)end
        if loading then blockedDraw=blockedDraw and calls==0 else return calls==1 end
    end
    local okay,reason=xpcall(function()
        R.App.update(0)
        while R._commute and (R._commute.loading or not R._commute.renderer)do
            loadingFrames=loadingFrames+1
            local oldMovement,oldDrive=R.Input.movement,Bindings.drive
            R.Input.movement=function()return 1,-1 end
            Bindings.drive=function()return 1,-1,true end
            local x,y,boost=C.localInput(R)
            R.Input.movement,Bindings.drive=oldMovement,oldDrive
            blockedInput=blockedInput and x==0 and y==0 and boost~=true
            if loadingFrames<=2 or not progressSeen and R._commute.renderer then drawProbe(true)end
            assert(love.timer.getTime()<deadline,'Town loading did not finish within 60 seconds')
            R.App.update(0)
        end
        local renderer=assert(R._commute and R._commute.renderer,'Town renderer missing after loading')
        local size=renderer.world.size;local stats=renderer:terrainStats()
        local reusedReady=initiallyReady and renderer==initialRenderer and stats.ready
        check(prefix..'_loading_blocks_controls_and_exterior_draw',blockedInput and blockedDraw
            and (loadingFrames>1 or reusedReady),
            ('loadingFrames=%d reusedReady=%s'):format(loadingFrames,tostring(reusedReady==true)))
        check(prefix..'_loading_reports_terrain_progress',progressSeen or reusedReady)
        check(prefix..'_first_exterior_reveal_has_complete_terrain',stats.ready and stats.completed==stats.total
            and stats.uncovered==0 and renderer:terrainCoverage(0,0) and renderer:terrainCoverage(size,size)
            and renderer:terrainCoverage(0,size) and renderer:terrainCoverage(size,0) and drawProbe(false))
    end,debug.traceback)
    R.Input.movement,Bindings.drive=originalMovement,originalDrive
    canvas:release()
    if not okay then error(reason,0)end
end
return Test
