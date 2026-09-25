local root=assert(os.getenv("PICTURE_SHOP_PROJECT_ROOT")):gsub("\\","/"):gsub("/$","")
package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
local images={}
local function image(path)
    if not images[path] then
        local file=assert(io.open(root.."/"..path,"rb"));local bytes=file:read("*a");file:close()
        images[path]=love.graphics.newImage(love.filesystem.newFileData(bytes,path))
        images[path]:setFilter("linear","linear")
    end
    return images[path]
end
local function fixture(stage)
    local project={id="WUP-0001",bayId="front_left",optionId="storage",phase="building",stage=stage}
    local worker={projectId=project.id,bayId=project.bayId,phase="working",moving=false,
        x=260,y=505,workTime=0.5,workStage=stage}
    return {warehouse={activeProjectId=project.id,projects={project},bays={
        front_left={status="building",optionId="storage",projectId=project.id},front_right={status="locked"}}},
        constructionWorker=worker}
end
function love.load()
    local okay,reason=pcall(function()
        local count=0
        local function check(name,value,detail)
            if not value then error(name..": "..tostring(detail or "failed")) end
            count=count+1;print("PASS "..name)
        end
        require("src.tests.warehouse_construction_presentation_test").run({constructionImage=image},check)
        local Config=require("src.config")
        local Presentation=require("src.warehouse_construction_presentation")
        local Work=require("src.mechanic_work_presentation")
        local Scene=require("src.warehouse_scene")
        local Renderer=require("src.warehouse_renderer")
        local assets={get=function(name)
            if name=="warehouse" then return image(Config.paths.warehouse) end
            if name=="warehouseArchitecture" then return image(Config.paths.warehouseArchitecture) end
        end}
        for stage=1,4 do
            local state=fixture(stage)
            local plan,code=Presentation.plan(state,"front_left",{review=true})
            assert(plan,code)
            local canvas=love.graphics.newCanvas(960,678)
            love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true})
            love.graphics.clear(0,0,0,1)
            Scene.drawArchitecture(assets)
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(assets.get("warehouse"),0,0,0,960/1536,678/1024)
            Renderer.drawFloors(assets,state)
            -- Same ordering as the real world: builder's feet y505, then the
            -- complete construction image at its registered front-ground depth.
            assert(Work.draw(state.constructionWorker,state,image,{review=true}))
            assert(Presentation.draw(state,"front_left",image,{review=true}))
            love.graphics.setColor(1,0.85,0.4,1)
            love.graphics.print("Stage "..stage.." / 4 - authored construction sprite review",12,12)
            love.graphics.setCanvas();love.graphics.pop()
            local data=canvas:newImageData():encode("png")
            local path=root.."/output/warehouse-expansion-v1/construction-sprite-review/stage-"..stage..".png"
            local file=assert(io.open(path,"wb"));file:write(data:getString());file:close();canvas:release()
            print("CAPTURE "..path)
        end
        print("CONSTRUCTION SPRITES PASS "..count.." checks")
    end)
    if not okay then print("CONSTRUCTION SPRITES FAIL "..tostring(reason)) end
    io.stdout:flush();love.event.quit(okay and 0 or 1)
end
function love.errorhandler(message)
    print("CONSTRUCTION SPRITES ERROR "..tostring(message));io.stdout:flush();return function() return 1 end
end
