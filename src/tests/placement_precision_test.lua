local Test = {}
local Config = require("src.config")
local State = require("src.state")
local Jobs = require("src.jobs")
local Fleet = require("src.machine_fleet")
local Pallets = require("src.pallet_state")
local Grid = require("src.placement_grid")
local Floor = require("src.floor_footprint")
local Protocol = require("src.net.protocol")
local Schema = require("src.save_schema")
local World = require("src.world")
local Jack = require("src.pallet_jack")
local Cutter = require("src.cutter_zones")
local Wrapper = require("src.wrapper")
local Windmill = require("src.windmill")

local models = {cutter="polar_115",wrapper="skid_wrapper",windmill="heidelberg_10x15"}

local function fixture(kind, suffix)
    local state = State.new()
    if kind == "windmill" then
        state.money = 100000
        assert(Fleet.buy(state,"dealer",3))
    end
    local machine = assert(Fleet.installed(state,models[kind]))
    state.machines.items = {machine}
    machine.world = state[kind]
    machine.world.x,machine.world.y,machine.world.direction = 625,405,"northwest"
    state._operatingMachineId = machine.id
    local job = Jobs.createOffer({id="PRECISION-"..kind.."-"..suffix,company="Placement test",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},
        press=kind == "windmill" and {colors=1,coverage=0.35,artworkSize={width=4,height=6},
            colorSequence={"Black"},requestedCopies={500}} or nil})
    Jobs.accept(job)
    state.jobs.active = {job}
    local pallet = job.pallets[1]
    pallet.location,pallet.status = "warehouse","raw"
    pallet.world = {x=695,y=430,fromX=695,fromY=430,spawnProgress=1,direction="northwest",rotation=1}
    if kind ~= "cutter" then pallet.paper.status,pallet.status = "complete","cut" end
    World.placementSelection = nil
    return state,pallet,machine
end

