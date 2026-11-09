-- Native material pixels: no test shaders or duplicated rendering code.
local Review={}
local function save(canvas,path)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();data:release()
end
function Review.run(check)
    local Art=require('src.commute.bike_art');local Material=require('src.commute.bike_paint_art')
    local regions=require('assets.commute.bike.wheel_regions');local g=love.graphics
    local folder=os.getenv('PICTURE_SHOP_BIKE_FX_OUTPUT') or 'output/bike-motion-fx-review'
    local art=Art.new();local canvas=g.newCanvas(320,320)
    local function render(image,quad,state,frame,speed,distance,plain)
        g.push('all');g.setCanvas(canvas);g.origin();g.setShader();g.clear(0,0,0,0);g.setColor(1,1,1,1)
        if plain then g.draw(image,quad,0,0)
        else Material.draw(image,quad,'bronze',0,0,0,1,1,0,0,frame,state,{speed=speed,distance=distance}) end
        g.pop();return canvas:newImageData()
    end
    local pixels,still,restricted,alpha,changed=true,true,true,true,0
    local function inside(row,x,y)
        for wheel=0,1 do local n=wheel*4
            if row[n+3]>0 then
                local qx=(x-row[n+1])/row[n+3];local qy=(y-row[n+2])/row[n+4]
                if qx*qx+qy*qy<1.12 and qy>-.40 then return true end
            end
        end
        return false
    end
    local poses={};for state in pairs(regions) do poses[#poses+1]=state end;table.sort(poses)
    local coverage=0;local records={}
    for _,state in ipairs(poses) do
        for frame=1,64,8 do
            local image,quad=art:resolve(state,frame)
            local source=render(image,quad,state,frame,0,0,true)
            local stopped=render(image,quad,state,frame,0,34,false)
            local moving=render(image,quad,state,frame,8,.27,false)
            local moved=render(image,quad,state,frame,8,.39,false)
            local stationaryExact=source:getString()==stopped:getString()
            local phaseChanges=moving:getString()~=moved:getString()
            still=still and stationaryExact;pixels=pixels and phaseChanges
            local n,outside,alphaChanges=0,0,0;local row=regions[state][frame]
            for y=0,319 do for x=0,319 do
                local r,b,c,a=source:getPixel(x,y);local mr,mb,mc,ma=moving:getPixel(x,y)
                alpha=alpha and ma==a
                if ma~=a then alphaChanges=alphaChanges+1 end
                if math.max(math.abs(r-mr),math.abs(b-mb),math.abs(c-mc))>1/255 then
                    n=n+1
                    if not inside(row,x+.5,y+.5) then outside=outside+1;restricted=false end
                end
            end end
            changed=changed+n;coverage=coverage+1
            records[#records+1]=('{"state":"%s","frame":%d,"stationaryExact":%s,"distanceChangesPixels":%s,"changedMaterialPixels":%d,"outsideWheelRegions":%d,"alphaChanges":%d}')
                :format(state,frame,tostring(stationaryExact),tostring(phaseChanges),n,outside,alphaChanges)
            if state=='upright' then save(canvas,folder..('/tire-moving-view-%02d.png'):format(frame)) end
            source:release();stopped:release();moving:release();moved:release()
        end
    end
    local file=assert(io.open(folder..'/tire-motion-acceptance.json','wb'))
    file:write('{"samples":['..table.concat(records,',')..']}\n');file:close()
    check('bike_tire_native_120_pose_angle_samples_stay_pixel_exact_while_stopped',still and coverage==120)
    check('bike_tire_native_distance_changes_only_lower_wheel_material_pixels',pixels and restricted and changed>100)
    check('bike_tire_native_motion_preserves_sprite_alpha_at_every_sample',alpha)
    -- Native-size sequential side/rear/front examples for a procedural cue review.
    for _,frame in ipairs({1,17,33,49}) do
        local image,quad=art:resolve('upright',frame)
        for tick=0,31 do
            local data=render(image,quad,'upright',frame,6,tick*.055,false);data:release()
            save(canvas,folder..('/tire-roll-%02d-%02d.png'):format(frame,tick))
        end
    end
    canvas:release();art:release()
end
return Review
