-- SOAP requests, mapping arguments, and external address queries.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.validService(service, requireVersionTwo)
        local serviceTrust = type(service) == "table" and Runtime.TRUSTED_SERVICES[service] or nil
        if not serviceTrust
            or not Runtime.SERVICE_RANKS[service.serviceType]
            or type(service.control) ~= "table" or type(service.control.url) ~= "string"
            or service.control.host ~= service.gatewayAddress
            or service.control.origin ~= service.trustedOrigin
            or not Runtime.isLocalGatewayAddress(service.gatewayAddress)
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
        local checkedControl = Runtime.parseHttpUrl(service.control.url)
        if not checkedControl or checkedControl.url ~= service.control.url
            or checkedControl.host ~= service.control.host
            or checkedControl.port ~= service.control.port
            or checkedControl.origin ~= service.control.origin
            or checkedControl.path ~= service.control.path
        then
            return nil, "UPnP WAN service URL context was altered"
        end
        if requireVersionTwo and service.serviceType ~= Runtime.UpnpIgd.WAN_IP_V2 then
            return nil, "AddAnyPortMapping requires WANIPConnection version 2"
        end
        return true
    end

    function Runtime.xmlEscape(value)
        return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
            :gsub("\"", "&quot;"):gsub("'", "&apos;"))
    end

    function Runtime.mappingOptions(options)
        if type(options) ~= "table" then return nil, "UPnP mapping options are required" end
        local internalPort = options.internalPort or options.port
        local externalPort = options.externalPort or options.port
        if not Runtime.integerInRange(internalPort, Runtime.UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535)
            or not Runtime.integerInRange(externalPort, Runtime.UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535)
        then
            return nil, "UPnP mapping ports must be between 1024 and 65535"
        end
        if not Runtime.isLocalGatewayAddress(options.controlPointAddress) then
            return nil, "UPnP control point address must be canonical private or link-local IPv4"
        end
        if not Runtime.isLocalGatewayAddress(options.internalClient) then
            return nil, "UPnP internal client must be canonical private or link-local IPv4"
        end
        if options.internalClient ~= options.controlPointAddress then
            return nil, "unauthenticated UPnP mappings must target the control point itself"
        end
        local lease = options.leaseSeconds
        if not Runtime.integerInRange(lease, 1, Runtime.UpnpIgd.MAX_LEASE_SECONDS) then
            return nil, "UPnP mapping lease must be finite and no longer than one hour"
        end
        local description = options.description or "The Picture Shop co-op"
        if type(description) ~= "string" or description == "" or #description > 64
            or Runtime.hasControl(description, false) or description:find("[\r\n]")
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

    function Runtime.soapEnvelope(serviceType, action, arguments)
        local body = {
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            "<s:Envelope xmlns:s=\"" .. Runtime.UpnpIgd.SOAP_ENVELOPE
                .. "\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">",
            "<s:Body><u:" .. action .. " xmlns:u=\"" .. serviceType .. "\">",
        }
        for _, argument in ipairs(arguments) do
            body[#body + 1] = "<" .. argument[1] .. ">" .. Runtime.xmlEscape(tostring(argument[2]))
                .. "</" .. argument[1] .. ">"
        end
        body[#body + 1] = "</u:" .. action .. "></s:Body></s:Envelope>"
        return table.concat(body)
    end

    function Runtime.buildSoapRequest(service, action, arguments, context)
        local body = Runtime.soapEnvelope(service.serviceType, action, arguments)
        if #body > Runtime.UpnpIgd.MAX_SOAP_BODY_BYTES then return nil, "SOAP request body is too large" end
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
        context = Runtime.copyTable(context)
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
        Runtime.TRUSTED_REQUESTS[request] = {
            service = service,
            context = Runtime.copyTable(context),
            url = service.control.url,
        }
        return request
    end

    function Runtime.mappingArguments(mapping)
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

    function Runtime.UpnpIgd.buildAddAnyPortMapping(service, options)
        local valid, serviceError = Runtime.validService(service, true)
        if not valid then return nil, serviceError end
        local mapping, mappingError = Runtime.mappingOptions(options)
        if not mapping then return nil, mappingError end
        return Runtime.buildSoapRequest(service, "AddAnyPortMapping", Runtime.mappingArguments(mapping), {
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

    function Runtime.UpnpIgd.buildAddPortMapping(service, options)
        local valid, serviceError = Runtime.validService(service, false)
        if not valid then return nil, serviceError end
        local mapping, mappingError = Runtime.mappingOptions(options)
        if not mapping then return nil, mappingError end
        return Runtime.buildSoapRequest(service, "AddPortMapping", Runtime.mappingArguments(mapping), {
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

    function Runtime.UpnpIgd.buildDeletePortMapping(service, mappingHandle, lifecycle)
        local valid, serviceError = Runtime.validService(service, false)
        if not valid then return nil, serviceError end
        local ownership = type(mappingHandle) == "table"
            and Runtime.TRUSTED_MAPPING_HANDLES[mappingHandle] or nil
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
        if not Runtime.finiteNonnegative(nowSeconds) or type(networkEpoch) ~= "string"
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
        return Runtime.buildSoapRequest(service, "DeletePortMapping", {
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

    function Runtime.UpnpIgd.buildGetExternalIPAddress(service)
        local valid, serviceError = Runtime.validService(service, false)
        if not valid then return nil, serviceError end
        return Runtime.buildSoapRequest(service, "GetExternalIPAddress", {}, {})
    end
end

return Component
