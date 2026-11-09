-- Temporary diagnostic entry point, installed only in the app's private save
-- directory for physical-device acceptance. It is not part of a release APK.
local root=love.filesystem.getSaveDirectory()
local config=assert(love.filesystem.load('live-device-config.lua'))()
assert(config.version==1 and (config.mode=='smoke' or config.mode=='live'))
local originalGetenv=os.getenv
if config.mode=='smoke' then
    assert(type(config.id)=='string' and config.id:match('^[a-z0-9%-]+$'))
    for _,override in ipairs(config.overrides or {}) do
        assert(config.diagnostic==true and override.module:match('^src%..*tests%.'))
        assert(override.file:match('^live%-overlay%-%d+%.lua$'))
        package.preload[override.module]=assert(loadfile(root..'/'..override.file))
    end
    if love.system.getOS()=='Android' then
        -- Existing render fixtures write relative output/*.png artifacts.
        -- Give io.open a writable app-private working directory on Android.
        assert(love.filesystem.createDirectory('output'))
        local ffi=require('ffi');ffi.cdef('int chdir(const char *path);')
        assert(ffi.C.chdir(root)==0,'Cannot select private diagnostic directory')
    end
    local values={PICTURE_SHOP_SMOKE='1',PICTURE_SHOP_MOBILE='1',
        PICTURE_SHOP_TEST_IDENTITY='the-picture-shop-test-device-'..config.id,
        PICTURE_SHOP_SMOKE_FOCUS=config.focus or 'full',
        PICTURE_SHOP_SMOKE_REPORT=root..'/live-'..config.id..'.rpt',
        PICTURE_SHOP_GAMEPLAY_SEED=config.seed and tostring(config.seed) or nil}
    os.getenv=function(name)
        if name:match('^PICTURE_SHOP_') then return values[name] end
        return originalGetenv(name)
    end
else
    local component=require('src.runtime.context')
    local install=component.install
    component.install=function(R) install(R);_G.LiveDeviceRuntime=R end
end
require('src.bootstrap').install()
if config.mode=='smoke' then
    local load=love.load
    function love.load(...)
        local g=love.graphics
        local width,height=g.getDimensions()
        local font=g.newFont(22)
        g.push('all');g.setCanvas();g.origin();g.setScissor();g.setShader()
        g.clear(.035,.055,.065,1);g.setColor(.9,.95,.9,1);g.setFont(font)
        g.printf('GAMEPLAY TESTS RUNNING\n\nPlease leave the game open.\nThis can take several minutes.\nResults are being saved.',
            24,height*.26,width-48,'center')
        g.pop();g.present();font:release()
        return load(...)
    end
end
if config.mode=='live' then
    local load,update=love.load,love.update
    function love.load(...)
        load(...)
        _G.LiveDeviceRuntime.liveEvidenceRoot=root
        assert(love.filesystem.load('live-device-controller.lua'))()(_G.LiveDeviceRuntime,config)
    end
    function love.update(dt)
        update(dt)
        if _G.LiveDeviceRuntime.liveDevicePoll then _G.LiveDeviceRuntime.liveDevicePoll(dt) end
    end
end
