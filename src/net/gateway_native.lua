-- Narrow LuaJIT FFI boundary for read-only Windows default-route discovery.
-- The native side owns all operating-system structures.  Lua receives only
-- bounded text and one interface index, and every failure is sanitized.
local IpScope = require("src.net.ip_scope")

local GatewayNative = {
    expectedAbiVersion = 1,
    readOnly = true,
    networkTrafficSent = false,
}

local ADDRESS_BYTES = 16
local MAX_INTERFACE_INDEX = 4294967295
local ffi
local nativeLibrary
local loadAttempted = false

local function addUnique(values, seen, value)
    if type(value) ~= "string" or value == "" or seen[value] then return end
    seen[value] = true
    values[#values + 1] = value
end

local function directoryName(path)
    if type(path) ~= "string" then return nil end
    return path:match("^(.*)[/\\][^/\\]+$")
end

local function joinPath(root, relative)
    if type(root) ~= "string" or root == "" then return relative end
    local separator = package.config:sub(1, 1)
    relative = relative:gsub("[/\\]", separator)
    if root:sub(-1) == "/" or root:sub(-1) == "\\" then
        return root .. relative
    end
    return root .. separator .. relative
end

local function sourceRoots()
    local roots, seen = {}, {}

    if love and love.filesystem then
        local filesystem = love.filesystem
        if type(filesystem.getSource) == "function" then
            local ok, source = pcall(filesystem.getSource)
            if ok and type(source) == "string" then
                if source:lower():sub(-5) == ".love" then
                    source = directoryName(source)
                end
                addUnique(roots, seen, source)
            end
        end
        if type(filesystem.getSourceBaseDirectory) == "function" then
            local ok, base = pcall(filesystem.getSourceBaseDirectory)
            if ok then addUnique(roots, seen, base) end
        end
    end

    if debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, 1, "S")
        local source = ok and info and info.source or nil
        if type(source) == "string" and source:sub(1, 1) == "@" then
            source = source:sub(2)
            local root = source:match(
                "^(.*)[/\\]src[/\\]net[/\\]gateway_native%.lua$")
            if not root and source:match(
                    "^src[/\\]net[/\\]gateway_native%.lua$") then
                root = "."
            end
            addUnique(roots, seen, root)
        end
    end

    return roots
end

local function libraryCandidates()
    local candidates, seen = {}, {}
    local override
    if os and type(os.getenv) == "function" then
        local ok, configured = pcall(os.getenv, "TPS_ROUTE_LIBRARY")
        if ok and type(configured) == "string" then
            configured = configured:match("^%s*(.-)%s*$")
            if configured ~= "" then override = configured end
        end
    end
    if override then
        addUnique(candidates, seen, override)
        return candidates
    end

    for _, root in ipairs(sourceRoots()) do
        addUnique(candidates, seen, joinPath(root, "tps_route.dll"))
        addUnique(candidates, seen,
            joinPath(root, "native/route/tps_route.dll"))
        addUnique(candidates, seen,
            joinPath(root,
                "output/native-route/build/windows-x64/tps_route.dll"))
    end
    return candidates
end

local function bindLibrary()
    if loadAttempted then return nativeLibrary, ffi end
    loadAttempted = true

    local ffiOk, ffiModule = pcall(require, "ffi")
    if not ffiOk or type(ffiModule) ~= "table" then return nil end
    ffi = ffiModule
    local cdefOk = pcall(ffi.cdef, [[
        uint32_t tps_route_abi_version(void);
        int32_t tps_route_default_ipv4(
            char source[16], char gateway[16], uint32_t *interface_index);
    ]])
    if not cdefOk then return nil end

    for _, candidate in ipairs(libraryCandidates()) do
        local loadOk, library = pcall(ffi.load, candidate)
        if loadOk and library then
            local abiOk, abi = pcall(function()
                return tonumber(library.tps_route_abi_version())
            end)
            if abiOk and abi == GatewayNative.expectedAbiVersion then
                nativeLibrary = library
                return nativeLibrary, ffi
            end
        end
    end
    return nil
end

local function decodeBoundedCString(buffer, ffiModule)
    local raw = ffiModule.string(buffer, ADDRESS_BYTES)
    local terminator = raw:find("\0", 1, true)
    if not terminator then return nil end
    return raw:sub(1, terminator - 1)
end

local function defaultInvoke()
    local library, ffiModule = bindLibrary()
    if not library or not ffiModule then return nil end

    local source = ffiModule.new("char[16]")
    local gateway = ffiModule.new("char[16]")
    local interfaceIndex = ffiModule.new("uint32_t[1]")
    local result = tonumber(library.tps_route_default_ipv4(
        source, gateway, interfaceIndex))
    if result ~= 0 then return result end
    return result,
        decodeBoundedCString(source, ffiModule),
        decodeBoundedCString(gateway, ffiModule),
        tonumber(interfaceIndex[0])
end

local function validInterfaceIndex(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 1 and value <= MAX_INTERFACE_INDEX
end

function GatewayNative.discover(options)
    options = type(options) == "table" and options or {}
    local invoke = rawget(options, "invoke") or defaultInvoke
    if type(invoke) ~= "function" then
        return nil, "native_route_unavailable"
    end

    local ok, result, source, gateway, interfaceIndex = pcall(invoke)
    if not ok or result ~= 0 then
        return nil, "native_route_unavailable"
    end
    if not IpScope.parse(source) or not IpScope.parse(gateway) or
        not validInterfaceIndex(interfaceIndex) then
        return nil, "invalid_native_route"
    end

    return {
        family = 4,
        internalAddress = source,
        gatewayAddress = gateway,
        interfaceIndex = interfaceIndex,
        routePrefixLength = 0,
    }
end

return GatewayNative
