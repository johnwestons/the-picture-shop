local Art=require('src.commute.truck_art')

local function writePng(canvas,path)
    local encoded=canvas:newImageData():encode('png')
    local file=assert(io.open(path,'wb'))
    assert(file:write(encoded:getString()))
    assert(file:close())
end

function love.load()
    local art=Art.new()
    local world={supportHeight=function() return 0 end}
    local output=assert(os.getenv('PICTURE_SHOP_TRUCK_CAPTURE_OUTPUT'))
    for _,kind in ipairs({'chase','isometric'}) do
        local width=kind=='chase' and 640 or 384
        local canvas=love.graphics.newCanvas(width,384)
        local camera={yaw=0,zoom=kind=='chase' and 1/.42 or 1,
            tilt=kind=='chase' and 8 or 55}
        camera.screen=function() return width/2,kind=='chase' and 352 or 316 end
        for _,livery in ipairs({'plain','picture_shop'}) do
            for frame=1,64 do
                camera.yaw=(frame-1)*360/64-90
                assert(Art.frame(camera,0)==frame,'Incorrect runtime truck angle')
                love.graphics.push('all')
                love.graphics.setCanvas(canvas)
                love.graphics.clear(0,0,0,0)
                art:draw({x=0,z=0,h=0,heading=0,livery=livery},camera,world)
                love.graphics.pop()
                if (frame-1)%8==0 then
                    writePng(canvas,('%s/review-%s-%s-%02d.png'):format(output,kind,livery,frame))
                end
            end
        end
        canvas:release()
    end
    art:release()
    print('TRUCK_RUNTIME_64_REVIEW_OK')
    love.event.quit()
end
