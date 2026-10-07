-- HTTP response framing and description requests.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.decodeChunkedBody(value, limit)
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

    function Runtime.UpnpIgd.parseHttpResponse(data, maxBodyBytes)
        maxBodyBytes = maxBodyBytes or Runtime.UpnpIgd.MAX_SOAP_BODY_BYTES
        if type(data) ~= "string" then return nil, "HTTP response must be bytes" end
        if not Runtime.integerInRange(maxBodyBytes, 0, Runtime.UpnpIgd.MAX_DESCRIPTION_BYTES) then
            return nil, "HTTP body limit is invalid"
        end
        local separator = data:find("\r\n\r\n", 1, true)
        if not separator then return nil, "HTTP response has no complete header block" end
        if separator - 1 > Runtime.UpnpIgd.MAX_HTTP_HEADER_BYTES then
            return nil, "HTTP response headers are too large"
        end
        local parsed, parseError = Runtime.parseHeaderBlock(data:sub(1, separator - 1))
        if not parsed then return nil, parseError end
        local version, statusText, reason = parsed.startLine:match(
            "^HTTP/(1%.[01]) ([0-9][0-9][0-9]) ([\t -~]*)$")
        local statusCode = tonumber(statusText)
        if not version or not Runtime.integerInRange(statusCode, 100, 599) then
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
            body, parseError = Runtime.decodeChunkedBody(body, maxBodyBytes)
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

    function Runtime.UpnpIgd.buildDescriptionRequest(discovery)
        local trust = type(discovery) == "table" and Runtime.TRUSTED_DISCOVERIES[discovery] or nil
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

    Runtime.XML_NAME = "[%a_:][%w_.:%-]*"
end

return Component
