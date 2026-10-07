-- Office keyboard and text input.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.ComputerScreen.keypressed(state, key)
        local focused = Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoFocused
            or (Runtime.ComputerScreen.tab == "estimating" and Runtime.ComputerScreen.quoteFocused)
        if not focused then return false end
        if key == "backspace" then
            local value = Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoText or Runtime.ComputerScreen.quoteText
            if not Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.quoteReplaceOnType then
                value = ""
                Runtime.ComputerScreen.quoteReplaceOnType = false
            else
                local offset = Runtime.utf8.offset(value, -1)
                value = offset and value:sub(1, offset - 1) or ""
            end
            if Runtime.ComputerScreen.promoJobId then Runtime.ComputerScreen.promoText = value
            else Runtime.ComputerScreen.quoteText = value end
            return true
        end
        return false
    end

    function Runtime.ComputerScreen.textinput(state, text)
        if Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoFocused then
            if #Runtime.ComputerScreen.promoText < 240 then
                Runtime.ComputerScreen.promoText = (Runtime.ComputerScreen.promoText .. text):sub(1, 240)
            end
            return true
        elseif Runtime.ComputerScreen.tab == "estimating" and Runtime.ComputerScreen.quoteFocused then
            for character in text:gmatch(".") do
                if character:match("%d") and #Runtime.ComputerScreen.quoteText < 8 then
                    if Runtime.ComputerScreen.quoteReplaceOnType then
                        Runtime.ComputerScreen.quoteText = ""
                        Runtime.ComputerScreen.quoteReplaceOnType = false
                    end
                    Runtime.ComputerScreen.quoteText = Runtime.ComputerScreen.quoteText .. character
                end
            end
            return true
        end
        return false
    end

    function Runtime.ComputerScreen.wantsTextInput()
        return Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoFocused
            or Runtime.ComputerScreen.tab == "estimating" and Runtime.ComputerScreen.quoteFocused
    end
end

return Component
