-- This hook is present only in the manually operated engineering APK.
-- Detection happens when the player opens a Direct setup screen; no peer is
-- contacted, invite generated, approval granted, or save created here.
local Setup = {}

function Setup.install()
    local DirectScreen = require("src.screens.direct_screen")
    local DirectOpeningCode = require("src.net.direct_opening_code")
    local LocalIpv6 = require("src.net.local_ipv6")
    local originalEnter = DirectScreen.enter
    DirectScreen.enter = function(options)
        local copied = {}
        for key, value in pairs(options or {}) do copied[key] = value end
        -- Tests and callers may supply their own selector. Smoke runs exercise
        -- the shared screen contract with deterministic fake routes and never
        -- inspect the machine running the packaged smoke test.
        if copied.detectLocalIpv6 == nil and os.getenv("PICTURE_SHOP_SMOKE") ~= "1" then
            copied.detectLocalIpv6 = function(hostCode)
                local peerAddress
                if hostCode then
                    local parsed = DirectOpeningCode.parseHost(hostCode, os.time())
                    if not parsed then
                        return nil, "Paste a valid, unexpired TPS2H host code first."
                    end
                    peerAddress = parsed.address
                end
                local address, reason = LocalIpv6.detect({ peerAddress = peerAddress })
                if address then return address end
                return nil, LocalIpv6.messageFor(reason)
            end
        end
        return originalEnter(copied)
    end
end

return Setup
