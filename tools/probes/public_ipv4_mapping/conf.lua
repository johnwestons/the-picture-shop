function love.conf(t)
    t.identity = "tps-public-ipv4-acceptance"
    t.version = "11.5"
    t.console = true
    t.window.title = "The Picture Shop - Public IPv4 Acceptance Test"
    t.window.width = 940
    t.window.height = 620
    t.window.resizable = false
    t.window.vsync = 1
    t.modules.audio = false
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
