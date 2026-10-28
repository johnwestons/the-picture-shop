-- Bounded presentation only: gait phase, continuous turn heading and idle clock.
local Config=require("src.config")
local Codec=require("src.net.codec")
local Pose={CYCLE_DISTANCE=(Config.palletJack.gaitPixelsPerFrame or 20)*8}
local TAU=math.pi*2
local IDLE_PERIOD=2/.65
local function integer(value,maximum)
    return type(value)=="number" and value==math.floor(value) and value>=0 and value<=maximum
end
function Pose.headingForRender(heading)
    return (math.floor((heading%TAU)*10000+.5)%62832)/10000
end
function Pose.normalize(value)
    if type(value)~="table" or #value~=3 then return nil end
    local count=0
    for key in pairs(value) do
        if not integer(key,3) or key==0 then return nil end
        count=count+1
    end
    if count~=3 or not integer(value[1],Pose.CYCLE_DISTANCE*100-1)
        or not integer(value[2],62831) or not integer(value[3],3076) then return nil end
    return Codec.array({value[1],value[2],value[3]})
end
function Pose.capture(distance,heading,clock)
    return Codec.array({math.floor((distance%Pose.CYCLE_DISTANCE)*100+.5)%(Pose.CYCLE_DISTANCE*100),
        math.floor(Pose.headingForRender(heading)*10000+.5),
        math.floor((clock%IDLE_PERIOD)*1000)})
end
return Pose
