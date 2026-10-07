-- Components share one private context and preserve the public Screen API.
local Runtime = {}
require("src.screens.workshop_remote.context").install(Runtime)
require("src.screens.workshop_remote.views").install(Runtime)
require("src.screens.workshop_remote.lifecycle").install(Runtime)
require("src.screens.workshop_remote.keyboard").install(Runtime)
require("src.screens.workshop_remote.machine_actions").install(Runtime)
require("src.screens.workshop_remote.pointer").install(Runtime)
require("src.screens.workshop_remote.reception").install(Runtime)
require("src.screens.workshop_remote.wrapper").install(Runtime)
require("src.screens.workshop_remote.cutter").install(Runtime)
require("src.screens.workshop_remote.windmill").install(Runtime)
require("src.screens.workshop_remote.render").install(Runtime)

return Runtime.Screen
