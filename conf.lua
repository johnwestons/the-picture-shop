function love.conf(t)
    if os.getenv("PICTURE_SHOP_CUTSCENE_STUDIO") == "1" then
        t.identity = "the-picture-shop-cutscene-studio"
        t.version = "11.5"
        t.externalstorage = false
        t.window.title = "The Picture Shop - Cutscene Studio"
        t.window.width = 1440
        t.window.height = 900
        t.window.minwidth = 1100
        t.window.minheight = 760
        t.window.resizable = true
        t.window.vsync = 1
        t.modules.physics = false
        t.modules.joystick = false
        return
    end

    if os.getenv("PICTURE_SHOP_PRIVATE_SERVER") == "1" then
        -- The private dedicated server has its own persistence namespace and
        -- intentionally starts without window, renderer, audio or input devices.
        t.identity = "the-picture-shop-server-private"
        t.version = "11.5"
        t.externalstorage = false
        t.console = true
        t.window = nil
        t.modules.window = false
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.sound = false
        t.modules.joystick = false
        t.modules.mouse = false
        t.modules.keyboard = false
        t.modules.touch = false
        t.modules.video = false
        t.modules.physics = false
        t.modules.thread = true
        t.modules.event = true
        t.modules.filesystem = true
        t.modules.timer = true
        t.modules.system = true
        return
    end

    t.identity = os.getenv("PICTURE_SHOP_SMOKE") == "1"
        and "the-picture-shop-smoke" or "the-picture-shop"
    -- A new isolated identity lets art/test runs leave existing saves alone.
    local testIdentity = os.getenv("PICTURE_SHOP_TEST_IDENTITY")
    if os.getenv("PICTURE_SHOP_SMOKE") == "1" and testIdentity
        and testIdentity:match("^the%-picture%-shop%-test%-[%w%-]+$") then
        t.identity = testIdentity
    end
    t.version = "11.5"
    t.externalstorage = false
    t.accelerometerjoystick = false
    t.window.title = "The Picture Shop"
    t.window.width = 960
    t.window.height = 678
    t.window.minwidth = 720
    t.window.minheight = 509
    t.window.resizable = true
    t.window.vsync = 1
    t.window.highdpi = false
    if love._os == "Android" then
        t.window.resizable = false
        t.window.fullscreen = true
        t.window.fullscreentype = "desktop"
    end
end
