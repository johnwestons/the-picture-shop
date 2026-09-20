local Codec = require("src.net.codec")
local Games = require("src.press_setup_games")
local View = {}
local fields = {
    chase={"offset","angle","locks"}, packing={"layers","wrinkles","clamped"},
    rollers={"leftStripe","rightStripe"}, ink={"key1","key2","key3","ductor"},
    feeder={"prepared","suction","air","cleanFeeds"}, register={"xOffset","yOffset","tests"},
}
local flags = {clamped=true,ductor=true,prepared=true}
function View.encode(game)
    local result={}
    for index,field in ipairs(fields[game.task] or {}) do
        local key=tonumber(field:match("^key(%d)$"))
        local value=key and game.keys[key] or game[field]
        result[index]=flags[field] and (value and 1 or 0) or value
    end
    return Codec.array(result)
end
function View.normalize(task,value)
    local names=fields[task]
    if not names or type(value)~="table" then return nil,"Invalid press setup display." end
    local count=0
    for key in pairs(value) do
        if type(key)~="number" or key%1~=0 or key<1 or key>#names then return nil,"Invalid setup display field." end
        count=count+1
    end
    if count~=#names then return nil,"Incomplete setup display." end
    local result={}
    for index,field in ipairs(names) do
        local n=value[index]
        if type(n)~="number" or n%1~=0 or n< -4 or n>20
            or (flags[field] and n~=0 and n~=1) then return nil,"Invalid setup display value." end
        result[index]=n
    end
    return Codec.array(result)
end
function View.project(task,values,job,summary)
    local valid=View.normalize(task,values)
    if not valid then return nil end
    local game=Games.new(task,job)
    for index,field in ipairs(fields[task]) do
        local key=tonumber(field:match("^key(%d)$"))
        if key then game.keys[key]=valid[index]
        elseif flags[field] then game[field]=valid[index]==1
        else game[field]=valid[index] end
    end
    if task=="feeder" and summary then
        game.feederFeedback=summary:match("^.-  •  (.*)$") or summary
        -- The first separator belongs to the status; retain only the instruction.
        local prefix=Games.feederStatus(game).."  •  "
        if summary:sub(1,#prefix)==prefix then game.feederFeedback=summary:sub(#prefix+1) end
    end
    return game
end
return View
