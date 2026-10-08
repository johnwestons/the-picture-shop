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
    check("employee_capacity_allows_ten_active_payroll_records",
        Employees.employedCount(state)==10 and Employees.valid(state.employment)
        and Schema.snapshot(state)~=nil)

    local eleventh=acceptedApplicant(state)
    local sent
    local ui=Hiring.new()
    ui.selectedId=eleventh.id
    local signX,signY=Hiring.buttonCenter("sign")
    local uiResult=Hiring.mousepressed(state,ui,signX,signY,function(intent)
        sent=intent
        return {action="sent"}
    end,false)
    local hired,hireReason=sign(state,eleventh)
    check("employee_capacity_blocks_eleventh_hire_in_ui_and_authority",
        uiResult and uiResult.action=="blocked" and sent==nil and not hired
        and tostring(hireReason):find("10/10 employees",1,true)~=nil
        and Employees.employedCount(state)==10)
    check("employee_capacity_counter_shows_full_payroll",Hiring.employeeCountText(state)=="10/10 employees — payroll full")

    local overLimit=Schema.copy(state.employment)
    local extra=Schema.copy(overLimit.staff[1])
    extra.id="EMP-OVERLIMIT"
    overLimit.staff[#overLimit.staff+1]=extra
    check("employee_capacity_rejects_over_limit_save_state",not Employees.valid(overLimit))

    state.employment.staff[1].status="dismissed"
    local replacementHired=sign(state,eleventh)
    check("employee_capacity_reopens_one_slot_after_dismissal",
        replacementHired and Employees.employedCount(state)==10
        and eleventh.status=="hired" and Schema.snapshot(state)~=nil)
end

return Test
