local Test={}
function Test.run(c,check)
    local M=c.machine
    local state=c.State.new();state.screen='machine';state.machineType='paper_cutter'
    local job=c.jobs.createOffer({
        id='JOB-CUTTER-OPERATOR',company='Console Test Co.',
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},
    })
    assert(c.jobs.accept(job))
    state.jobs.active[1]=job
    local pallet=job.pallets[1]
    local x,y=c.CutterZones.inputAnchor(state,c.config.cutterPlacement)
    pallet.location='warehouse'
    pallet.world={x=x,y=y,fromX=x,fromY=y,direction='northwest',rotation=1,spawnProgress=1}
    M.reset(state)
    local screen=require('src.screens.machine_screen').new()
    screen.enter()
    local function click(action,value)
        local x,y=screen.buttonCenter(action,value);assert(x,action)
        screen.mousepressed(state,x,y,1);screen.mousereleased(state,x,y,1)
    end
    local function capture(name, pixelX, pixelY)
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
        screen.draw(state,c.assets);love.graphics.pop()
        local data=canvas:newImageData();data:encode('png','cutter-operator-'..name..'.png')
        local hash=love.data.hash('sha256',data:getString())
        local warning
        if pixelX then
            local r,g,b=data:getPixel(pixelX,pixelY)
            warning=r>.8 and g<.45 and b<.4
        end
        data:release();canvas:release()
        return hash,warning
    end
    c.assets.activatePack('cutter')
    capture('pallets')
    local lx,ly=screen.loadMenuRowCenter(1)
    screen.mousepressed(state,lx,ly,1)
    M.update(M.transferTime+.01,state)
    check('operator_pallet_card_loads_existing_run',M.loaded and M.step=='loaded')
    click('page','cutter');capture('machine')
    local angle=M.paper.orientation
    local rx,ry=screen.buttonCenter('rotate')
    screen.mousepressed(state,rx-30,ry,1);screen.mousereleased(state,rx-30,ry,1)
    check('operator_left_arrow_turns_clockwise',M.paper.orientation==(angle+90)%360)
    screen.mousepressed(state,rx,ry,1);screen.mousereleased(state,rx+40,ry,1)
    check('operator_swipe_right_turns_counterclockwise',M.paper.orientation==angle)
    click('computer')
    check('operator_computer_is_separate_view',screen.cutterPage=='computer')
    click('digit','C');click('digit','1');click('digit','2');click('digit','.');click('digit','5')
    check('operator_physical_keypad_keeps_native_keyboard_closed',screen.gaugeText=='12.5' and not screen.wantsTextInput())
    click('erase');check('operator_delete_edits_draft',screen.gaugeText=='12.')
    click('digit','5');click('digit','.');check('operator_keypad_rejects_second_decimal',screen.gaugeText=='12.5')
    click('unit');check('operator_units_convert_draft_without_moving_gauge',M.gauge==0 and screen.gaugeText=='317.50')
    click('unit')
    click('set_gauge')
    check('operator_keypad_commits_valid_inches',math.abs(M.gauge-12.5)<.001)
    click('unit');check('operator_metric_display_matches_inches',math.abs(tonumber(screen.gaugeText)-317.5)<.01)
    click('digit','C');for character in ('254'):gmatch('.') do click('digit',character) end
    click('set_gauge');check('operator_metric_entry_preserves_internal_inches',math.abs(M.gauge-10)<.001)
    screen.update(.2)
    local normal=capture('computer')
    local enterX,enterY=screen.buttonCenter('set_gauge')
    screen.mousepressed(state,enterX,enterY,1)
    local pressed=capture('key-pressed')
    screen.update(.4)
    check('operator_key_uses_pressed_sprite_while_held',pressed~=normal and capture('key-held')==pressed)
    screen.mousereleased(state,enterX,enterY,1);screen.update(.2)
    check('operator_key_returns_to_raised_sprite_after_release',capture('key-released')==normal)
    local item=require('src.machine_fleet').installed(state,'polar_115')
    item.variables.bladeSharpness=50
    local _,dull=capture('computer-dull',558,188)
    item.variables.bladeSharpness=51
    local _,sharp=capture('computer-sharp',558,188)
    check('operator_low_blade_light_only_at_dull_threshold',dull and not sharp)
    click('page','cutter');click('cut_left')
    check('operator_single_cut_cannot_cut_unclamped_stock',M.step=='loaded')
    click('estop');check('operator_sprite_estop_blocks_machine',M.emergencyStopped)
    click('estop');check('operator_sprite_estop_resets_safely',not M.emergencyStopped)
    local rect=screen.operatorSceneRect
    check('operator_machine_fills_console_without_header_overlap',rect.width>=800 and rect.y>=54 and rect.y+rect.height<630)
    M.reset(state)
    local serviceX,serviceY=744,33
    screen.mousepressed(state,serviceX,serviceY,1)
    screen.mousereleased(state,serviceX,serviceY,1)
    check('operator_service_opens_blade_condition_panel',screen.maintenanceView=='hub')
    item.variables.bladeSharpness=35
    local worn=capture('service-dull')
    item.variables.bladeSharpness=85
    check('operator_service_readout_changes_with_blade_sharpness',capture('service-sharp')~=worn)
    M.reset(c.state)
end
return Test
