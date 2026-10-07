-- Each office console owns its context, including remote and local instances.
local function create(dependencies)
    local Runtime = { dependencies = dependencies or {} }
    require("src.screens.machine.context").install(Runtime)
    require("src.screens.machine.maintenance").install(Runtime)
    require("src.screens.machine.wrapper").install(Runtime)
    require("src.screens.machine.lubrication").install(Runtime)
    require("src.screens.machine.paper").install(Runtime)
    require("src.screens.machine.render").install(Runtime)
    require("src.screens.machine.pointer").install(Runtime)
    require("src.screens.machine.controls").install(Runtime)
    require("src.screens.machine.remote_service").install(Runtime)
    return Runtime.Screen
end

local default = create()
default.new = create
return default
