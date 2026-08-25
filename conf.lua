function love.conf(t)
    t.identity = "the-picture-shop"
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
