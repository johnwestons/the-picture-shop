local Customer = require("src.customer")
local EmployeeAI = require("src.employee_ai")
local Technician = require("src.technician")
local Truck = require("src.truck")

local Test = {}

function Test.run(_, check)
    local visitor = Customer.new({
        character = "tan-cat",
        route = { { x = 0, y = 0 }, { x = 1000, y = 0 } },
        speed = 100,
        initialArrivalDelay = 60,
    })
    visitor.state = "entering"
    visitor.visible = true
    visitor:update(1, { x = 5000, y = 5000 }, false, 0.1)
    check("accelerated_shop_time_does_not_speed_up_client_walking",
        math.abs(visitor.x - 10) < 0.0001 and math.abs(visitor.animationClock - 0.1) < 0.0001)

    local waitingVisitor = Customer.new({
        character = "tan-cat",
        route = { { x = 0, y = 0 }, { x = 100, y = 0 } },
        speed = 100,
        initialArrivalDelay = 60,
    })
    waitingVisitor.state = "waiting"
    waitingVisitor.visible = true
    waitingVisitor:update(1, { x = 5000, y = 5000 }, false, 0.1)
    check("client_wait_deadline_accelerates_while_idle_animation_stays_real_time",
        waitingVisitor.waitTimer == 1 and math.abs(waitingVisitor.idleClock - 0.1) < 0.0001)

    local function employee()
        return { x = 500, y = 500, distance = 0, idleClock = 0,
            intentX = 1, intentY = 0, velocityX = 0, velocityY = 0 }
    end
    local function employeeContext(motionScale)
        return {
            assets = { getData = function() return nil end },
            obstacles = function() return {} end,
            motionScale = motionScale,
        }
    end
    local acceleratedEmployee, normalEmployee = employee(), employee()
    EmployeeAI.move(acceleratedEmployee, { x = 600, y = 500 }, 0.1,
        employeeContext(0.1))
    EmployeeAI.move(normalEmployee, { x = 600, y = 500 }, 0.1,
        employeeContext(1))
    check("employee_walking_uses_real_time_during_shop_acceleration",
        acceleratedEmployee.x > 500 and acceleratedEmployee.x < normalEmployee.x)

    local technicianState = { technicianVisit = {
        kind = "cutter", species = "mouse", status = "entering", visible = true,
        x = 500, y = 500, route = { { x = 500, y = 500 }, { x = 1000, y = 500 } },
        waypoint = 2, animationClock = 0, serviceTimer = 0,
    } }
    Technician.update(1, technicianState, false, 0.1)
    check("technician_walking_uses_real_time_during_shop_acceleration",
        math.abs(technicianState.technicianVisit.x - 507.8) < 0.0001
        and math.abs(technicianState.technicianVisit.animationClock - 0.1) < 0.0001)

    local truck = Truck.new({
        scheduleDelay = 0.2,
        backingDuration = 2.2,
        cargoDuration = 0.75,
        start = { x = 0, y = 0, scale = 1 },
        parked = { x = 100, y = 0, scale = 1 },
        interaction = { x = 50, y = 0, radius = 20 },
        obstacle = { offsetX = 0, offsetY = 0, radius = 20 },
    })
    truck:schedule("TIME-SCALE-TEST", "delivery")
    local scheduledEvent = truck:update(2, "closed", 0.2)
    local backingEvent = truck:update(0, "open", 0)
    truck:update(2, "open", 0.2)
    check("truck_schedule_accelerates_but_backing_uses_real_time",
        scheduledEvent == "request_bay_open" and backingEvent == "backing_started"
        and truck.state == "backing" and math.abs(truck.backingProgress - (0.2 / 2.2)) < 0.0001)

    truck.state = "parked_closed"
    truck.backingProgress = 1
    truck:toggleCargoDoor()
    truck:update(2, "open", 0.2)
    check("truck_cargo_door_animation_uses_real_time",
        truck.state == "cargo_opening" and math.abs(truck.cargoProgress - (0.2 / 0.75)) < 0.0001)
end

return Test
