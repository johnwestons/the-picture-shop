-- Components share one private context and preserve the public Protocol API.
local Runtime = {}
require("src.net.protocol.context").install(Runtime)
require("src.net.protocol.validation").install(Runtime)
require("src.net.protocol.interactions").install(Runtime)
require("src.net.protocol.workshop_contract").install(Runtime)
require("src.net.protocol.reception").install(Runtime)
require("src.net.protocol.wrapper").install(Runtime)
require("src.net.protocol.cutter").install(Runtime)
require("src.net.protocol.windmill").install(Runtime)
require("src.net.protocol.workshop_views").install(Runtime)
require("src.net.protocol.workshop_commands").install(Runtime)
require("src.net.protocol.workshop_snapshots").install(Runtime)
require("src.net.protocol.world_snapshots").install(Runtime)
require("src.net.protocol.envelope").install(Runtime)

return Runtime.Protocol
