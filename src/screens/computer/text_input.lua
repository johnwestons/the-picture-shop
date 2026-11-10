-- Office keyboard and text input.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.ComputerScreen.keypressed(state, key)
        if Runtime.ComputerScreen.tab=='receipts' then
            if key=='up' or key=='pageup' then return Runtime.ComputerScreen.receiptScroll(state,-1) end
            if key=='down' or key=='pagedown' then return Runtime.ComputerScreen.receiptScroll(state,1) end
        end
        local focused = Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoFocused
            or (Runtime.ComputerScreen.tab == "estimating" and (Runtime.ComputerScreen.quoteFocused
                or Runtime.ComputerScreen.deliveryQuoteFocused))
        if not focused then return false end
        if key == "backspace" then
            local deliveryFocused = Runtime.ComputerScreen.tab == "estimating"
                and Runtime.ComputerScreen.deliveryQuoteFocused
            local value = Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoText
                or deliveryFocused and Runtime.ComputerScreen.deliveryQuoteText
                or Runtime.ComputerScreen.quoteText
            local replaceOnType = deliveryFocused and Runtime.ComputerScreen.deliveryQuoteReplaceOnType
                or not deliveryFocused and not Runtime.ComputerScreen.promoJobId
                    and Runtime.ComputerScreen.quoteReplaceOnType
            if not Runtime.ComputerScreen.promoJobId and replaceOnType then
                value = ""
                if deliveryFocused then Runtime.ComputerScreen.deliveryQuoteReplaceOnType = false
                else Runtime.ComputerScreen.quoteReplaceOnType = false end
            else
                local offset = Runtime.utf8.offset(value, -1)
                value = offset and value:sub(1, offset - 1) or ""
            end
            if Runtime.ComputerScreen.promoJobId then Runtime.ComputerScreen.promoText = value
            elseif deliveryFocused then Runtime.ComputerScreen.deliveryQuoteText = value
            else Runtime.ComputerScreen.quoteText = value end
            return true
        end
        return false
    end

    function Runtime.ComputerScreen.textinput(state, text)
        if Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoFocused then
            local current=Runtime.ComputerScreen.promoText
            local addition=tostring(text or ""):sub(1,math.max(0,600-#current))
            while #addition>0 and not Runtime.utf8.len(addition) do
                addition=addition:sub(1,-2)
            end
            Runtime.ComputerScreen.promoText = current .. addition
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
        elseif Runtime.ComputerScreen.tab == "estimating" and Runtime.ComputerScreen.deliveryQuoteFocused then
            for character in text:gmatch(".") do
                if character:match("%d") and #Runtime.ComputerScreen.deliveryQuoteText < 8 then
                    if Runtime.ComputerScreen.deliveryQuoteReplaceOnType then
                        Runtime.ComputerScreen.deliveryQuoteText = ""
                        Runtime.ComputerScreen.deliveryQuoteReplaceOnType = false
                    end
                    Runtime.ComputerScreen.deliveryQuoteText = Runtime.ComputerScreen.deliveryQuoteText .. character
                end
            end
            return true
        end
        return false
    end

    function Runtime.ComputerScreen.wantsTextInput()
        return Runtime.ComputerScreen.promoJobId and Runtime.ComputerScreen.promoFocused
            or Runtime.ComputerScreen.tab == "estimating" and (Runtime.ComputerScreen.quoteFocused
                or Runtime.ComputerScreen.deliveryQuoteFocused)
    end
end

return Component
