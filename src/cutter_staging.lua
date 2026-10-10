local Config=require("src.config")
local StagingAreas=require("src.staging_areas")
local Staging={}
function Staging.slots(state)
    local area=StagingAreas.findById(state,"cutter-output")
    if area then return StagingAreas.positions(area) end
    local c=Config.cutterStaging
    local slots={}
    for row=1,c.rows do for column=1,c.columns do
        slots[#slots+1]={number=#slots+1,x=c.firstX+(column-1)*c.columnSpacing,
            y=c.firstY+(row-1)*c.rowSpacing,direction=c.direction,rotation=1}
    end end
    return slots
end
function Staging.find(isClear,state,machineId)
    return StagingAreas.findMachineOutput(state,machineId,isClear,false)
end
function Staging.draw(state) StagingAreas.draw(state) end
return Staging
