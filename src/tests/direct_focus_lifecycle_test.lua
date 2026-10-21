local FocusGrace = require("src.net.focus_grace")
local DirectScreen = require("src.screens.direct_screen")

local Test = {}

local function fixture(android, role)
    local observed = {now=10, wallNow=1000, closeCalls=0, neutral=0, cancelled=0, saved=0,
        closeOkay=true, clipboard="test-invitation"}
    local function noop() end
    local multiplayer = {active=false, host=false, networkKind="direct"}
    function multiplayer:isActive() return self.active end
    function multiplayer:isHost() return self.host end
    function multiplayer:isClient() return self.active and not self.host end
    function multiplayer:sendNeutralInput() observed.neutral=observed.neutral+1 end
    local connection = {issuedAt=10, lifetime=600}
    function connection:close()
        observed.closeCalls=observed.closeCalls+1
        return observed.closeOkay
    end
    local Runtime = {
        App={}, state={screen="direct"}, multiplayer=multiplayer,
        directConnection=connection, pendingDirectSession={role=role},
        DirectScreen=DirectScreen, DirectIpv4Runtime={hosts={}},
        Assets={clearCache=noop}, CharacterAssets={clearCache=noop},
        WorldRenderer={clearCache=noop}, isAndroidPlatform=function() return android end,
        saveCurrent=function() observed.saved=observed.saved+1 end,
        syncMobileKeyboard=function() observed.keyboardSynced=true end,
        mobileControls={cancelAll=function() observed.cancelled=observed.cancelled+1 end},
        controller={cancelAll=function() observed.cancelled=observed.cancelled+1 end},
    }
    Runtime.App.sound={setPaused=function(_, paused) observed.paused=paused end}
    Runtime.App.multiplayerFocusGrace=FocusGrace.new({clock=function() return observed.now end,
        wallClock=function() return observed.wallNow end})
    require("src.runtime.direct_setup").install(Runtime)
    require("src.runtime.simulation").install(Runtime)
    require("src.runtime.lifecycle").install(Runtime)
    DirectScreen.clipboardCode=nil
    DirectScreen.enter({
        readClipboard=function() return observed.clipboard end,
        writeClipboard=function(value) observed.clipboard=value;return true end,
    })
    DirectScreen.mode=role=="host" and "host_reply" or "opening_guest"
    DirectScreen.displayCode="test-invitation"
    DirectScreen.clipboardCode=DirectScreen.displayCode
    return Runtime, observed, connection
end

function Test.run(_, check)
    local previous={}
    for key,value in pairs(DirectScreen) do previous[key]=value end
    local okay, reason=pcall(function()
        local runtime, observed, connection=fixture(true,"host")
        local callbacks=DirectScreen.callbacks
        runtime.App.focus(false)
        check("direct_android_host_can_share_invite_without_cancelling_setup",
            runtime.directConnection==connection and observed.closeCalls==0
            and DirectScreen.mode=="host_reply" and DirectScreen.displayCode=="test-invitation"
            and DirectScreen.callbacks==callbacks and observed.clipboard=="test-invitation")
        check("direct_android_invite_sharing_neutralizes_inputs_and_saves",
            observed.neutral==1 and observed.cancelled==2 and observed.saved==1 and observed.paused)
        observed.now=70
        runtime.App.focus(false)
        check("direct_android_repeated_focus_loss_does_not_extend_grace",
            runtime.App.multiplayerFocusGrace:elapsed()==60)
        observed.now=130
        runtime.App.focus(true)
        check("direct_android_resume_within_grace_preserves_original_expiring_connection",
            runtime.directConnection==connection and observed.closeCalls==0
            and connection.issuedAt==10 and connection.lifetime==600
            and not runtime.App.multiplayerFocusGrace:isTracking() and not observed.paused)

        runtime, observed, connection=fixture(true,"guest")
        runtime.App.focus(false)
        observed.now=45
        runtime.App.focus(true)
        check("direct_android_guest_can_share_reply_without_cancelling_opening",
            runtime.directConnection==connection and observed.closeCalls==0
            and DirectScreen.mode=="opening_guest" and DirectScreen.displayCode=="test-invitation")

        runtime, observed=fixture(true,"host")
        runtime.App.focus(false)
        observed.now=131
        runtime.App.focus(true)
        check("direct_android_pending_invite_expires_after_background_grace",
            runtime.directConnection==nil and runtime.pendingDirectSession==nil
            and observed.closeCalls==1 and not runtime.App.multiplayerFocusGrace:isTracking())
        check("direct_android_background_timeout_clears_invite_and_owned_clipboard",
            DirectScreen.displayCode==nil and DirectScreen.mode=="menu" and observed.clipboard==""
            and DirectScreen.message:find("more than 2 minutes",1,true) and observed.keyboardSynced)

        runtime, observed=fixture(true,"guest")
        runtime.App.focus(false)
        observed.wallNow=1121
        runtime.App.focus(true)
        check("direct_android_resume_after_deep_sleep_expires_pending_reply",
            observed.now==10 and runtime.directConnection==nil and observed.closeCalls==1
            and DirectScreen.displayCode==nil and observed.clipboard=="")

        runtime, observed, connection=fixture(true,"guest")
        observed.closeOkay=false
        runtime.App.focus(false)
        observed.now=131
        runtime.App.focus(true)
        check("direct_android_background_cleanup_failure_retains_socket_owner",
            runtime.directConnection==connection and runtime.pendingDirectSession~=nil
            and observed.closeCalls==1 and DirectScreen.mode=="cleanup_failed"
            and DirectScreen.displayCode==nil and observed.clipboard=="")
        observed.closeOkay=true
        check("direct_android_background_cleanup_owner_can_retry",
            runtime.closeDirectConnection()==true and runtime.directConnection==nil
            and runtime.pendingDirectSession==nil and observed.closeCalls==2)

        runtime, observed=fixture(false,"host")
        runtime.App.focus(false)
        check("direct_desktop_pending_invite_still_cancels_on_focus_loss",
            runtime.directConnection==nil and observed.closeCalls==1
            and not runtime.App.multiplayerFocusGrace:isTracking()
            and DirectScreen.displayCode==nil and observed.clipboard=="")

        runtime, observed, connection=fixture(true,"host")
        runtime.multiplayer.active=true
        runtime.multiplayer.host=true
        runtime.pendingDirectSession.kind="additional_host"
        runtime.App.focus(false)
        check("direct_android_additional_invite_sharing_preserves_existing_host",
            runtime.multiplayer:isHost() and runtime.multiplayer:isActive()
            and runtime.directConnection==connection and observed.closeCalls==0
            and runtime.App.multiplayerFocusGrace:isTracking())

        runtime, observed=fixture(true,"host")
        runtime.directConnection=nil
        runtime.pendingDirectSession=nil
        runtime.App.focus(false)
        check("direct_idle_android_has_no_background_session_to_expire",
            not runtime.App.multiplayerFocusGrace:isTracking()
            and runtime.App.expireBackgroundMultiplayer()==false and observed.closeCalls==0)
    end)
    for key in pairs(DirectScreen) do DirectScreen[key]=nil end
    for key,value in pairs(previous) do DirectScreen[key]=value end
    if not okay then error(reason) end
end

return Test
