local ImageContract = require("src.image_contract")

local Test = {}

function Test.run(context, check)
    local width, height = ImageContract.dimensions(context.config.paths.polarBackButton)
    check("domain_png_header_contract", width == 384 and height == 128)
    context.characterAssets.retainCharacters({})
    check("domain_character_startup_has_no_pixel_scans",
        context.characterAssets.anchorPixelScans() == 0)
    check("domain_asset_pack_transitions",
        context.assets.activatePack("menu")
        and context.assets.get("polarOperatorConsole") ~= nil
        and context.assets.get("cutterClamp") == nil
        and context.assets.activatePack("cutter")
        and context.assets.get("cutterClamp") ~= nil
        and context.assets.activatePack("wrapper")
        and context.assets.get("cutterClamp") == nil
        and context.assets.get("wrappedPalletStages") ~= nil
        and context.assets.get("wrapperMaintenanceAtlas") ~= nil
        and context.assets.getQuad("wrapperMaintenance1") ~= nil
        and context.assets.getQuad("wrapperMaintenance4") ~= nil
        and context.assets.activatePack("press")
        and context.assets.get("wrapperMaintenanceAtlas") == nil
        and context.assets.get("pressProcessStages") ~= nil
        and context.assets.getQuad("pressProcessStage1") ~= nil
        and context.assets.getQuad("pressProcessStage4") ~= nil
        and context.assets.activatePack(nil)
        and context.assets.get("wrappedPalletStages") ~= nil
        and context.assets.get("pressProcessStages") == nil)
end

return Test
