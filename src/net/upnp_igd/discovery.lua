-- SSDP discovery requests and response validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.UpnpIgd.buildSearchRequest(version, mxSeconds)
        local target
        if version == 2 or version == Runtime.UpnpIgd.IGD2_TARGET then
            target = Runtime.UpnpIgd.IGD2_TARGET
        elseif version == 1 or version == Runtime.UpnpIgd.IGD1_TARGET then
            target = Runtime.UpnpIgd.IGD1_TARGET
        else
            return nil, "UPnP search version must be IGD 2 or IGD 1"
        end
        mxSeconds = mxSeconds == nil and 2 or mxSeconds
        if not Runtime.integerInRange(mxSeconds, 1, 5) then
            return nil, "UPnP multicast response window must be 1 to 5 seconds"
        end

        local request = table.concat({
            "M-SEARCH * HTTP/1.1",
            "HOST: " .. Runtime.UpnpIgd.SSDP_ADDRESS .. ":" .. tostring(Runtime.UpnpIgd.SSDP_PORT),
            "MAN: \"ssdp:discover\"",
            "MX: " .. tostring(mxSeconds),
            "ST: " .. target,
            "",
            "",
        }, "\r\n")
        return request, {
            expectedTarget = target,
            destinationAddress = Runtime.UpnpIgd.SSDP_ADDRESS,
            destinationPort = Runtime.UpnpIgd.SSDP_PORT,
            mxSeconds = mxSeconds,
        }
    end

    function Runtime.UpnpIgd.buildSearchRequests(mxSeconds)
        local second, secondContext = Runtime.UpnpIgd.buildSearchRequest(2, mxSeconds)
        if not second then return nil, secondContext end
        local first, firstContext = Runtime.UpnpIgd.buildSearchRequest(1, mxSeconds)
        return {
            { bytes = second, context = secondContext },
            { bytes = first, context = firstContext },
        }
    end

    function Runtime.parseSsdpMaxAge(value)
        if type(value) ~= "string" then return nil, "SSDP response is missing CACHE-CONTROL" end
        local secondsText = value:lower():match("^max%-age%s*=%s*(%d+)$")
        if not secondsText or #secondsText > 10 then
            return nil, "SSDP CACHE-CONTROL must contain only a max-age directive"
        end
        local seconds = tonumber(secondsText)
        if not Runtime.integerInRange(seconds, 1, Runtime.UpnpIgd.MAX_SSDP_MAX_AGE_SECONDS) then
            return nil, "SSDP max-age is outside the accepted bound"
        end
        return seconds
    end

    function Runtime.canonicalUdnFromUsn(value, target)
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

    function Runtime.UpnpIgd.parseSsdpResponse(data, expected)
        if type(data) ~= "string" then return nil, "SSDP response must be bytes" end
        if #data > Runtime.UpnpIgd.MAX_SSDP_BYTES then return nil, "SSDP response is too large" end
        expected = expected or {}
        local separator = data:find("\r\n\r\n", 1, true)
        if not separator then return nil, "SSDP response has no complete header block" end
        if data:sub(separator + 4) ~= "" then return nil, "SSDP response unexpectedly has a body" end

        local parsed, parseError = Runtime.parseHeaderBlock(data:sub(1, separator - 1))
        if not parsed then return nil, parseError end
        if parsed.startLine ~= "HTTP/1.1 200 OK" and parsed.startLine ~= "HTTP/1.0 200 OK" then
            return nil, "SSDP response status is not 200 OK"
        end

        local sourceAddress = expected.sourceAddress
        if not Runtime.isLocalGatewayAddress(sourceAddress) then
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
        local maxAge, maxAgeError = Runtime.parseSsdpMaxAge(headers["cache-control"])
        if not maxAge then return nil, maxAgeError end
        if searchTarget ~= Runtime.UpnpIgd.IGD2_TARGET and searchTarget ~= Runtime.UpnpIgd.IGD1_TARGET then
            return nil, "SSDP response is not for a supported Internet Gateway Device"
        end
        if expected.expectedTarget and searchTarget ~= expected.expectedTarget then
            return nil, "SSDP response search target does not match the request"
        end
        local udn, usnError = Runtime.canonicalUdnFromUsn(usn, searchTarget)
        if not udn then return nil, usnError end
        local bootId
        if headers.server:find("UPnP/1.1", 1, true) then
            local bootText = headers["bootid.upnp.org"]
            if not bootText or not bootText:match("^%d+$") or #bootText > 10 then
                return nil, "UPnP 1.1 SSDP response has no valid BOOTID"
            end
            bootId = tonumber(bootText)
            if not Runtime.integerInRange(bootId, 1, 2147483647) then
                return nil, "UPnP 1.1 SSDP BOOTID is outside its valid range"
            end
        end

        local location, locationError = Runtime.parseHttpUrl(locationText)
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
        Runtime.TRUSTED_DISCOVERIES[discovery] = {
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
end

return Component
