-- Screen-space ball physics and the measured face of the portable backboard.
local Trajectory={RADIUS=12,GRAVITY=620,APEX=.62,PERFECT_WINDOW=.012,
    MAX_CHARGE=1.08,RECOVERY=.34,CHARGE_FRAMES=12}
local goal=require("src.breakroom_games").CATALOG.basketball
Trajectory.board={goal.x-20,goal.y-208,goal.x+56,goal.y-233,
    goal.x+59,goal.y-184,goal.x-17,goal.y-157}
Trajectory.rim={x=goal.rimX,y=goal.rimY,halfWidth=12}
-- The rim projects forward from the board. A foreground ball can overlap the
-- board's painted face without being behind its physical plane (2.5D depth).
Trajectory.boardPlaneX=goal.rimX-28
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
function Trajectory.jumpHeight(elapsed)
    local t=clamp((elapsed-.22)/.8,0,1)
    return math.sin(t*math.pi)*23
end
function Trajectory.path(x,y,aimX,height,elapsed)
    local delta=elapsed-Trajectory.APEX
    local endX=Trajectory.rim.x+clamp(aimX or 0,-100,100)+delta*140
    local endY=Trajectory.rim.y
    local rise=clamp(height or 105,45,190)+math.max(0,y-endY)
    -- Choose launch speed from the requested apex, then solve the descending
    -- crossing time. The preview and simulation share these exact velocities.
    local vy=-math.sqrt(2*Trajectory.GRAVITY*rise)
    local duration=(-vy+math.sqrt(vy*vy+2*Trajectory.GRAVITY*(endY-y)))/Trajectory.GRAVITY
    return {x=x,y=y,vx=(endX-x)/duration,vy=vy,duration=duration,
        endX=endX,endY=endY,quality=clamp(1-math.abs(delta)/.16,0,1),
        perfect=math.abs(delta)<=Trajectory.PERFECT_WINDOW}
end
function Trajectory.point(path,t)
    return path.x+path.vx*t,path.y+path.vy*t+.5*Trajectory.GRAVITY*t*t
end
local function inside(x,y)
    local sign
    for i=1,#Trajectory.board,2 do
        local j=i+2>#Trajectory.board and 1 or i+2
        local cross=(Trajectory.board[j]-Trajectory.board[i])*(y-Trajectory.board[i+1])
            -(Trajectory.board[j+1]-Trajectory.board[i+1])*(x-Trajectory.board[i])
        if math.abs(cross)>.00001 then
            local nextSign=cross>0
            if sign~=nil and nextSign~=sign then return false end
            sign=nextSign
        end
    end
    return true
end
function Trajectory.overlapsBoard(x,y,radius)
    if inside(x,y) then return true end
    radius=radius or Trajectory.RADIUS
    for i=1,#Trajectory.board,2 do
        local j=i+2>#Trajectory.board and 1 or i+2
        local ax,ay=Trajectory.board[i],Trajectory.board[i+1]
        local dx,dy=Trajectory.board[j]-ax,Trajectory.board[j+1]-ay
        local t=clamp(((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy),0,1)
        if (x-ax-dx*t)^2+(y-ay-dy*t)^2<=radius^2 then return true end
    end
    return false
end
function Trajectory.sweepBoard(ax,ay,bx,by)
    if Trajectory.overlapsBoard(ax,ay) then
        local nx,ny=Trajectory.boardNormal(ax,ay)
        for i=1,180 do
            local x,y=ax+nx*i*.5,ay+ny*i*.5
            if not Trajectory.overlapsBoard(x,y) then return x,y,0 end
        end
    end
    -- Subdivide every movement by distance, independent of frame duration,
    -- then bisect the first contact. Even a fast long frame cannot tunnel.
    local count=math.max(1,math.ceil(math.sqrt((bx-ax)^2+(by-ay)^2)/2))
    local previous=0
    for i=1,count do
        local t=i/count
        if Trajectory.overlapsBoard(ax+(bx-ax)*t,ay+(by-ay)*t) then
            local lo,hi=previous,t
            for _=1,12 do
                local mid=(lo+hi)/2
                if Trajectory.overlapsBoard(ax+(bx-ax)*mid,ay+(by-ay)*mid) then hi=mid else lo=mid end
            end
            return ax+(bx-ax)*lo,ay+(by-ay)*lo,lo
        end
        previous=t
    end
end
function Trajectory.sweepFlight(ax,ay,bx,by)
    local plane=Trajectory.boardPlaneX+Trajectory.RADIUS
    if ax>plane and bx>plane then return end
    if ax>plane then
        local t=(plane-ax)/(bx-ax)
        ay=ay+(by-ay)*t;ax=plane
        if Trajectory.overlapsBoard(ax,ay) then return plane+.01,ay,1,0 end
    elseif bx>plane then
        local t=(plane-ax)/(bx-ax)
        by=ay+(by-ay)*t;bx=plane
    end
    local hx,hy=Trajectory.sweepBoard(ax,ay,bx,by)
    if hx then
        local nx,ny=Trajectory.boardNormal(hx,hy)
        return hx,hy,nx,ny
    end
end
function Trajectory.boardNormal(x,y)
    local best,normal=math.huge,{1,0}
    for i=1,#Trajectory.board,2 do
        local j=i+2>#Trajectory.board and 1 or i+2
        local ax,ay=Trajectory.board[i],Trajectory.board[i+1]
        local dx,dy=Trajectory.board[j]-ax,Trajectory.board[j+1]-ay
        local t=clamp(((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy),0,1)
        local nx,ny=x-ax-dx*t,y-ay-dy*t
        local length=math.sqrt(nx*nx+ny*ny)
        if length<best and length>.00001 then best,normal=length,{nx/length,ny/length} end
    end
    if inside(x,y) then normal={-normal[1],-normal[2]} end
    return normal[1],normal[2]
end
return Trajectory
