-- Components share one private context and preserve the public Fleet API.
local Runtime = {}
require("src.machine_fleet.catalog").install(Runtime)
require("src.machine_fleet.normalization").install(Runtime)
require("src.machine_fleet.maintenance").install(Runtime)
require("src.machine_fleet.operation").install(Runtime)
require("src.machine_fleet.purchases").install(Runtime)
require("src.machine_fleet.sales").install(Runtime)
require("src.machine_fleet.validation").install(Runtime)

return Runtime.Fleet
