local Body=require('src.commute.first_person_bike')
local FP=require('src.commute.first_person_camera')
local Test={}
function Test.run(check)
    local image=love.image.newImageData(Body.PATH)
    local function alpha(x,y)local _,_,_,a=image:getPixel(x,y);return a end
    check('first_person_bike_complete_transparent_sprite',image:getWidth()==1024 and image:getHeight()==1536
        and alpha(0,0)==0 and alpha(100,800)==0 and alpha(512,25)>.8
        and alpha(512,850)>.8 and alpha(512,1500)>.8 and alpha(512,1535)==0)
    image:release()
    local camera={bikeHeading=.7,viewHeading=.7,headPitch=0,focal=640/math.tan(math.rad(FP.FOV)*.5)}
    local function project(x,y)
        local forward,height,right=Body.point(x,y)
        return FP.screen(Body.camera(camera),forward,right,height)
    end
    local x,baseY=project(511,235)
    check('first_person_bike_instruments_registered_forward',math.abs(x-640)<2 and baseY>600 and baseY<750)
    camera.viewHeading=.7+math.rad(30);camera.headPitch=math.rad(10)
    local rx,ry=project(511,235)
    camera.viewHeading=.7-math.rad(30);camera.headPitch=math.rad(-10)
    local lx,ly=project(511,235)
    check('first_person_bike_geometry_stays_with_bike_during_head_look',rx<300 and ry>baseY and lx>980 and ly<baseY)
    camera.viewHeading=.7;camera.headPitch=-math.pi/2
    local sx,sy,sd=project(512,880)
    check('first_person_bike_seat_visible_when_looking_straight_down',math.abs(sx-640)<2 and sy>200 and sy<700 and sd>FP.NEAR)
    camera.viewHeading=.7+math.pi;camera.headPitch=math.rad(-65)
    local bx,by,bd=project(512,1100)
    local _,_,frontDepth=project(511,235)
    check('first_person_bike_rear_rack_visible_without_front_flipping',math.abs(bx-640)<2 and by>100 and by<700
        and bd>FP.NEAR and frontDepth<FP.NEAR)
end
return Test
