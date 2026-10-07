-- SOAP responses, faults, and opaque mapping handles.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.descendantElements(node, localName, destination)
        destination = destination or {}
        for _, child in ipairs(node.children or {}) do
            if child.localName == localName then destination[#destination + 1] = child end
            Runtime.descendantElements(child, localName, destination)
        end
        return destination
    end

    function Runtime.parseFault(fault, statusCode)
        local errors = Runtime.descendantElements(fault, "UPnPError")
        if #errors ~= 1 or errors[1].namespace ~= Runtime.UpnpIgd.UPNP_CONTROL then
            return nil, "SOAP fault has no unambiguous UPnPError"
        end
        local codeMatches = Runtime.directChildrenExactNamespace(
            errors[1], "errorCode", Runtime.UpnpIgd.UPNP_CONTROL)
        if #codeMatches ~= 1 then return nil, "SOAP fault must contain exactly one errorCode" end
        local codeText, codeError = Runtime.scalarText(codeMatches[1], false)
        if not codeText then return nil, codeError end
        if not codeText:match("^%d+$") or #codeText > 4 then return nil, "UPnP error code is invalid" end
        local code = tonumber(codeText)
        if not Runtime.integerInRange(code, 1, 9999) then return nil, "UPnP error code is invalid" end
        local descriptions = Runtime.directChildrenExactNamespace(
            errors[1], "errorDescription", Runtime.UpnpIgd.UPNP_CONTROL)
        if #descriptions > 1 then return nil, "UPnP fault has duplicate descriptions" end
        local description
        if #descriptions == 1 then
            description, codeError = Runtime.scalarText(descriptions[1], true)
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

    function Runtime.singleOutput(responseNode, name)
        local matches = Runtime.directChildrenExactNamespace(responseNode, name, nil)
        if #matches ~= 1 then return nil, "SOAP response must contain exactly one " .. name end
        return Runtime.scalarText(matches[1], false)
    end

    function Runtime.createMappingHandle(requestTrust, externalPort, lifecycle)
        if requestTrust.mappingHandle then
            return nil, "mapping success was already consumed for this SOAP request"
        end
        local nowSeconds = type(lifecycle) == "table" and lifecycle.nowSeconds or nil
        local networkEpoch = type(lifecycle) == "table" and lifecycle.networkEpoch or nil
        if not Runtime.finiteNonnegative(nowSeconds) or type(networkEpoch) ~= "string"
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
        Runtime.TRUSTED_MAPPING_HANDLES[handle] = {
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

    function Runtime.UpnpIgd.parseSoapResponse(response, request, lifecycle)
        local requestTrust = type(request) == "table" and Runtime.TRUSTED_REQUESTS[request] or nil
        if not requestTrust or type(requestTrust.context) ~= "table"
            or type(requestTrust.context.action) ~= "string"
            or type(requestTrust.context.serviceType) ~= "string"
            or type(requestTrust.url) ~= "string"
        then
            return nil, "SOAP request context is required"
        end
        local expectedUrl, urlError = Runtime.parseHttpUrl(requestTrust.url)
        if not expectedUrl then return nil, urlError end
        local parsedResponse, responseError = Runtime.coerceHttpResponse(response, Runtime.UpnpIgd.MAX_SOAP_BODY_BYTES)
        if not parsedResponse then return nil, responseError end
        local noRedirect, redirectError = Runtime.validateNoRedirect(parsedResponse, expectedUrl)
        if not noRedirect then return nil, redirectError end

        local root, xmlError = Runtime.parseXml(parsedResponse.body, Runtime.UpnpIgd.MAX_SOAP_BODY_BYTES)
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
        if root.localName ~= "Envelope" or root.namespace ~= Runtime.UpnpIgd.SOAP_ENVELOPE then
            return nil, "SOAP response has the wrong envelope namespace"
        end
        local bodies = Runtime.directChildren(root, "Body", Runtime.UpnpIgd.SOAP_ENVELOPE)
        if #bodies ~= 1 then return nil, "SOAP response must have exactly one Body" end
        local bodyElements = Runtime.directChildren(bodies[1])
        if #bodyElements ~= 1 then return nil, "SOAP Body must have exactly one result element" end

        local resultElement = bodyElements[1]
        if resultElement.localName == "Fault" and resultElement.namespace == Runtime.UpnpIgd.SOAP_ENVELOPE then
            return Runtime.parseFault(resultElement, parsedResponse.statusCode)
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
            local portText, portError = Runtime.singleOutput(resultElement, "NewReservedPort")
            if not portText then return nil, portError end
            if not portText:match("^%d+$") or #portText > 5 then
                return nil, "reserved UPnP port is invalid"
            end
            local port = tonumber(portText)
            if not Runtime.integerInRange(port, Runtime.UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535) then
                return nil, "reserved UPnP port is invalid"
            end
            result.externalPort = port
            result.requestedPort = requestTrust.context.requestedPort
            result.portChanged = port ~= requestTrust.context.requestedPort
            result.mappingHandle, portError = Runtime.createMappingHandle(requestTrust, port, lifecycle)
            if not result.mappingHandle then return nil, portError end
        elseif action == "GetExternalIPAddress" then
            local address, addressError = Runtime.singleOutput(resultElement, "NewExternalIPAddress")
            if not address then return nil, addressError end
            if not Runtime.IpScope.parse(address) then return nil, "UPnP external address is not canonical IPv4" end
            local global, classification = Runtime.IpScope.isGlobal(address)
            result.externalAddress = address
            result.addressIsGlobal = global
            result.reachabilityVerified = false
            result.addressClassification = classification
        elseif action == "AddPortMapping" then
            result.externalPort = requestTrust.context.requestedPort
            local mappingError
            result.mappingHandle, mappingError = Runtime.createMappingHandle(
                requestTrust, result.externalPort, lifecycle)
            if not result.mappingHandle then return nil, mappingError end
        elseif action == "DeletePortMapping" then
            local handle = requestTrust.context.mappingHandle
            local ownership = type(handle) == "table" and Runtime.TRUSTED_MAPPING_HANDLES[handle] or nil
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

    Runtime.UpnpIgd.parseHttpUrl = Runtime.parseHttpUrl
    Runtime.UpnpIgd.resolveUrl = Runtime.resolveUrl
end

return Component
