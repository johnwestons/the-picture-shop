-- Regression for the visible size pulse during a complete driving circle.
local Test={}
function Test.run(check)
    local g=love.graphics
    local Pages=require('src.commute.kei_turntable_pages')
    local Art=require('src.commute.truck_art')
    for _,kind in ipairs({'isometric','chase'}) do
        local w,h=kind=='isometric' and 314 or 405,kind=='isometric' and 314 or 243
        local low,high,bottomLow,bottomHigh=math.huge,0,math.huge,0
        local widths={}
        for page=1,4 do
            local data=love.image.newImageData(('assets/commute/truck/kei-turntables/%s-64-%d.png'):format(kind,page))
            for slot=0,15 do
                local first,last=h,-1
                local left,right=w,-1
                for y=0,h-1 do for x=0,w-1 do
                    local _,_,_,a=data:getPixel(slot%4*w+x,math.floor(slot/4)*h+y)
                    if a>128/255 then
                        first=math.min(first,y);last=math.max(last,y)
                        left=math.min(left,x);right=math.max(right,x)
                    end
                end end
                low=math.min(low,last-first+1);high=math.max(high,last-first+1)
                bottomLow=math.min(bottomLow,last);bottomHigh=math.max(bottomHigh,last)
                widths[(page-1)*16+slot+1]=right-left+1
            end
            data:release()
        end
        local expectedHeight=kind=='isometric' and 144 or 180
        check('kei_'..kind..'_visible_height_stable',low==expectedHeight and high==expectedHeight,
            ('height=%d..%d'):format(low,high))
        check('kei_'..kind..'_tire_baseline_stable',bottomHigh-bottomLow<=1)
        for _,seam in ipairs({{358,0},{177,180}}) do
            local a=widths[Pages.frame(math.rad(seam[1]),kind)]
            local b=widths[Pages.frame(math.rad(seam[2]),kind)]
            check(('kei_%s_no_width_pop_at_%d'):format(kind,seam[2]),math.abs(a-b)/math.max(a,b)<.08)
        end
    end
    -- Capture actual runtime draw transforms, including camera pitch handling.
    local art=Art.new()
    local actor={x=0,z=0,h=0,heading=0,model='kei'}
    local originalDraw=g.draw
    local okay,err=xpcall(function()
        for _,kind in ipairs({'isometric','chase'}) do
            for _,tilt in ipairs({30,55,62,75}) do
                local camera={zoom=1,yaw=0,tilt=tilt,
                    outsideMode=kind=='chase' and 'shoulder' or 'follow',
                    screen=function()return 200,200 end}
                local minScale,maxScale=math.huge,0
                g.draw=function(_,_,_,_,_,sx,sy)
                    minScale=math.min(minScale,sy/sx);maxScale=math.max(maxScale,sy/sx)
                end
                for degrees=0,360 do
                    actor.heading=math.rad(degrees)-math.pi/2
                    art:draw(actor,camera,{},true)
                    if kind=='chase' then
                        assert(Art.frame(camera,actor.heading,'kei',kind)==Pages.frame(math.rad(degrees),kind),
                            'Kei shoulder view skipped a calibrated direction')
                    end
                end
                check(('kei_%s_heading_never_stretches_body_at_%d'):format(kind,tilt),maxScale-minScale<1e-9)
            end
        end
    end,debug.traceback)
    g.draw=originalDraw;art:release()
    assert(okay,err)
end
return Test
