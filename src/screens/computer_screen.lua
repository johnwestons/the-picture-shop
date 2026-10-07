-- Each office console owns its context, including remote and local instances.
local function create(dependencies)
    local Runtime = { dependencies = dependencies or {} }
    require("src.screens.computer.context").install(Runtime)
    require("src.screens.computer.warehouse").install(Runtime)
    require("src.screens.computer.navigation").install(Runtime)
    require("src.screens.computer.shopping").install(Runtime)
    require("src.screens.computer.job_queries").install(Runtime)
    require("src.screens.computer.actions").install(Runtime)
    require("src.screens.computer.pointer").install(Runtime)
    require("src.screens.computer.text_input").install(Runtime)
    require("src.screens.computer.chrome").install(Runtime)
    require("src.screens.computer.jobs").install(Runtime)
    require("src.screens.computer.suppliers").install(Runtime)
    require("src.screens.computer.finance").install(Runtime)
    require("src.screens.computer.email").install(Runtime)
    require("src.screens.computer.calendar").install(Runtime)
    require("src.screens.computer.render").install(Runtime)
    return Runtime.ComputerScreen
end

local default = create()
default.new = create
return default
