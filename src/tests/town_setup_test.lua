local Town=require('src.commute.town')
local Presets=require('src.commute.town_presets')
local Setup=require('src.screens.town_setup_screen')
local Home=require('src.home')
local Schema=require('src.save_schema')
local State=require('src.state')
local Test={}
local function renderPreview(context,check)
    if not (context and context.assets and love.graphics) then return end
    local loader=require('src.image_loader');local enabled=loader.enabled
    local previousPack=context.assets.activePackName();loader.setEnabled(false)
    assert(context.assets.activatePack('menu'))
    local town=assert(Town.generate(712345));local options={town=town,apartmentId='garden'}
    local preview=Setup.new(options)
    preview.items={{name='River town',town=town}};preview.selected=1;preview.nameText='River town'
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
    Setup.draw(preview,options,1,context.assets)
    love.graphics.pop()
    local destination=os.getenv('PICTURE_SHOP_TOWN_PREVIEW_DIR')
    if destination then
        local data=canvas:newImageData();local encoded=data:encode('png')
        local file=assert(io.open(destination..'/town-setup.png','wb'));file:write(encoded:getString());file:close()
        encoded:release();data:release()
        preview.terrainVisible=false
        love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
        Setup.draw(preview,options,1,context.assets);love.graphics.pop()
        data=canvas:newImageData();encoded=data:encode('png')
        file=assert(io.open(destination..'/town-layout-only.png','wb'));file:write(encoded:getString());file:close()
        encoded:release();data:release()
    end
    canvas:release();assert(context.assets.activatePack(previousPack));loader.setEnabled(enabled)
    if preview.terrainImage then preview.terrainImage:release() end
    check('town_setup_renders_roads_all_buildings_and_topography',true)
