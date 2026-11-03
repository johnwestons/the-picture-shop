-- Household images use the same one-image decode / bounded GPU upload queue as
-- screen assets. The art modules retain ownership of completed images.
local Loader=require("src.image_loader")
local Images={}
local families,errors,active={}, {}, {}
function Images.beginFrame() active={} end
function Images.protect(family) active[family]=true end
local function cancel(path,owner)
    -- Mug/bundle files are also used by held props. An idle family must not
    -- cancel another resident's pending request for the same source image.
    for family,row in pairs(families) do
        if family~=owner and active[family] and row.paths[path] then return end
    end
    Loader.cancel(path)
end
function Images.load(family,path)
    local row=families[family] or {paths={},images={}}
    families[family]=row;row.paths[path]=true
    local image,reason=Loader.load(path)
    if image then
        row.images[path]=image
    elseif reason and reason~="pending" then
        errors[path]=path..": "..tostring(reason)
    end
    return image
end
function Images.release(family)
    local row=families[family]
    if row then for path in pairs(row.paths) do cancel(path,family);errors[path]=nil end end
    families[family]=nil
end
function Images.cancelPending(family)
    local row=families[family]
    if row then for path in pairs(row.paths) do cancel(path,family) end end
end
function Images.bytes(family)
    local bytes=0
    local function count(row)
        for _,image in pairs(row.images) do
            -- A direction cache may retire one image before its whole family.
            local okay,w,h=pcall(image.getDimensions,image)
            if okay then bytes=bytes+w*h*4 end
        end
    end
    if family then if families[family] then count(families[family]) end
    else for _,row in pairs(families) do count(row) end end
    return bytes
end
function Images.failure() for _,reason in pairs(errors) do return reason end end
return Images
