local UpnpIgd = require("src.net.upnp_igd")

local Test = {}

local TEST_UDN = "uuid:12345678-1234-4abc-8def-1234567890ab"
local CONTROL_POINT = "192.168.1.134"
local LIFECYCLE = { nowSeconds = 1000, networkEpoch = "wifi-a" }

local function rejected(callable, ...)
    local value, errorMessage = callable(...)
    return value == nil and type(errorMessage) == "string" and errorMessage ~= ""
end

local function replacePlain(value, old, new)
    local position = value:find(old, 1, true)
    if not position then return value end
    return value:sub(1, position - 1) .. new .. value:sub(position + #old)
end

local function ssdpResponse(target, location, extras)
    extras = extras or {}
    local fields = {
        extras.status or "HTTP/1.1 200 OK",
        "CACHE-CONTROL: max-age=1800",
        "EXT:",
        "LOCATION: " .. (location or "http://192.168.1.1:5000/root.xml"),
        "ST: " .. target,
        "USN: " .. TEST_UDN .. "::" .. target,
        "SERVER: test/1 UPnP/1.1 gateway/1",
        "BOOTID.UPNP.ORG: 1",
    }
    for _, field in ipairs(extras.fields or {}) do fields[#fields + 1] = field end
    return table.concat(fields, "\r\n") .. "\r\n\r\n"
end

local function discover(target, location)
    return UpnpIgd.parseSsdpResponse(ssdpResponse(target, location), {
        sourceAddress = "192.168.1.1",
        gatewayAddress = "192.168.1.1",
        expectedTarget = target,
    })
end

local function serviceXml(serviceType, controlUrl)
    return "<service><serviceType>" .. serviceType .. "</serviceType>"
        .. "<serviceId>urn:upnp-org:serviceId:test</serviceId>"
        .. "<SCPDURL>/service.xml</SCPDURL>"
        .. "<controlURL>" .. controlUrl .. "</controlURL>"
        .. "<eventSubURL>/event</eventSubURL></service>"
end

local function descriptionXml(deviceType, services, urlBase)
    local wanDeviceType = deviceType == UpnpIgd.IGD2_TARGET
        and UpnpIgd.WAN_DEVICE_V2 or UpnpIgd.WAN_DEVICE_V1
    local connectionDeviceType = deviceType == UpnpIgd.IGD2_TARGET
        and UpnpIgd.WAN_CONNECTION_DEVICE_V2 or UpnpIgd.WAN_CONNECTION_DEVICE_V1
    return "<?xml version=\"1.0\"?>"
        .. "<root xmlns=\"" .. UpnpIgd.DEVICE_NAMESPACE .. "\">"
        .. "<specVersion><major>1</major><minor>0</minor></specVersion>"
        .. (urlBase and "<URLBase>" .. urlBase .. "</URLBase>" or "")
        .. "<device><deviceType>" .. deviceType .. "</deviceType>"
        .. "<UDN>" .. TEST_UDN .. "</UDN>"
        .. "<friendlyName>Test gateway</friendlyName>"
        .. "<deviceList><device><deviceType>" .. wanDeviceType .. "</deviceType>"
        .. "<deviceList><device><deviceType>" .. connectionDeviceType .. "</deviceType>"
        .. "<serviceList>" .. table.concat(services) .. "</serviceList>"
        .. "</device></deviceList></device></deviceList>"
        .. "</device></root>"
end

local function trustedHttp(url, statusCode, body, overrides)
    local parsed = UpnpIgd.parseHttpUrl(url)
    local response = {
        statusCode = statusCode,
        body = body,
        finalUrl = url,
        peerAddress = parsed.host,
        peerPort = parsed.port,
        redirectCount = 0,
    }
    for key, value in pairs(overrides or {}) do response[key] = value end
    return response
end

local function parsedDescription(discovery, xml)
    return UpnpIgd.parseDeviceDescription(
        trustedHttp(discovery.location.url, 200, xml), discovery)
end

local function soapResponse(serviceType, action, contents)
    return "<?xml version=\"1.0\"?>"
        .. "<s:Envelope xmlns:s=\"" .. UpnpIgd.SOAP_ENVELOPE .. "\">"
        .. "<s:Body><u:" .. action .. "Response xmlns:u=\"" .. serviceType .. "\">"
        .. (contents or "") .. "</u:" .. action .. "Response></s:Body></s:Envelope>"
end

local function soapFault(code, description, extra)
    return "<s:Envelope xmlns:s=\"" .. UpnpIgd.SOAP_ENVELOPE .. "\">"
        .. "<s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>"
        .. "<detail><UPnPError xmlns=\"" .. UpnpIgd.UPNP_CONTROL .. "\">"
        .. "<errorCode>" .. tostring(code) .. "</errorCode>"
        .. "<errorDescription>" .. description .. "</errorDescription>"
        .. (extra or "") .. "</UPnPError></detail></s:Fault></s:Body></s:Envelope>"
end


local function soapHttp(request, statusCode, body, overrides)
    return trustedHttp(request.url, statusCode, body, overrides)
end

function Test.run(_, check)
    local search2, context2 = UpnpIgd.buildSearchRequest(2, 2)
    local search1, context1 = UpnpIgd.buildSearchRequest(1, 1)
    check("upnp_igd_builds_canonical_bounded_igd2_and_igd1_searches",
        search2 == "M-SEARCH * HTTP/1.1\r\n"
            .. "HOST: 239.255.255.250:1900\r\n"
            .. "MAN: \"ssdp:discover\"\r\n"
            .. "MX: 2\r\n"
            .. "ST: urn:schemas-upnp-org:device:InternetGatewayDevice:2\r\n\r\n"
        and context2.expectedTarget == UpnpIgd.IGD2_TARGET
        and context2.destinationAddress == UpnpIgd.SSDP_ADDRESS
        and search1:find("MX: 1\r\n", 1, true)
        and search1:find(UpnpIgd.IGD1_TARGET, 1, true)
        and context1.expectedTarget == UpnpIgd.IGD1_TARGET
        and rejected(UpnpIgd.buildSearchRequest, 3, 2)
        and rejected(UpnpIgd.buildSearchRequest, 2, 0)
        and rejected(UpnpIgd.buildSearchRequest, 2, 6))

    local discovery = discover(UpnpIgd.IGD2_TARGET)
    local descriptionRequest = UpnpIgd.buildDescriptionRequest(discovery)
    check("upnp_igd_accepts_only_matching_private_gateway_ssdp_responses",
        discovery and discovery.location.host == "192.168.1.1"
        and discovery.location.port == 5000
        and discovery.location.path == "/root.xml"
        and discovery.searchTarget == UpnpIgd.IGD2_TARGET
        and discovery.udn == TEST_UDN
        and discovery.maxAgeSeconds == 1800
        and discovery.bootId == 1
        and descriptionRequest and descriptionRequest.method == "GET"
        and descriptionRequest.host == discovery.gatewayAddress
        and descriptionRequest.wire:find("CONNECTION: close\r\n", 1, true)
        and rejected(UpnpIgd.parseSsdpResponse,
            ssdpResponse(UpnpIgd.IGD2_TARGET), {
                sourceAddress = "8.8.8.8",
                gatewayAddress = "8.8.8.8",
                expectedTarget = UpnpIgd.IGD2_TARGET,
            })
        and rejected(UpnpIgd.parseSsdpResponse,
            ssdpResponse(UpnpIgd.IGD2_TARGET), {
                sourceAddress = "192.168.1.2",
                gatewayAddress = "192.168.1.1",
                expectedTarget = UpnpIgd.IGD2_TARGET,
            })
        and rejected(UpnpIgd.parseSsdpResponse,
            ssdpResponse(UpnpIgd.IGD1_TARGET), {
                sourceAddress = "192.168.1.1",
                gatewayAddress = "192.168.1.1",
                expectedTarget = UpnpIgd.IGD2_TARGET,
            }))

    local hostileSsdp = {
        ssdpResponse(UpnpIgd.IGD2_TARGET, "http://192.168.1.2:5000/root.xml"),
        ssdpResponse(UpnpIgd.IGD2_TARGET, "http://user@192.168.1.1/root.xml"),
        ssdpResponse(UpnpIgd.IGD2_TARGET, "https://192.168.1.1/root.xml"),
        ssdpResponse(UpnpIgd.IGD2_TARGET, "http://gateway.local/root.xml"),
        ssdpResponse(UpnpIgd.IGD2_TARGET, nil, {
            fields = { "LOCATION: http://192.168.1.1/duplicate.xml" },
        }),
        ssdpResponse(UpnpIgd.IGD2_TARGET):gsub("\r\n", "\n"),
        ssdpResponse(UpnpIgd.IGD2_TARGET) .. "body",
        ssdpResponse(UpnpIgd.IGD2_TARGET):gsub(
            "CACHE%-CONTROL: max%-age=1800\r\n", ""),
        ssdpResponse(UpnpIgd.IGD2_TARGET):gsub("EXT:\r\n", ""),
        ssdpResponse(UpnpIgd.IGD2_TARGET):gsub("BOOTID%.UPNP%.ORG: 1\r\n", ""),
        replacePlain(ssdpResponse(UpnpIgd.IGD2_TARGET), TEST_UDN, "uuid:not-a-uuid"),
        replacePlain(ssdpResponse(UpnpIgd.IGD2_TARGET),
            "::" .. UpnpIgd.IGD2_TARGET, "::" .. UpnpIgd.IGD1_TARGET),
        string.rep("x", UpnpIgd.MAX_SSDP_BYTES + 1),
    }
    local hostileRejected = true
    for _, packet in ipairs(hostileSsdp) do
        hostileRejected = hostileRejected and rejected(UpnpIgd.parseSsdpResponse, packet, {
            sourceAddress = "192.168.1.1",
            gatewayAddress = "192.168.1.1",
            expectedTarget = UpnpIgd.IGD2_TARGET,
        })
    end
    check("upnp_igd_ssdp_parser_binds_required_bounded_identity_metadata",
        hostileRejected)

    local rawBody = "hello"
    local rawHttp = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n" .. rawBody
    local parsedHttp = UpnpIgd.parseHttpResponse(rawHttp, 16)
    local chunkedHttp = UpnpIgd.parseHttpResponse(
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            .. "2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n", 16)
    check("upnp_igd_http_parser_bounds_content_length_and_chunked_bodies",
        parsedHttp and parsedHttp.statusCode == 200 and parsedHttp.body == "hello"
        and chunkedHttp and chunkedHttp.body == "hello"
        and rejected(UpnpIgd.parseHttpResponse,
            "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nhello", 16)
        and rejected(UpnpIgd.parseHttpResponse,
            "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\nhello", 16)
        and rejected(UpnpIgd.parseHttpResponse,
            "HTTP/1.1 200 OK\r\n\r\n" .. string.rep("x", 17), 16))

    local fullDescription = descriptionXml(UpnpIgd.IGD2_TARGET, {
        serviceXml(UpnpIgd.WAN_PPP_V1, "/control/ppp"),
        serviceXml(UpnpIgd.WAN_IP_V1, "/control/ip1"),
        serviceXml(UpnpIgd.WAN_IP_V2, "../control/ip2?mode=a&amp;safe=1"),
    }, "http://192.168.1.1:5000/base/")
    local described = parsedDescription(discovery, fullDescription)
    local originalLocationUrl = discovery.location.url
    discovery.location.url = "http://192.168.1.1:5000/substituted.xml"
    local mutatedDiscoveryRejected = rejected(UpnpIgd.parseDeviceDescription,
        trustedHttp(discovery.location.url, 200, fullDescription), discovery)
    discovery.location.url = originalLocationUrl
    check("upnp_igd_description_uses_exact_igd2_hierarchy_and_same_origin_urls",
        described and described.deviceType == UpnpIgd.IGD2_TARGET
        and described.service.serviceType == UpnpIgd.WAN_IP_V2
        and described.service.supportsAddAnyPortMapping
        and described.service.controlUrl
            == "http://192.168.1.1:5000/control/ip2?mode=a&safe=1"
        and #described.services == 2
        and described.services[2].fallback
        and mutatedDiscoveryRejected)

    local discovery1 = discover(UpnpIgd.IGD1_TARGET)
    local v1Only = parsedDescription(discovery1, descriptionXml(UpnpIgd.IGD1_TARGET, {
        serviceXml(UpnpIgd.WAN_IP_V1, "/control/ip1"),
        serviceXml(UpnpIgd.WAN_PPP_V1, "/control/ppp"),
    }))
    local pppOnly = parsedDescription(discovery1, descriptionXml(UpnpIgd.IGD1_TARGET, {
        serviceXml(UpnpIgd.WAN_PPP_V1, "/control/ppp"),
    }))
    check("upnp_igd_description_uses_igd1_ip_then_documented_ppp_fallback",
        v1Only and v1Only.service.serviceType == UpnpIgd.WAN_IP_V1
        and not v1Only.service.fallback
        and pppOnly and pppOnly.service.serviceType == UpnpIgd.WAN_PPP_V1
        and pppOnly.service.fallback)

    local hostileDescriptions = {
        descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "http://192.168.1.2:5000/control"),
        }),
        descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "http://user@192.168.1.1:5000/control"),
        }),
        descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "/control"),
        }, "http://192.168.1.1:5001/base/"),
        descriptionXml("urn:example:device:NotAGateway:1", {
            serviceXml(UpnpIgd.WAN_IP_V2, "/control"),
        }),
        "<!DOCTYPE root [<!ENTITY x SYSTEM \"file:///etc/passwd\">]>"
            .. descriptionXml(UpnpIgd.IGD2_TARGET, {
                serviceXml(UpnpIgd.WAN_IP_V2, "/control"),
            }),
        descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "/control?x=&future;"),
        }),
        replacePlain(descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "/control"),
        }), UpnpIgd.WAN_DEVICE_V2, UpnpIgd.WAN_DEVICE_V1),
        replacePlain(descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "/control"),
        }), UpnpIgd.WAN_CONNECTION_DEVICE_V2, UpnpIgd.WAN_CONNECTION_DEVICE_V1),
        replacePlain(descriptionXml(UpnpIgd.IGD2_TARGET, {
            serviceXml(UpnpIgd.WAN_IP_V2, "/control"),
        }), TEST_UDN, "uuid:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
    }
    local descriptionsRejected = true
    for _, xml in ipairs(hostileDescriptions) do
        descriptionsRejected = descriptionsRejected and rejected(
            UpnpIgd.parseDeviceDescription,
            trustedHttp(discovery.location.url, 200, xml),
            discovery)
    end
    check("upnp_igd_description_rejects_ssrf_redirect_dtd_entity_and_wrong_device_inputs",
        descriptionsRejected
        and rejected(UpnpIgd.parseDeviceDescription,
            trustedHttp(discovery.location.url, 302, ""), discovery)
        and rejected(UpnpIgd.parseDeviceDescription,
            trustedHttp(discovery.location.url, 200, fullDescription, {
                finalUrl = "http://192.168.1.1:5000/redirected.xml",
            }), discovery)
        and rejected(UpnpIgd.parseDeviceDescription,
            trustedHttp(discovery.location.url, 200,
                string.rep("x", UpnpIgd.MAX_DESCRIPTION_BYTES + 1)), discovery)
        and rejected(UpnpIgd.parseDeviceDescription, {
            statusCode = 200,
            body = fullDescription,
            finalUrl = discovery.location.url,
            peerAddress = "192.168.1.1",
            peerPort = 5000,
        }, discovery)
        and rejected(UpnpIgd.parseDeviceDescription,
            trustedHttp(discovery.location.url, 200, fullDescription, {
                peerAddress = "192.168.1.2",
            }), discovery)
        and rejected(UpnpIgd.parseDeviceDescription,
            trustedHttp(discovery.location.url, 200, fullDescription, {
                redirectCount = 1,
            }), discovery))

    local service2 = described.service
    local originalControlUrl = service2.control.url
    service2.control.url = "http://192.168.1.1:5000/substituted-control"
    local mutatedServiceRejected = rejected(
        UpnpIgd.buildGetExternalIPAddress, service2)
    service2.control.url = originalControlUrl
    local addAny = UpnpIgd.buildAddAnyPortMapping(service2, {
        port = 22122,
        internalClient = CONTROL_POINT,
        controlPointAddress = CONTROL_POINT,
        leaseSeconds = 1800,
        description = "TPS & co-op",
    })
    local addV1 = UpnpIgd.buildAddPortMapping(v1Only.service, {
        port = 22122,
        internalClient = CONTROL_POINT,
        controlPointAddress = CONTROL_POINT,
        leaseSeconds = 900,
    })
    local splitPorts = UpnpIgd.buildAddPortMapping(service2, {
        internalPort = 22122,
        externalPort = 33000,
        internalClient = CONTROL_POINT,
        controlPointAddress = CONTROL_POINT,
        leaseSeconds = 120,
    })
    local externalQuery = UpnpIgd.buildGetExternalIPAddress(service2)
    check("upnp_igd_builds_exact_self_only_udp_finite_lease_soap_requests",
        addAny and addAny.context.action == "AddAnyPortMapping"
        and addAny.context.protocol == "UDP" and addAny.context.requestedPort == 22122
        and addAny.context.controlPointAddress == CONTROL_POINT
        and addAny.context.internalClient == CONTROL_POINT
        and addAny.body:find("<NewExternalPort>22122</NewExternalPort>", 1, true)
        and addAny.body:find("<NewInternalPort>22122</NewInternalPort>", 1, true)
        and addAny.body:find("<NewProtocol>UDP</NewProtocol>", 1, true)
        and not addAny.body:find("TCP", 1, true)
        and addAny.body:find("<NewLeaseDuration>1800</NewLeaseDuration>", 1, true)
        and addAny.body:find("TPS &amp; co-op", 1, true)
        and tonumber(addAny.headers["content-length"]) == #addAny.body
        and addAny.headers.soapaction
            == "\"" .. UpnpIgd.WAN_IP_V2 .. "#AddAnyPortMapping\""
        and addV1 and addV1.context.action == "AddPortMapping"
        and splitPorts and splitPorts.context.requestedPort == 33000
        and splitPorts.context.internalPort == 22122
        and splitPorts.body:find("<NewExternalPort>33000</NewExternalPort>", 1, true)
        and splitPorts.body:find("<NewInternalPort>22122</NewInternalPort>", 1, true)
        and externalQuery and externalQuery.context.action == "GetExternalIPAddress"
        and mutatedServiceRejected)

    check("upnp_igd_soap_builder_rejects_nonself_clients_privileged_ports_and_permanent_leases",
        rejected(UpnpIgd.buildAddAnyPortMapping, v1Only.service, {
            port = 22122, internalClient = CONTROL_POINT,
            controlPointAddress = CONTROL_POINT, leaseSeconds = 60,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 80, internalClient = CONTROL_POINT,
            controlPointAddress = CONTROL_POINT, leaseSeconds = 60,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 22122, internalClient = "8.8.8.8",
            controlPointAddress = CONTROL_POINT, leaseSeconds = 60,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 22122, internalClient = "192.168.001.134",
            controlPointAddress = CONTROL_POINT, leaseSeconds = 60,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 22122, internalClient = "192.168.1.135",
            controlPointAddress = CONTROL_POINT, leaseSeconds = 60,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 22122, internalClient = CONTROL_POINT,
            controlPointAddress = "8.8.8.8", leaseSeconds = 60,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 22122, internalClient = CONTROL_POINT,
            controlPointAddress = CONTROL_POINT, leaseSeconds = 0,
        })
        and rejected(UpnpIgd.buildAddAnyPortMapping, service2, {
            port = 22122, internalClient = CONTROL_POINT,
            controlPointAddress = CONTROL_POINT,
            leaseSeconds = UpnpIgd.MAX_LEASE_SECONDS + 1,
        })
        and rejected(UpnpIgd.buildDeletePortMapping, service2, 40000, LIFECYCLE))

    local addAnyBody = soapResponse(UpnpIgd.WAN_IP_V2, "AddAnyPortMapping",
        "<NewReservedPort>40000</NewReservedPort>")
    local missingLifecycleRejected = rejected(UpnpIgd.parseSoapResponse,
        soapHttp(addAny, 200, addAnyBody), addAny)
    local addAnyResult = UpnpIgd.parseSoapResponse(
        soapHttp(addAny, 200, addAnyBody), addAny, LIFECYCLE)
    local replayedAddSuccessRejected = rejected(UpnpIgd.parseSoapResponse,
        soapHttp(addAny, 200, addAnyBody), addAny, LIFECYCLE)
    local addResult = UpnpIgd.parseSoapResponse(
        soapHttp(addV1, 200,
            soapResponse(UpnpIgd.WAN_IP_V1, "AddPortMapping", "")),
        addV1, LIFECYCLE)
    local ownership = addAnyResult and addAnyResult.mappingHandle
    local wrongEpochRejected = ownership and rejected(
        UpnpIgd.buildDeletePortMapping, service2, ownership,
        { nowSeconds = 1001, networkEpoch = "wifi-b" })
    local lateDeleteRejected = ownership and rejected(
        UpnpIgd.buildDeletePortMapping, service2, ownership,
        { nowSeconds = 2800, networkEpoch = "wifi-a" })
    local deletion = ownership and UpnpIgd.buildDeletePortMapping(
        service2, ownership, { nowSeconds = 1001, networkEpoch = "wifi-a" })
    local deleteResult = deletion and UpnpIgd.parseSoapResponse(
        soapHttp(deletion, 200,
            soapResponse(UpnpIgd.WAN_IP_V2, "DeletePortMapping", "")), deletion)
    check("upnp_igd_mapping_success_mints_a_bounded_owned_cleanup_handle",
        missingLifecycleRejected
        and replayedAddSuccessRejected
        and addAnyResult and addAnyResult.success and addAnyResult.externalPort == 40000
        and addAnyResult.requestedPort == 22122 and addAnyResult.portChanged
        and ownership and ownership.internalClient == CONTROL_POINT
        and ownership.expiresAt == 2800 and ownership.networkEpoch == "wifi-a"
        and addResult and addResult.success and addResult.action == "AddPortMapping"
        and addResult.mappingHandle and addResult.mappingHandle.externalPort == 22122
        and wrongEpochRejected and lateDeleteRejected
        and deletion and deletion.body:find("<NewExternalPort>40000</NewExternalPort>", 1, true)
        and deletion.body:find("<NewProtocol>UDP</NewProtocol>", 1, true)
        and not deletion.body:find("NewLeaseDuration", 1, true)
        and deleteResult and deleteResult.success and deleteResult.cleanupConfirmed
        and rejected(UpnpIgd.buildDeletePortMapping, service2, ownership,
            { nowSeconds = 1002, networkEpoch = "wifi-a" }))

    local globalAddress = UpnpIgd.parseSoapResponse(
        soapHttp(externalQuery, 200,
            soapResponse(UpnpIgd.WAN_IP_V2, "GetExternalIPAddress",
                "<NewExternalIPAddress>8.8.4.4</NewExternalIPAddress>")), externalQuery)
    local privateAddress = UpnpIgd.parseSoapResponse(
        soapHttp(externalQuery, 200,
            soapResponse(UpnpIgd.WAN_IP_V2, "GetExternalIPAddress",
                "<NewExternalIPAddress>100.64.0.1</NewExternalIPAddress>")), externalQuery)
    check("upnp_igd_external_address_classification_never_claims_reachability",
        globalAddress and globalAddress.success and globalAddress.addressIsGlobal
        and not globalAddress.reachabilityVerified and globalAddress.publiclyReachable == nil
        and globalAddress.externalAddress == "8.8.4.4"
        and privateAddress and privateAddress.success and not privateAddress.addressIsGlobal
        and not privateAddress.reachabilityVerified and privateAddress.publiclyReachable == nil
        and privateAddress.addressClassification.reason == "carrier_grade_nat")

    local faultResult = UpnpIgd.parseSoapResponse(
        soapHttp(addAny, 500, soapFault(718, "ConflictInMappingEntry",
            "<NewReservedPort>22122</NewReservedPort>")), addAny)
    local faultAt200 = UpnpIgd.parseSoapResponse(
        soapHttp(addAny, 200, soapFault(606, "Action not authorized")), addAny)
    local fakeSuccessAt500 = UpnpIgd.parseSoapResponse(
        soapHttp(addAny, 500,
            soapResponse(UpnpIgd.WAN_IP_V2, "AddAnyPortMapping",
                "<NewReservedPort>22122</NewReservedPort>")), addAny)
    check("upnp_igd_fault_and_http_failures_never_expose_mapping_success_fields",
        faultResult and not faultResult.success and faultResult.errorCode == 718
        and faultResult.errorDescription == "ConflictInMappingEntry"
        and faultResult.externalPort == nil
        and faultAt200 and not faultAt200.success and faultAt200.errorCode == 606
        and fakeSuccessAt500 and not fakeSuccessAt500.success
        and fakeSuccessAt500.errorKind == "http_status"
        and fakeSuccessAt500.externalPort == nil)

    local malformedSoap = {
        soapResponse(UpnpIgd.WAN_IP_V2, "AddAnyPortMapping",
            "<NewReservedPort>0</NewReservedPort>"),
        soapResponse(UpnpIgd.WAN_IP_V2, "AddAnyPortMapping",
            "<NewReservedPort>22122</NewReservedPort><NewReservedPort>22123</NewReservedPort>"),
        soapResponse(UpnpIgd.WAN_IP_V1, "AddAnyPortMapping",
            "<NewReservedPort>22122</NewReservedPort>"),
        soapResponse(UpnpIgd.WAN_IP_V2, "AddPortMapping", ""),
        "<!DOCTYPE s:Envelope [<!ENTITY x \"22122\">]>"
            .. soapResponse(UpnpIgd.WAN_IP_V2, "AddAnyPortMapping",
                "<NewReservedPort>&x;</NewReservedPort>"),
        soapResponse(UpnpIgd.WAN_IP_V2, "AddAnyPortMapping",
            "<evil:NewReservedPort xmlns:evil=\"urn:evil\">22122</evil:NewReservedPort>"),
    }
    local malformedRejected = true
    for _, body in ipairs(malformedSoap) do
        malformedRejected = malformedRejected and rejected(UpnpIgd.parseSoapResponse,
            soapHttp(addAny, 200, body), addAny, LIFECYCLE)
    end
    check("upnp_igd_soap_parser_rejects_duplicate_wrong_namespace_wrong_action_and_dtd_results",
        malformedRejected
        and rejected(UpnpIgd.parseSoapResponse,
            soapHttp(addAny, 302, ""), addAny, LIFECYCLE)
        and rejected(UpnpIgd.parseSoapResponse,
            soapHttp(addAny, 200, addAnyBody, {
                finalUrl = "http://192.168.1.1:5000/redirected-control",
            }), addAny, LIFECYCLE)
        and rejected(UpnpIgd.parseSoapResponse, {
            statusCode = 200,
            body = addAnyBody,
            finalUrl = addAny.url,
            peerAddress = addAny.host,
            peerPort = addAny.port,
        }, addAny, LIFECYCLE)
        and rejected(UpnpIgd.parseSoapResponse,
            soapHttp(addAny, 200, addAnyBody, { peerAddress = "192.168.1.2" }),
            addAny, LIFECYCLE)
        and rejected(UpnpIgd.parseSoapResponse,
            soapHttp(addAny, 200, addAnyBody, { redirectCount = 1 }),
            addAny, LIFECYCLE)
        and rejected(UpnpIgd.parseSoapResponse,
            soapHttp(addAny, 200,
                string.rep("x", UpnpIgd.MAX_SOAP_BODY_BYTES + 1)),
            addAny, LIFECYCLE))
end

return Test
