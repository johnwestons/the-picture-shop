local Customer = require("src.customer")
local Config = require("src.config")
local State = require("src.state")
local Navigation = require("src.navigation")
local Camera = require("src.mobile_camera")
local Viewport = require("src.viewport")
local Test = {}
local function near(a,b) return math.abs(a-b)<.01 end

local function capture(context,state,name,width,height,mobile)
    if not os.getenv("PICTURE_SHOP_SEATING_CAPTURE_DIR") then return end
    width,height=width or 960,height or 678
    local canvas=love.graphics.newCanvas(width,height)
    local dimensions=love.graphics.getDimensions
    love.graphics.getDimensions=function() return width,height end
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true})
    love.graphics.clear(.04,.05,.07,1)
    Viewport.beginDraw(960,678,not mobile)
    local camera
    if mobile then
        camera=Camera.new({enabled=true,followOffsetY=-38})
        local bounds=Viewport.gameBounds(960,678)
        camera:setViewport(bounds.width,bounds.height);camera:selectView("world",true)
        camera:setFollowTarget({x=765,y=240});camera:zoomBy(1)
        for _=1,120 do camera:update(1/60) end
        camera:beginDraw()
    end
    context.world.draw(context.assets,context.characterAssets,state,nil,nil,{})
    if camera then camera:endDraw() end
    Viewport.endDraw();love.graphics.pop();love.graphics.getDimensions=dimensions
    local data=canvas:newImageData();local bytes=data:encode("png"):getString()
    data:release();canvas:release()
    local file=assert(io.open(os.getenv("PICTURE_SHOP_SEATING_CAPTURE_DIR").."/"..name..".png","wb"))
    file:write(bytes);file:close()
end

local function visitorAt(index,character)
    local visitor=Customer.new(Config.customer)
    for _=2,index do visitor:reset(false) end
    visitor.character=character;visitor.timer=0
    return visitor
end

local function seating(context,check)
    local world,assets=context.world,context.characterAssets
    local state=State.new();state.screen="world";state.employment.recruiting=false
    world.vendor=Customer.new(Config.vendor)
    world.player.x,world.player.y=100,600
    local map=require("src.warehouse_registration")
    local noTable=true
    for _,shape in ipairs(map.furniture) do if shape.kind=="lobby_table" then noTable=false end end
    check("client_seating_removed_coffee_table_has_no_collision",noTable)
    check("client_seating_removed_coffee_table_cannot_erase_legs",
        not map.lobbyForegrounds["sofa-left"] and not map.lobbyForegrounds["sofa-right"])
    local floor=world.employeeContext(state,context.assets).assets
    check("client_seating_former_coffee_table_front_is_walkable",
        Navigation.isWalkable(floor,765,216,map.obstacles("warehouse"))
        and Navigation.isWalkable(floor,765,201,map.obstacles("warehouse")))
    for _,character in ipairs(Config.customer.characterPool) do
        for index,seat in ipairs(Config.customer.seatSpots) do
            local visitor=visitorAt(index,character);world.customer=visitor
            local ctx=world.employeeContext(state,context.assets)
            for _=1,350 do
                visitor:update(.1,nil,false,.1,ctx)
                if visitor.state=="waiting" then break end
            end
            local label=character.."_"..seat.name
            check("client_seating_"..label.."_reaches_seat",visitor.state=="waiting")
            visitor.idleClock=.5
            local pose=visitor:renderPose(assets)
            local _,top,_,bottom=assets.getVisibleBounds(character,"sit",1)
            check("client_seating_"..label.."_fits_cushion",pose.action=="sit"
                and near(pose.x,seat.seatedPose.x) and near(pose.y,seat.seatedPose.y)
                and pose.mirror==seat.seatedPose.mirror and near((bottom-top)*pose.scale,54))
            local logicalX,logicalY=visitor.x,visitor.y
            visitor.idleClock=2/visitor.idleAnimationRate-.07
            local blink=visitor:renderPose(assets)
            local _,_,_,blinkBottom=assets.getVisibleBounds(character,"sit",2)
            check("client_seating_"..label.."_blinks_without_sliding",pose.frame==1 and blink.frame==2
                and near(pose.x,blink.x) and near(pose.y,blink.y)
                and pose.anchorX==blink.anchorX and pose.anchorY==blink.anchorY
                and math.abs(bottom-blinkBottom)*pose.scale<.3
                and visitor.x==logicalX and visitor.y==logicalY)
            visitor.idleClock=.5
            capture(context,state,label)
            check("client_seating_"..label.."_review_stays_seated",visitor:beginReview()
                and visitor:renderPose(assets).action=="sit"
                and near(visitor:renderPose(assets).y,seat.seatedPose.y))
            local guest=Customer.new(Config.customer)
            local applied=guest:applySnapshot(visitor:snapshot())
            local guestPose=guest:renderPose(assets)
            check("client_seating_"..label.."_guest_matches_host",applied and guestPose.action==pose.action
                and guestPose.frame==pose.frame and guestPose.mirror==pose.mirror
                and near(guestPose.x,pose.x) and near(guestPose.y,pose.y) and near(guestPose.scale,pose.scale))
            visitor:resolve("accepted")
            local standing=visitor:renderPose(assets)
            check("client_seating_"..label.."_stands_on_clear_floor",visitor.state=="exiting"
                and standing.action~="sit" and standing.x==visitor.x and standing.y==visitor.y
                and Navigation.isWalkable(ctx.assets,visitor.x,visitor.y,ctx.obstacles(visitor)))
            for _=1,350 do visitor:update(.1,nil,false,.1,ctx);if not visitor.visible then break end end
            check("client_seating_"..label.."_leaves_normally",not visitor.visible)
        end
    end
    -- Both couch positions face the room, regardless of their approach direction.
    world.customer=visitorAt(2,"business-dragon");world.vendor=visitorAt(3,"business-cat")
    for _,visitor in ipairs({world.customer,world.vendor}) do
        visitor.state,visitor.visible="waiting",true
        visitor.x,visitor.y=visitor.seat.x,visitor.seat.y;visitor.idleClock=.5
    end
    check("client_seating_two_couch_clients_face_same_direction",
        world.customer:renderPose(assets).mirror==1 and world.vendor:renderPose(assets).mirror==1)
    capture(context,state,"couch-desktop",1440,1080)
    capture(context,state,"couch-mobile",1440,810,true)
    capture(context,state,"couch-neutral")
    world.customer.idleClock,world.vendor.idleClock=2/.65-.07,2/.65-.07
    capture(context,state,"couch-blink")
end

function Test.run(context,check)
    local world=context.world
    local fields={"player","customer","vendor","_state","_assets","selectedInteraction","_employeeOptions"}
    local before={};for _,key in ipairs(fields) do before[key]=world[key] end
    world.player={id=1,x=100,y=600,sceneId="warehouse",character="rabbit-worker",idleClock=0,
        animationDistance=0,facing=1,intentX=0,intentY=-1,velocityX=0,velocityY=0,moving=false,interactionClock=0}
    world._employeeOptions={};world.selectedInteraction=nil
    local okay,reason=xpcall(function() seating(context,check) end,debug.traceback)
    for _,key in ipairs(fields) do world[key]=before[key] end
    assert(okay,reason)
end
return Test
