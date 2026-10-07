-- Local gateway URL parsing, normalization, and resolution.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.percentEncodingIsValid(value)
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

    function Runtime.normalizePath(path)
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

    function Runtime.parseHttpUrl(value)
        if type(value) ~= "string" then return nil, "UPnP URL must be text" end
        value = Runtime.trim(value)
        if value == "" or #value > Runtime.UpnpIgd.MAX_URL_BYTES then
            return nil, "UPnP URL is empty or too long"
        end
        if Runtime.hasControl(value, false) or value:find("[ \t\r\n]")
            or value:find("\\", 1, true) or value:find("#", 1, true)
        then
            return nil, "UPnP URL contains a forbidden character"
        end
        for index = 1, #value do
            local byte = value:byte(index)
            if byte < 33 or byte > 126 then return nil, "UPnP URL must be ASCII" end
        end
        if not Runtime.percentEncodingIsValid(value) then return nil, "UPnP URL has invalid percent encoding" end

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
        local parsedHost = Runtime.IpScope.parse(host)
        if not parsedHost or parsedHost.address ~= host then
            return nil, "UPnP URL host must be canonical IPv4 text"
        end
        local port = 80
        if portText then
            if not portText:match("^%d+$") or #portText > 5 then
                return nil, "UPnP URL port is invalid"
            end
            port = tonumber(portText)
            if not Runtime.integerInRange(port, 1, 65535) then return nil, "UPnP URL port is invalid" end
        end

        local path, query = target, ""
        local question = target:find("?", 1, true)
        if question then
            path, query = target:sub(1, question - 1), target:sub(question)
        end
        local normalizedPath, pathError = Runtime.normalizePath(path)
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

    function Runtime.resolveUrl(reference, base, trustedOrigin)
        if type(reference) ~= "string" then return nil, "UPnP control URL must be text" end
        reference = Runtime.trim(reference)
        if reference == "" or #reference > Runtime.UpnpIgd.MAX_URL_BYTES then
            return nil, "UPnP control URL is empty or too long"
        end
        if Runtime.hasControl(reference, false) or reference:find("\\", 1, true)
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

        local resolved, resolveError = Runtime.parseHttpUrl(candidate)
        if not resolved then return nil, resolveError end
        if resolved.origin ~= trustedOrigin then
            return nil, "UPnP control URL leaves the responding gateway origin"
        end
        return resolved
    end
end

return Component
