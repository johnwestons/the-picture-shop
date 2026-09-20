local Scene=require("src.warehouse_scene")
local Config=require("src.config")
local Test={}
function Test.run(context,check)
    local function test(name,value) check("warehouse_scene_"..name,value) end
    local data=Scene.registration()
    test("top_only_registration",data.topOnly and data.preservesGameplayMask)
    test("legacy_dimensions_stay_fixed",data.legacyWidth==1536 and data.legacyHeight==1024)
    test("candidate_dimensions_explicit",data.sourceWidth==1672 and data.sourceHeight==941)
    for index,strip in ipairs(data.strips) do
        local x,y=Scene.sourcePoint(strip.sourceX,0)
        test("architectural_post_"..index,math.abs(x-strip.legacyX*Config.baseWidth/1536)<0.00001 and y==0)
    end
    test("top_left_gap_filled",Scene.topContains(60,20))
    test("top_right_gap_filled",Scene.topContains(900,35))
    test("lower_upgrade_bays_untouched",not Scene.topContains(80,550) and not Scene.topContains(890,550))
    test("floor_and_front_edge_untouched",not Scene.topContains(480,455) and not Scene.topContains(480,643))
    test("dock_footprint_untouched",not Scene.topContains(220,270))
    test("lounge_and_entrance_untouched",not Scene.topContains(782,305) and not Scene.topContains(645,235))
    test("invalid_coordinates_rejected",not Scene.topContains(-1,0) and not Scene.sourcePoint(2000,0)
        and not Scene.sourcePoint(100,400))
    local x,y=Scene.worldPoint(Config.loadingBay.sourceX,Config.loadingBay.sourceY)
    test("dock_anchor_identical",x==125 and math.abs(y-112.55859375)<0.00001)
    local wx,wy=Scene.worldPoint(Config.loungeSeating.foregrounds["left-chair"].sourceX,
        Config.loungeSeating.foregrounds["left-chair"].sourceY)
    test("lounge_anchor_identical",wx==698.75 and math.abs(wy-248.291015625)<0.00001)
    data.strips[1].sourceX=300;data.roof[1].y=600
    test("registration_is_detached",Scene.registration().strips[1].sourceX==0 and Scene.registration().roof[1].y==202)
    if context and context.assets then
        local base=context.assets.get("warehouse")
        local architecture=context.assets.get("warehouseArchitecture")
        test("original_registered_base_retained",base and base:getWidth()==1536 and base:getHeight()==1024)
        test("new_architecture_is_loaded",architecture and architecture:getWidth()==1672 and architecture:getHeight()==941)
        if base and architecture and love.graphics and love.graphics.newCanvas then
            local canvas=love.graphics.newCanvas(Config.baseWidth,Config.baseHeight)
            local previousCanvas=love.graphics.getCanvas()
            love.graphics.push("all")
            local function sample(withArchitecture)
                love.graphics.setCanvas({canvas,stencil=true})
                love.graphics.origin()
                love.graphics.clear(0,0,0,1)
                if withArchitecture then Scene.drawArchitecture(context.assets) end
                love.graphics.setColor(1,1,1,1)
                love.graphics.draw(base,0,0,0,Config.baseWidth/1536,Config.baseHeight/1024)
                love.graphics.setCanvas(previousCanvas)
                return canvas:newImageData()
            end
            local before,after=sample(false),sample(true)
            love.graphics.pop()
            local identical=true
            for py=190,Config.baseHeight-1 do
                for px=0,Config.baseWidth-1 do
                    local ar,ag,ab,aa=before:getPixel(px,py)
                    local br,bg,bb,ba=after:getPixel(px,py)
                    if ar~=br or ag~=bg or ab~=bb or aa~=ba then identical=false;break end
                end
                if not identical then break end
            end
            test("every_lower_pixel_is_unchanged",identical)
            local r,g,b=after:getPixel(50,20)
            local oldR,oldG,oldB=before:getPixel(50,20)
            test("upper_gap_now_contains_architecture",r+g+b>0.08 and oldR+oldG+oldB<0.001)
            before:release();after:release();canvas:release()
        end
    end
end
return Test
