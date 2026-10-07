-- Components share one private context and preserve the public World API.
local Runtime = {}
require("src.world.context").install(Runtime)
require("src.world.placement").install(Runtime)
require("src.world.interactions").install(Runtime)
require("src.world.simulation").install(Runtime)
require("src.world.movement").install(Runtime)
require("src.world.workshop_access").install(Runtime)
require("src.world.customer_actions").install(Runtime)
require("src.world.truck_actions").install(Runtime)
require("src.world.pallet_controls").install(Runtime)
require("src.world.network_relocation").install(Runtime)
require("src.world.machine_relocation").install(Runtime)
require("src.world.snapshots").install(Runtime)
require("src.world.warehouse").install(Runtime)
require("src.world.employees").install(Runtime)

return Runtime.World
