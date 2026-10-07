-- Components share one private context and preserve the public Session API.
local Runtime = {}
require("src.net.session.context").install(Runtime)
require("src.net.session.lifecycle").install(Runtime)
require("src.net.session.send").install(Runtime)
require("src.net.session.high_five").install(Runtime)
require("src.net.session.workshop").install(Runtime)
require("src.net.session.roster").install(Runtime)
require("src.net.session.admission").install(Runtime)
require("src.net.session.host_messages").install(Runtime)
require("src.net.session.client_messages").install(Runtime)
require("src.net.session.service").install(Runtime)
require("src.net.session.client_update").install(Runtime)
require("src.net.session.workshop_controls").install(Runtime)

return Runtime.Session
