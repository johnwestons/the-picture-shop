-- Pin writes to the captured profile even if the main thread changes identity.
return function(directory)
    local function path(relative)
        assert(relative:match("^saves/[%w%.%-]+$"),"Unexpected save path")
        return directory.."/"..relative
    end
    return {
        getSaveDirectory=function() return directory end,
        createDirectory=function(name) return name=="saves" end,
        getInfo=function(relative)
            local file=io.open(path(relative),"rb")
            if not file then return nil end
            local size=file:seek("end");file:close()
            return {type="file",size=size}
        end,
        read=function(relative)
            local file,reason=io.open(path(relative),"rb")
            if not file then return nil,reason end
            local source=file:read("*a");file:close();return source
        end,
        write=function(relative,source)
            local file,reason=io.open(path(relative),"wb")
            if not file then return false,reason end
            local wrote,writeReason=file:write(source)
            local closed,closeReason=file:close()
            return wrote~=nil and closed~=nil,writeReason or closeReason
        end,
        remove=function(relative) return os.remove(path(relative)) end,
    }
end
