if os.getenv("PICTURE_SHOP_WAREHOUSE_ACCEPTANCE") == "1" then
    love.filesystem.setIdentity("the-picture-shop-warehouse-acceptance")
    require("src.warehouse_acceptance_runner").install()
elseif os.getenv("PICTURE_SHOP_FORKLIFT_LAB") == "1" then
    local Lab = require("src.screens.forklift_lift_lab")
    function love.load() Lab.load() end
    function love.update(dt) Lab.update(dt) end
    function love.draw() Lab.draw() end
    function love.keypressed(key) Lab.keypressed(key) end
    function love.mousepressed(x, y, button, istouch) Lab.mousepressed(x, y, button, istouch) end
    function love.touchpressed(id, x, y) Lab.touchpressed(id, x, y) end
    function love.quit() Lab.quit() end
elseif os.getenv("PICTURE_SHOP_LAN_LOOPBACK") == "1" then
    local Probe = require("src.net.loopback_probe")
    function love.load()
        local ok, message = Probe.run({
            port = tonumber(os.getenv("PICTURE_SHOP_LAN_LOOPBACK_PORT")) or 22129,
        })
        print((ok and "[LAN LOOPBACK] PASS: " or "[LAN LOOPBACK] FAIL: ") .. tostring(message))
        io.flush()
        love.event.quit(ok and 0 or 1)
    end
else
    local app = require("src.app")

    function love.load() app.load() end
    function love.update(dt) app.update(dt) end
    function love.draw() app.draw() end
    function love.keypressed(key) app.keypressed(key) end
    function love.keyreleased(key) app.keyreleased(key) end
    function love.textinput(text) app.textinput(text) end
    function love.mousepressed(x, y, button, istouch) app.mousepressed(x, y, button, istouch) end
    function love.mousereleased(x, y, button, istouch) app.mousereleased(x, y, button, istouch) end
    function love.mousemoved(x, y, dx, dy, istouch) app.mousemoved(x, y, dx, dy, istouch) end
    function love.wheelmoved(x, y) app.wheelmoved(x, y) end
    function love.touchpressed(id, x, y) app.touchpressed(id, x, y) end
    function love.touchmoved(id, x, y, dx, dy) app.touchmoved(id, x, y, dx, dy) end
    function love.touchreleased(id, x, y) app.touchreleased(id, x, y) end
    function love.gamepadpressed(joystick, button) app.gamepadpressed(joystick, button) end
    function love.gamepadreleased(joystick, button) app.gamepadreleased(joystick, button) end
    function love.focus(focused) app.focus(focused) end
    function love.quit() app.quit() end
end
