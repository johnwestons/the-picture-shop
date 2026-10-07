-- Bounded XML parsing and scalar extraction.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.encodeUtf8(codepoint)
        if codepoint <= 127 then return string.char(codepoint) end
        if codepoint <= 2047 then
            return string.char(192 + math.floor(codepoint / 64), 128 + codepoint % 64)
        end
        if codepoint <= 65535 then
            return string.char(
                224 + math.floor(codepoint / 4096),
                128 + math.floor(codepoint / 64) % 64,
                128 + codepoint % 64)
        end
        return string.char(
            240 + math.floor(codepoint / 262144),
            128 + math.floor(codepoint / 4096) % 64,
            128 + math.floor(codepoint / 64) % 64,
            128 + codepoint % 64)
    end

    function Runtime.decodeCharacterReference(name)
        local codepoint
        if name:match("^#[0-9]+$") and #name <= 8 then
            codepoint = tonumber(name:sub(2), 10)
        elseif name:match("^#[xX][0-9A-Fa-f]+$") and #name <= 9 then
            codepoint = tonumber(name:sub(3), 16)
        end
        if not codepoint or codepoint > 1114111
            or codepoint >= 55296 and codepoint <= 57343
            or not (codepoint == 9 or codepoint == 10 or codepoint == 13
                or codepoint >= 32 and codepoint <= 55295
                or codepoint >= 57344 and codepoint <= 65533
                or codepoint >= 65536 and codepoint <= 1114111)
        then
            return nil
        end
        return Runtime.encodeUtf8(codepoint)
    end

    function Runtime.decodeXmlText(value)
        local replacements = {
            amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'",
        }
        local output, position = {}, 1
        while true do
            local marker = value:find("&", position, true)
            if not marker then
                output[#output + 1] = value:sub(position)
                break
            end
            output[#output + 1] = value:sub(position, marker - 1)
            local ending = value:find(";", marker + 1, true)
            if not ending or ending - marker > 10 then return nil, "unsupported XML entity" end
            local name = value:sub(marker + 1, ending - 1)
            local replacement = replacements[name] or Runtime.decodeCharacterReference(name)
            if not replacement then return nil, "document-defined XML entities are not accepted" end
            output[#output + 1] = replacement
            position = ending + 1
        end
        return table.concat(output)
    end

    function Runtime.copyTable(source)
        local result = {}
        for key, value in pairs(source or {}) do result[key] = value end
        return result
    end

    function Runtime.findTagEnd(xml, position)
        local quote
        for index = position, #xml do
            local character = xml:sub(index, index)
            if quote then
                if character == quote then quote = nil end
            elseif character == "\"" or character == "'" then
                quote = character
            elseif character == ">" then
                return index
            end
            if index - position > 4096 then return nil end
        end
        return nil
    end

    function Runtime.parseStartTag(content)
        local selfClosing = content:match("/%s*$") ~= nil
        if selfClosing then content = content:gsub("/%s*$", "") end
        local position = content:find("%S")
        if not position then return nil, "empty XML tag" end
        local name = content:sub(position):match("^(" .. Runtime.XML_NAME .. ")")
        if not name then return nil, "invalid XML element name" end
        position = position + #name
        local attributes = {}
        while true do
            local whitespace = content:sub(position):match("^[ \t\r\n]*") or ""
            position = position + #whitespace
            if position > #content then break end
            local attributeName = content:sub(position):match("^(" .. Runtime.XML_NAME .. ")")
            if not attributeName then return nil, "invalid XML attribute name" end
            position = position + #attributeName
            whitespace = content:sub(position):match("^[ \t\r\n]*") or ""
            position = position + #whitespace
            if content:sub(position, position) ~= "=" then return nil, "XML attribute has no equals sign" end
            position = position + 1
            whitespace = content:sub(position):match("^[ \t\r\n]*") or ""
            position = position + #whitespace
            local quote = content:sub(position, position)
            if quote ~= "\"" and quote ~= "'" then return nil, "XML attribute is not quoted" end
            local ending = content:find(quote, position + 1, true)
            if not ending then return nil, "unterminated XML attribute" end
            if attributes[attributeName] ~= nil then return nil, "duplicate XML attribute" end
            local decoded, decodeError = Runtime.decodeXmlText(content:sub(position + 1, ending - 1))
            if not decoded then return nil, decodeError end
            attributes[attributeName] = decoded
            position = ending + 1
        end
        return name, attributes, selfClosing
    end

    function Runtime.appendXmlText(stack, value)
        if value == "" then return true end
        local decoded, decodeError = Runtime.decodeXmlText(value)
        if not decoded then return nil, decodeError end
        if #stack == 0 then
            if decoded:match("^%s*$") then return true end
            return nil, "XML has text outside its root element"
        end
        local parts = stack[#stack].textParts
        parts[#parts + 1] = decoded
        return true
    end

    function Runtime.parseXml(xml, maximumBytes)
        if type(xml) ~= "string" then return nil, "XML body must be bytes" end
        if #xml > maximumBytes then return nil, "XML body is too large" end
        if xml:find("\0", 1, true) or Runtime.hasControl(xml, true) then
            return nil, "XML body contains forbidden control bytes"
        end

        local root, stack, position, nodeCount, declarationSeen = nil, {}, 1, 0, false
        while position <= #xml do
            local marker = xml:find("<", position, true)
            if not marker then
                local ok, textError = Runtime.appendXmlText(stack, xml:sub(position))
                if not ok then return nil, textError end
                position = #xml + 1
                break
            end
            local ok, textError = Runtime.appendXmlText(stack, xml:sub(position, marker - 1))
            if not ok then return nil, textError end

            if xml:sub(marker, marker + 3) == "<!--" then
                local ending = xml:find("-->", marker + 4, true)
                if not ending then return nil, "unterminated XML comment" end
                local comment = xml:sub(marker + 4, ending - 1)
                if comment:find("--", 1, true) then return nil, "invalid XML comment" end
                position = ending + 3
            elseif xml:sub(marker, marker + 8) == "<![CDATA[" then
                local ending = xml:find("]]>", marker + 9, true)
                if not ending then return nil, "unterminated XML CDATA" end
                if #stack == 0 then return nil, "XML CDATA appears outside the root" end
                local parts = stack[#stack].textParts
                parts[#parts + 1] = xml:sub(marker + 9, ending - 1)
                position = ending + 3
            elseif xml:sub(marker, marker + 1) == "<?" then
                local ending = xml:find("?>", marker + 2, true)
                if not ending then return nil, "unterminated XML processing instruction" end
                local instruction = xml:sub(marker + 2, ending - 1)
                if root or declarationSeen or not instruction:match("^xml%s") then
                    return nil, "only one leading XML declaration is accepted"
                end
                declarationSeen = true
                position = ending + 2
            elseif xml:sub(marker, marker + 1) == "<!" then
                return nil, "XML DTDs and entity declarations are not accepted"
            else
                local ending = Runtime.findTagEnd(xml, marker + 1)
                if not ending then return nil, "unterminated or oversized XML tag" end
                local content = xml:sub(marker + 1, ending - 1)
                if content:sub(1, 1) == "/" then
                    local closingName = content:match("^/%s*(" .. Runtime.XML_NAME .. ")%s*$")
                    if not closingName or #stack == 0 or stack[#stack].name ~= closingName then
                        return nil, "mismatched XML closing tag"
                    end
                    table.remove(stack)
                else
                    local name, attributes, selfClosing = Runtime.parseStartTag(content)
                    if not name then return nil, attributes end
                    if root and #stack == 0 then return nil, "XML has more than one root element" end
                    nodeCount = nodeCount + 1
                    if nodeCount > Runtime.UpnpIgd.MAX_XML_NODES then return nil, "XML has too many elements" end
                    if #stack + 1 > Runtime.UpnpIgd.MAX_XML_DEPTH then return nil, "XML nesting is too deep" end

                    local namespaces = Runtime.copyTable(#stack > 0 and stack[#stack].namespaces or nil)
                    for attributeName, attributeValue in pairs(attributes) do
                        if attributeName == "xmlns" then
                            namespaces[""] = attributeValue
                        else
                            local prefix = attributeName:match("^xmlns:(" .. Runtime.XML_NAME .. ")$")
                            if prefix then namespaces[prefix] = attributeValue end
                        end
                    end
                    local prefix, localName = name:match("^([^:]+):(.+)$")
                    if not localName then prefix, localName = "", name end
                    local namespace = namespaces[prefix]
                    if prefix ~= "" and not namespace then return nil, "XML element prefix is undeclared" end
                    local node = {
                        name = name,
                        localName = localName,
                        namespace = namespace,
                        namespaces = namespaces,
                        attributes = attributes,
                        children = {},
                        textParts = {},
                    }
                    if #stack > 0 then
                        local parent = stack[#stack]
                        parent.children[#parent.children + 1] = node
                    else
                        root = node
                    end
                    if not selfClosing then stack[#stack + 1] = node end
                end
                position = ending + 1
            end
        end
        if #stack ~= 0 then return nil, "XML document is truncated" end
        if not root then return nil, "XML document has no root element" end
        return root
    end

    function Runtime.directChildren(node, localName, namespace)
        local result = {}
        for _, child in ipairs(node.children or {}) do
            if (not localName or child.localName == localName)
                and (namespace == nil or child.namespace == namespace)
            then
                result[#result + 1] = child
            end
        end
        return result
    end

    function Runtime.directChildrenExactNamespace(node, localName, namespace)
        local result = {}
        for _, child in ipairs(node.children or {}) do
            if (not localName or child.localName == localName)
                and child.namespace == namespace
            then
                result[#result + 1] = child
            end
        end
        return result
    end

    function Runtime.scalarText(node, allowEmpty)
        if not node or #(node.children or {}) ~= 0 then return nil, "XML scalar contains child elements" end
        local value = Runtime.trim(table.concat(node.textParts or {}))
        if not allowEmpty and value == "" then return nil, "XML scalar is empty" end
        return value
    end

    function Runtime.singleDirectText(node, localName, namespace, allowEmpty)
        local matches = Runtime.directChildren(node, localName, namespace)
        if #matches ~= 1 then return nil, "expected exactly one " .. localName .. " element" end
        return Runtime.scalarText(matches[1], allowEmpty)
    end
end

return Component
