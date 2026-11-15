local Condition=require('src.warehouse_condition')
local Renderer=require('src.warehouse_condition_renderer')
local Test={}

function Test.run(context,check)
    local g=love.graphics
    local originalCanvas=g.newCanvas
    local results={}
    local profiles={
        {id='phone_dpi2_base',dpi=2,width=960,height=678,scale=1,x=0,y=0},
        {id='desktop_scaled',dpi=1,width=1440,height=1017,scale=1.5,x=0,y=0},
        {id='phone_dpi2',dpi=2,width=2340,height=1080,scale=1080/678,x=(2340-960*1080/678)/2,y=0},
        {id='phone_dpi3_zoom',dpi=3,width=2340,height=1080,scale=1.8,x=300,y=-180},
    }
    local target
    local okay,reason=xpcall(function()
        for _,view in ipairs(profiles) do
            -- Exercise actual high-DPI GPU canvases on the desktop runner.
            -- Only the window's default DPI is simulated; explicit canvas
            -- settings still take precedence, just as they do on a phone.
            g.newCanvas=function(width,height,settings)
                local options={}
                for key,value in pairs(settings or {}) do options[key]=value end
                options.dpiscale=options.dpiscale or view.dpi
                return originalCanvas(width,height,options)
            end
            target=originalCanvas(view.width,view.height,{dpiscale=1})
            local state={warehouse={condition=Condition.new('story',771)}}
            local left,right=Condition.anchors.puddle1,Condition.anchors.puddle2
            Renderer.clear()
            local function capture()
                g.push('all')
                g.setCanvas(target);g.origin();g.setShader();g.setStencilTest()
                g.setScissor();g.setBlendMode('alpha','alphamultiply')
                g.clear(0,0,0,0)
                g.translate(view.x,view.y);g.scale(view.scale)
                g.setScissor(math.max(0,view.x),0,view.width-math.max(0,view.x),view.height)
                local sx,sy,sw,sh=g.getScissor()
                Renderer.drawStatic(state)
                local ax,ay=g.transformPoint(left.x,left.y)
                local nx,ny,nw,nh=g.getScissor()
                local restored=g.getCanvas()==target and sx==nx and sy==ny and sw==nw and sh==nh
                    and math.abs(ax-(view.x+left.x*view.scale))<.001
                    and math.abs(ay-(view.y+left.y*view.scale))<.001
                g.pop()
                local data=target:newImageData()
                local function alpha(point)
                    local _,_,_,a=data:getPixel(math.floor(view.x+point.x*view.scale),
                        math.floor(view.y+point.y*view.scale))
                    return a
                end
                local l,r,b=alpha(left),alpha(right),alpha(Condition.anchors.breaker)
                data:release()
                return l,r,b,restored
            end
            local beforeLeft,beforeRight,breaker,restored=capture()
            results[#results+1]={'puddle_render_'..view.id..'_matches_actions',
                beforeLeft>.55 and beforeRight>.55 and breaker<.005 and restored,
                ('left=%.3f right=%.3f breaker=%.3f restored=%s'):format(beforeLeft,beforeRight,breaker,tostring(restored))}
            local folder=os.getenv('PICTURE_SHOP_RESTORATION_PREVIEW_DIR')
            if folder and folder~='' then
                local picture=originalCanvas(view.width,view.height,{dpiscale=1})
                g.push('all');g.setCanvas(picture);g.origin();g.setScissor();g.setShader();g.setStencilTest()
                g.clear(.04,.05,.07,1);g.setColor(1,1,1,1)
                local plate=Renderer.image(state,context.assets)
                g.draw(plate,view.x,view.y,0,960/plate:getWidth()*view.scale,678/plate:getHeight()*view.scale)
                g.setBlendMode('alpha','premultiplied');g.draw(target);g.pop()
                local data=picture:newImageData()
                local encoded=data:encode('png')
                local file=assert(io.open(folder..'/puddles-'..view.id..'.png','wb'))
                file:write(encoded:getString());file:close()
                data:release();picture:release()
            end
            Condition.mopPoint(state,'puddle1',left.x,left.y)
            local afterLeft,afterRight=capture()
            results[#results+1]={'puddle_render_'..view.id..'_mops_visible_spill',
                afterLeft>0 and afterLeft<beforeLeft-.1 and math.abs(afterRight-beforeRight)<.01,
                ('left=%.3f -> %.3f right=%.3f -> %.3f'):format(beforeLeft,afterLeft,beforeRight,afterRight)}
            view.x=view.x+25
            local movedLeft,movedRight=capture()
            results[#results+1]={'puddle_render_'..view.id..'_camera_move_keeps_alignment',
                math.abs(movedLeft-afterLeft)<.01 and math.abs(movedRight-afterRight)<.01}
            -- Rebuilding from saved mop strokes must match the incremental mask.
            Renderer.clear()
            local reloadedLeft,reloadedRight=capture()
            results[#results+1]={'puddle_render_'..view.id..'_reload_keeps_cleanup',
                math.abs(reloadedLeft-afterLeft)<.01 and math.abs(reloadedRight-afterRight)<.01}
            target:release();target=nil
        end
    end,debug.traceback)
    g.newCanvas=originalCanvas
    Renderer.clear()
    if target then target:release() end
    assert(okay,reason)
    for _,result in ipairs(results) do check(unpack(result)) end
end

return Test
