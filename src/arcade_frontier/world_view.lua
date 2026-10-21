-- Only scene artwork enters this transform. HUD and pointer coordinates stay
-- in logical screen space; world interactions explicitly use toWorld.
local function new(initial)
local WorldView={}
local callbacks=initial or {}
local depth=0

function WorldView.configure(value)
    callbacks=value or {}
    depth=0
end

function WorldView.begin(options)
    if depth==0 and callbacks.apply then
        love.graphics.push("all")
        if options and options.clip then
            local r=options.clip
            local x,y=love.graphics.transformPoint(r[1],r[2])
            local right,bottom=love.graphics.transformPoint(r[1]+r[3],r[2]+r[4])
            local sx,sy,sw,sh=love.graphics.getScissor()
            if sx then
                x,y,right,bottom=math.max(x,sx),math.max(y,sy),math.min(right,sx+sw),math.min(bottom,sy+sh)
            end
            love.graphics.setScissor(x,y,math.max(0,right-x),math.max(0,bottom-y))
        end
        callbacks.apply(options)
    end
    depth=depth+1
end

function WorldView.finish()
    assert(depth>0,"unbalanced world drawing")
    depth=depth-1
    if depth==0 and callbacks.apply then love.graphics.pop() end
end

function WorldView.toWorld(x,y)
    if callbacks.toWorld then return callbacks.toWorld(x,y) end
    return x,y
end

function WorldView.toScreen(x,y)
    if callbacks.toScreen then return callbacks.toScreen(x,y) end
    return x,y
end

return WorldView
end
local WorldView=new()
WorldView.new=new
return WorldView
