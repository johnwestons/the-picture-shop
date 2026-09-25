-- Isolated engine-only acceptance; no normal title/save or App is loaded.
local Runner={}
function Runner.install()
    local root=love.filesystem.getSource():gsub("\\","/"):gsub("/$","")
    local runId=os.date("%Y%m%d-%H%M%S")
    function love.errorhandler(message)
        print("WAREHOUSE ACCEPTANCE ERROR "..tostring(message));io.stdout:flush()
        return function() return 1 end
    end
    local pending=true
    function love.update()
        if not pending then return end
        pending=false
        local okay,reason=pcall(function()
            local assets=require("src.assets")
            local characters=require("src.character_assets")
            assets.load();characters.load()
            local count=0
            local context={assets=assets,captureWarehouse=function(name,state,world,rack,view)
                local canvas=love.graphics.newCanvas(960,678)
                love.graphics.push("all")
                love.graphics.setCanvas({canvas,stencil=true})
                love.graphics.clear(0.015,0.019,0.025,1)
                if view then
                    love.graphics.translate(480,339)
                    love.graphics.scale(view.zoom or 1)
                    love.graphics.translate(-view.x,-view.y)
                end
                world.draw(assets,characters,state)
                if rack then rack:draw(state,{body=love.graphics.getFont()}) end
                love.graphics.setCanvas()
                love.graphics.pop()
                local data=canvas:newImageData():encode("png")
                local path=root.."/output/warehouse-expansion-v1/live-acceptance/"..runId.."-"..name..".png"
                local file=assert(io.open(path,"wb"));file:write(data:getString());file:close()
                canvas:release()
                print("CAPTURE "..path)
            end}
            local function check(name,value,detail)
                if not value then error(name..": "..tostring(detail or "failed")) end
                count=count+1;print("PASS "..name)
            end
            require("src.tests.warehouse_layout_test").run(context,check)
            require("src.tests.warehouse_live_acceptance_test").run(context,check)
            print("WAREHOUSE ACCEPTANCE PASS "..count.." checks")
        end)
        if not okay then print("WAREHOUSE ACCEPTANCE FAIL "..tostring(reason)) end
        io.stdout:flush()
        love.event.quit(okay and 0 or 1)
    end
end
return Runner