end
function Test.run(context,check)
    local files,writes,reads={},0,0
    local previous=love.filesystem
    local originalGenerate=Town.generate
    local rejectWrite=false
    love.filesystem={getInfo=function(name)return files[name] and {size=#files[name]} end,
        getSaveDirectory=function()return 'town-memory://no-disk-files' end,
        createDirectory=function()return true end,
        remove=function(name)files[name]=nil;return true end,
        read=function(name,bytes)reads=reads+1;return files[name] and files[name]:sub(1,bytes or #files[name]) end,
        write=function(name,source)
            writes=writes+1
            if rejectWrite then return false,'test disk full' end
            files[name]=source;return true
        end}
    local ok,err=xpcall(function()
        local town=assert(Town.generate(712345))
        local fingerprint=Town.fingerprint(town)
        check('town_invalid_new_game_options_rejected',not Home.new({town=false})
            and not Home.new({town={}}) and not Home.new({townSeed=0}))
        local options={town=town,apartmentId='garden',furnishingPreset='modest'}
        local home=assert(Home.new(options))
        check('town_home_owns_detached_full_plan',home.town~=town and home.town.roads~=town.roads
            and Town.fingerprint(home.town)==fingerprint)
        local state=State.new();state.home=home
        Town.generate=function()error('Loading a saved layout must not regenerate it') end
        local snapshot=assert(Schema.snapshot(state))
        local store=require('src.save_store')(love.filesystem)
        assert(store.save(3,state,{x=320,y=400,sceneId='warehouse'}))
        local disk=assert(store.load(3))
        local exact=Town.fingerprint(disk.state.home.town)==fingerprint
        for i,height in ipairs(town.terrain.heights) do
            exact=exact and disk.state.home.town.terrain.heights[i]==height
        end
        check('town_disk_save_preserves_every_height_and_preview_fingerprint',exact)
        local localState,guest=State.new(),State.new()
        assert(State.applyLocalSave(localState,{state=snapshot,slot=3}))
        assert(State.applySharedSnapshot(guest,snapshot))
        check('town_local_reload_and_host_snapshot_keep_exact_preview',
            Town.fingerprint(localState.home.town)==fingerprint and Town.fingerprint(guest.home.town)==fingerprint)
        local legacy=Home.new();legacy.town=nil
        check('town_legacy_home_keeps_canonical_map',Home.valid(legacy)
            and Town.fingerprint(assert(Home.normalize(legacy)).town)==Town.fingerprint(Town.legacy()))
        local invalid=Home.normalize(home);invalid.town.seed=0/0
        check('town_invalid_layout_rejected_before_local_or_shared_apply',not Home.valid(invalid)
            and not Home.normalize(invalid))
        local beforeCancel=writes
        local preview=Setup.new(options)
        local beforeToggle=Town.fingerprint(preview.town)
        local x,y=Setup.buttonCenter('terrain');Setup.mousepressed(preview,x,y,options)
        check('town_terrain_toggle_hides_underlay_without_changing_seed_or_layout',not preview.terrainVisible
            and Town.fingerprint(preview.town)==beforeToggle and not preview.dirty)
        Setup.keypressed(preview,'t',options)
        check('town_terrain_shortcut_restores_underlay',preview.terrainVisible and Town.fingerprint(preview.town)==beforeToggle)
        local relief=require('src.commute.town_preview').sample(town,16)
        local world=Town.world(town);local exact=true
        for z=0,15 do for x=0,15 do
            exact=exact and math.abs(relief.heights[z*16+x+1]-world:height((x+.5)*town.size/16,(z+.5)*town.size/16))<1e-9
        end end
        check('town_topography_samples_exact_saved_world_including_road_grading',exact and relief.high>0)
        x,y=Setup.buttonCenter('cancel')
        local cancelled=Setup.mousepressed(preview,x,y,options)
        check('town_open_cancel_does_not_write_files',writes==beforeCancel and cancelled=='cancel')
        local items=assert(Presets.upsert({}, {name='My Town',town=town}))
        local loaded=assert(Presets.load())
        check('town_named_preset_retains_generated_plan',#loaded==1 and loaded[1].name=='My Town'
            and Town.fingerprint(loaded[1].town)==fingerprint and loaded[1].town~=town)
        items=assert(Presets.upsert(items,{name='my town',town=town}))
        check('town_preset_name_replace_is_case_insensitive',#items==1 and items[1].name=='my town')
        preview.items=items;preview.selected=1
        x,y=Setup.buttonCenter('load');Setup.mousepressed(preview,x,y,options)
        x,y=Setup.buttonCenter('start')
        check('town_create_uses_loaded_preview_without_regeneration',Setup.mousepressed(preview,x,y,options)=='start'
            and Town.fingerprint(options.town)==fingerprint)
        rejectWrite=true
        local rejected,message=Presets.upsert(items,{name='Disk full',town=town})
        check('town_preset_write_failure_is_reported_without_mutating_list',not rejected
            and message:find('test disk full',1,true)~=nil and #items==1)
        rejectWrite=false
        for i=2,Presets.MAX_ITEMS do items[i]={name='Town '..i,town=town} end
        local before=writes
        check('town_preset_count_and_name_limits',not Presets.upsert(items,{name='Extra',town=town})
            and writes==before and #Presets.cleanName(string.rep('x',100))==Presets.MAX_NAME
            and not Presets.upsert({}, {name='***',town=town}))
        files[Presets.FILE]='return (function() while true do end end)()'
        local malformed,reason=Presets.load()
        check('town_presets_parse_data_without_executing_lua',#malformed==0 and reason~=nil)
        files[Presets.FILE]=string.rep('x',Presets.MAX_BYTES+1);local beforeReads=reads
        malformed,reason=Presets.load()
        check('town_presets_reject_oversize_before_read',#malformed==0 and reason~=nil and reads==beforeReads)
        files[Presets.FILE]=nil
        Town.generate=originalGenerate
        preview=Setup.new({townSeed=712345})
        x,y=Setup.buttonCenter('seed');Setup.mousepressed(preview,x,y,options)
        Setup.textinput(preview,'0');x,y=Setup.buttonCenter('start')
        check('town_seed_edit_requires_valid_new_preview',Setup.mousepressed(preview,x,y,options)~='start'
            and not Setup.generate(preview))
        x,y=Setup.buttonCenter('seed');Setup.mousepressed(preview,x,y,options)
        Setup.textinput(preview,'812345');Setup.keypressed(preview,'return',options)
        check('town_seed_enter_replaces_selection_and_generates',preview.town.seed==812345 and not preview.dirty)
        x,y=Setup.buttonCenter('name');Setup.mousepressed(preview,x,y,options)
        Setup.textinput(preview,'Seed test');Setup.keypressed(preview,'return',options)
        check('town_preset_name_enter_saves_and_hides_keyboard',#preview.items==1
            and not Setup.wantsTextInput(preview))
        x,y=Setup.buttonCenter('delete');Setup.mousepressed(preview,x,y,options)
        check('town_delete_preset_retains_live_preview',#preview.items==0 and preview.town.seed==812345
            and #Presets.load()==0)
    end,debug.traceback)
    Town.generate=originalGenerate;love.filesystem=previous
    if not ok then error(err,0) end
    renderPreview(context,check)
end
return Test
