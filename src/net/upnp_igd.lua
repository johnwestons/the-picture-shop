-- Components share one private context and preserve the public UpnpIgd API.
local Runtime = {}
require("src.net.upnp_igd.context").install(Runtime)
require("src.net.upnp_igd.urls").install(Runtime)
require("src.net.upnp_igd.discovery").install(Runtime)
require("src.net.upnp_igd.http").install(Runtime)
require("src.net.upnp_igd.xml").install(Runtime)
require("src.net.upnp_igd.descriptions").install(Runtime)
require("src.net.upnp_igd.soap_requests").install(Runtime)
require("src.net.upnp_igd.soap_responses").install(Runtime)

return Runtime.UpnpIgd
