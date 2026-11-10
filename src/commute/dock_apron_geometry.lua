-- Exact dock/queue/stall paint, shared by the terrain and doorway renderers.
local Paint={}
function Paint.build(site)
    local out={}
    if not site.localTruckParkingArea then return out end
    local function vertex(x,z,h)
        out[#out+1]={x,z,h,0,1,0,x/4,z/4,x/4,z/4,0,0,.95,.70,.24,1,0,1,0,1,0,1,0,0}
    end
    local function line(a,b,width,height)
        local ax,az,ah=site:toWorld(a[1],a[2],0)
        local bx,bz,bh=site:toWorld(b[1],b[2],0)
        local dx,dz=bx-ax,bz-az;local length=math.sqrt(dx*dx+dz*dz)
        if length<1e-8 then return end
        local nx,nz=-dz/length*width*.5,dx/length*width*.5
        for _,p in ipairs({{ax+nx,az+nz,ah},{bx+nx,bz+nz,bh},{bx-nx,bz-nz,bh},
            {ax+nx,az+nz,ah},{bx-nx,bz-nz,bh},{ax-nx,az-nz,ah}})do vertex(p[1],p[2],p[3]+height)end
    end
    local area=site.localTruckParkingArea;local inset=.16
    local z0,z1=area.minZ+inset,area.maxZ-inset
    local x0,x1=area.minX+inset,area.maxX-inset
    line({x0,z0},{x1,z0},.075,.065);line({x0,z1},{x1,z1},.075,.065)
    line({x0,z0},{x0,z1},.11,.065);line({x1,z0},{x1,z1},.075,.065)
    local digits={{{.5,-1},{.5,1}},{{-.5,-1},{.5,-1},{.5,0},{-.5,0},{-.5,1},{.5,1}},
        {{-.5,-1},{.5,-1},{.5,0},{-.35,0},{.5,0},{.5,1},{-.5,1}}}
    for index,anchor in ipairs(site.truckQueueAnchors or {})do
        line({anchor.x-1.8,anchor.z+3.1},{anchor.x+1.8,anchor.z+3.1},.085,.07)
        for _,side in ipairs({-1,1}) do
            line({anchor.x+side*1.8,anchor.z-3.1},{anchor.x+side*1.8,anchor.z+3.1},.075,.07)
        end
        local strokes=digits[index]
        for i=2,#(strokes or {}) do
            local a,b=strokes[i-1],strokes[i]
            line({anchor.x+a[1],anchor.z+a[2]},{anchor.x+b[1],anchor.z+b[2]},.14,.075)
        end
    end
    for _,stall in pairs(site.localTruckHomeStalls or {})do
        local a,b,c,d=stall.minX,stall.maxX,stall.minZ,stall.maxZ
        line({a,c},{b,c},.10,.075);line({b,c},{b,d},.10,.075)
        line({b,d},{a,d},.10,.075);line({a,d},{a,c},.10,.075)
    end
    return out
end
return Paint
