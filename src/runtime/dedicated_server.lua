-- Private, headless workshop authority bootstrap.
-- The server principal owns persistence; the compatibility host actor remains
-- internal to Session and is omitted from guest rosters and motion snapshots.
local Component = {}

local IDENTITY_PREFIX = "the-picture-shop-server-"
local IDENTITY_DEFAULT = IDENTITY_PREFIX .. "private"
local INVITE_PATH = "server-invite.txt"

local function environment(getenv, name)
    local value = getenv(name)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

local function integerEnvironment(getenv, name, fallback, minimum, maximum)
    local raw = environment(getenv, name)
    if not raw then return fallback end
    local value = tonumber(raw)
    if not value or value ~= math.floor(value) or value < minimum or value > maximum then
        return nil, name .. " must be an integer between " .. minimum .. " and " .. maximum .. "."
    end
    return value
end

local function validIdentity(value)
    return type(value) == "string" and #value <= 80
        and value:sub(1, #IDENTITY_PREFIX) == IDENTITY_PREFIX
        and value:match("^[a-z0-9%-]+$") ~= nil
end

local function endpointFor(bind, publicHost, port)
    if not publicHost then
        if bind ~= "127.0.0.1" and bind ~= "localhost" then
            return nil, "Set PICTURE_SHOP_SERVER_PUBLIC_HOST before binding beyond loopback."
        end
        publicHost = "127.0.0.1"
    end
    local parsed, reason = require("src.net.address").parse(publicHost, port)
    if not parsed then return nil, "The configured public host is invalid: " .. tostring(reason) end
    return parsed.endpoint
end

local function loadOrCreateInvite(Runtime, endpoint)
    local Invite = require("src.net.direct_invite")
    local existing = love.filesystem.read(INVITE_PATH)
    if existing then
        local parsed, reason = Invite.parse(existing)
        if not parsed then
            return nil, "The saved private invite is malformed; preserve it and inspect " .. INVITE_PATH
                .. " before replacing it: " .. tostring(reason)
        end
        if parsed.endpoint ~= endpoint then
            local updated, updateError = Invite.encode(endpoint, parsed.psk)
            if not updated then return nil, updateError end
            local wrote, writeError = love.filesystem.write(INVITE_PATH, updated .. "\n")
            if not wrote then return nil, "Could not update the private invite: " .. tostring(writeError) end
            parsed = assert(Invite.parse(updated))
        end
        return parsed
    end

    local psk, randomError = Runtime.CryptoNative.randomBytes(Invite.KEY_BYTES)
    if type(psk) ~= "string" or #psk ~= Invite.KEY_BYTES then
        return nil, "The native cryptographic provider could not create a private invite key: "
            .. tostring(randomError or Runtime.CryptoNative.loadError)
    end
    local invite, encodeError = Invite.encode(endpoint, psk)
    if not invite then return nil, encodeError end
    local wrote, writeError = love.filesystem.write(INVITE_PATH, invite .. "\n")
    if not wrote then return nil, "Could not persist the private invite: " .. tostring(writeError) end
    return assert(Invite.parse(invite))
end

local function secureFactory(Runtime, psk)
    local DirectTransport = require("src.net.transport_direct")
    -- This explicit, private-only engineering path exercises the same encrypted
    -- handshake without changing CryptoNative.productionReady or normal Direct Play.
    return DirectTransport.newFactory({
        baseFactory = require("src.net.transport_enet"),
        cryptoProvider = Runtime.CryptoNative,
        key = psk,
        allowEngineeringProvider = true,
        maxReadyPeers = 3,
    })
end

function Component.install(Runtime)
    Runtime.privateServerMode = false
    Runtime.privateServerStarted = false
    Runtime.privateServerRunLimit = 0
    Runtime.privateServerElapsed = 0
    Runtime.privateServerClientRunLimit = 0
    Runtime.privateServerClientElapsed = 0
    Runtime.privateServerClientExitRequested = false
    Runtime.privateServerPrincipal = nil
    Runtime.privateServerInvite = nil
    Runtime.privateServerReconnect = nil

    function Runtime.startPrivateServerClient(inviteCode, playerName)
        playerName=playerName or require('src.player_profile').name(Runtime.App.settings)
        local invite, reason = require("src.net.direct_invite").parse(inviteCode)
        if not invite then return false, reason end
        if Runtime.privateServerClientRunLimit == 0 then
            local runLimit, runLimitError = integerEnvironment(os.getenv,
                "PICTURE_SHOP_SERVER_CLIENT_RUN_SECONDS", 0, 0, 3600)
            if not runLimit then return false, runLimitError end
            Runtime.privateServerClientRunLimit = runLimit
        end
        local previous = Runtime.privateServerReconnect
        local attempts = previous and previous.invite.endpoint == invite.endpoint
            and previous.invite.psk == invite.psk and previous.attempts or 0
        local factory, factoryError = secureFactory(Runtime, invite.psk)
        if not factory then return false, factoryError end
        local ok, startError = Runtime.multiplayer:startClient(invite.endpoint, {
            networkKind = "server",
            transportFactory = factory,
            name = playerName or "Private Server Worker",
            character = Runtime.Config.player.character,
            furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
            overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
        })
        if not ok then
            factory.close()
            return false, startError
        end
        Runtime.privateServerReconnect = {
            invite = invite,
            playerName = playerName or "Private Server Worker",
            wait = 0,
            attempts = attempts,
        }
        Runtime.state.message = "Connecting to the private workshop server…"
        return true
    end

    function Runtime.schedulePrivateServerReconnect(message)
        local pending = Runtime.privateServerReconnect
        if not pending then return false end
        local stopped, stopError = Runtime.multiplayer:stop("Private server connection ended")
        if not stopped then
            pending.wait = 10
            Runtime.state.screen = "world"
            Runtime.state.message = "Private server cleanup failed; reconnect paused: "
                .. tostring(stopError)
            return true
        end
        pending.attempts = (pending.attempts or 0) + 1
        pending.wait = math.min(30, 2 ^ math.min(pending.attempts - 1, 5))
        Runtime.state.screen = "world"
        Runtime.state.message = tostring(message or "Private server connection ended.")
            .. " Reconnecting in " .. tostring(pending.wait) .. "s."
        return true
    end

    function Runtime.startDedicatedServer()
        if os.getenv("PICTURE_SHOP_PRIVATE_SERVER") ~= "1" then
            return false, "Dedicated server startup is restricted to the private server launcher."
        end

        local getenv = os.getenv
        local identity = environment(getenv, "PICTURE_SHOP_SERVER_IDENTITY") or IDENTITY_DEFAULT
        if not validIdentity(identity) then
            return false, "PICTURE_SHOP_SERVER_IDENTITY must use the the-picture-shop-server- namespace."
        end
        local port, portError = integerEnvironment(getenv, "PICTURE_SHOP_SERVER_PORT", 22122, 1, 65535)
        if not port then return false, portError end
        local slot, slotError = integerEnvironment(getenv, "PICTURE_SHOP_SERVER_SLOT", 1, 1, 3)
        if not slot then return false, slotError end
        local runLimit, runLimitError = integerEnvironment(getenv,
            "PICTURE_SHOP_SERVER_RUN_SECONDS", 0, 0, 3600)
        if not runLimit then return false, runLimitError end
        local bind = environment(getenv, "PICTURE_SHOP_SERVER_BIND") or "127.0.0.1"
        local publicHost = environment(getenv, "PICTURE_SHOP_SERVER_PUBLIC_HOST")
        local endpoint, endpointError = endpointFor(bind, publicHost, port)
        if not endpoint then return false, endpointError end

        love.filesystem.setIdentity(identity)
        Runtime.privateServerMode = true
        Runtime.privateServerRunLimit = runLimit
        Runtime.privateServerElapsed = 0
        Runtime.syncMobileKeyboard = function() end
        Runtime.privateServerPrincipal = {
            id = "server-owner",
            name = environment(getenv, "PICTURE_SHOP_SERVER_OWNER") or "Workshop Owner",
            identity = identity,
        }

        local invite, inviteError = loadOrCreateInvite(Runtime, endpoint)
        if not invite then return false, inviteError end
        local factory, factoryError = secureFactory(Runtime, invite.psk)
        if not factory then return false, factoryError end

        Runtime.App.settings = Runtime.Settings.DEFAULTS
        local payload, mode, saveError = Runtime.prepareHostSave(slot)
        if not payload then
            factory.close()
            return false, "The dedicated workshop save could not be opened: " .. tostring(saveError)
        end
        print(string.format("[PRIVATE SERVER] Save loaded slot=%d mode=%s%s",
            slot, tostring(mode), payload.recovered
                and (" recovery=" .. tostring(payload.recoverySource or "unknown")) or ""))
        local started, startError = Runtime.startGame(payload, mode)
        if not started then
            factory.close()
            return false, startError
        end

        Runtime.state.screen = "world"
        Runtime.workshopAuthority = Runtime.createWorkshopAuthority()
        Runtime.localWorkshopLease = nil
        Runtime.localWorkshopRequestId = 0
        Runtime.activeCutterRemote = nil
        Runtime.activeWrapperRemote = nil
        Runtime.activeWindmillRemote = nil
        Runtime.machineRemoteSessions = {}

        local hosted, hostError = Runtime.multiplayer:startHost({
            port = port,
            bind = bind,
            networkKind = "server",
            dedicatedServer = true,
            transportFactory = factory,
            name = "Workshop Server Authority",
            character = Runtime.Config.player.character,
            x = Runtime.World.player.x,
            y = Runtime.World.player.y,
        })
        if not hosted then
            factory.close()
            Runtime.clearWorkshopAuthority("dedicated_server_start_failed")
            return false, hostError
        end

        Runtime.privateServerInvite = invite
        Runtime.privateServerSlot = slot
        Runtime.privateServerSaveDirectory = love.filesystem.getSaveDirectory()
        Runtime.privateServerStarted = true
        print(string.format(
            "[PRIVATE SERVER] READY bind=%s port=%d save=%s protocol=%d crypto=engineering-only",
            bind, port, Runtime.privateServerSaveDirectory,
            require("src.net.protocol").VERSION))
        print("[PRIVATE SERVER] Invite file: " .. Runtime.privateServerSaveDirectory .. "/" .. INVITE_PATH)
        print("[PRIVATE SERVER] Keep this endpoint private; CryptoNative.productionReady remains false.")
        io.flush()
        return true
    end

    function Runtime.stopDedicatedServer()
        if not Runtime.privateServerStarted then
            if Runtime.Save and Runtime.Save.shutdown then Runtime.Save.shutdown() end
            return false
        end
        local saveOkay, saveError = Runtime.saveCurrent(true)
        local sessionOkay, sessionError = Runtime.multiplayer:stop("Private server shutdown")
        Runtime.clearWorkshopAuthority("dedicated_server_shutdown")
        if Runtime.Save and Runtime.Save.shutdown then Runtime.Save.shutdown() end
        if not saveOkay then
            io.stderr:write("[PRIVATE SERVER] Final save failed: " .. tostring(saveError) .. "\n")
        end
        if not sessionOkay then
            io.stderr:write("[PRIVATE SERVER] Transport shutdown needs attention: "
                .. tostring(sessionError) .. "\n")
        end
        Runtime.privateServerStarted = false
        Runtime.privateServerMode = false
        io.flush()
        return false
    end

    function Runtime.updatePrivateServerReconnect(dt)
        local pending = Runtime.privateServerReconnect
        if not pending or not pending.wait or pending.wait <= 0 then return end
        if Runtime.multiplayer:isActive() then return end
        pending.wait = pending.wait - math.max(0, tonumber(dt) or 0)
        if pending.wait > 0 then return end
        local code = require("src.net.direct_invite").encode(
            pending.invite.endpoint, pending.invite.psk)
        local okay, reason = Runtime.startPrivateServerClient(code, pending.playerName)
        if not okay then
            pending.attempts = (pending.attempts or 0) + 1
            pending.wait = math.min(30, 2 ^ math.min(pending.attempts, 5))
            Runtime.state.message = "Private server reconnect will retry: " .. tostring(reason)
        else
            pending.wait = 0
        end
    end

    function Runtime.advancePrivateServerRunTimer(dt)
        if not Runtime.privateServerStarted or Runtime.privateServerRunLimit <= 0 then return end
        Runtime.privateServerElapsed = Runtime.privateServerElapsed + math.max(0, tonumber(dt) or 0)
        if Runtime.privateServerElapsed >= Runtime.privateServerRunLimit then
            print("[PRIVATE SERVER] Bounded test run complete; flushing and stopping.")
            io.flush()
            love.event.quit(0)
        end
    end

    function Runtime.updatePrivateServerClientTimer(dt)
        if Runtime.privateServerClientRunLimit <= 0 or Runtime.privateServerClientExitRequested then return end
        Runtime.privateServerClientElapsed = Runtime.privateServerClientElapsed + math.max(0, tonumber(dt) or 0)
        if Runtime.privateServerClientElapsed >= Runtime.privateServerClientRunLimit then
            Runtime.privateServerClientExitRequested = true
            print("[PRIVATE SERVER CLIENT] Bounded test run complete; leaving the workshop.")
            io.flush()
            love.event.quit(0)
        end
    end

    Runtime.App.startDedicatedServer = Runtime.startDedicatedServer
    Runtime.App.stopDedicatedServer = Runtime.stopDedicatedServer
    Runtime.App.advancePrivateServerRunTimer = Runtime.advancePrivateServerRunTimer
end

return Component
