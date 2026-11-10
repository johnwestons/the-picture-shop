-- Stress a late-game receiving surge through the same job, purchasing,
-- delivery-traffic, pallet-unload and employee-simulation paths as gameplay.
local Test = {}

local Calendar = require("src.business_calendar")
local Employees = require("src.employees")
local EmployeeAI = require("src.employee_ai")
local Logistics = require("src.pallet_logistics")
local Network = require("src.commute.delivery_traffic")
local Town = require("src.commute.town")

local STAFF_COUNT = Employees.MAX_STAFF
local JOB_COUNT = 12
local VENDOR_TRUCK_COUNT = 12
local PALLETS_PER_JOB = 5

local function hireAll(state, now)
    for _ = 1, STAFF_COUNT do
        local applicant = assert(Employees.createApplicant(state, now))
        assert(Employees.requestResume(state, applicant.id, now))
        Employees.advance(state, now + .5)
        local startHour = applicant.shiftPreference == "night" and 20 or 8
        local sent, message = Employees.command(state, {
            kind = "offer_employee", applicationId = applicant.id,
            expectedRevision = applicant.revision, wageCents = 2500,
            days = 31, startHour = startHour, endHour = (startHour + 8) % 24,
        }, now + .5)
        assert(sent, message)
        Employees.advance(state, now + 1.25)
        local hired, hireMessage = Employees.command(state, {
            kind = "hire_employee", applicationId = applicant.id,
            expectedRevision = applicant.revision,
        }, now + 1.25)
        assert(hired, hireMessage)
    end
end

