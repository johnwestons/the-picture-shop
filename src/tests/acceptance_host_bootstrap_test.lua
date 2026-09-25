local Bootstrap = require("src.acceptance_host_bootstrap")

local Test = {}

local function environment(values)
    return function(name) return values[name] end
end

function Test.run(_, check)
    local disabled, disabledError = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({}),
    })
    check("acceptance_host_bootstrap_is_disabled_without_explicit_slot",
        disabled == nil and disabledError == nil)

    local plan = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "2",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop-acceptance-test-123",
        }),
    })
    check("acceptance_host_bootstrap_accepts_guarded_windows_plan",
        plan and plan.slot == 2
        and plan.identity == "the-picture-shop-acceptance-test-123"
        and plan.playerName == "Acceptance Worker")

    local menuPlan = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "1",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop-acceptance-test-menu",
            PICTURE_SHOP_ACCEPTANCE_HOST_SCREEN = "computer",
        }),
    })
    check("acceptance_host_bootstrap_accepts_computer_screen",
        menuPlan and menuPlan.screen == "computer")

    local invalidScreen, invalidScreenError = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "1",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop-acceptance-test-menu",
            PICTURE_SHOP_ACCEPTANCE_HOST_SCREEN = "machine",
        }),
    })
    check("acceptance_host_bootstrap_rejects_other_screens",
        invalidScreen == nil and type(invalidScreenError) == "string")

    local invalidSlot, invalidSlotError = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "4",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop-acceptance-test",
        }),
    })
    check("acceptance_host_bootstrap_rejects_invalid_slot",
        invalidSlot == nil and type(invalidSlotError) == "string")

    local normalIdentity, normalIdentityError = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "1",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop",
        }),
    })
    check("acceptance_host_bootstrap_cannot_open_normal_save_identity",
        normalIdentity == nil and type(normalIdentityError) == "string")

    local traversal, traversalError = Bootstrap.plan({
        osName = "Windows",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "1",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop-acceptance-..-other",
        }),
    })
    check("acceptance_host_bootstrap_rejects_identity_traversal",
        traversal == nil and type(traversalError) == "string")

    local android, androidError = Bootstrap.plan({
        osName = "Android",
        getenv = environment({
            PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = "1",
            PICTURE_SHOP_ACCEPTANCE_IDENTITY = "the-picture-shop-acceptance-test",
        }),
    })
    check("acceptance_host_bootstrap_cannot_run_on_android",
        android == nil and type(androidError) == "string")
end

return Test
