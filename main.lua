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