local function deliveryEntries(state)
    local entries = {}
    for _, shipment in ipairs(state.procurement.shipments or {}) do
        entries[#entries + 1] = { id = shipment.id, delivery = shipment.delivery, shipment = shipment }
    end
    for _, job in ipairs(state.jobs.active or {}) do
        if job.delivery then entries[#entries + 1] = { id = job.id, delivery = job.delivery, job = job } end
    end
    return entries
end

local function activeLeaders(entries)
    local result = {}
    for _, entry in ipairs(entries) do
        local route = entry.delivery and entry.delivery.route
        if route and not route.transportId and type(route.departedAtEpoch) == "number"
            and entry.delivery.status ~= "received" then
            result[#result + 1] = entry
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function pendingPallets(state, entries)
    local total = 0
    for _, entry in ipairs(entries) do
        if entry.job then
            for _, pallet in ipairs(entry.job.pallets or {}) do
                if pallet.location == "awaiting_delivery" then total = total + 1 end
            end
        elseif entry.shipment then
            for _, orderId in ipairs(entry.shipment.orderIds or {}) do
                local order = require("src.procurement").orderById(state, orderId)
                if order then
                    for _, pallet in ipairs(order.pallets or {}) do
                        if pallet.location == "awaiting_delivery" then total = total + 1 end
                    end
                end
            end
        end
    end
    return total
end

local function vendorOrders(state, shipment)
    local wanted, result = {}, {}
    for _, id in ipairs(shipment.orderIds or {}) do wanted[id] = true end
    for _, order in ipairs(state.procurement.orders or {}) do
        if wanted[order.id] then result[#result + 1] = order end
    end
    return result
end

local function moveOffDock(pallet, index, lanes, occupied)
    local world = assert(pallet.world)
    local function clear(x, y)
        for _, lane in ipairs(lanes) do
            if (x - lane.x)^2 + (y - lane.y)^2 <= 50^2 then return false end
        end
        for _, point in ipairs(occupied) do
            if (x - point.x)^2 + (y - point.y)^2 <= 38^2 then return false end
        end
        return true
    end
    local selectedX, selectedY
    for y = 96, 620, 44 do
        for x = 72, 888, 52 do
            if clear(x, y) then selectedX, selectedY = x, y; break end
        end
        if selectedX then break end
    end
    assert(selectedX, "no clear staging point for delivered pallet " .. tostring(index))
    world.x, world.y = selectedX, selectedY
    world.fromX, world.fromY = selectedX, selectedY
    world.spawnProgress = 1
    occupied[#occupied + 1] = { x = selectedX, y = selectedY }
end

local function unloadEntry(state, entry, epoch, lanes, origin, moved)
    assert(Network.arrived(entry.delivery, epoch), "truck did not reach the dock: " .. entry.id)
    if entry.job then
        for _, pallet in ipairs(entry.job.pallets or {}) do
            if pallet.location == "awaiting_delivery" then
                local ok, result = Logistics.unload(state, entry.job.id, pallet.id, lanes, origin)
                assert(ok, result)
                moved.count = moved.count + 1
                moveOffDock(result, moved.count, lanes, moved.positions)
            end
        end
    else
        for _, order in ipairs(vendorOrders(state, entry.shipment)) do
            for _, pallet in ipairs(order.pallets or {}) do
                if pallet.location == "awaiting_delivery" then
                    local ok, result = Logistics.unload(state, order.id, pallet.id, lanes, origin)
                    assert(ok, result)
                    moved.count = moved.count + 1
                    moveOffDock(result, moved.count, lanes, moved.positions)
                end
            end
        end
    end
end

local function finitePosition(actor)
    return actor and type(actor.x) == "number" and actor.x == actor.x
        and math.abs(actor.x) < math.huge and type(actor.y) == "number"
        and actor.y == actor.y and math.abs(actor.y) < math.huge
end

function Test.run(context, check)
    local state = context.State.new()
    state.calendar = Calendar.dateFromTotalDay(1001)
    state.calendar.secondsPerDay = 1200
    state.calendar.elapsed = 0
    state.home.weekend = state.home.weekend or {}
    state.home.weekend.phase = "working"
    state.employment.recruiting = false
    state.money = 1000000

    local now = Calendar.absoluteHours(state)
    hireAll(state, now)
    for _, worker in ipairs(state.employment.staff) do
        worker.contract.startDay = state.calendar.totalDays
        worker.contract.days = 31
        worker.contract.startHour, worker.contract.endHour = 4, 16
    end
    check("late_game_load_hires_full_ten_person_staff", Employees.employedCount(state) == STAFF_COUNT)

    for index = 1, JOB_COUNT do
        local job = assert(context.jobs.createOffer({
            id = string.format("LOAD-SURGE-JOB-%02d", index),
            company = "Late Game Print Client " .. index,
            sourceSize = { width = 20, height = 16 },
            finishedSize = { width = 10, height = 8 },
            sheetCounts = { 500, 600, 700, 800, 900 },
            packaging = "flat",
            stockSpec = { suppliedBy = "client" },
        }))
        local accepted, message = context.jobService.acceptOffer(state, job, now)
        assert(accepted, message)
        job.delivery.readyAtHours = Calendar.absoluteHours(state) + 12.2
    end

    for _ = 1, VENDOR_TRUCK_COUNT do
        state.calendar.elapsed = state.calendar.elapsed + state.calendar.secondsPerDay * 1.01 / 24
        local bought, order = context.procurement.buy(state, 1, 1)
        assert(bought, order)
    end

    now = Calendar.absoluteHours(state)
    for _, job in ipairs(state.jobs.active) do job.delivery.readyAtHours = now end
    for _, shipment in ipairs(state.procurement.shipments) do
        shipment.delivery.expectedAtHours = now
        for _, order in ipairs(vendorOrders(state, shipment)) do
            order.delivery.expectedAtHours = now
        end
    end
    assert(#state.procurement.shipments == VENDOR_TRUCK_COUNT,
        "supplier purchases should create separate traffic manifests")

    local worldContext = context.world.employeeContext(state, context.assets)
    local secondsPerHour = Calendar.secondsPerDay(state) / 24
    state.employment.lastAtHours = now - .25 / secondsPerHour
    EmployeeAI.update(state, .25, worldContext)
    local visibleStaff = Employees.actors(state)
    check("late_game_load_staff_simulation_runs_with_all_ten_on_shift",
        #visibleStaff == STAFF_COUNT)

    local town = assert(Town.generate(712345))
    local epoch = 1700000000
    local lanes = context.config.palletLogistics.spawnPoints
    local origin = context.config.palletLogistics.unloadOrigin
    local moved, totalTrucks, maxConcurrent = { count = 0, positions = {} }, 0, 0
    local frameCount = 0
    local expectedPallets = JOB_COUNT * PALLETS_PER_JOB + VENDOR_TRUCK_COUNT
    now=require('src.business_hours').nextService(now,11)

    while pendingPallets(state, deliveryEntries(state)) > 0 and frameCount < 60 do
        frameCount = frameCount + 1
        Network.update(state, town, now, epoch)
        local entries = deliveryEntries(state)
        local leaders = activeLeaders(entries)
        -- Dispatch can wait for road clearance or the measured simulation
        -- budget. Continue advancing existing trucks while that happens.
        for wait=1,1800 do
            if #leaders>0 then break end
            epoch=epoch+.1
            Network.simulate(state,town,.1,epoch)
            if wait%10==0 then
                Network.update(state,town,now,epoch)
                entries=deliveryEntries(state);leaders=activeLeaders(entries)
            end
        end
        local waiting=entries[1] and entries[1].delivery and entries[1].delivery.route or {}
        assert(#leaders > 0, ("late-game deliveries stalled: frame=%d now=%.2f epoch=%.2f start=%s departed=%s"):
            format(frameCount,now,epoch,tostring(waiting.startAtHours),tostring(waiting.departedAtEpoch)))
        assert(#leaders <= Network.MAX_ACTIVE_TRUCKS,
            "dispatch exceeded the active truck budget")
        maxConcurrent = math.max(maxConcurrent, #leaders)
        totalTrucks = totalTrucks + #leaders

        for _ = 1, 4 do
            frameCount = frameCount + 1
            Network.simulate(state, town, .25, epoch + frameCount * .25)
        end
        local inTown = Network.actors(state, town, now, epoch + frameCount * .25)
        local finiteTraffic = #inTown >= #leaders
        for _, actor in ipairs(inTown) do
            finiteTraffic = finiteTraffic and actor.actor and type(actor.actor.x) == "number"
                and actor.actor.x == actor.actor.x and math.abs(actor.actor.x) < math.huge
                and type(actor.actor.z) == "number" and actor.actor.z == actor.actor.z
                and math.abs(actor.actor.z) < math.huge
        end
        assert(finiteTraffic, "heavy delivery traffic produced a missing or non-finite truck actor")

        local arrivalEpoch = epoch + frameCount * .25 + 1
        for _, leader in ipairs(leaders) do
            leader.delivery.route.arrivedAtEpoch = arrivalEpoch
            leader.delivery.route.arrivalAtHours = now
            leader.delivery.route.vehicle = nil
        end
        Network.update(state, town, now, arrivalEpoch)
        local atBay = Network.actors(state, town, now, arrivalEpoch)
        local bayCount = 0
        for _, actor in ipairs(atBay) do if actor.phase == "at_bay" then bayCount = bayCount + 1 end end
        assert(bayCount >= #leaders, "arriving trucks were not represented at the warehouse dock")

        for _, leader in ipairs(leaders) do
            for _, entry in ipairs(entries) do
                local route = entry.delivery and entry.delivery.route
                if entry.id == leader.id or route and route.transportId == leader.id then
                    unloadEntry(state, entry, arrivalEpoch, lanes, origin, moved)
                end
            end
        end
        Network.update(state,town,now,arrivalEpoch)
        for step=1,Network.DISPATCH_HEADWAY_SECONDS*10 do
            Network.simulate(state,town,.1,arrivalEpoch+step*.1)
        end
        epoch = arrivalEpoch + Network.DISPATCH_HEADWAY_SECONDS
    end

    local remaining = pendingPallets(state, deliveryEntries(state))
    local physical = Logistics.physicalPallets(state)
    local allPositionsFinite = true
    for _, item in ipairs(physical) do
        allPositionsFinite = allPositionsFinite and finitePosition(item)
    end
    check("late_game_load_routes_eight_plus_trucks_with_staggered_departures",
        remaining == 0 and totalTrucks >= math.ceil(expectedPallets / Network.TRUCK_CAPACITY)
            and maxConcurrent >= 1 and maxConcurrent <= Network.MAX_ACTIVE_TRUCKS,
        string.format("remaining=%d trucks=%d maxConcurrent=%d", remaining, totalTrucks, maxConcurrent))
    check("late_game_load_unloads_all_seventy_two_pallets_to_the_warehouse",
        moved.count == expectedPallets and #physical == expectedPallets and allPositionsFinite,
        string.format("unloaded=%d physical=%d finite=%s", moved.count, #physical, tostring(allPositionsFinite)))

    local before = Calendar.absoluteHours(state)
    state.calendar.elapsed = state.calendar.elapsed + .25
    state.employment.lastAtHours = before
    EmployeeAI.update(state, .25, context.world.employeeContext(state, context.assets))
    local actors = Employees.actors(state)
    local finiteEmployees = #actors == STAFF_COUNT
    for _, entry in ipairs(actors) do finiteEmployees = finiteEmployees and finitePosition(entry.actor) end
    check("late_game_load_ten_employees_keep_finite_poses_among_seventy_two_pallets",
        finiteEmployees and #Logistics.physicalPallets(state) == expectedPallets)
end

return Test