function Test.run(context,check)
    local previousSelection,previousPlayerId = World.placementSelection,World.player.id
    World.player.id = 1
    World.load()
    local x,y = Grid.snap(629.7,409.9,Config.placementGrid)
    check("placement_fine_grid_limits_snap_error_to_four_by_three_pixels",
        Config.placementGrid.cellWidth == 8 and Config.placementGrid.cellHeight == 6
        and math.abs(x-629.7) <= 4 and math.abs(y-409.9) <= 3)
    local cells = Grid.cells(624,408,Config.placementGrid,function() return true end)
    local tap = Grid.hit(cells,627.8,410.8,Config.placementGrid)
    check("placement_fine_grid_has_no_gaps_between_touch_targets",tap and tap.x == 624 and tap.y == 408)
    local fullMapCell = Grid.cellId(904,600,Config.placementGrid)
    local decodedX,decodedY = Grid.decode(fullMapCell,Config.placementGrid)
    check("placement_cell_ids_cover_entire_fine_grid_and_reject_malformed_ids",
        decodedX == 904 and decodedY == 600 and not Grid.decode("c256r1")
        and not Grid.decode("c01r2") and not Grid.decode("c-1r2"))

    for _,kind in ipairs({"cutter","wrapper","windmill"}) do
        local state,pallet,machine = fixture(kind,"close")
        -- The new position is in the old rectangles' empty overlapping
        -- corners, while the actual floor diamonds remain separate.
        local close = World.isPalletPlacementClear(state,context.assets,695,430,pallet.id)
        local overlap = World.isPalletPlacementClear(state,context.assets,645,410,pallet.id)
        local wall = World.isPalletPlacementClear(state,context.assets,5,405,pallet.id)
        check("placement_"..kind.."_allows_tight_corners_but_blocks_body_and_wall",
            close and not overlap and not wall)
        local view = love.graphics.newCanvas(960,678)
        love.graphics.push("all")
        love.graphics.setCanvas({view,stencil=true})
        love.graphics.origin()
        love.graphics.clear()
        local rendered,renderError = pcall(World.draw,context.assets,context.characterAssets,state)
        love.graphics.pop()
        check("placement_"..kind.."_tight_floor_arrangement_renders",rendered,tostring(renderError))
        local reviewDirectory = os.getenv("PICTURE_SHOP_PLACEMENT_REVIEW_DIR")
        if reviewDirectory and rendered then
            local data = view:newImageData()
            local png = data:encode("png")
            local file = assert(io.open(reviewDirectory.."/"..kind.."-close.png","wb"))
            file:write(png:getString());file:close()
            png:release();data:release()
        end
        view:release()
        if kind == "cutter" then
            check("placement_cutter_detects_close_feed_corner",Pallets.cutterCandidates(state)[1].pallet == pallet)
            pallet.world.x,pallet.world.y = 540,385
            check("placement_cutter_does_not_feed_from_back_side",#Pallets.cutterCandidates(state) == 0)
        elseif kind == "wrapper" then
            local wrapper = Wrapper.forId(machine.id)
            pallet.world.x,pallet.world.y = 760,405
            check("placement_wrapper_detects_pallet_edge_beyond_old_center_radius",
                wrapper.nearbyPallets(state)[1] and wrapper.nearbyPallets(state)[1].pallet == pallet)
            pallet.world.x = 900
            check("placement_wrapper_rejects_distant_floor_pallet",#wrapper.nearbyPallets(state) == 0)
        else
            pallet.world.x,pallet.world.y = 770,405
            check("placement_press_detects_pallet_edge_beyond_old_center_radius",
                Windmill.candidates(state)[1] and Windmill.candidates(state)[1].pallet == pallet)
            pallet.world.x = 900
            check("placement_press_rejects_distant_floor_pallet",#Windmill.candidates(state) == 0)
        end
        pallet.world.x,pallet.world.y = 695,430
        machine.world.moving = true
        local jack = Jack.ensure(state,Config.palletJack)
        jack.operating,jack.operatorPlayerId,jack.x,jack.y = true,2,625,413
        local grid = World.placementGridSnapshot(state,context.assets)
        local target = Grid.find(grid.cells,624,408)
        local accepted = World.placeNetworkMachine({id=2},state,context.assets,
            Grid.cellId(624,408,Config.placementGrid))
        check("placement_"..kind.."_can_be_set_closely_beside_floor_pallet",
            target and target.valid and accepted and machine.world.x == 624 and machine.world.y == 408)
        check("placement_"..kind.."_preserves_fine_position_in_save_snapshot",
            Schema.snapshot(state)[kind].x == 624 and Schema.snapshot(state)[kind].y == 408)
    end

    local rotated,rotatedPallet = fixture("cutter","rotations")
    for direction,sign in pairs({northwest={1,1},north={0,1},northeast={-1,1},east={-1,0},
        southeast={-1,-1},south={0,-1},southwest={1,-1},west={1,0}}) do
        rotated.cutter.direction = direction
        rotatedPallet.world.x,rotatedPallet.world.y = 625+sign[1]*70,405+sign[2]*25
        check("placement_cutter_recognizes_close_feed_pallet_when_facing_"..direction,
            Cutter.inInputZone(rotated,rotatedPallet,Config.cutterPlacement))
        rotatedPallet.world.x,rotatedPallet.world.y = 625-sign[1]*100,405-sign[2]*50
        check("placement_cutter_rejects_back_side_when_facing_"..direction,
            not Cutter.inInputZone(rotated,rotatedPallet,Config.cutterPlacement))
    end

    local state,pallet = fixture("cutter","network")
    local jack = Jack.ensure(state,Config.palletJack)
    jack.operating,jack.operatorPlayerId,jack.x,jack.y,jack.direction = true,2,590,470,"east"
    assert(Pallets.transition(state,pallet,"on_pallet_jack"))
    pallet.world.x,pallet.world.y = jack.x,jack.y
    local grid = World.placementGridSnapshot(state,context.assets)
    local target
    for _,cell in ipairs(grid.cells) do
        if cell.valid and cell.x ~= grid.selected.x and cell.x > 600 and cell.y > 450 then target=cell;break end
    end
    assert(target,"no precision test drop position")
    World.selectPlacement(state,context.assets,target.x,target.y,true)
    local cellId = World.networkPlacementCellId(state,context.assets)
    local selectedGrid = World.placementGridSnapshot(state,context.assets)
    local beforeX,beforeY = pallet.world.x,pallet.world.y
    local outside = World.lowerNetworkPallet({id=2},state,context.assets,pallet.id,"c1r1")
    check("placement_network_drop_rejects_remote_cell_without_changing_cargo",
        not outside and jack.carriedPalletId == pallet.id and pallet.world.x == beforeX and pallet.world.y == beforeY)
    local accepted = World.lowerNetworkPallet({id=2},state,context.assets,pallet.id,cellId)
    check("placement_network_drop_uses_guests_exact_fine_cell",
        accepted and pallet.world.x == target.x and pallet.world.y == target.y
        and not jack.carriedPalletId and Pallets.validate(state))

    assert(Pallets.transition(state,pallet,"on_pallet_jack"))
    local blocker = Jobs.createOffer({id="PRECISION-BLOCKER",company="Blocked drop",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}})
    Jobs.accept(blocker)
    state.jobs.active[2] = blocker
    local blockingPallet = blocker.pallets[1]
    blockingPallet.location = "warehouse"
    blockingPallet.world = {x=target.x,y=target.y,fromX=target.x,fromY=target.y,
        spawnProgress=1,direction="northwest",rotation=1}
    local stale = World.lowerNetworkPallet({id=2},state,context.assets,pallet.id,cellId)
    check("placement_network_drop_rechecks_cell_after_another_pallet_moves_in",
        not stale and jack.carriedPalletId == pallet.id and pallet.location == "on_pallet_jack")
    local staleGrid = World.placementGridSnapshot(state,context.assets)
    check("placement_selected_cell_cannot_outlive_its_clearance",staleGrid.selected == nil)
    assert(Pallets.transition(state,pallet,"warehouse",{world={x=target.x+80,y=target.y+40,
        fromX=target.x+80,fromY=target.y+40,spawnProgress=1,direction="northwest",rotation=1}}))

    local packet = {sessionId="precision",commandId=1,leaseId="jack-lease",resourceId="pallet_jack",
        action="lower_pallet",expectedRevision=0,palletId=pallet.id,placementCell=cellId}
    local encoded = Protocol.encode("workshop_command",packet)
    packet.x = 700
    check("placement_drop_protocol_accepts_bounded_cell_and_rejects_coordinates",
        encoded and not Protocol.encode("workshop_command",packet))

    local motions = {
        {kind="cutter",module=require("src.cutter_placement"),config=Config.cutterPlacement},
        {kind="wrapper",module=require("src.wrapper_placement"),config=Config.wrapperPlacement},
        {kind="windmill",module=require("src.windmill_placement"),config=Config.windmillPlacement},
    }
    for _,motion in ipairs(motions) do
        local moving = State.new()
        local item = moving[motion.kind]
        item.moving,item.x,item.y = true,500,500
        motion.module.move(moving,0.25,0,0.1,motion.config,function() return true end)
        check("placement_"..motion.kind.."_supports_slow_analog_positioning",
            math.abs(item.x-500-motion.config.speed*0.025) < 0.001)
        item.x = 500
        motion.module.move(moving,1,0,1,motion.config,function(nextX) return nextX < 506 end)
        check("placement_"..motion.kind.."_cannot_tunnel_through_thin_obstacle",
            item.x > 500 and item.x < 506)
    end
    jack.x,jack.y = 500,500
    Jack.move(state,0.25,0,0.1,Config.palletJack,function() return true end)
    check("placement_jack_supports_slow_analog_positioning",math.abs(jack.x-500-Config.palletJack.speed*0.025)<0.001)
    jack.x = 500
    Jack.move(state,1,0,1,Config.palletJack,function(nextX) return nextX < 506 end)
    check("placement_jack_cannot_tunnel_through_thin_obstacle",jack.x > 500 and jack.x < 506)

    local canvas = love.graphics.newCanvas(960,678)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.08,0.10,0.12,1)
    local drawn,err = pcall(Grid.draw,selectedGrid)
    love.graphics.setCanvas()
    love.graphics.pop()
    check("placement_fine_grid_and_actual_floor_outline_render",drawn,tostring(err))
    local reviewDirectory = os.getenv("PICTURE_SHOP_PLACEMENT_REVIEW_DIR")
    if reviewDirectory and drawn then
        local data = canvas:newImageData()
        local png = data:encode("png")
        local file = assert(io.open(reviewDirectory.."/fine-grid.png","wb"))
        file:write(png:getString());file:close()
        png:release();data:release()
    end
    canvas:release()
    World.placementSelection,World.player.id = previousSelection,previousPlayerId
end

return Test
