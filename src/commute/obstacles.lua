-- Collision shapes use the same candidate, lifecycle and visual scale as scenery.
-- Trees contribute only a narrow central trunk; shrubs, fallen logs and pebble
-- clutter never enter the solid set. Dimensions are in world metres (48px/m).
local Flora=require('src.commute.flora')
local Obstacles={MAX_RADIUS=4.34}
local rockTops={85,133,8,122,30,15,8,117,11,39,45}
local upland={2,4,7,8,9,10}
local alpine={2,4,5,6,7,8,9,10}

function Obstacles.solidKind(kind)
    return kind=='rock' or Flora.canopy[kind]==true
end

function Obstacles.shape(p,seed,calendar)
    if not Obstacles.solidKind(p.kind) then return nil end
    Flora.present(p,seed,calendar)
    local scale=(p.scale or 1)*Flora.scale(p)
    if p.kind=='rock' then
        -- Match the static rock selection in plant_sprites.drawPlant. Use the
        -- broad central body, leaving irregular silhouette tips forgiving.
        local index=(p.id or 0)%11
        if p.h>18 then index=alpine[(p.id or 0)%#alpine+1]
        elseif p.h>2 then index=upland[(p.id or 0)%#upland+1]
        elseif p.h<1 then index=(p.id or 0)%2==0 and 1 or 3 end
        return 2*scale,(248-rockTops[index+1])/48*scale
    end
    local state=Flora.catalog.appearance(p,calendar)
    -- Seeds and sprouts are not trunks. The decay artwork is a fallen log,
    -- whereas dead trees still have a standing central trunk.
    if not state or state=='seed' or state=='sprout' or state=='decay' then return nil end
    return .28*scale,3.8*scale
end

-- Sweep the bike's horizontal disc against an upright solid. Returns a time
-- fraction and outward normal; no hit tables or temporary vectors are made.
function Obstacles.sweep(x,z,nx,nz,radius,p,bottom,top)
    if bottom and bottom>=p.h+p.collisionHeight then return nil end
    if top and top<=p.h then return nil end
    local dx,dz=nx-x,nz-z
    local ox,oz=x-p.x,z-p.z
    local total=radius+p.collisionRadius
    local a=dx*dx+dz*dz
    local c=ox*ox+oz*oz-total*total
    local b=ox*dx+oz*dz
    local t
    if c<=1e-10 then
        -- A zero-length query intentionally reports overlap for safe spawning
        -- and save restoration. A moving bike may back out of an overlap.
        if a>1e-16 and b>=-1e-12 then return nil end
        t=0
    else
        if a<1e-16 or b>=0 then return nil end
        local discriminant=b*b-a*c
        if discriminant<=1e-12 then return nil end
        t=(-b-math.sqrt(discriminant))/a
        if t<0 or t>1 then return nil end
    end
    local hx,hz=ox+dx*t,oz+dz*t
    local length=math.sqrt(hx*hx+hz*hz)
    if length>1e-8 then return t,hx/length,hz/length end
    if a>1e-16 then local speed=math.sqrt(a);return t,-dx/speed,-dz/speed end
    return t,1,0
end

return Obstacles
