local Layout=require("src.home_layouts")
local Footprint=require("src.floor_footprint")
local Navigation=require("src.navigation")
local Routes={}
function Routes.validate(state,candidate,players)
    local Furniture=require("src.home_furniture")
    local obstacles=Furniture.obstacles(state,candidate.id,candidate)
    for i,o in ipairs(obstacles) do obstacles[i]=Footprint.expand(o,{x=6,y=3}) end
    local assets={getData=function() return Layout.mask(state.home.apartmentId) end}
    local sx,sy=Layout.spawn(state,1)
    if not Navigation.isWalkable(assets,sx,sy,obstacles) then return false,"Leave the entrance clear." end
    local queue={{x=sx,y=sy,gx=0,gy=0}};local visited={["0:0"]=true};local head=1
    while head<=#queue do
        local node=queue[head];head=head+1
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local gx,gy=node.gx+d[1],node.gy+d[2];local key=gx..":"..gy
            if not visited[key] then
                visited[key]=true;local x,y=sx+gx*8,sy+gy*8
                if x>0 and x<960 and y>0 and y<678 and Navigation.isWalkable(assets,x,y,obstacles)
                    and Navigation.canTraverse(assets,node.x,node.y,x,y,obstacles) then
                    queue[#queue+1]={x=x,y=y,gx=gx,gy=gy}
                end
            end
        end
    end
    local function reached(point)
        for _,node in ipairs(queue) do
            if (node.x-point.x)^2+(node.y-point.y)^2<=12^2 and Navigation.canTraverse(assets,node.x,node.y,point.x,point.y,obstacles) then return true end
        end
        return false
    end
    for _,point in ipairs(Furniture.essential(state)) do if not reached(point) then return false,"Keep a walkable route to every entrance, fixture and laptop." end end
    for _,p in ipairs(players or {}) do if p.sceneId=="home" and not reached(p) then return false,"This placement would trap a resident." end end
    local items={candidate}
    for _,item in ipairs(state.home.furniture.items) do if item.id~=candidate.id and item.location=="floor" then items[#items+1]=item end end
    for _,item in ipairs(items) do
        local accessible=false
        for _,point in ipairs(Furniture.approaches(item)) do if reached(point) then accessible=true;break end end
        if not accessible then return false,"Leave an approach beside every piece of furniture." end
    end
    return true
end
return Routes
