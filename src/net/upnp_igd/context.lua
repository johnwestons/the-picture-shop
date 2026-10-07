-- UPnP constants, trust registries, and low-level HTTP field checks.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.IpScope = require("src.net.ip_scope")

    Runtime.UpnpIgd = {
        SSDP_ADDRESS = "239.255.255.250",
        SSDP_PORT = 1900,
        IGD2_TARGET = "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
        IGD1_TARGET = "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
        WAN_DEVICE_V2 = "urn:schemas-upnp-org:device:WANDevice:2",
        WAN_DEVICE_V1 = "urn:schemas-upnp-org:device:WANDevice:1",
        WAN_CONNECTION_DEVICE_V2 = "urn:schemas-upnp-org:device:WANConnectionDevice:2",
        WAN_CONNECTION_DEVICE_V1 = "urn:schemas-upnp-org:device:WANConnectionDevice:1",
        WAN_IP_V2 = "urn:schemas-upnp-org:service:WANIPConnection:2",
        WAN_IP_V1 = "urn:schemas-upnp-org:service:WANIPConnection:1",
        WAN_PPP_V1 = "urn:schemas-upnp-org:service:WANPPPConnection:1",
        SOAP_ENVELOPE = "http://schemas.xmlsoap.org/soap/envelope/",
        UPNP_CONTROL = "urn:schemas-upnp-org:control-1-0",
        DEVICE_NAMESPACE = "urn:schemas-upnp-org:device-1-0",
        MAX_SSDP_BYTES = 16 * 1024,
        MAX_HTTP_HEADER_BYTES = 16 * 1024,
        MAX_DESCRIPTION_BYTES = 256 * 1024,
        MAX_SOAP_BODY_BYTES = 64 * 1024,
        MAX_URL_BYTES = 2048,
        MAX_XML_NODES = 4096,
        MAX_XML_DEPTH = 64,
        MAX_SSDP_MAX_AGE_SECONDS = 7 * 24 * 60 * 60,
        MAX_LEASE_SECONDS = 3600,
        MIN_UNPRIVILEGED_PORT = 1024,
    }

    -- These weak registries keep network-derived contexts and successful mapping
    -- handles opaque. Callers cannot fabricate a service or delete an arbitrary
    -- port by assembling a look-alike Lua table.
    Runtime.TRUSTED_DISCOVERIES = setmetatable({}, { __mode = "k" })
    Runtime.TRUSTED_SERVICES = setmetatable({}, { __mode = "k" })
    Runtime.TRUSTED_REQUESTS = setmetatable({}, { __mode = "k" })
    Runtime.TRUSTED_MAPPING_HANDLES = setmetatable({}, { __mode = "k" })

    function Runtime.integerInRange(value, minimum, maximum)
        return type(value) == "number" and value == math.floor(value)
            and value >= minimum and value <= maximum
            and value == value and value ~= math.huge and value ~= -math.huge
    end

    function Runtime.finiteNonnegative(value)
        return type(value) == "number" and value >= 0 and value == value
            and value ~= math.huge and value ~= -math.huge
    end

    function Runtime.trim(value)
        return (value:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
    end

    function Runtime.hasControl(value, allowHttpTab)
        for index = 1, #value do
            local byte = value:byte(index)
            if byte == 127 or byte < 32
                and not (allowHttpTab and byte == 9)
                and byte ~= 10 and byte ~= 13
            then
                return true
            end
        end
        return false
    end

    function Runtime.isLocalGatewayAddress(value)
        local parsed = Runtime.IpScope.parse(value)
        if not parsed then return false end
        local classification = Runtime.IpScope.classify(value)
        return classification.reason == "private_use"
            or classification.reason == "link_local"
    end

    function Runtime.validHeaderName(value)
        return type(value) == "string" and value ~= ""
            and value:match("^[!#$%%&'*+%.%^_`|~%w%-]+$") ~= nil
    end

    function Runtime.splitCrLfLines(value)
        if value:find("\n", 1, true) and value:gsub("\r\n", ""):find("\n", 1, true) then
            return nil, "message contains a bare line feed"
        end
        if value:find("\r", 1, true) and value:gsub("\r\n", ""):find("\r", 1, true) then
            return nil, "message contains a bare carriage return"
        end

        local lines = {}
        local position = 1
        while true do
            local ending = value:find("\r\n", position, true)
            if not ending then
                lines[#lines + 1] = value:sub(position)
                break
            end
            lines[#lines + 1] = value:sub(position, ending - 1)
            position = ending + 2
        end
        return lines
    end

    function Runtime.parseHeaderBlock(block)
        local lines, lineError = Runtime.splitCrLfLines(block)
        if not lines then return nil, lineError end
        if #lines < 1 or lines[1] == "" then return nil, "message has no start line" end
        if #lines > 129 then return nil, "message has too many header fields" end

        local headers = {}
        for index = 2, #lines do
            local line = lines[index]
            if #line > 2048 then return nil, "header field is too long" end
            if line:match("^[ \t]") then return nil, "folded header fields are not accepted" end
            local name, value = line:match("^([^:]+):(.*)$")
            if not name or not Runtime.validHeaderName(name) then return nil, "invalid header field" end
            value = value:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
            if Runtime.hasControl(value, true) then return nil, "header value contains control bytes" end
            local key = name:lower()
            if headers[key] ~= nil then return nil, "duplicate header field: " .. key end
            headers[key] = value
        end
        return {
            startLine = lines[1],
            headers = headers,
        }
    end
end

return Component
