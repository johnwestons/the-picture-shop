-- Components share one private context and preserve the public DirectTransport API.
local Runtime = {}
require("src.net.transport_direct.context").install(Runtime)
require("src.net.transport_direct.admission").install(Runtime)
require("src.net.transport_direct.handshake").install(Runtime)
require("src.net.transport_direct.receive").install(Runtime)
require("src.net.transport_direct.service").install(Runtime)
require("src.net.transport_direct.send").install(Runtime)
require("src.net.transport_direct.factory").install(Runtime)

return Runtime.DirectTransport
