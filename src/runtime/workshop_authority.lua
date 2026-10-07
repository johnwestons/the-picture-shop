-- Workshop resource definitions and authority setup.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.createWorkshopAuthority()
        Runtime.cutterMaintenanceAuthority = Runtime.RuntimeDependencies.CutterMaintenanceAuthority.create({
            state = Runtime.state,
            baseView = Runtime.cutterView,
            validateAccess = function(player)
                return Runtime.World.validateNetworkWorkshopAccess(player, Runtime.state,
                    Runtime.state._activeWorkshopResourceId or "cutter")
            end,
            save = Runtime.saveCurrent,
            machineReady = function()
                if Runtime.Machine.loaded or Runtime.Machine.step ~= "idle" then
                    return false, "Unload the cutter and return it to idle before beginning maintenance."
                end
                return true
            end,
        })
        Runtime.wrapperMaintenanceAuthority = Runtime.RuntimeDependencies.WrapperMaintenanceAuthority.create({
            state = Runtime.state,
            baseView = Runtime.wrapperView,
            validateAccess = function(player)
                return Runtime.World.validateNetworkWorkshopAccess(player, Runtime.state,
                    Runtime.state._activeWorkshopResourceId or "skid_wrapper")
            end,
            save = Runtime.saveCurrent,
            machineReady = function()
                if Runtime.Wrapper.isActive() then
                    return false, "machine_busy",
                        "Wait for the wrapping cycle to finish before beginning maintenance."
                end
                if Runtime.Wrapper.nearbyPallet(Runtime.state) then
                    return false, "turntable_occupied",
                        "Move every eligible pallet away from the wrapper before beginning maintenance."
                end
                return true
            end,
            resetRuntime = function()
                return Runtime.Wrapper.reset(Runtime.state)
            end,
        })
        local authority = Runtime.WorkshopAuthority.new({
            leaseTimeout = 12,
            resources = {
                reception_customer = {
                    canAcquire = function(player)
                        return Runtime.World.validateNetworkWorkshopAccess(
                            player, Runtime.state, "reception_customer")
                    end,
                    onAcquire = function(_, player)
                        if player.id == 1 then
                            return true, "acquired", "Reception reserved for the host player."
                        end
                        local offer, errors = Runtime.JobService.createNextOffer(Runtime.state, os.time())
                        if not offer then
                            return false, "offer_failed",
                                "Could not prepare the customer job: " .. table.concat(errors or {}, "; ")
                        end
                        if not Runtime.World.customer:beginReview() then
                            return false, "customer_unavailable", "That customer is no longer waiting."
                        end
                        return true, "acquired", "Customer conversation opened.",
                            Runtime.customerView(offer), { offer = offer, remote = true, resolved = false }
                    end,
                    onRelease = function(lease)
                        if lease.private and lease.private.remote and not lease.private.resolved then
                            Runtime.World.customer:cancelReview()
                        end
                        return true
                    end,
                    commands = {
                        request_details = {
                            normalize = function(arguments)
                                if not Runtime.exactArguments(arguments, {}) then
                                    return nil, "invalid_arguments", "Request details takes no additional data."
                                end
                                return {}
                            end,
                            perform = function(lease)
                                local offer = lease.private and lease.private.offer
                                if not offer then return false, "offer_missing", "The customer paperwork expired." end
                                local succeeded, result = Runtime.JobService.requestEstimateDetails(
                                    Runtime.state, offer, os.time())
                                if not succeeded then
                                    return false, "details_failed", "Could not request the details: " .. tostring(result)
                                end
                                lease.private.resolved = true
                                Runtime.World.resolveCustomer("accepted", Runtime.state)
                                Runtime.saveCurrent()
                                return true, "details_requested",
                                    offer.company .. " will email the written job details."
                            end,
                        },
                    },
                },
                vendor = Runtime.RuntimeDependencies.VendorAuthority.resource({
                    state = Runtime.state,
                    world = Runtime.World,
                    save = Runtime.saveCurrent,
                }),
                truck = Runtime.RuntimeDependencies.TruckAuthority.resource({
                    state = Runtime.state,
                    world = Runtime.World,
                    save = Runtime.saveCurrent,
                }),
                work_phone = Runtime.RuntimeDependencies.PhoneAuthority.resource({ state = Runtime.state, world = Runtime.World, save = Runtime.saveCurrent }),
                office_computer = {
                    canAcquire = function(player)
                        return Runtime.World.validateNetworkWorkshopAccess(player, Runtime.state, "office_computer")
                    end,
                    onAcquire = function()
                        return true, "acquired", "Office computer connected.", {}
                    end,
                    commands = {
                        office_action = Runtime.RuntimeDependencies.OfficeAuthority.command({ state = Runtime.state, world = Runtime.World, save = Runtime.saveCurrent,
                            warehouseEnabled = Runtime.Config.warehouse.enabled,
                            warehouseFirstStorageOnly = Runtime.Config.warehouse.firstStorageOnly }),
                        request_pickup = {
                            normalize = function(arguments)
                                local jobId = type(arguments) == "table" and arguments.jobId
                                if not Runtime.exactArguments(arguments, { "jobId" })
                                    or type(jobId) ~= "string" or #jobId < 1 or #jobId > 64
                                    or not jobId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                                then
                                    return nil, "invalid_job", "Choose a valid active job."
                                end
                                return { jobId = jobId }
                            end,
                            perform = function(_, _, arguments)
                                local job = Runtime.findActiveJob(arguments.jobId)
                                if not job then return false, "job_not_found", "That active job no longer exists." end
                                local succeeded, result = Runtime.JobService.requestPickup(Runtime.state, job, os.time())
                                if not succeeded then
                                    return false, "pickup_blocked", "Could not request pickup: " .. tostring(result)
                                end
                                Runtime.saveCurrent()
                                return true, "pickup_requested", job.id .. " is awaiting customer pickup.", {}
                            end,
                        },
                    },
                },
                cutter = {
                    canAcquire = function(player)
                        return Runtime.World.validateNetworkWorkshopAccess(player, Runtime.state,
                            Runtime.state._activeWorkshopResourceId or "cutter")
                    end,
                    onAcquire = function()
                        Runtime.Machine.open(Runtime.state)
                        local session = Runtime.RuntimeDependencies.CutterMaintenanceAuthority.newSession()
                        Runtime.activeCutterRemote = session
                        Runtime.machineRemoteSessions[Runtime.state._activeWorkshopResourceId or "cutter"] = session
                        return true, "acquired", "Cutter console connected.",
                            Runtime.cutterMaintenanceAuthority.view(session, true), session
                    end,
                    onRelease = function(lease)
                        local changed = Runtime.Machine.releaseOperator(Runtime.state)
                        Runtime.machineRemoteSessions[Runtime.state._activeWorkshopResourceId or "cutter"] = nil
                        if Runtime.activeCutterRemote == (lease and lease.private) then
                            Runtime.activeCutterRemote = nil
                        end
                        if changed then Runtime.saveCurrent() end
                        return true, "released", "Cutter controls released safely."
                    end,
                    commands = Runtime.cutterMaintenanceAuthority.withProductionCommands({
                        load_pallet = {
                            normalize = function(arguments)
                                local palletId = type(arguments) == "table" and arguments.palletId
                                if not Runtime.exactArguments(arguments, { "palletId" })
                                    or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                    or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                                then
                                    return nil, "invalid_pallet", "Choose a valid nearby pallet."
                                end
                                return { palletId = palletId }
                            end,
                            perform = function(_, player, arguments)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.load(Runtime.state, arguments.palletId) end, true)
                            end,
                        },
                        load_stock = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.load(Runtime.state, "__generic_stock__") end, false)
                            end,
                        },
                        select_program = {
                            normalize = function(arguments)
                                local index = type(arguments) == "table" and arguments.programIndex
                                if not Runtime.exactArguments(arguments, { "programIndex" })
                                    or type(index) ~= "number" or index ~= math.floor(index)
                                    or index < 1 or index > 4
                                then
                                    return nil, "invalid_program", "Choose cutter program 1 through 4."
                                end
                                return { programIndex = index }
                            end,
                            perform = function(_, player, arguments)
                                return Runtime.performCutterAction(player, function()
                                    return Runtime.Machine.selectProgram(arguments.programIndex, Runtime.state)
                                end, false)
                            end,
                        },
                        set_gauge = {
                            normalize = function(arguments)
                                local gauge = type(arguments) == "table" and arguments.gaugeCentiInch
                                if not Runtime.exactArguments(arguments, { "gaugeCentiInch" })
                                    or type(gauge) ~= "number" or gauge ~= math.floor(gauge)
                                    or gauge < 0 or gauge > 2500
                                then
                                    return nil, "invalid_gauge", "Enter a gauge from 0.00 to 25.00 inches."
                                end
                                return { gaugeCentiInch = gauge }
                            end,
                            perform = function(_, player, arguments)
                                return Runtime.performCutterAction(player, function()
                                    return Runtime.Machine.setGauge(arguments.gaugeCentiInch / 100, Runtime.state)
                                end, false)
                            end,
                        },
                        auto_gauge = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.autoGauge(Runtime.state) end, false)
                            end,
                        },
                        save_gauge = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.saveGauge(Runtime.state) end, true)
                            end,
                        },
                        recall_gauge = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.recallGauge(Runtime.state) end, false)
                            end,
                        },
                        rotate_paper = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.rotate(Runtime.state) end, true)
                            end,
                        },
                        position_paper = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.position(Runtime.state) end, false)
                            end,
                        },
                        set_clamp = {
                            normalize = function(arguments)
                                local clamp = type(arguments) == "table" and arguments.clamp
                                if not Runtime.exactArguments(arguments, { "clamp" }) or type(clamp) ~= "boolean" then
                                    return nil, "invalid_clamp", "Clamp state must be true or false."
                                end
                                return { clamp = clamp }
                            end,
                            perform = function(_, player, arguments)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.setClamp(arguments.clamp, Runtime.state) end, false)
                            end,
                        },
                        set_barrier = {
                            normalize = function(arguments)
                                local clear = type(arguments) == "table" and arguments.barrierClear
                                if not Runtime.exactArguments(arguments, { "barrierClear" })
                                    or type(clear) ~= "boolean"
                                then
                                    return nil, "invalid_barrier", "Barrier state must be true or false."
                                end
                                return { barrierClear = clear }
                            end,
                            perform = function(_, player, arguments)
                                return Runtime.performCutterAction(player, function()
                                    return Runtime.Machine.setBarrier(arguments.barrierClear, Runtime.state)
                                end, false)
                            end,
                        },
                        guarded_cut = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.guardedCut(Runtime.state) end, false)
                            end,
                        },
                        emergency_stop = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.emergencyStop(Runtime.state) end, false)
                            end,
                        },
                        reset_safety = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.resetSafety(Runtime.state) end, false)
                            end,
                        },
                        return_to_pallet = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.unload(Runtime.state) end, false)
                            end,
                        },
                        run_next_lift = {
                            normalize = Runtime.cutterNoArguments,
                            perform = function(_, player)
                                return Runtime.performCutterAction(player,
                                    function() return Runtime.Machine.repeatLift(Runtime.state) end, true)
                            end,
                        },
                    }),
                },
                windmill = {
                    canAcquire = function(player)
                        return Runtime.World.validateNetworkWorkshopAccess(player, Runtime.state,
                            Runtime.state._activeWorkshopResourceId or "windmill")
                    end,
                    onAcquire = function(lease)
                        local session = {
                            setupTask = nil,
                            setupGame = nil,
                            maintenance = nil,
                            lockoutStep = nil,
                        }
                        Runtime.activeWindmillRemote = session
                        Runtime.machineRemoteSessions[Runtime.state._activeWorkshopResourceId or "windmill"] = session
                        return true, "acquired", "Windmill console connected.",
                            Runtime.windmillView(session), session
                    end,
                    onRelease = function(lease, _, reason)
                        local changed = reason ~= "closed" and Runtime.Windmill.releaseOperator(Runtime.state)
                        Runtime.machineRemoteSessions[Runtime.state._activeWorkshopResourceId or "windmill"] = nil
                        if Runtime.activeWindmillRemote == (lease and lease.private) then
                            Runtime.activeWindmillRemote = nil
                        end
                        if changed then Runtime.saveCurrent() end
                        return true, "released", "Windmill controls released safely."
                    end,
                    commands = Runtime.createWindmillCommands(),
                },
                skid_wrapper = {
                    canAcquire = function(player)
                        local allowed, code, message = Runtime.World.validateNetworkWorkshopAccess(
                            player, Runtime.state, Runtime.state._activeWorkshopResourceId or "skid_wrapper")
                        if not allowed then return false, code, message end
                        if Runtime.Wrapper.step == "wrapping" then
                            return false, "machine_busy", "The skid wrapper is already running a cycle."
                        end
                        return true
                    end,
                    onAcquire = function()
                        local session = Runtime.RuntimeDependencies.WrapperMaintenanceAuthority.newSession()
                        Runtime.activeWrapperRemote = session
                        Runtime.machineRemoteSessions[Runtime.state._activeWorkshopResourceId or "skid_wrapper"] = session
                        return true, "acquired", "Skid-wrapper console connected.",
                            Runtime.wrapperMaintenanceAuthority.view(session, true), session
                    end,
                    onRelease = function(lease)
                        Runtime.machineRemoteSessions[Runtime.state._activeWorkshopResourceId or "skid_wrapper"] = nil
                        if Runtime.activeWrapperRemote == (lease and lease.private) then
                            Runtime.activeWrapperRemote = nil
                        end
                        return true, "released", "Skid-wrapper controls released safely."
                    end,
                    commands = Runtime.wrapperMaintenanceAuthority.withProductionCommands({
                        select_pallet = {
                            normalize = function(arguments)
                                local palletId = type(arguments) == "table" and arguments.palletId
                                if not Runtime.exactArguments(arguments, { "palletId" })
                                    or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                    or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                                then
                                    return nil, "invalid_pallet", "Choose a valid nearby pallet."
                                end
                                return { palletId = palletId }
                            end,
                            perform = function(_, _, arguments)
                                if not Runtime.Wrapper.selectPallet(Runtime.state, arguments.palletId) then
                                    return false, "pallet_unavailable", tostring(Runtime.state.message)
                                end
                                return true, "pallet_selected", tostring(Runtime.state.message), Runtime.wrapperView()
                            end,
                        },
                        start_cycle = {
                            normalize = function(arguments)
                                local palletId = type(arguments) == "table" and arguments.palletId
                                if not Runtime.exactArguments(arguments, { "palletId" })
                                    or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                    or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                                then
                                    return nil, "invalid_pallet", "Choose a valid nearby pallet."
                                end
                                return { palletId = palletId }
                            end,
                            perform = function(_, _, arguments)
                                if not Runtime.Wrapper.selectPallet(Runtime.state, arguments.palletId)
                                    or not Runtime.Wrapper.start(Runtime.state)
                                then
                                    return false, "cycle_blocked", tostring(Runtime.state.message)
                                end
                                return true, "cycle_started", tostring(Runtime.state.message), Runtime.wrapperView()
                            end,
                        },
                    }),
                },
                pallet_jack = {
                    canAcquire = function(player)
                        local allowed, code, message = Runtime.World.validateNetworkWorkshopAccess(
                            player, Runtime.state, "pallet_jack")
                        if not allowed then return false, code, message end
                        if Runtime.machineRelocationActive() then
                            return false, "machine_moving",
                                "Finish locking the moving machine onto the floor first."
                        end
                        return true
                    end,
                    onAcquire = function(_, player)
                        local accepted, code, message = Runtime.World.operateNetworkPalletJack(
                            player, Runtime.state)
                        return accepted, code, message, accepted and {} or nil
                    end,
                    onRelease = function(lease, player)
                        -- Timeout, disconnect, and normal release all use the same
                        -- safe recovery. An attached machine is locked to a valid
                        -- snapped cell (or its relocation origin) before the jack
                        -- relinquishes ownership.
                        Runtime.World.recoverNetworkMachineMove(Runtime.state, Runtime.Assets, player)
                        Runtime.PalletJack.forceRelease(Runtime.state, Runtime.Config.palletJack,
                            lease and lease.ownerPlayerId or nil)
                        Runtime.saveCurrent()
                        return true, "released", Runtime.state.palletJack.carriedPalletId
                            and "Loaded pallet jack parked safely."
                            or "Pallet jack parked."
                    end,
                    commands = {
                        lift_pallet = {
                            normalize = function(arguments)
                                local palletId = type(arguments) == "table" and arguments.palletId
                                if not Runtime.exactArguments(arguments, { "palletId" })
                                    or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                    or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                                then
                                    return nil, "invalid_pallet", "Choose a valid nearby pallet."
                                end
                                return { palletId = palletId }
                            end,
                            perform = function(_, player, arguments)
                                if Runtime.machineRelocationActive() then
                                    return false, "equipment_moving",
                                        "Place the moving machine before lifting a pallet."
                                end
                                local accepted, code, message = Runtime.World.liftNetworkPallet(
                                    player, Runtime.state, arguments.palletId)
                                if accepted then Runtime.saveCurrent() end
                                return accepted, code, message
                            end,
                        },
                        lower_pallet = {
                            normalize = function(arguments)
                                local palletId = type(arguments) == "table" and arguments.palletId
                                if not Runtime.exactArguments(arguments, { "palletId" }, { "placementCell" })
                                    or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                    or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                                then
                                    return nil, "invalid_pallet", "Choose the pallet currently on the forks."
                                end
                                if arguments.placementCell ~= nil and not Runtime.RuntimeDependencies.PlacementGrid.decode(arguments.placementCell) then
                                    return nil,"invalid_cell","Choose a valid highlighted drop cell."
                                end
                                return { palletId = palletId,placementCell=arguments.placementCell }
                            end,
                            perform = function(_, player, arguments)
                                if Runtime.machineRelocationActive() then
                                    return false, "equipment_moving",
                                        "Place the moving machine before lowering a pallet."
                                end
                                local accepted, code, message = Runtime.World.lowerNetworkPallet(
                                    player, Runtime.state, Runtime.Assets, arguments.palletId, arguments.placementCell)
                                if accepted then Runtime.saveCurrent() end
                                return accepted, code, message
                            end,
                        },
                        park_jack = {
                            normalize = function(arguments)
                                if not Runtime.exactArguments(arguments, {}) then
                                    return nil, "invalid_arguments", "Parking takes no additional data."
                                end
                                return {}
                            end,
                            perform = function(_, player)
                                if Runtime.machineRelocationActive() then
                                    return false, "equipment_moving",
                                        "Place the moving machine before parking the jack."
                                end
                                local accepted, code, message = Runtime.World.releaseNetworkPalletJack(
                                    player, Runtime.state, false)
                                if accepted then Runtime.saveCurrent() end
                                return accepted, code, message
                            end,
                        },
                        move_machine = {
                            normalize = function(arguments)
                                local machineIndex = type(arguments) == "table"
                                    and arguments.machineIndex
                                if not Runtime.exactArguments(arguments, { "machineIndex" })
                                    or type(machineIndex) ~= "number"
                                    or machineIndex % 1 ~= 0
                                    or machineIndex < 1 or machineIndex > 3
                                then
                                    return nil, "invalid_machine", "Choose a valid nearby machine."
                                end
                                return { machineIndex = machineIndex }
                            end,
                            perform = function(_, player, arguments)
                                local resources = { "cutter", "skid_wrapper", "windmill" }
                                local resourceId = resources[arguments.machineIndex]
                                local occupied = Runtime.workshopAuthority
                                    and Runtime.workshopAuthority:leaseForResource(resourceId) ~= nil
                                local accepted, code, message = Runtime.World.beginNetworkMachineMove(
                                    player, Runtime.state, arguments.machineIndex, occupied)
                                if accepted then Runtime.saveCurrent() end
                                return accepted, code, message
                            end,
                        },
                        rotate_machine = {
                            normalize = function(arguments)
                                if not Runtime.exactArguments(arguments, {}) then
                                    return nil, "invalid_arguments", "Rotation takes no additional data."
                                end
                                return {}
                            end,
                            perform = function(_, player)
                                local accepted, code, message = Runtime.World.rotateNetworkMachine(
                                    player, Runtime.state)
                                if accepted then Runtime.saveCurrent() end
                                return accepted, code, message
                            end,
                        },
                        place_machine = {
                            normalize = function(arguments)
                                local cell = type(arguments) == "table" and arguments.placementCell
                                if not Runtime.exactArguments(arguments, { "placementCell" })
                                    or not Runtime.RuntimeDependencies.PlacementGrid.decode(cell)
                                then
                                    return nil, "invalid_cell", "Choose a valid highlighted placement cell."
                                end
                                return { placementCell = cell }
                            end,
                            perform = function(_, player, arguments)
                                local accepted, code, message = Runtime.World.placeNetworkMachine(
                                    player, Runtime.state, Runtime.Assets, arguments.placementCell)
                                if accepted then Runtime.saveCurrent() end
                                return accepted, code, message
                            end,
                        },
                    },
                },
            },
        })
        authority.resources.pallet_jack = Runtime.RuntimeDependencies.MachineRelocationAuthority.resource({
            state = Runtime.state,
            assets = Runtime.Assets,
            world = Runtime.World,
            palletJack = Runtime.PalletJack,
            config = Runtime.Config,
            save = Runtime.saveCurrent,
            controlOccupied = function(machineIndex)
                local resources = { "cutter", "skid_wrapper", "windmill" }
                local base = resources[machineIndex]
                for _, unit in ipairs(Runtime.MachineFleet.installedUnits(Runtime.state, Runtime.MachineResource.model(base))) do
                    if authority:leaseForResource(Runtime.MachineResource.forUnit(base, unit.id)) then
                        return true
                    end
                end
                return authority:leaseForResource(base) ~= nil
            end,
        })
        local warehouseCommand = Runtime.RuntimeDependencies.WarehouseAuthority.command({state=Runtime.state,world=Runtime.World,save=Runtime.saveCurrent})
        authority.resources.pallet_jack.commands.warehouse_action = warehouseCommand
        authority.resources.warehouse = {
            canAcquire=function(player) return Runtime.World.warehouseAccess(player,Runtime.state) end,
            onAcquire=function() return true,"acquired","Warehouse controls connected.",{} end,
            commands={warehouse_action=warehouseCommand},
            onRelease=function(_,player)
                if Runtime.state.forklift and Runtime.state.forklift.operatorPlayerId==player.id then
                    Runtime.World.forceReleaseForklift(player,Runtime.state)
                    Runtime.saveCurrent()
                end
                return true,"released","Forklift safely stopped.",{}
            end,
            view=function() return {} end,
        }
        Runtime.registerInstalledMachineResources(authority)
        return authority
    end
end

return Component
