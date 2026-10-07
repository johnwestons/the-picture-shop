-- Redirect, device hierarchy, and service validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.coerceHttpResponse(response, maximumBody)
        if type(response) ~= "table" or not Runtime.integerInRange(response.statusCode, 100, 599)
            or type(response.body) ~= "string"
        then
            return nil, "structured HTTP response context is required"
        end
        if #response.body > maximumBody then return nil, "HTTP response body is too large" end
        return response
    end

    function Runtime.validateNoRedirect(response, expectedUrl)
        if type(expectedUrl) ~= "table" or type(expectedUrl.url) ~= "string"
            or type(expectedUrl.host) ~= "string" or not Runtime.integerInRange(expectedUrl.port, 1, 65535)
        then
            return nil, "trusted HTTP request URL context is required"
        end
        if type(response.finalUrl) ~= "string"
            or type(response.peerAddress) ~= "string"
            or not Runtime.integerInRange(response.peerPort, 1, 65535)
            or response.redirectCount ~= 0
        then
            return nil, "HTTP response lacks exact no-redirect peer evidence"
        end
        if response.statusCode >= 300 and response.statusCode <= 399 then
            return nil, "UPnP redirects are not allowed"
        end
        local final, finalError = Runtime.parseHttpUrl(response.finalUrl)
        if not final then return nil, finalError end
        if final.url ~= expectedUrl.url then return nil, "UPnP redirect or URL substitution is not allowed" end
        if response.peerAddress ~= expectedUrl.host or response.peerPort ~= expectedUrl.port then
            return nil, "UPnP HTTP peer does not match the trusted gateway origin"
        end
        return true
    end

    Runtime.SERVICE_RANKS = {
        [Runtime.UpnpIgd.WAN_IP_V2] = 300,
        [Runtime.UpnpIgd.WAN_IP_V1] = 200,
        [Runtime.UpnpIgd.WAN_PPP_V1] = 100,
    }

    function Runtime.embeddedDevices(deviceNode, namespace)
        local destination = {}
        for _, deviceList in ipairs(Runtime.directChildren(deviceNode, "deviceList", namespace)) do
            for _, childDevice in ipairs(Runtime.directChildren(deviceList, "device", namespace)) do
                destination[#destination + 1] = childDevice
            end
        end
        return destination
    end

    function Runtime.deviceTypeOf(deviceNode, namespace)
        return Runtime.singleDirectText(deviceNode, "deviceType", namespace, false)
    end

    function Runtime.embeddedDevicesOfType(deviceNode, wantedType, namespace)
        local result = {}
        for _, childDevice in ipairs(Runtime.embeddedDevices(deviceNode, namespace)) do
            local childType = Runtime.deviceTypeOf(childDevice, namespace)
            if childType == wantedType then result[#result + 1] = childDevice end
        end
        return result
    end

    function Runtime.directServices(deviceNode, namespace)
        local destination = {}
        for _, serviceList in ipairs(Runtime.directChildren(deviceNode, "serviceList", namespace)) do
            for _, service in ipairs(Runtime.directChildren(serviceList, "service", namespace)) do
                destination[#destination + 1] = service
            end
        end
        return destination
    end

    function Runtime.UpnpIgd.parseDeviceDescription(response, discovery)
        local discoveryTrust = type(discovery) == "table"
            and Runtime.TRUSTED_DISCOVERIES[discovery] or nil
        if not discoveryTrust
            or type(discovery.location) ~= "table"
            or not Runtime.isLocalGatewayAddress(discovery.gatewayAddress)
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
        local checkedLocation = Runtime.parseHttpUrl(discovery.location.url)
        if not checkedLocation or checkedLocation.url ~= discovery.location.url
            or checkedLocation.host ~= discovery.gatewayAddress
            or checkedLocation.origin ~= discovery.location.origin
        then
            return nil, "SSDP discovery URL context was altered"
        end
        local parsedResponse, responseError = Runtime.coerceHttpResponse(response, Runtime.UpnpIgd.MAX_DESCRIPTION_BYTES)
        if not parsedResponse then return nil, responseError end
        local noRedirect, redirectError = Runtime.validateNoRedirect(parsedResponse, discovery.location)
        if not noRedirect then return nil, redirectError end
        if parsedResponse.statusCode ~= 200 then return nil, "UPnP device description HTTP status is not 200" end

        local root, xmlError = Runtime.parseXml(parsedResponse.body, Runtime.UpnpIgd.MAX_DESCRIPTION_BYTES)
        if not root then return nil, xmlError end
        if root.localName ~= "root" or root.namespace ~= Runtime.UpnpIgd.DEVICE_NAMESPACE then
            return nil, "UPnP device description has the wrong root namespace"
        end

        local urlBases = Runtime.directChildren(root, "URLBase", Runtime.UpnpIgd.DEVICE_NAMESPACE)
        if #urlBases > 1 then return nil, "UPnP device description has duplicate URLBase elements" end
        local base = discovery.location
        if #urlBases == 1 then
            local baseText, baseTextError = Runtime.scalarText(urlBases[1], false)
            if not baseText then return nil, baseTextError end
            local parsedBase, baseError = Runtime.parseHttpUrl(baseText)
            if not parsedBase then return nil, baseError end
            if parsedBase.origin ~= discovery.location.origin then
                return nil, "UPnP URLBase leaves the responding gateway origin"
            end
            base = parsedBase
        end

        local devices = Runtime.directChildren(root, "device", Runtime.UpnpIgd.DEVICE_NAMESPACE)
        if #devices ~= 1 then return nil, "UPnP description must have exactly one root device" end
        local deviceType, deviceTypeError = Runtime.singleDirectText(
            devices[1], "deviceType", Runtime.UpnpIgd.DEVICE_NAMESPACE, false)
        if not deviceType then return nil, deviceTypeError end
        if deviceType ~= Runtime.UpnpIgd.IGD1_TARGET and deviceType ~= Runtime.UpnpIgd.IGD2_TARGET then
            return nil, "UPnP root device is not an Internet Gateway Device"
        end
        if discovery.searchTarget == Runtime.UpnpIgd.IGD2_TARGET and deviceType ~= Runtime.UpnpIgd.IGD2_TARGET then
            return nil, "IGD 2 discovery response described a different device version"
        end

        local udn, udnError = Runtime.singleDirectText(
            devices[1], "UDN", Runtime.UpnpIgd.DEVICE_NAMESPACE, false)
        if not udn then return nil, udnError end
        if udn:lower() ~= discovery.udn then
            return nil, "UPnP description UDN does not match the SSDP USN"
        end

        local serviceNodes = {}
        local wanDeviceType = deviceType == Runtime.UpnpIgd.IGD2_TARGET
            and Runtime.UpnpIgd.WAN_DEVICE_V2 or Runtime.UpnpIgd.WAN_DEVICE_V1
        local connectionDeviceType = deviceType == Runtime.UpnpIgd.IGD2_TARGET
            and Runtime.UpnpIgd.WAN_CONNECTION_DEVICE_V2 or Runtime.UpnpIgd.WAN_CONNECTION_DEVICE_V1
        local wanDevices = Runtime.embeddedDevicesOfType(
            devices[1], wanDeviceType, Runtime.UpnpIgd.DEVICE_NAMESPACE)
        if #wanDevices == 0 then
            return nil, "UPnP description has no version-matched WANDevice"
        end
        for _, wanDevice in ipairs(wanDevices) do
            local connectionDevices = Runtime.embeddedDevicesOfType(
                wanDevice, connectionDeviceType, Runtime.UpnpIgd.DEVICE_NAMESPACE)
            for _, connectionDevice in ipairs(connectionDevices) do
                for _, serviceNode in ipairs(Runtime.directServices(
                        connectionDevice, Runtime.UpnpIgd.DEVICE_NAMESPACE)) do
                    serviceNodes[#serviceNodes + 1] = serviceNode
                end
            end
        end

        local allowedServiceTypes
        if deviceType == Runtime.UpnpIgd.IGD2_TARGET then
            allowedServiceTypes = {
                [Runtime.UpnpIgd.WAN_IP_V2] = true,
                [Runtime.UpnpIgd.WAN_PPP_V1] = true,
            }
        else
            allowedServiceTypes = {
                [Runtime.UpnpIgd.WAN_IP_V1] = true,
                [Runtime.UpnpIgd.WAN_PPP_V1] = true,
            }
        end
        local candidates = {}
        for order, serviceNode in ipairs(serviceNodes) do
            local typeMatches = Runtime.directChildren(serviceNode, "serviceType", Runtime.UpnpIgd.DEVICE_NAMESPACE)
            local controlMatches = Runtime.directChildren(serviceNode, "controlURL", Runtime.UpnpIgd.DEVICE_NAMESPACE)
            if #typeMatches == 1 and #controlMatches == 1 then
                local serviceType = Runtime.scalarText(typeMatches[1], false)
                local rank = serviceType and allowedServiceTypes[serviceType]
                    and Runtime.SERVICE_RANKS[serviceType]
                if rank then
                    local controlReference = Runtime.scalarText(controlMatches[1], false)
                    local control = controlReference and Runtime.resolveUrl(
                        controlReference, base, discovery.location.origin) or nil
                    if control then
                        local candidate = {
                            serviceType = serviceType,
                            controlUrl = control.url,
                            control = control,
                            gatewayAddress = discovery.gatewayAddress,
                            trustedOrigin = discovery.location.origin,
                            supportsAddAnyPortMapping = serviceType == Runtime.UpnpIgd.WAN_IP_V2,
                            fallback = serviceType == Runtime.UpnpIgd.WAN_PPP_V1,
                            rank = rank,
                            order = order,
                        }
                        Runtime.TRUSTED_SERVICES[candidate] = {
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
end

return Component
