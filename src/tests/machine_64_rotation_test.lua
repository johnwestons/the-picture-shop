local Config=require("src.config")
local MachinePose=require("src.machine_pose")
local Rotation=require("src.machine_rotation")
local CutterPlacement=require("src.cutter_placement")
local WrapperPlacement=require("src.wrapper_placement")
local WindmillPlacement=require("src.windmill_placement")

local Test={}
local machines={
    {kind="cutter",image="polarDirections",quadPrefix="polarDirection",
        placement=CutterPlacement,config=Config.cutterPlacement,frameSize=384},
    {kind="wrapper",image="skidWrapper64Directions",quadPrefix="skidWrapper64Direction",
        placement=WrapperPlacement,config=Config.wrapperPlacement,frameSize=256},
    {kind="windmill",image="windmillDirections",quadPrefix="windmillDirection",
        placement=WindmillPlacement,config=Config.windmillPlacement,frameSize=256},
}
local candidateAtlases={
    "assets/generated/polar-cutter-64-v2.png",
    "assets/generated/skid-wrapper-64-v1.png",
    "assets/generated/loaded-paper-pallet-64-v1.png",
    "assets/generated/pallet-jack-64-v1.png",
    "assets/generated/pallet-jack-loaded-64-v1.png",
    "assets/generated/empty-pallet-64-v1.png",
    "assets/generated/printing-press-64-v1.png",
    "assets/generated/heidelberg-windmill-64-v1.png",
}

local function pose(kind,frame,x)
    return {x=x,y=20,direction=Rotation.directionForFrame(kind,frame),
        rotationIndex=frame,moving=false,inMotion=false}
end

function Test.run(context,check)
    local candidatesPresent=true
    for _,path in ipairs(candidateAtlases) do
        candidatesPresent=candidatesPresent and love.filesystem.getInfo(path,"file")~=nil
    end
    check("machine_64_candidate_atlases_are_in_the_runtime_package",candidatesPresent)

    for _,machine in ipairs(machines) do
        local image=context.assets.get(machine.image)
        local columns=machine.config.frameColumns
        local size=machine.config.frameSize
        local width,height=0,0
        if image then width,height=image:getDimensions() end
        local atlasValid=image~=nil and machine.config.frameCount==64
            and columns==8 and size==machine.frameSize
            and width==columns*size and height==8*size
        local quadsValid=atlasValid
        local framesResolve=atlasValid
        for frame=1,64 do
            local quad=context.assets.getQuad(machine.quadPrefix..frame)
            quadsValid=quadsValid and quad~=nil and quad.width==size and quad.height==size
            local direction=Rotation.directionForFrame(machine.kind,frame)
            local framePose={direction=direction,rotationIndex=frame}
            framesResolve=framesResolve and direction~=nil
                and Rotation.frameFor(machine.kind,framePose)==frame
                and machine.placement.rotationFrameFor(framePose)==frame
        end
        check("machine_64_atlas_and_all_quads_"..machine.kind,atlasValid and quadsValid)
        check("machine_64_rotation_selects_each_frame_"..machine.kind,framesResolve)

        local state={}
        state[machine.kind]=machine.placement.defaultState(machine.config)
        local advances=true
        local rotationFailure
        for step=1,64 do
            local expected=step%64+1
            local ok,direction,frame=machine.placement.rotate(state,machine.config)
            local placement=state[machine.kind]
            local stepValid=ok and frame==expected
                and placement.rotationIndex==expected
                and direction==Rotation.directionForFrame(machine.kind,expected)
            if not stepValid and not rotationFailure then
                rotationFailure=string.format("step=%d expected=%d got=%s state=%s/%s",
                    step,expected,tostring(frame),tostring(placement.rotationIndex),tostring(direction))
            end
            advances=advances and stepValid
        end
        check("machine_64_rotation_completes_and_wraps_"..machine.kind,advances,rotationFailure)
    end

    local source={
        cutter=pose("cutter",37,10),
        wrapper=pose("wrapper",41,20),
        windmill=pose("windmill",52,30),
    }
    local normalized=MachinePose.normalize(source)
    check("machine_64_poses_survive_network_normalization",
        normalized~=nil and normalized.cutter.rotationIndex==37
            and normalized.wrapper.rotationIndex==41
            and normalized.windmill.rotationIndex==52
            and normalized.cutter.direction==source.cutter.direction
            and normalized.wrapper.direction==source.wrapper.direction
            and normalized.windmill.direction==source.windmill.direction)
end

return Test
