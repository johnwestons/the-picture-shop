local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Hiring=require("src.screens.hiring_screen")
local Contracts=require("src.employment_contracts")
local Test={}

local function acceptedApplicant(state)
    local applicant=assert(Employees.createApplicant(state,0))
    assert(Employees.requestResume(state,applicant.id,0))
    Employees.advance(state,.5)
    local startHour=applicant.shiftPreference=="night" and 20 or 8
    local endHour=(startHour+8)%24
    local sent,message=Employees.command(state,{kind="offer_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision,wageCents=2500,days=31,startHour=startHour,endHour=endHour},.5)
    assert(sent,message)
    Employees.advance(state,1.25)
    assert(applicant.status=="offer_accepted")
    return applicant
end

local function sign(state,applicant)
    return Employees.command(state,{kind="hire_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision},1.25)
end

function Test.run(_,check)
    local state=State.new()
    for _=1,Employees.MAX_STAFF do
        local applicant=acceptedApplicant(state)
        local hired,message=sign(state,applicant)
        assert(hired,message)
    end
    check("employee_capacity_allows_one_per_unique_character",
        Employees.employedCount(state)==Employees.MAX_STAFF and Employees.valid(state.employment)
        and Schema.snapshot(state)~=nil)

    local unavailable=Employees.createApplicant(state,4)
    local capacityLabel=("%d/%d employees"):format(Employees.MAX_STAFF,Employees.MAX_STAFF)
    check("employee_capacity_exhausts_the_unique_roster",
        unavailable==nil and #require("src.worker_catalog").availableProfiles(state.employment)==0
        and Hiring.employeeCountText(state)==capacityLabel.." — unique roster full")

    local duplicate=Schema.copy(state.employment.applications[1])
    duplicate.id="APP-DUPLICATE-CHARACTER"
    duplicate.status="offer_accepted"
    duplicate.employeeId=nil
    duplicate.revision=1
    duplicate.offer=Contracts.terms(2500,31,9,17)
    state.employment.applications[#state.employment.applications+1]=duplicate
    local sent
    local ui=Hiring.new()
    ui.selectedId=duplicate.id
    local signX,signY=Hiring.buttonCenter("sign")
    local uiResult=Hiring.mousepressed(state,ui,signX,signY,function(intent)
        sent=intent
        return {action="sent"}
    end,false)
    local hired,hireReason=sign(state,duplicate)
    check("employee_capacity_blocks_another_hire_in_ui_and_authority",
        uiResult and uiResult.action=="blocked" and sent==nil and not hired
        and tostring(hireReason):find("already on the employee roster",1,true)~=nil
        and Employees.employedCount(state)==Employees.MAX_STAFF)

    duplicate.status="withdrawn"
    state.employment.staff[1].status="dismissed"
    local replacement=acceptedApplicant(state)
    local replacementHired=sign(state,replacement)
    check("employee_capacity_reopens_one_slot_after_dismissal",
        replacementHired and Employees.employedCount(state)==Employees.MAX_STAFF
        and replacement.status=="hired" and Schema.snapshot(state)~=nil)
end

return Test
