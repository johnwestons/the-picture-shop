-- Device-owned identity; the private resident credential remains separate.
local Profile={DEFAULT_NAME='Printmaker',MAX_NAME_BYTES=24}
local hasUtf8,utf8=pcall(require,'utf8')
function Profile.backspace(value)
    return value:match('^(.*)[%z\1-\127\194-\244][\128-\191]*$') or ''
end
function Profile.input(value)
    if type(value)~='string' then return '' end
    value=value:gsub('[%z\1-\31\127]','')
    if hasUtf8 then
        local okay,length=pcall(utf8.len,value)
        if not okay or not length then return '' end
    end
    while #value>Profile.MAX_NAME_BYTES do value=Profile.backspace(value) end
    return value
end
function Profile.cleanName(value)
    return (Profile.input(value):gsub('%s+',' '):match('^%s*(.-)%s*$') or '')
end
function Profile.validName(value)
    return type(value)=='string' and value~='' and Profile.cleanName(value)==value
end
function Profile.name(settings)
    local name=Profile.cleanName(settings and settings.playerName)
    return name~='' and name or Profile.DEFAULT_NAME
end
function Profile.isHost(player) return player and tonumber(player.id or player.playerId)==1 end
function Profile.drawStar(x,y,radius)
    local points={}
    for i=0,9 do
        local angle=-math.pi*.5+i*math.pi/5
        local r=i%2==0 and radius or radius*.43
        points[#points+1]=x+math.cos(angle)*r;points[#points+1]=y+math.sin(angle)*r
    end
    love.graphics.polygon('fill',points)
end
function Profile.drawNameplate(player,x,y)
    local g=love.graphics
    local name=Profile.name({playerName=player.name})
    local star=Profile.isHost(player) and 16 or 0
    local width=math.max(54,g.getFont():getWidth(name)+12+star)
    local height=g.getFont():getHeight()+6
    local left=x-width*.5
    g.setColor(.025,.035,.04,.88);g.rectangle('fill',left,y,width,height,3,3)
    g.setColor(.95,.82,.26,1)
    if star>0 then Profile.drawStar(left+10,y+height*.5,6) end
    g.printf(name,left+6+star,y+3,width-12-star,'center')
end
return Profile
