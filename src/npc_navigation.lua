-- Shared, transient navigation for every autonomous walking actor. Routes and
-- retry clocks deliberately stay out of saves and network snapshots.
local Navigation = require("src.navigation")
local Config = require("src.config")
local Navigator = {}
local routes = setmetatable({}, { __mode = "k" })
local STEP, RETRY, STALL = 10, .75, .9
local directions = {{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{-1,-1},{1,-1}}

local function distance(a, b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end
local function push(heap, node)
    local index = #heap + 1
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap[parent].f <= node.f then break end
        heap[index] = heap[parent]; index = parent
    end
    heap[index] = node
end
local function pop(heap)
    local result, last = heap[1], table.remove(heap)
    if #heap > 0 then
        local index = 1
        while index * 2 <= #heap do
            local child = index * 2
            if child < #heap and heap[child+1].f < heap[child].f then child = child+1 end
            if heap[child].f >= last.f then break end
            heap[index] = heap[child]; index = child
        end
        heap[index] = last
    end
    return result
end

function Navigator.findPath(actor, candidates, context)
    local obstacles = context.obstacles(actor)
    local goals = {}
    for _, goal in ipairs(candidates or {}) do
        if Navigation.isWalkable(context.assets, goal.x, goal.y, obstacles) then
            goals[#goals+1] = goal
        end
    end
    if #goals == 0 then return nil end
    local function clear(a, b, recover)
        return Navigation.canTraverse(context.assets, a.x, a.y, b.x, b.y, obstacles, recover)
    end
    -- The usual case needs no grid search at all.
    for _, goal in ipairs(goals) do
        if clear(actor, goal) then return {{x=goal.x,y=goal.y}}, goal end
    end
    local columns = math.floor(Config.baseWidth / STEP) + 1
    local function key(x, y) return y * columns + x + 1 end
    local function heuristic(x, y)
        local best = math.huge
        for _, goal in ipairs(goals) do
            best = math.min(best, math.sqrt((x-goal.x)^2+(y-goal.y)^2))
        end
        return best
    end
    local heap, scores, closed, walkable = {}, {}, {}, {}
    local function walk(x, y)
        if x < 0 or y < 0 or x * STEP >= Config.baseWidth or y * STEP >= Config.baseHeight then return false end
        local id = key(x,y)
        if walkable[id] == nil then
            walkable[id] = Navigation.isWalkable(context.assets,x*STEP,y*STEP,obstacles)
        end
        return walkable[id]
    end
    -- Connect from the real position, not a rounded cell on the other side of
    -- a wall. These same connectors let embedded actors walk out of overlaps.
    local sx, sy = math.floor(actor.x/STEP+.5), math.floor(actor.y/STEP+.5)
    for ox=-3,3 do for oy=-3,3 do
        local x,y=sx+ox,sy+oy
        local node={x=x*STEP,y=y*STEP,id=key(x,y),gx=x,gy=y}
        if walk(x,y) and distance(actor,node)<=32 and clear(actor,node,true) then
            node.g=distance(actor,node);node.f=node.g+heuristic(node.x,node.y)
            scores[node.id]=node.g;push(heap,node)
        end
    end end
    local target, selected, visited
    visited=0
    while #heap>0 and visited<10000 do
        local node=pop(heap)
        if not closed[node.id] then
            closed[node.id]=true;visited=visited+1
            for _,goal in ipairs(goals) do
                if distance(node,goal)<=STEP*2 and clear(node,goal) then
                    target,selected=node,goal;break
                end
            end
            if target then break end
            for _,d in ipairs(directions) do
                local x,y=node.gx+d[1],node.gy+d[2]
                local id=key(x,y)
                local diagonal=d[1]~=0 and d[2]~=0
                if not closed[id] and walk(x,y)
                    and (not diagonal or (walk(node.gx,y) and walk(x,node.gy))) then
                    local nextNode={x=x*STEP,y=y*STEP,gx=x,gy=y,id=id,parent=node}
                    local cost=node.g+(diagonal and STEP*math.sqrt(2) or STEP)
                    if (not scores[id] or cost<scores[id]) and clear(node,nextNode) then
                        scores[id]=cost;nextNode.g=cost
                        nextNode.f=cost+heuristic(nextNode.x,nextNode.y);push(heap,nextNode)
                    end
                end
            end
        end
    end
    if not target then return nil end
    local reverse={{x=selected.x,y=selected.y}}
    while target do
        reverse[#reverse+1]={x=target.x,y=target.y};target=target.parent
    end
    local points={}
    for index=#reverse,1,-1 do points[#points+1]=reverse[index] end
    -- String pulling keeps motion natural while retaining collision-safe turns.
    local smooth, origin, index={},actor,1
    while index<=#points do
        local last=index
        for nextIndex=index+1,#points do
            if clear(origin,points[nextIndex],#smooth==0) then last=nextIndex end
        end
        smooth[#smooth+1]=points[last];origin=points[last];index=last+1
    end
    return smooth,selected
end

function Navigator.reset(actor) routes[actor]=nil end
function Navigator.status(actor)
    local route=routes[actor]
    return route and route.status or "idle",route and route.failures or 0
end
function Navigator.findReachablePoint(actor, goals, context)
    local points,goal=Navigator.findPath(actor,goals,context)
    if not points then return nil end
    routes[actor]={points=points,index=1,goal={x=goal.x,y=goal.y},retry=0,
        stalled=0,failures=0,status="walking"}
    return {x=goal.x,y=goal.y}
end

local function prepare(actor,goal,dt,context,obstacles)
    local route=routes[actor]
    if not route or distance(route.goal,goal)>.01 then
        route={goal={x=goal.x,y=goal.y},retry=0,stalled=0,failures=0,status="planning"}
        routes[actor]=route
    end
    route.retry=math.max(0,route.retry-dt)
    local target=route.points and route.points[route.index]
    if route.points and not target then route.points=nil;route.retry=0 end
    if target and not Navigation.canTraverse(context.assets,actor.x,actor.y,target.x,target.y,obstacles,true) then
        route.points=nil;route.retry=0;route.status="replanning"
    end
    if route.last and distance(actor,route.last)>32 then
        route.points=nil;route.retry=0 -- pushed aside, restored or took a wrong turn
    end
    if route.stalled>=STALL then
        route.points=nil;route.retry=0;route.stalled=0;route.status="replanning"
    end
    if not route.points and route.retry<=0 then
        route.points=Navigator.findPath(actor,{goal},context)
        route.index=1;route.retry=RETRY
        if not route.points then
            route.failures=route.failures+1;route.status="unreachable"
        else
            route.status="walking"
        end
    end
    return route
end

-- Consume actual world distance. Gait/acceleration remain the caller's choice.
-- No waypoint is considered reached merely because the actor is near it on
-- the opposite side of a wall, and no movement step skips over a collider.
function Navigator.travel(actor,goal,budget,dt,context)
    dt=math.max(0,dt or 0);budget=math.max(0,budget or 0)
    local obstacles=context.obstacles(actor)
    if distance(actor,goal)<.01 and Navigation.isWalkable(context.assets,goal.x,goal.y,obstacles) then
        local route=routes[actor];if route then route.status="arrived" end
        return true,budget,0,false
    end
    local route=prepare(actor,goal,dt,context,obstacles)
    if not route.points then return false,0,0,route.failures>=2 end
    local lastMotionX,lastMotionY
    local target=route.points[route.index]
    local before=target and distance(actor,target) or 0
    local travelled=0
    while budget>0 and target do
        local length=distance(actor,target)
        local amount=math.min(budget,length)
        local nx,ny=target.x,target.y
        if length>amount then
            nx=actor.x+(target.x-actor.x)/length*amount
            ny=actor.y+(target.y-actor.y)/length*amount
        end
        if not Navigation.canTraverse(context.assets,actor.x,actor.y,nx,ny,obstacles,true) then
            -- An invalid mask start must reach open floor as one short checked
            -- connector. Check its entire escape, then take a bounded step.
            if Navigation.isWalkable(context.assets,actor.x,actor.y,{})
                or not Navigation.canTraverse(context.assets,actor.x,actor.y,target.x,target.y,obstacles,true) then
                route.points=nil;route.retry=0;break
            end
        end
        if amount>.001 then lastMotionX,lastMotionY=(nx-actor.x)/amount,(ny-actor.y)/amount end
        actor.x,actor.y=nx,ny;budget=budget-amount;travelled=travelled+amount
        if length>amount then break end
        route.index=route.index+1;route.stalled=0
        target=route.points[route.index];before=target and distance(actor,target) or 0
    end
    -- Track progress toward the current waypoint, not just any displacement;
    -- oscillation or sideways sliding therefore cannot reset the stuck timer.
    local progress=target and before-distance(actor,target) or travelled
    if progress>.05 then route.stalled=0;route.failures=0
    else route.stalled=route.stalled+dt end
    route.last={x=actor.x,y=actor.y}
    if lastMotionX then
        actor.intentX,actor.intentY=lastMotionX,lastMotionY
        if math.abs(lastMotionX)>.08 then actor.facing=lastMotionX<0 and -1 or 1 end
    end
    local reached=distance(actor,goal)<.01
    route.status=reached and "arrived" or route.status
    return reached,budget,travelled,route.failures>=2
end

return Navigator
