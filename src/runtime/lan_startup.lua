-- LAN host/client startup and local play.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.prepareHostSave(slot)
        local payload, status = Runtime.Save.load(slot)
        local mode = "continue"
        if not payload and status == "empty" then
            payload, mode = Runtime.Save.newGame(slot), "new"
        elseif not payload then
            return nil, nil, "That host save is damaged. Choose another slot or delete it first."
        end
        local writable, writableError = Runtime.Save.preflightWritable(slot)
        if not writable then return nil, nil, writableError end
        return payload, mode
    end

    function Runtime.startLanHost(slot, playerName)
        local payload, mode, loadError = Runtime.prepareHostSave(slot)
        if not payload then return false, loadError end
        local addressOptions
        local connectionMode = Runtime.App.settings and Runtime.App.settings.lanConnectionMode
        if connectionMode == "usb" or connectionMode == "wifi" then
            local matchingInterfaces = {}
            for _, interface in ipairs(Runtime.LanAddress.detectLanInterfaces()) do
                if (connectionMode == "usb" and interface.isUsb)
                    or (connectionMode == "wifi" and not interface.isUsb)
                then
                    matchingInterfaces[#matchingInterfaces + 1] = interface
                end
            end
            if #matchingInterfaces > 0 then addressOptions = { candidates = matchingInterfaces } end
        end
        Runtime.workshopAuthority = Runtime.createWorkshopAuthority()
        Runtime.localWorkshopLease = nil
        Runtime.localWorkshopRequestId = 0
        Runtime.activeCutterRemote = nil
        Runtime.activeWrapperRemote = nil
        Runtime.activeWindmillRemote = nil
        Runtime.machineRemoteSessions = {}
        local hostName = tostring(playerName or "LAN Worker"):gsub("Worker", "Host")
        local ok, errorMessage = Runtime.multiplayer:startHost({
            port = 22122,
            name = hostName,
            character = Runtime.Config.player.character,
            furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
            overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
            addressOptions = addressOptions,
        })
        if not ok then
            Runtime.clearWorkshopAuthority("host_start_failed")
            return false, errorMessage
        end
        Runtime.lanReconnect:cancel(true)
        Runtime.lanReconnectArmed = false
        local discoveryOk, discoveryError = Runtime.lanDiscovery:startHost({
            gamePort = 22122,
            name = hostName .. " - Slot " .. tostring(slot),
        })
        local started, startError = Runtime.startGame(payload, mode)
        if not started then
            Runtime.lanDiscovery:stop()
            Runtime.multiplayer:stop("Host save could not be opened")
            Runtime.clearWorkshopAuthority("host_save_failed")
            Runtime.state.screen = "lan"
            return false, startError
        end
        if Runtime.isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
            love.window.setDisplaySleepEnabled(false)
        end
        Runtime.state.message = discoveryOk
            and ("Local Play host active at " .. tostring(Runtime.multiplayer.localAddress or "this device")
                .. ". Nearby workers can find this shop automatically or join by local IPv4.")
            or ("Local Play host active at " .. tostring(Runtime.multiplayer.localAddress or "this device")
                .. ". Automatic discovery is unavailable: " .. tostring(discoveryError))
        return true
    end

    function Runtime.startLanSearch()
        local interfaces = Runtime.LanAddress.detectLanInterfaces()
        Runtime.LanScreen.setLocalInterfaces(interfaces)
        local ok, message = Runtime.lanDiscovery:startSearch({ localInterfaces = interfaces })
        local activeInterfaces = Runtime.lanDiscovery:interfaces()
        if #activeInterfaces > 0 then Runtime.LanScreen.setLocalInterfaces(activeInterfaces) end
        local _, status = Runtime.lanDiscovery:status()
        Runtime.LanScreen.setDiscovery({}, ok and status or message)
        return ok, message
    end

    function Runtime.startLanClient(address, playerName, reconnecting)
        if reconnecting ~= true then
            Runtime.lanReconnect:cancel(false)
            Runtime.lanReconnect:remember(address, playerName)
            Runtime.lanReconnectArmed = false
        end
        Runtime.lanDiscovery:stop()
        local ok, message = Runtime.multiplayer:startClient(address, {
            name = playerName,
            character = Runtime.Config.player.character,
            furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
            overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
        })
        if not ok and reconnecting ~= true then Runtime.startLanSearch() end
        return ok, message
    end

    Runtime.openLocalPlay = function(slot)
        local sessionClean, sessionError = Runtime.multiplayer:stop("Opening Local Play")
        Runtime.clearWorkshopAuthority("session_closed")
        Runtime.lanReconnect:cancel(true)
        Runtime.lanReconnectArmed = false
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not sessionClean or not connectionClean or not hostClean then
            Runtime.state.screen = "direct"
            Runtime.DirectScreen.showCleanupError(sessionError or connectionError or hostError)
            return false
        end
        Runtime.state.screen = "lan"
        Runtime.LanScreen.enter({
            slot = slot,
            settings = Runtime.App.settings,
            saveSettings = function() return Runtime.Settings.save(Runtime.App.settings) end,
            refresh = Runtime.startLanSearch,
            host = Runtime.startLanHost,
            join = Runtime.startLanClient,
            cancel = function()
                Runtime.lanReconnect:cancel(true)
                Runtime.lanReconnectArmed = false
                Runtime.multiplayer:stop("Connection cancelled")
                Runtime.startLanSearch()
            end,
            back = function()
                Runtime.lanDiscovery:stop()
                Runtime.lanReconnect:cancel(true)
                Runtime.lanReconnectArmed = false
                Runtime.multiplayer:stop("Leaving Local Play")
                Runtime.state.screen = "title"
                Runtime.TitleScreen.enter(Runtime.startGame, Runtime.openLocalPlay,
                    Runtime.CryptoNative.productionReady == true and Runtime.openDirectPlay or nil)
            end,
        })
        Runtime.startLanSearch()
    end
end

return Component
