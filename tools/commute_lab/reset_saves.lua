-- User-authorized disposable-save reset. Existing .bak files are never changed.
-- Write fresh valid primaries so automatic recovery cannot resurrect old progress.
function love.load()
    love.filesystem.setIdentity('the-picture-shop')
    local directory=love.filesystem.getSaveDirectory():gsub('\\','/')
    assert(directory:match('/LOVE/the%-picture%-shop$'), 'Unexpected save directory: '..directory)
    local store=require('src.save_store')(love.filesystem)
    local function encode(v)
        if type(v)=='table' then
            local parts={'{'}
            for k,item in pairs(v) do parts[#parts+1]='['..encode(k)..']='..encode(item)..',' end
            parts[#parts+1]='}';return table.concat(parts)
        elseif type(v)=='string' then return string.format('%q',v)
        elseif type(v)=='number' or type(v)=='boolean' then return tostring(v) end
        error('Unsupported reset data')
    end
    assert(love.filesystem.createDirectory('saves'))
    for slot=1,3 do
        local payload=assert(store.newGame(slot,{apartmentId='brick-walkup',furnishingPreset='empty'}))
        local path='saves/slot'..slot..'.lua'
        assert(love.filesystem.write(path,encode(payload)))
        if love.filesystem.getInfo(path..'.tmp') then assert(love.filesystem.remove(path..'.tmp')) end
        print('RESET '..directory..'/'..path)
    end
    love.event.quit(0)
end
