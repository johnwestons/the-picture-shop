-- Operator view in 512px wrapper-art coordinates. The same confirmed cycle
-- position determines the table, carriage, and every deposited film band.
local Scene = {}
local tau = 2 * math.pi
local height, band = 92, 33

local function carriage(turn)
    local rise = math.min(1, math.max(0, (turn - 0.6) / 2.55))
    local fall = math.min(1, math.max(0, (turn - 3.5) / 2.55))
    return (height - band) * (rise - fall)
end

local function face(a,b,low,high)
    love.graphics.polygon("fill",a.x,a.y-low,b.x,b.y-low,b.x,b.y-high,a.x,a.y-high)
end

function Scene.draw(assets, wrapper, hasLoad, boxed, x,y,scale)
    local image = assets.get("skidWrapperDirections")
    if not image then return end
    love.graphics.push("all")
    love.graphics.translate(x,y)
    love.graphics.scale(scale)
    local function part(name, px, py, sy)
        local sprite = assets.getQuad(name)
        if sprite then love.graphics.draw(image,sprite.quad,px,py,0,1,sy or 1) end
    end
    local wrapping = wrapper.step == "wrapping"
    local phase = wrapper.step == "finished" and 1 or wrapping and
        math.max(0,math.min(1,wrapper.progress / wrapper.cycleTime)) or 0
    -- Short motor ramp at each end, constant speed through the middle.
    local ramp = 0.08
    local travel = phase < ramp and phase^2/(2*ramp)
        or phase > 1-ramp and 1-ramp-(1-phase)^2/(2*ramp) or phase-ramp/2
    local turns = 7 * travel / (1-ramp)
    local lift = carriage(turns)
    love.graphics.setColor(1,1,1)
    part("wrapUpper",0,0)
    part("wrapBase",0,337)
    part("wrapMast",0,246)
    part("wrapOuter",236,246)
    love.graphics.setColor(0.19,0.30,0.38)
    love.graphics.rectangle("fill",194,331-lift,41,5,1,1)
    love.graphics.setColor(1,1,1)
    part("wrapRoll",203,296-lift,0.43)
    if hasLoad then
        local angle = 0.48 + tau*turns
        local c,s = math.cos(angle), math.sin(angle)
        local function point(u,v)
            return {x=291+u*c-v*s,y=388+(u*s+v*c)*0.48}
        end
        local corners = {point(-57,-41),point(57,-41),point(57,41),point(-57,41)}
        -- Select the tangent from the roll in table space. Choosing the
        -- leftmost screen point alone hides the web behind the front face.
        local contact, tangent
        for _,p in ipairs(corners) do
            local bearing=math.atan2(p.x-225,(p.y-333)/0.48)
            if not tangent or bearing>tangent then contact,tangent=p,bearing end
        end
        local base = 12
        if wrapping and turns > 0 then
            -- The web stays tangent to the nearest silhouette corner. Draw it
            -- before the load so its far end passes behind the turning face.
            local py, edge = 333-lift, contact.y-base-lift
            love.graphics.setColor(0.76,0.91,0.99,0.37)
            love.graphics.polygon("fill",225,py,contact.x,edge,contact.x,edge-band,225,py-band)
            love.graphics.setColor(0.88,0.97,1,0.76)
            love.graphics.line(225,py-band,contact.x,edge-band)
        end
        for i,a in ipairs(corners) do
            local b = corners[i%4+1]
            if b.x < a.x then
                local light = 0.75+0.23*math.abs(b.x-a.x)/114
                love.graphics.setColor(0.44*light,0.30*light,0.18*light)
                face(a,b,0,base)
                for j=0,2 do
                    local f=(j+0.25)/3
                    love.graphics.setColor(0.16,0.12,0.09)
                    local px,py=a.x+(b.x-a.x)*f,a.y+(b.y-a.y)*f
                    love.graphics.line(px,py-2,px,py-8)
                end
                love.graphics.setColor(light,light*(boxed and 0.76 or 0.97),light*(boxed and 0.49 or 0.9))
                face(a,b,base,base+height)
                love.graphics.setColor(0.31,0.27,0.20,boxed and 0.75 or 0.27)
                for h=boxed and 46 or 5,height-1,boxed and 46 or 5 do
                    love.graphics.line(a.x,a.y-base-h,b.x,b.y-base-h)
                end
                -- Each face crosses the dispensing side once per revolution.
                -- Keep earlier laps visible while new film travels up and down.
                -- The roll approaches the back-right quadrant of the load.
                local start = ((-0.17 - math.atan2(a.y-388,(a.x-291)*0.48)/tau + turns) % 1)
                local arc = math.atan2((a.x-291)*(b.y-388)-(a.y-388)*(b.x-291),
                    (a.x-291)*(b.x-291)*0.48+(a.y-388)*(b.y-388)/0.48)/tau
                for lap=-1,7 do
                    local ta,tb=lap+start,lap+start-arc
                    local lo=math.max(0,(ta-turns)/arc)
                    local hi=math.min(1,ta/arc)
                    if hi > lo then
                        local function stripPoint(f)
                            local level=carriage(ta+(tb-ta)*f)
                            return a.x+(b.x-a.x)*f,a.y+(b.y-a.y)*f-base-level
                        end
                        local ax,ay=stripPoint(lo)
                        local bx,by=stripPoint(hi)
                        love.graphics.setColor(0.69,0.85,0.94,0.23)
                        love.graphics.polygon("fill",ax,ay,bx,by,bx,by-band,ax,ay-band)
                        love.graphics.setColor(0.94,0.98,1,0.45)
                        love.graphics.line(ax,ay-band,bx,by-band)
                    end
                end
            end
        end
        local top={}
        for _,p in ipairs(corners) do
            top[#top+1]=p.x
            top[#top+1]=p.y-base-height
        end
        love.graphics.setColor(boxed and 0.84 or 0.96,boxed and 0.66 or 0.94,boxed and 0.43 or 0.86)
        love.graphics.polygon("fill",top)
        if boxed then
            local a,b=point(-57,0),point(57,0)
            love.graphics.setColor(0.69,0.50,0.29)
            love.graphics.line(a.x,a.y-base-height,b.x,b.y-base-height)
        end
    end
    love.graphics.pop()
end

return Scene
