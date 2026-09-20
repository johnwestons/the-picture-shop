local IpScope = require("src.net.ip_scope")

local UpnpIgd = {
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
local TRUSTED_DISCOVERIES = setmetatable({}, { __mode = "k" })
local TRUSTED_SERVICES = setmetatable({}, { __mode = "k" })
local TRUSTED_REQUESTS = setmetatable({}, { __mode = "k" })
local TRUSTED_MAPPING_HANDLES = setmetatable({}, { __mode = "k" })

local function integerInRange(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
        and value == value and value ~= math.huge and value ~= -math.huge
end

local function finiteNonnegative(value)
    return type(value) == "number" and value >= 0 and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function trim(value)
    return (value:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

local function hasControl(value, allowHttpTab)
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

local function isLocalGatewayAddress(value)
    local parsed = IpScope.parse(value)
    if not parsed then return false end
    local classification = IpScope.classify(value)
    return classification.reason == "private_use"
        or classification.reason == "link_local"
end

local function validHeaderName(value)
    return type(value) == "string" and value ~= ""
        and value:match("^[!#$%%&'*+%.%^_`|~%w%-]+$") ~= nil
end

local function splitCrLfLines(value)
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

local function parseHeaderBlock(block)
    local lines, lineError = splitCrLfLines(block)
    if not lines then return nil, lineError end
    if #lines < 1 or lines[1] == "" then return nil, "message has no start line" end
    if #lines > 129 then return nil, "message has too many header fields" end

    local headers = {}
    for index = 2, #lines do
        local line = lines[index]
        if #line > 2048 then return nil, "header field is too long" end
        if line:match("^[ \t]") then return nil, "folded header fields are not accepted" end
        local name, value = line:match("^([^:]+):(.*)$")
        if not name or not validHeaderName(name) then return nil, "invalid header field" end
        value = value:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
        if hasControl(value, true) then return nil, "header value contains control bytes" end
        local key = name:lower()
        if headers[key] ~= nil then return nil, "duplicate header field: " .. key end
        headers[key] = value
    end
    return {
        startLine = lines[1],
        headers = headers,
    }
end

local function percentEncodingIsValid(value)
    local position = 1
    while true do
        local marker = value:find("%", position, true)
        if not marker then return true end
        if not value:sub(marker + 1, marker + 2):match("^[0-9A-Fa-f][0-9A-Fa-f]$") then
            return false
        end
        position = marker + 3
    end
end

local function normalizePath(path)
    if path == "" then return "/" end
    if path:sub(1, 1) ~= "/" then return nil, "HTTP URL path must be absolute" end
    local trailingSlash = path:sub(-1) == "/"
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        if segment == "." then
            -- Nothing.
        elseif segment == ".." then
            if #segments > 0 then table.remove(segments) end
        else
            segments[#segments + 1] = segment
        end
    end
    local normalized = "/" .. table.concat(segments, "/")
    if trailingSlash and normalized ~= "/" then normalized = normalized .. "/" end
    return normalized
end

local function parseHttpUrl(value)
    if type(value) ~= "string" then return nil, "UPnP URL must be text" end
    value = trim(value)
    if value == "" or #value > UpnpIgd.MAX_URL_BYTES then
        return nil, "UPnP URL is empty or too long"
    end
    if hasControl(value, false) or value:find("[ \t\r\n]")
        or value:find("\\", 1, true) or value:find("#", 1, true)
    then
        return nil, "UPnP URL contains a forbidden character"
    end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 33 or byte > 126 then return nil, "UPnP URL must be ASCII" end
    end
    if not percentEncodingIsValid(value) then return nil, "UPnP URL has invalid percent encoding" end

    local scheme, remainder = value:match("^([A-Za-z][A-Za-z0-9+%.%-]*)://(.*)$")
    if not scheme or scheme:lower() ~= "http" then
        return nil, "UPnP URL must use plain HTTP on the local gateway"
    end
    local authority, target = remainder:match("^([^/]*)(/.*)$")
    if not authority then authority, target = remainder, "/" end
    if authority == "" or authority:find("@", 1, true) then
        return nil, "UPnP URL authority is invalid"
    end

    local host, portText = authority, nil
    local colon = authority:find(":", 1, true)
    if colon then
        if authority:find(":", colon + 1, true) then
            return nil, "IPv6 UPnP URLs are not supported"
        end
        host, portText = authority:sub(1, colon - 1), authority:sub(colon + 1)
    end
    local parsedHost = IpScope.parse(host)
    if not parsedHost or parsedHost.address ~= host then
        return nil, "UPnP URL host must be canonical IPv4 text"
    end
    local port = 80
    if portText then
        if not portText:match("^%d+$") or #portText > 5 then
            return nil, "UPnP URL port is invalid"
        end
        port = tonumber(portText)
        if not integerInRange(port, 1, 65535) then return nil, "UPnP URL port is invalid" end
    end

    local path, query = target, ""
    local question = target:find("?", 1, true)
    if question then
        path, query = target:sub(1, question - 1), target:sub(question)
    end
    local normalizedPath, pathError = normalizePath(path)
    if not normalizedPath then return nil, pathError end
    local requestTarget = normalizedPath .. query
    local hostHeader = host .. (port == 80 and "" or ":" .. tostring(port))
    local origin = "http://" .. host .. ":" .. tostring(port)
    return {
        scheme = "http",
        host = host,
        port = port,
        hostHeader = hostHeader,
        origin = origin,
        path = requestTarget,
        pathOnly = normalizedPath,
        query = query,
        url = "http://" .. hostHeader .. requestTarget,
    }
end

local function resolveUrl(reference, base, trustedOrigin)
    if type(reference) ~= "string" then return nil, "UPnP control URL must be text" end
    reference = trim(reference)
    if reference == "" or #reference > UpnpIgd.MAX_URL_BYTES then
        return nil, "UPnP control URL is empty or too long"
    end
    if hasControl(reference, false) or reference:find("\\", 1, true)
        or reference:find("#", 1, true) or reference:find("[ \t\r\n]")
    then
        return nil, "UPnP control URL contains a forbidden character"
    end

    local candidate
    if reference:match("^[A-Za-z][A-Za-z0-9+%.%-]*://") then
        candidate = reference
    elseif reference:sub(1, 2) == "//" then
        candidate = "http:" .. reference
    elseif reference:sub(1, 1) == "/" then
        candidate = base.origin .. reference
    elseif reference:sub(1, 1) == "?" then
        candidate = base.origin .. base.pathOnly .. reference
    else
        local directory = base.pathOnly:match("^(.*)/") or ""
        candidate = base.origin .. directory .. "/" .. reference
    end

    local resolved, resolveError = parseHttpUrl(candidate)
    if not resolved then return nil, resolveError end
    if resolved.origin ~= trustedOrigin then
        return nil, "UPnP control URL leaves the responding gateway origin"
    end
    return resolved
end

function UpnpIgd.buildSearchRequest(version, mxSeconds)
    local target
    if version == 2 or version == UpnpIgd.IGD2_TARGET then
        target = UpnpIgd.IGD2_TARGET
    elseif version == 1 or version == UpnpIgd.IGD1_TARGET then
        target = UpnpIgd.IGD1_TARGET
    else
        return nil, "UPnP search version must be IGD 2 or IGD 1"
    end
    mxSeconds = mxSeconds == nil and 2 or mxSeconds
    if not integerInRange(mxSeconds, 1, 5) then
        return nil, "UPnP multicast response window must be 1 to 5 seconds"
    end

    local request = table.concat({
        "M-SEARCH * HTTP/1.1",
        "HOST: " .. UpnpIgd.SSDP_ADDRESS .. ":" .. tostring(UpnpIgd.SSDP_PORT),
        "MAN: \"ssdp:discover\"",
        "MX: " .. tostring(mxSeconds),
        "ST: " .. target,
        "",
        "",
    }, "\r\n")
    return request, {
        expectedTarget = target,
        destinationAddress = UpnpIgd.SSDP_ADDRESS,
        destinationPort = UpnpIgd.SSDP_PORT,
        mxSeconds = mxSeconds,
    }
end

function UpnpIgd.buildSearchRequests(mxSeconds)
    local second, secondContext = UpnpIgd.buildSearchRequest(2, mxSeconds)
    if not second then return nil, secondContext end
    local first, firstContext = UpnpIgd.buildSearchRequest(1, mxSeconds)
    return {
        { bytes = second, context = secondContext },
        { bytes = first, context = firstContext },
    }
end

local function parseSsdpMaxAge(value)
    if type(value) ~= "string" then return nil, "SSDP response is missing CACHE-CONTROL" end
    local secondsText = value:lower():match("^max%-age%s*=%s*(%d+)$")
    if not secondsText or #secondsText > 10 then
        return nil, "SSDP CACHE-CONTROL must contain only a max-age directive"
    end
    local seconds = tonumber(secondsText)
    if not integerInRange(seconds, 1, UpnpIgd.MAX_SSDP_MAX_AGE_SECONDS) then
        return nil, "SSDP max-age is outside the accepted bound"
    end
    return seconds
end

local function canonicalUdnFromUsn(value, target)
    if type(value) ~= "string" or type(target) ~= "string" then
        return nil, "SSDP USN context is invalid"
    end
    local udn, suffix = value:match("^(uuid:[^:]+)::(.+)$")
    if not udn or suffix ~= target then
        return nil, "SSDP USN does not identify the advertised search target"
    end
    local first, second, third, fourth, fifth = udn:match(
        "^uuid:([0-9A-Fa-f]+)%-([0-9A-Fa-f]+)%-([0-9A-Fa-f]+)%-([0-9A-Fa-f]+)%-([0-9A-Fa-f]+)$")
    if not first or #first ~= 8 or #second ~= 4 or #third ~= 4
        or #fourth ~= 4 or #fifth ~= 12
    then
        return nil, "SSDP USN does not contain a canonical UUID"
    end
    return udn:lower()
end

function UpnpIgd.parseSsdpResponse(data, expected)
    if type(data) ~= "string" then return nil, "SSDP response must be bytes" end
    if #data > UpnpIgd.MAX_SSDP_BYTES then return nil, "SSDP response is too large" end
    expected = expected or {}
    local separator = data:find("\r\n\r\n", 1, true)
    if not separator then return nil, "SSDP response has no complete header block" end
    if data:sub(separator + 4) ~= "" then return nil, "SSDP response unexpectedly has a body" end

    local parsed, parseError = parseHeaderBlock(data:sub(1, separator - 1))
    if not parsed then return nil, parseError end
    if parsed.startLine ~= "HTTP/1.1 200 OK" and parsed.startLine ~= "HTTP/1.0 200 OK" then
        return nil, "SSDP response status is not 200 OK"
    end

    local sourceAddress = expected.sourceAddress
    if not isLocalGatewayAddress(sourceAddress) then
        return nil, "SSDP response source is not a private or link-local gateway"
    end
    if expected.gatewayAddress and sourceAddress ~= expected.gatewayAddress then
        return nil, "SSDP response source does not match the queried gateway"
    end

    local headers = parsed.headers
    local locationText, searchTarget, usn = headers.location, headers.st, headers.usn
    if not locationText or not searchTarget or not usn or usn == "" or #usn > 512
        or not headers.server or headers.server == ""
    then
        return nil, "SSDP response is missing LOCATION, SERVER, ST, or USN"
    end
    if headers.ext == nil or headers.ext ~= "" then
        return nil, "SSDP response must contain an empty EXT field"
    end
    local maxAge, maxAgeError = parseSsdpMaxAge(headers["cache-control"])
    if not maxAge then return nil, maxAgeError end
    if searchTarget ~= UpnpIgd.IGD2_TARGET and searchTarget ~= UpnpIgd.IGD1_TARGET then
        return nil, "SSDP response is not for a supported Internet Gateway Device"
    end
    if expected.expectedTarget and searchTarget ~= expected.expectedTarget then
        return nil, "SSDP response search target does not match the request"
    end
    local udn, usnError = canonicalUdnFromUsn(usn, searchTarget)
    if not udn then return nil, usnError end
    local bootId
    if headers.server:find("UPnP/1.1", 1, true) then
        local bootText = headers["bootid.upnp.org"]
        if not bootText or not bootText:match("^%d+$") or #bootText > 10 then
            return nil, "UPnP 1.1 SSDP response has no valid BOOTID"
        end
        bootId = tonumber(bootText)
        if not integerInRange(bootId, 1, 2147483647) then
            return nil, "UPnP 1.1 SSDP BOOTID is outside its valid range"
        end
    end

    local location, locationError = parseHttpUrl(locationText)
    if not location then return nil, locationError end
    if location.host ~= sourceAddress then
        return nil, "SSDP LOCATION does not point back to the responding gateway"
    end
    local discovery = {
        location = location,
        searchTarget = searchTarget,
        usn = usn,
        udn = udn,
        maxAgeSeconds = maxAge,
        bootId = bootId,
        server = headers.server,
        sourceAddress = sourceAddress,
        gatewayAddress = sourceAddress,
        headers = headers,
    }
    TRUSTED_DISCOVERIES[discovery] = {
        gatewayAddress = discovery.gatewayAddress,
        searchTarget = discovery.searchTarget,
        usn = discovery.usn,
        udn = discovery.udn,
        locationUrl = location.url,
        locationOrigin = location.origin,
        locationHost = location.host,
        locationPort = location.port,
        locationHostHeader = location.hostHeader,
        locationPath = location.path,
        locationPathOnly = location.pathOnly,
        locationQuery = location.query,
    }
    return discovery
end

local function decodeChunkedBody(value, limit)
    local output, total, position = {}, 0, 1
    while true do
        local lineEnd = value:find("\r\n", position, true)
        if not lineEnd or lineEnd - position > 32 then return nil, "invalid chunk size line" end
        local sizeText = value:sub(position, lineEnd - 1)
        if not sizeText:match("^[0-9A-Fa-f]+$") or #sizeText > 8 then
            return nil, "invalid chunk size"
        end
        local size = tonumber(sizeText, 16)
        position = lineEnd + 2
        if size == 0 then
            if value:sub(position) ~= "\r\n" then
                return nil, "chunked response trailers are not accepted"
            end
            return table.concat(output)
        end
        total = total + size
        if total > limit then return nil, "chunked response body is too large" end
        local dataEnd = position + size - 1
        if dataEnd > #value or value:sub(dataEnd + 1, dataEnd + 2) ~= "\r\n" then
            return nil, "truncated chunked response body"
        end
        output[#output + 1] = value:sub(position, dataEnd)
        position = dataEnd + 3
    end
end

function UpnpIgd.parseHttpResponse(data, maxBodyBytes)
    maxBodyBytes = maxBodyBytes or UpnpIgd.MAX_SOAP_BODY_BYTES
    if type(data) ~= "string" then return nil, "HTTP response must be bytes" end
    if not integerInRange(maxBodyBytes, 0, UpnpIgd.MAX_DESCRIPTION_BYTES) then
        return nil, "HTTP body limit is invalid"
    end
    local separator = data:find("\r\n\r\n", 1, true)
    if not separator then return nil, "HTTP response has no complete header block" end
    if separator - 1 > UpnpIgd.MAX_HTTP_HEADER_BYTES then
        return nil, "HTTP response headers are too large"
    end
    local parsed, parseError = parseHeaderBlock(data:sub(1, separator - 1))
    if not parsed then return nil, parseError end
    local version, statusText, reason = parsed.startLine:match(
        "^HTTP/(1%.[01]) ([0-9][0-9][0-9]) ([\t -~]*)$")
    local statusCode = tonumber(statusText)
    if not version or not integerInRange(statusCode, 100, 599) then
        return nil, "HTTP response status line is invalid"
    end

    local body = data:sub(separator + 4)
    local lengthText = parsed.headers["content-length"]
    local transferEncoding = parsed.headers["transfer-encoding"]
    if lengthText and transferEncoding then
        return nil, "HTTP response has both content length and transfer encoding"
    end
    if transferEncoding then
        if transferEncoding:lower() ~= "chunked" then
            return nil, "unsupported HTTP transfer encoding"
        end
        body, parseError = decodeChunkedBody(body, maxBodyBytes)
        if not body then return nil, parseError end
    elseif lengthText then
        if not lengthText:match("^%d+$") or #lengthText > 10 then
            return nil, "HTTP content length is invalid"
        end
        local expectedLength = tonumber(lengthText)
        if expectedLength ~= #body then return nil, "HTTP content length does not match body" end
    end
    if #body > maxBodyBytes then return nil, "HTTP response body is too large" end
    return {
        version = version,
        statusCode = statusCode,
        reason = reason,
        headers = parsed.headers,
        body = body,
    }
end

function UpnpIgd.buildDescriptionRequest(discovery)
    local trust = type(discovery) == "table" and TRUSTED_DISCOVERIES[discovery] or nil
    if not trust or type(discovery.location) ~= "table"
        or discovery.gatewayAddress ~= trust.gatewayAddress
        or discovery.searchTarget ~= trust.searchTarget
        or discovery.usn ~= trust.usn
        or discovery.udn ~= trust.udn
        or discovery.location.url ~= trust.locationUrl
        or discovery.location.origin ~= trust.locationOrigin
        or discovery.location.host ~= trust.locationHost
        or discovery.location.port ~= trust.locationPort
        or discovery.location.hostHeader ~= trust.locationHostHeader
        or discovery.location.path ~= trust.locationPath
        or discovery.location.pathOnly ~= trust.locationPathOnly
        or discovery.location.query ~= trust.locationQuery
    then
        return nil, "trusted SSDP discovery context is required"
    end
    local wire = table.concat({
        "GET " .. discovery.location.path .. " HTTP/1.1",
        "HOST: " .. discovery.location.hostHeader,
        "ACCEPT: text/xml, application/xml",
        "CONNECTION: close",
        "",
        "",
    }, "\r\n")
    return {
        method = "GET",
        url = discovery.location.url,
        path = discovery.location.path,
        host = discovery.location.host,
        port = discovery.location.port,
        wire = wire,
        context = { kind = "description" },
    }
end

local XML_NAME = "[%a_:][%w_.:%-]*"

local function encodeUtf8(codepoint)
    if codepoint <= 127 then return string.char(codepoint) end
    if codepoint <= 2047 then
        return string.char(192 + math.floor(codepoint / 64), 128 + codepoint % 64)
    end
    if codepoint <= 65535 then
        return string.char(
            224 + math.floor(codepoint / 4096),
            128 + math.floor(codepoint / 64) % 64,
            128 + codepoint % 64)
    end
    return string.char(
        240 + math.floor(codepoint / 262144),
        128 + math.floor(codepoint / 4096) % 64,
        128 + math.floor(codepoint / 64) % 64,
        128 + codepoint % 64)
end

local function decodeCharacterReference(name)
    local codepoint
    if name:match("^#[0-9]+$") and #name <= 8 then
        codepoint = tonumber(name:sub(2), 10)
    elseif name:match("^#[xX][0-9A-Fa-f]+$") and #name <= 9 then
        codepoint = tonumber(name:sub(3), 16)
    end
    if not codepoint or codepoint > 1114111
        or codepoint >= 55296 and codepoint <= 57343
        or not (codepoint == 9 or codepoint == 10 or codepoint == 13
            or codepoint >= 32 and codepoint <= 55295
            or codepoint >= 57344 and codepoint <= 65533
            or codepoint >= 65536 and codepoint <= 1114111)
    then
        return nil
    end
    return encodeUtf8(codepoint)
end

local function decodeXmlText(value)
    local replacements = {
        amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'",
    }
    local output, position = {}, 1
    while true do
        local marker = value:find("&", position, true)
        if not marker then
            output[#output + 1] = value:sub(position)
            break
        end
        output[#output + 1] = value:sub(position, marker - 1)
        local ending = value:find(";", marker + 1, true)
        if not ending or ending - marker > 10 then return nil, "unsupported XML entity" end
        local name = value:sub(marker + 1, ending - 1)
        local replacement = replacements[name] or decodeCharacterReference(name)
        if not replacement then return nil, "document-defined XML entities are not accepted" end
        output[#output + 1] = replacement
        position = ending + 1
    end
    return table.concat(output)
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function findTagEnd(xml, position)
    local quote
    for index = position, #xml do
        local character = xml:sub(index, index)
        if quote then
            if character == quote then quote = nil end
        elseif character == "\"" or character == "'" then
            quote = character
        elseif character == ">" then
            return index
        end
        if index - position > 4096 then return nil end
    end
    return nil
end

local function parseStartTag(content)
    local selfClosing = content:match("/%s*$") ~= nil
    if selfClosing then content = content:gsub("/%s*$", "") end
    local position = content:find("%S")
    if not position then return nil, "empty XML tag" end
    local name = content:sub(position):match("^(" .. XML_NAME .. ")")
    if not name then return nil, "invalid XML element name" end
    position = position + #name
    local attributes = {}
    while true do
        local whitespace = content:sub(position):match("^[ \t\r\n]*") or ""
        position = position + #whitespace
        if position > #content then break end
        local attributeName = content:sub(position):match("^(" .. XML_NAME .. ")")
        if not attributeName then return nil, "invalid XML attribute name" end
        position = position + #attributeName
        whitespace = content:sub(position):match("^[ \t\r\n]*") or ""
        position = position + #whitespace
        if content:sub(position, position) ~= "=" then return nil, "XML attribute has no equals sign" end
        position = position + 1
        whitespace = content:sub(position):match("^[ \t\r\n]*") or ""
        position = position + #whitespace
        local quote = content:sub(position, position)
        if quote ~= "\"" and quote ~= "'" then return nil, "XML attribute is not quoted" end
        local ending = content:find(quote, position + 1, true)
        if not ending then return nil, "unterminated XML attribute" end
        if attributes[attributeName] ~= nil then return nil, "duplicate XML attribute" end
        local decoded, decodeError = decodeXmlText(content:sub(position + 1, ending - 1))
        if not decoded then return nil, decodeError end
        attributes[attributeName] = decoded
        position = ending + 1
    end
    return name, attributes, selfClosing
end

local function appendXmlText(stack, value)
    if value == "" then return true end
    local decoded, decodeError = decodeXmlText(value)
    if not decoded then return nil, decodeError end
    if #stack == 0 then
        if decoded:match("^%s*$") then return true end
        return nil, "XML has text outside its root element"
    end
    local parts = stack[#stack].textParts
    parts[#parts + 1] = decoded
    return true
end

local function parseXml(xml, maximumBytes)
    if type(xml) ~= "string" then return nil, "XML body must be bytes" end
    if #xml > maximumBytes then return nil, "XML body is too large" end
    if xml:find("\0", 1, true) or hasControl(xml, true) then
        return nil, "XML body contains forbidden control bytes"
    end

    local root, stack, position, nodeCount, declarationSeen = nil, {}, 1, 0, false
    while position <= #xml do
        local marker = xml:find("<", position, true)
        if not marker then
            local ok, textError = appendXmlText(stack, xml:sub(position))
            if not ok then return nil, textError end
            position = #xml + 1
            break
        end
        local ok, textError = appendXmlText(stack, xml:sub(position, marker - 1))
        if not ok then return nil, textError end

        if xml:sub(marker, marker + 3) == "<!--" then
            local ending = xml:find("-->", marker + 4, true)
            if not ending then return nil, "unterminated XML comment" end
            local comment = xml:sub(marker + 4, ending - 1)
            if comment:find("--", 1, true) then return nil, "invalid XML comment" end
            position = ending + 3
        elseif xml:sub(marker, marker + 8) == "<![CDATA[" then
            local ending = xml:find("]]>", marker + 9, true)
            if not ending then return nil, "unterminated XML CDATA" end
            if #stack == 0 then return nil, "XML CDATA appears outside the root" end
            local parts = stack[#stack].textParts
            parts[#parts + 1] = xml:sub(marker + 9, ending - 1)
            position = ending + 3
        elseif xml:sub(marker, marker + 1) == "<?" then
            local ending = xml:find("?>", marker + 2, true)
            if not ending then return nil, "unterminated XML processing instruction" end
            local instruction = xml:sub(marker + 2, ending - 1)
            if root or declarationSeen or not instruction:match("^xml%s") then
                return nil, "only one leading XML declaration is accepted"
            end
            declarationSeen = true
            position = ending + 2
        elseif xml:sub(marker, marker + 1) == "<!" then
            return nil, "XML DTDs and entity declarations are not accepted"
        else
            local ending = findTagEnd(xml, marker + 1)
            if not ending then return nil, "unterminated or oversized XML tag" end
            local content = xml:sub(marker + 1, ending - 1)
            if content:sub(1, 1) == "/" then
                local closingName = content:match("^/%s*(" .. XML_NAME .. ")%s*$")
                if not closingName or #stack == 0 or stack[#stack].name ~= closingName then
                    return nil, "mismatched XML closing tag"
                end
                table.remove(stack)
            else
                local name, attributes, selfClosing = parseStartTag(content)
                if not name then return nil, attributes end
                if root and #stack == 0 then return nil, "XML has more than one root element" end
                nodeCount = nodeCount + 1
                if nodeCount > UpnpIgd.MAX_XML_NODES then return nil, "XML has too many elements" end
                if #stack + 1 > UpnpIgd.MAX_XML_DEPTH then return nil, "XML nesting is too deep" end

                local namespaces = copyTable(#stack > 0 and stack[#stack].namespaces or nil)
                for attributeName, attributeValue in pairs(attributes) do
                    if attributeName == "xmlns" then
                        namespaces[""] = attributeValue
                    else
                        local prefix = attributeName:match("^xmlns:(" .. XML_NAME .. ")$")
                        if prefix then namespaces[prefix] = attributeValue end
                    end
                end
                local prefix, localName = name:match("^([^:]+):(.+)$")
                if not localName then prefix, localName = "", name end
                local namespace = namespaces[prefix]
                if prefix ~= "" and not namespace then return nil, "XML element prefix is undeclared" end
                local node = {
                    name = name,
                    localName = localName,
                    namespace = namespace,
                    namespaces = namespaces,
                    attributes = attributes,
                    children = {},
                    textParts = {},
                }
                if #stack > 0 then
                    local parent = stack[#stack]
                    parent.children[#parent.children + 1] = node
                else
                    root = node
                end
                if not selfClosing then stack[#stack + 1] = node end
            end
            position = ending + 1
        end
    end
    if #stack ~= 0 then return nil, "XML document is truncated" end
    if not root then return nil, "XML document has no root element" end
    return root
end

local function directChildren(node, localName, namespace)
    local result = {}
    for _, child in ipairs(node.children or {}) do
        if (not localName or child.localName == localName)
            and (namespace == nil or child.namespace == namespace)
        then
            result[#result + 1] = child
        end
    end
    return result
end

local function directChildrenExactNamespace(node, localName, namespace)
    local result = {}
    for _, child in ipairs(node.children or {}) do
        if (not localName or child.localName == localName)
            and child.namespace == namespace
        then
            result[#result + 1] = child
        end
    end
    return result
end

local function scalarText(node, allowEmpty)
    if not node or #(node.children or {}) ~= 0 then return nil, "XML scalar contains child elements" end
    local value = trim(table.concat(node.textParts or {}))
    if not allowEmpty and value == "" then return nil, "XML scalar is empty" end
    return value
end

local function singleDirectText(node, localName, namespace, allowEmpty)
    local matches = directChildren(node, localName, namespace)
    if #matches ~= 1 then return nil, "expected exactly one " .. localName .. " element" end
    return scalarText(matches[1], allowEmpty)
end

local function coerceHttpResponse(response, maximumBody)
    if type(response) ~= "table" or not integerInRange(response.statusCode, 100, 599)
        or type(response.body) ~= "string"
    then
        return nil, "structured HTTP response context is required"
    end
    if #response.body > maximumBody then return nil, "HTTP response body is too large" end
    return response
end

local function validateNoRedirect(response, expectedUrl)
    if type(expectedUrl) ~= "table" or type(expectedUrl.url) ~= "string"
        or type(expectedUrl.host) ~= "string" or not integerInRange(expectedUrl.port, 1, 65535)
    then
        return nil, "trusted HTTP request URL context is required"
    end
    if type(response.finalUrl) ~= "string"
        or type(response.peerAddress) ~= "string"
        or not integerInRange(response.peerPort, 1, 65535)
        or response.redirectCount ~= 0
    then
        return nil, "HTTP response lacks exact no-redirect peer evidence"
    end
    if response.statusCode >= 300 and response.statusCode <= 399 then
        return nil, "UPnP redirects are not allowed"
    end
    local final, finalError = parseHttpUrl(response.finalUrl)
    if not final then return nil, finalError end
    if final.url ~= expectedUrl.url then return nil, "UPnP redirect or URL substitution is not allowed" end
    if response.peerAddress ~= expectedUrl.host or response.peerPort ~= expectedUrl.port then
        return nil, "UPnP HTTP peer does not match the trusted gateway origin"
    end
    return true
end

local SERVICE_RANKS = {
    [UpnpIgd.WAN_IP_V2] = 300,
    [UpnpIgd.WAN_IP_V1] = 200,
    [UpnpIgd.WAN_PPP_V1] = 100,
}

local function embeddedDevices(deviceNode, namespace)
    local destination = {}
    for _, deviceList in ipairs(directChildren(deviceNode, "deviceList", namespace)) do
        for _, childDevice in ipairs(directChildren(deviceList, "device", namespace)) do
            destination[#destination + 1] = childDevice
        end
    end
    return destination
end

local function deviceTypeOf(deviceNode, namespace)
    return singleDirectText(deviceNode, "deviceType", namespace, false)
end

local function embeddedDevicesOfType(deviceNode, wantedType, namespace)
    local result = {}
    for _, childDevice in ipairs(embeddedDevices(deviceNode, namespace)) do
        local childType = deviceTypeOf(childDevice, namespace)
        if childType == wantedType then result[#result + 1] = childDevice end
    end
    return result
end

local function directServices(deviceNode, namespace)
    local destination = {}
    for _, serviceList in ipairs(directChildren(deviceNode, "serviceList", namespace)) do
        for _, service in ipairs(directChildren(serviceList, "service", namespace)) do
            destination[#destination + 1] = service
        end
    end
    return destination
end

function UpnpIgd.parseDeviceDescription(response, discovery)
    local discoveryTrust = type(discovery) == "table"
        and TRUSTED_DISCOVERIES[discovery] or nil
    if not discoveryTrust
        or type(discovery.location) ~= "table"
        or not isLocalGatewayAddress(discovery.gatewayAddress)
        or discovery.location.host ~= discovery.gatewayAddress
        or discovery.gatewayAddress ~= discoveryTrust.gatewayAddress
        or discovery.searchTarget ~= discoveryTrust.searchTarget
        or discovery.usn ~= discoveryTrust.usn
        or discovery.udn ~= discoveryTrust.udn
        or discovery.location.url ~= discoveryTrust.locationUrl
        or discovery.location.origin ~= discoveryTrust.locationOrigin
        or discovery.location.host ~= discoveryTrust.locationHost
        or discovery.location.port ~= discoveryTrust.locationPort
        or discovery.location.hostHeader ~= discoveryTrust.locationHostHeader
        or discovery.location.path ~= discoveryTrust.locationPath
        or discovery.location.pathOnly ~= discoveryTrust.locationPathOnly
        or discovery.location.query ~= discoveryTrust.locationQuery
    then
        return nil, "trusted SSDP discovery context is required"
    end
    local checkedLocation = parseHttpUrl(discovery.location.url)
    if not checkedLocation or checkedLocation.url ~= discovery.location.url
        or checkedLocation.host ~= discovery.gatewayAddress
        or checkedLocation.origin ~= discovery.location.origin
    then
        return nil, "SSDP discovery URL context was altered"
    end
    local parsedResponse, responseError = coerceHttpResponse(response, UpnpIgd.MAX_DESCRIPTION_BYTES)
    if not parsedResponse then return nil, responseError end
    local noRedirect, redirectError = validateNoRedirect(parsedResponse, discovery.location)
    if not noRedirect then return nil, redirectError end
    if parsedResponse.statusCode ~= 200 then return nil, "UPnP device description HTTP status is not 200" end

    local root, xmlError = parseXml(parsedResponse.body, UpnpIgd.MAX_DESCRIPTION_BYTES)
    if not root then return nil, xmlError end
    if root.localName ~= "root" or root.namespace ~= UpnpIgd.DEVICE_NAMESPACE then
        return nil, "UPnP device description has the wrong root namespace"
    end

    local urlBases = directChildren(root, "URLBase", UpnpIgd.DEVICE_NAMESPACE)
    if #urlBases > 1 then return nil, "UPnP device description has duplicate URLBase elements" end
    local base = discovery.location
    if #urlBases == 1 then
        local baseText, baseTextError = scalarText(urlBases[1], false)
        if not baseText then return nil, baseTextError end
        local parsedBase, baseError = parseHttpUrl(baseText)
        if not parsedBase then return nil, baseError end
        if parsedBase.origin ~= discovery.location.origin then
            return nil, "UPnP URLBase leaves the responding gateway origin"
        end
        base = parsedBase
    end

    local devices = directChildren(root, "device", UpnpIgd.DEVICE_NAMESPACE)
    if #devices ~= 1 then return nil, "UPnP description must have exactly one root device" end
    local deviceType, deviceTypeError = singleDirectText(
        devices[1], "deviceType", UpnpIgd.DEVICE_NAMESPACE, false)
    if not deviceType then return nil, deviceTypeError end
    if deviceType ~= UpnpIgd.IGD1_TARGET and deviceType ~= UpnpIgd.IGD2_TARGET then
        return nil, "UPnP root device is not an Internet Gateway Device"
    end
    if discovery.searchTarget == UpnpIgd.IGD2_TARGET and deviceType ~= UpnpIgd.IGD2_TARGET then
        return nil, "IGD 2 discovery response described a different device version"
    end

    local udn, udnError = singleDirectText(
        devices[1], "UDN", UpnpIgd.DEVICE_NAMESPACE, false)
    if not udn then return nil, udnError end
    if udn:lower() ~= discovery.udn then
        return nil, "UPnP description UDN does not match the SSDP USN"
    end

    local serviceNodes = {}
    local wanDeviceType = deviceType == UpnpIgd.IGD2_TARGET
        and UpnpIgd.WAN_DEVICE_V2 or UpnpIgd.WAN_DEVICE_V1
    local connectionDeviceType = deviceType == UpnpIgd.IGD2_TARGET
        and UpnpIgd.WAN_CONNECTION_DEVICE_V2 or UpnpIgd.WAN_CONNECTION_DEVICE_V1
    local wanDevices = embeddedDevicesOfType(
        devices[1], wanDeviceType, UpnpIgd.DEVICE_NAMESPACE)
    if #wanDevices == 0 then
        return nil, "UPnP description has no version-matched WANDevice"
    end
    for _, wanDevice in ipairs(wanDevices) do
        local connectionDevices = embeddedDevicesOfType(
            wanDevice, connectionDeviceType, UpnpIgd.DEVICE_NAMESPACE)
        for _, connectionDevice in ipairs(connectionDevices) do
            for _, serviceNode in ipairs(directServices(
                    connectionDevice, UpnpIgd.DEVICE_NAMESPACE)) do
                serviceNodes[#serviceNodes + 1] = serviceNode
            end
        end
    end

    local allowedServiceTypes
    if deviceType == UpnpIgd.IGD2_TARGET then
        allowedServiceTypes = {
            [UpnpIgd.WAN_IP_V2] = true,
            [UpnpIgd.WAN_PPP_V1] = true,
        }
    else
        allowedServiceTypes = {
            [UpnpIgd.WAN_IP_V1] = true,
            [UpnpIgd.WAN_PPP_V1] = true,
        }
    end
    local candidates = {}
    for order, serviceNode in ipairs(serviceNodes) do
        local typeMatches = directChildren(serviceNode, "serviceType", UpnpIgd.DEVICE_NAMESPACE)
        local controlMatches = directChildren(serviceNode, "controlURL", UpnpIgd.DEVICE_NAMESPACE)
        if #typeMatches == 1 and #controlMatches == 1 then
            local serviceType = scalarText(typeMatches[1], false)
            local rank = serviceType and allowedServiceTypes[serviceType]
                and SERVICE_RANKS[serviceType]
            if rank then
                local controlReference = scalarText(controlMatches[1], false)
                local control = controlReference and resolveUrl(
                    controlReference, base, discovery.location.origin) or nil
                if control then
                    local candidate = {
                        serviceType = serviceType,
                        controlUrl = control.url,
                        control = control,
                        gatewayAddress = discovery.gatewayAddress,
                        trustedOrigin = discovery.location.origin,
                        supportsAddAnyPortMapping = serviceType == UpnpIgd.WAN_IP_V2,
                        fallback = serviceType == UpnpIgd.WAN_PPP_V1,
                        rank = rank,
                        order = order,
                    }
                    TRUSTED_SERVICES[candidate] = {
                        serviceType = candidate.serviceType,
                        controlUrl = candidate.controlUrl,
                        gatewayAddress = candidate.gatewayAddress,
                        trustedOrigin = candidate.trustedOrigin,
                        controlHost = control.host,
                        controlPort = control.port,
                        controlHostHeader = control.hostHeader,
                        controlOrigin = control.origin,
                        controlPath = control.path,
                    }
                    candidates[#candidates + 1] = candidate
                end
            end
        end
    end
    table.sort(candidates, function(left, right)
        if left.rank == right.rank then return left.order < right.order end
        return left.rank > right.rank
    end)
    if #candidates == 0 then return nil, "UPnP description has no safe WAN connection control service" end
    return {
        service = candidates[1],
        services = candidates,
        deviceType = deviceType,
        baseUrl = base.url,
        gatewayAddress = discovery.gatewayAddress,
        udn = discovery.udn,
    }
end

local function validService(service, requireVersionTwo)
    local serviceTrust = type(service) == "table" and TRUSTED_SERVICES[service] or nil
    if not serviceTrust
        or not SERVICE_RANKS[service.serviceType]
        or type(service.control) ~= "table" or type(service.control.url) ~= "string"
        or service.control.host ~= service.gatewayAddress
        or service.control.origin ~= service.trustedOrigin
        or not isLocalGatewayAddress(service.gatewayAddress)
        or service.serviceType ~= serviceTrust.serviceType
        or service.controlUrl ~= serviceTrust.controlUrl
        or service.gatewayAddress ~= serviceTrust.gatewayAddress
        or service.trustedOrigin ~= serviceTrust.trustedOrigin
        or service.control.host ~= serviceTrust.controlHost
        or service.control.port ~= serviceTrust.controlPort
        or service.control.hostHeader ~= serviceTrust.controlHostHeader
        or service.control.origin ~= serviceTrust.controlOrigin
        or service.control.path ~= serviceTrust.controlPath
    then
        return nil, "trusted UPnP WAN service is required"
    end
    local checkedControl = parseHttpUrl(service.control.url)
    if not checkedControl or checkedControl.url ~= service.control.url
        or checkedControl.host ~= service.control.host
        or checkedControl.port ~= service.control.port
        or checkedControl.origin ~= service.control.origin
        or checkedControl.path ~= service.control.path
    then
        return nil, "UPnP WAN service URL context was altered"
    end
    if requireVersionTwo and service.serviceType ~= UpnpIgd.WAN_IP_V2 then
        return nil, "AddAnyPortMapping requires WANIPConnection version 2"
    end
    return true
end

local function xmlEscape(value)
    return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub("\"", "&quot;"):gsub("'", "&apos;"))
end

local function mappingOptions(options)
    if type(options) ~= "table" then return nil, "UPnP mapping options are required" end
    local internalPort = options.internalPort or options.port
    local externalPort = options.externalPort or options.port
    if not integerInRange(internalPort, UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535)
        or not integerInRange(externalPort, UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535)
    then
        return nil, "UPnP mapping ports must be between 1024 and 65535"
    end
    if not isLocalGatewayAddress(options.controlPointAddress) then
        return nil, "UPnP control point address must be canonical private or link-local IPv4"
    end
    if not isLocalGatewayAddress(options.internalClient) then
        return nil, "UPnP internal client must be canonical private or link-local IPv4"
    end
    if options.internalClient ~= options.controlPointAddress then
        return nil, "unauthenticated UPnP mappings must target the control point itself"
    end
    local lease = options.leaseSeconds
    if not integerInRange(lease, 1, UpnpIgd.MAX_LEASE_SECONDS) then
        return nil, "UPnP mapping lease must be finite and no longer than one hour"
    end
    local description = options.description or "The Picture Shop co-op"
    if type(description) ~= "string" or description == "" or #description > 64
        or hasControl(description, false) or description:find("[\r\n]")
    then
        return nil, "UPnP mapping description is invalid"
    end
    return {
        externalPort = externalPort,
        internalPort = internalPort,
        internalClient = options.internalClient,
        controlPointAddress = options.controlPointAddress,
        leaseSeconds = lease,
        description = description,
    }
end

local function soapEnvelope(serviceType, action, arguments)
    local body = {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
        "<s:Envelope xmlns:s=\"" .. UpnpIgd.SOAP_ENVELOPE
            .. "\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">",
        "<s:Body><u:" .. action .. " xmlns:u=\"" .. serviceType .. "\">",
    }
    for _, argument in ipairs(arguments) do
        body[#body + 1] = "<" .. argument[1] .. ">" .. xmlEscape(tostring(argument[2]))
            .. "</" .. argument[1] .. ">"
    end
    body[#body + 1] = "</u:" .. action .. "></s:Body></s:Envelope>"
    return table.concat(body)
end

local function buildSoapRequest(service, action, arguments, context)
    local body = soapEnvelope(service.serviceType, action, arguments)
    if #body > UpnpIgd.MAX_SOAP_BODY_BYTES then return nil, "SOAP request body is too large" end
    local headers = {
        host = service.control.hostHeader,
        ["content-type"] = "text/xml; charset=\"utf-8\"",
        soapaction = "\"" .. service.serviceType .. "#" .. action .. "\"",
        ["content-length"] = tostring(#body),
        connection = "close",
    }
    local wire = table.concat({
        "POST " .. service.control.path .. " HTTP/1.1",
        "HOST: " .. headers.host,
        "CONTENT-TYPE: " .. headers["content-type"],
        "SOAPACTION: " .. headers.soapaction,
        "CONTENT-LENGTH: " .. headers["content-length"],
        "CONNECTION: close",
        "",
        body,
    }, "\r\n")
    context = copyTable(context)
    context.action = action
    context.serviceType = service.serviceType
    context.controlUrl = service.control.url
    local request = {
        method = "POST",
        url = service.control.url,
        path = service.control.path,
        host = service.control.host,
        port = service.control.port,
        headers = headers,
        body = body,
        wire = wire,
        context = context,
    }
    TRUSTED_REQUESTS[request] = {
        service = service,
        context = copyTable(context),
        url = service.control.url,
    }
    return request
end

local function mappingArguments(mapping)
    return {
        { "NewRemoteHost", "" },
        { "NewExternalPort", mapping.externalPort },
        { "NewProtocol", "UDP" },
        { "NewInternalPort", mapping.internalPort },
        { "NewInternalClient", mapping.internalClient },
        { "NewEnabled", 1 },
        { "NewPortMappingDescription", mapping.description },
        { "NewLeaseDuration", mapping.leaseSeconds },
    }
end

function UpnpIgd.buildAddAnyPortMapping(service, options)
    local valid, serviceError = validService(service, true)
    if not valid then return nil, serviceError end
    local mapping, mappingError = mappingOptions(options)
    if not mapping then return nil, mappingError end
    return buildSoapRequest(service, "AddAnyPortMapping", mappingArguments(mapping), {
        requestedPort = mapping.externalPort,
        internalPort = mapping.internalPort,
        internalClient = mapping.internalClient,
        controlPointAddress = mapping.controlPointAddress,
        leaseSeconds = mapping.leaseSeconds,
        description = mapping.description,
        remoteHost = "",
        protocol = "UDP",
    })
end

function UpnpIgd.buildAddPortMapping(service, options)
    local valid, serviceError = validService(service, false)
    if not valid then return nil, serviceError end
    local mapping, mappingError = mappingOptions(options)
    if not mapping then return nil, mappingError end
    return buildSoapRequest(service, "AddPortMapping", mappingArguments(mapping), {
        requestedPort = mapping.externalPort,
        internalPort = mapping.internalPort,
        internalClient = mapping.internalClient,
        controlPointAddress = mapping.controlPointAddress,
        leaseSeconds = mapping.leaseSeconds,
        description = mapping.description,
        remoteHost = "",
        protocol = "UDP",
    })
end

function UpnpIgd.buildDeletePortMapping(service, mappingHandle, lifecycle)
    local valid, serviceError = validService(service, false)
    if not valid then return nil, serviceError end
    local ownership = type(mappingHandle) == "table"
        and TRUSTED_MAPPING_HANDLES[mappingHandle] or nil
    if not ownership or ownership.service ~= service or ownership.cleaned
        or mappingHandle.externalPort ~= ownership.externalPort
        or mappingHandle.internalPort ~= ownership.internalPort
        or mappingHandle.internalClient ~= ownership.internalClient
        or mappingHandle.controlPointAddress ~= ownership.controlPointAddress
        or mappingHandle.protocol ~= "UDP"
        or mappingHandle.expiresAt ~= ownership.expiresAt
        or mappingHandle.networkEpoch ~= ownership.networkEpoch
    then
        return nil, "a live mapping handle owned by this UPnP service is required"
    end
    local nowSeconds = type(lifecycle) == "table" and lifecycle.nowSeconds or nil
    local networkEpoch = type(lifecycle) == "table" and lifecycle.networkEpoch or nil
    if not finiteNonnegative(nowSeconds) or type(networkEpoch) ~= "string"
        or networkEpoch == "" or #networkEpoch > 128
    then
        return nil, "monotonic time and network epoch cleanup context are required"
    end
    if networkEpoch ~= ownership.networkEpoch then
        return nil, "UPnP mapping belongs to a different network epoch"
    end
    if nowSeconds >= ownership.expiresAt then
        return nil, "UPnP mapping ownership is no longer current; late deletion is unsafe"
    end
    return buildSoapRequest(service, "DeletePortMapping", {
        { "NewRemoteHost", "" },
        { "NewExternalPort", ownership.externalPort },
        { "NewProtocol", "UDP" },
    }, {
        externalPort = ownership.externalPort,
        protocol = "UDP",
        mappingHandle = mappingHandle,
        networkEpoch = networkEpoch,
    })
end

function UpnpIgd.buildGetExternalIPAddress(service)
    local valid, serviceError = validService(service, false)
    if not valid then return nil, serviceError end
    return buildSoapRequest(service, "GetExternalIPAddress", {}, {})
end

local function descendantElements(node, localName, destination)
    destination = destination or {}
    for _, child in ipairs(node.children or {}) do
        if child.localName == localName then destination[#destination + 1] = child end
        descendantElements(child, localName, destination)
    end
    return destination
end

local function parseFault(fault, statusCode)
    local errors = descendantElements(fault, "UPnPError")
    if #errors ~= 1 or errors[1].namespace ~= UpnpIgd.UPNP_CONTROL then
        return nil, "SOAP fault has no unambiguous UPnPError"
    end
    local codeMatches = directChildrenExactNamespace(
        errors[1], "errorCode", UpnpIgd.UPNP_CONTROL)
    if #codeMatches ~= 1 then return nil, "SOAP fault must contain exactly one errorCode" end
    local codeText, codeError = scalarText(codeMatches[1], false)
    if not codeText then return nil, codeError end
    if not codeText:match("^%d+$") or #codeText > 4 then return nil, "UPnP error code is invalid" end
    local code = tonumber(codeText)
    if not integerInRange(code, 1, 9999) then return nil, "UPnP error code is invalid" end
    local descriptions = directChildrenExactNamespace(
        errors[1], "errorDescription", UpnpIgd.UPNP_CONTROL)
    if #descriptions > 1 then return nil, "UPnP fault has duplicate descriptions" end
    local description
    if #descriptions == 1 then
        description, codeError = scalarText(descriptions[1], true)
        if not description then return nil, codeError end
        if #description > 256 then return nil, "UPnP error description is too long" end
    end
    return {
        success = false,
        httpStatus = statusCode,
        errorCode = code,
        errorDescription = description,
        errorKind = "upnp_fault",
    }
end

local function singleOutput(responseNode, name)
    local matches = directChildrenExactNamespace(responseNode, name, nil)
    if #matches ~= 1 then return nil, "SOAP response must contain exactly one " .. name end
    return scalarText(matches[1], false)
end

local function createMappingHandle(requestTrust, externalPort, lifecycle)
    if requestTrust.mappingHandle then
        return nil, "mapping success was already consumed for this SOAP request"
    end
    local nowSeconds = type(lifecycle) == "table" and lifecycle.nowSeconds or nil
    local networkEpoch = type(lifecycle) == "table" and lifecycle.networkEpoch or nil
    if not finiteNonnegative(nowSeconds) or type(networkEpoch) ~= "string"
        or networkEpoch == "" or #networkEpoch > 128
    then
        return nil, "mapping success requires monotonic time and network epoch context"
    end
    local context = requestTrust.context
    local handle = {
        externalPort = externalPort,
        internalPort = context.internalPort,
        internalClient = context.internalClient,
        controlPointAddress = context.controlPointAddress,
        protocol = context.protocol,
        remoteHost = context.remoteHost,
        description = context.description,
        leaseSeconds = context.leaseSeconds,
        createdAt = nowSeconds,
        expiresAt = nowSeconds + context.leaseSeconds,
        networkEpoch = networkEpoch,
    }
    TRUSTED_MAPPING_HANDLES[handle] = {
        service = requestTrust.service,
        externalPort = handle.externalPort,
        internalPort = handle.internalPort,
        internalClient = handle.internalClient,
        controlPointAddress = handle.controlPointAddress,
        expiresAt = handle.expiresAt,
        networkEpoch = handle.networkEpoch,
        cleaned = false,
    }
    requestTrust.mappingHandle = handle
    return handle
end

function UpnpIgd.parseSoapResponse(response, request, lifecycle)
    local requestTrust = type(request) == "table" and TRUSTED_REQUESTS[request] or nil
    if not requestTrust or type(requestTrust.context) ~= "table"
        or type(requestTrust.context.action) ~= "string"
        or type(requestTrust.context.serviceType) ~= "string"
        or type(requestTrust.url) ~= "string"
    then
        return nil, "SOAP request context is required"
    end
    local expectedUrl, urlError = parseHttpUrl(requestTrust.url)
    if not expectedUrl then return nil, urlError end
    local parsedResponse, responseError = coerceHttpResponse(response, UpnpIgd.MAX_SOAP_BODY_BYTES)
    if not parsedResponse then return nil, responseError end
    local noRedirect, redirectError = validateNoRedirect(parsedResponse, expectedUrl)
    if not noRedirect then return nil, redirectError end

    local root, xmlError = parseXml(parsedResponse.body, UpnpIgd.MAX_SOAP_BODY_BYTES)
    if not root then
        if parsedResponse.statusCode ~= 200 then
            return {
                success = false,
                httpStatus = parsedResponse.statusCode,
                errorKind = "http_status",
            }
        end
        return nil, xmlError
    end
    if root.localName ~= "Envelope" or root.namespace ~= UpnpIgd.SOAP_ENVELOPE then
        return nil, "SOAP response has the wrong envelope namespace"
    end
    local bodies = directChildren(root, "Body", UpnpIgd.SOAP_ENVELOPE)
    if #bodies ~= 1 then return nil, "SOAP response must have exactly one Body" end
    local bodyElements = directChildren(bodies[1])
    if #bodyElements ~= 1 then return nil, "SOAP Body must have exactly one result element" end

    local resultElement = bodyElements[1]
    if resultElement.localName == "Fault" and resultElement.namespace == UpnpIgd.SOAP_ENVELOPE then
        return parseFault(resultElement, parsedResponse.statusCode)
    end
    if parsedResponse.statusCode ~= 200 then
        return {
            success = false,
            httpStatus = parsedResponse.statusCode,
            errorKind = "http_status",
        }
    end

    local action = requestTrust.context.action
    if resultElement.localName ~= action .. "Response"
        or resultElement.namespace ~= requestTrust.context.serviceType
    then
        return nil, "SOAP response action or service type does not match the request"
    end
    local result = {
        success = true,
        httpStatus = parsedResponse.statusCode,
        action = action,
    }
    if action == "AddAnyPortMapping" then
        local portText, portError = singleOutput(resultElement, "NewReservedPort")
        if not portText then return nil, portError end
        if not portText:match("^%d+$") or #portText > 5 then
            return nil, "reserved UPnP port is invalid"
        end
        local port = tonumber(portText)
        if not integerInRange(port, UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535) then
            return nil, "reserved UPnP port is invalid"
        end
        result.externalPort = port
        result.requestedPort = requestTrust.context.requestedPort
        result.portChanged = port ~= requestTrust.context.requestedPort
        result.mappingHandle, portError = createMappingHandle(requestTrust, port, lifecycle)
        if not result.mappingHandle then return nil, portError end
    elseif action == "GetExternalIPAddress" then
        local address, addressError = singleOutput(resultElement, "NewExternalIPAddress")
        if not address then return nil, addressError end
        if not IpScope.parse(address) then return nil, "UPnP external address is not canonical IPv4" end
        local global, classification = IpScope.isGlobal(address)
        result.externalAddress = address
        result.addressIsGlobal = global
        result.reachabilityVerified = false
        result.addressClassification = classification
    elseif action == "AddPortMapping" then
        result.externalPort = requestTrust.context.requestedPort
        local mappingError
        result.mappingHandle, mappingError = createMappingHandle(
            requestTrust, result.externalPort, lifecycle)
        if not result.mappingHandle then return nil, mappingError end
    elseif action == "DeletePortMapping" then
        local handle = requestTrust.context.mappingHandle
        local ownership = type(handle) == "table" and TRUSTED_MAPPING_HANDLES[handle] or nil
        if not ownership or ownership.cleaned then
            return nil, "SOAP deletion response has no live mapping ownership context"
        end
        ownership.cleaned = true
        result.cleanupConfirmed = true
    else
        return nil, "unsupported SOAP response action"
    end
    return result
end

UpnpIgd.parseHttpUrl = parseHttpUrl
UpnpIgd.resolveUrl = resolveUrl

return UpnpIgd
