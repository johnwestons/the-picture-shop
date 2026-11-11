-- Sprite-backed notification paper. Gameplay text and hit targets remain live.
local Text=require('src.screens.typography')
local Clipboard={}
local root='assets/generated/notification-clipboard-v1/'
local fontPath='assets/fonts/PatrickHand-Regular.ttf'
local fonts,images={},{}
local turnFadeShader
local INK={.15,.22,.25,1}
local MUTED={.31,.38,.39,1}
local ACCENT={.53,.25,.22,1}

local function font(size)
    size=math.floor(size)
    if not fonts[size] then
        fonts[size]=love.graphics.newFont(fontPath,size)
        fonts[size]:setLineHeight(1.12)
    end
    return fonts[size]
end

local function image(name)
    if not images[name] then
        images[name]=love.graphics.newImage(root..name..'.png')
        images[name]:setFilter('linear','linear')
    end
    return images[name]
end

local function write(value,x,y,width,size,color,align)
    local g=love.graphics
    g.setFont(font(size));g.setColor(color or INK)
    g.printf(tostring(value or ''),x,y,width,align or 'left')
end

function Clipboard.layout(R)
    local bounds={left=0,top=0,right=960,bottom=678,width=960,height=678}
    if R and R.Viewport and R.Viewport.gameBounds then
        local safe=R.App and R.App.officeUsesSafeArea and R.App.officeUsesSafeArea()
        bounds=R.Viewport.gameBounds(960,678,safe)
    end
    local wide=bounds.width>1100
    local board=wide and {x=bounds.left+8,y=6,width=bounds.width-16,height=633}
        or {x=0,y=39,width=960,height=600}
    local paper={x=board.x+board.width*.03,y=board.y+board.height*.13,
        width=board.width*.94,height=board.height*.82}
    local left=paper.x+(wide and 44 or 38)
    local right=paper.x+paper.width-(wide and 44 or 38)
    local list={x=left,y=251,width=wide and 450 or 270,height=278}
    local detailX=list.x+list.width+(wide and 54 or 38)
    local detail={x=detailX,y=215,width=right-detailX,height=315}
    local prevWidth=wide and 120 or 90
    local nextWidth=prevWidth
    local rects={
        close={x=right-(wide and 146 or 112),y=141,width=wide and 146 or 112,height=34},
        all={x=list.x,y=206,width=wide and 125 or 92,height=35},
        tutorial={x=list.x+(wide and 145 or 106),y=206,width=wide and 148 or 115,height=35},
        previous={x=list.x,y=538,width=prevWidth,height=35},
        next={x=list.x+list.width-nextWidth,y=538,width=nextWidth,height=35},
        up={x=right-(wide and 188 or 150),y=538,width=wide and 84 or 68,height=35},
        down={x=right-(wide and 94 or 76),y=538,width=wide and 84 or 68,height=35},
        toggle={x=list.x,y=576,width=wide and 228 or 176,height=33},
        readAll={x=list.x+(wide and 246 or 186),y=576,width=wide and 197 or 157,height=33},
    }
    return {bounds=bounds,wide=wide,board=board,paper=paper,list=list,detail=detail,
        body={x=detail.x,y=306,width=detail.width,height=221},right=right,rects=rects}
end

function Clipboard.detailHit(R,x,y)
    local d=Clipboard.layout(R).detail
    return x>=d.x and x<=d.x+d.width and y>=d.y and y<=d.y+d.height
end

local function action(rect,label,wide,active)
    local g=love.graphics
    local size=wide and 25 or 20
    g.setColor(active and ACCENT or INK)
    g.setLineWidth(active and 2.3 or 1.4)
    g.line(rect.x+4,rect.y+rect.height-4,rect.x+rect.width-4,rect.y+rect.height-4)
    write(label,rect.x+3,rect.y+1,rect.width-6,size,active and ACCENT or INK,'center')
end

local function listRows(R,layout,items,page)
    local g=love.graphics
    local r=layout.list
    for row=1,6 do
        local n=items[(page-1)*6+row]
        if n then
            local y=r.y+(row-1)*46
            if n.id==R.state.notificationSelection then
                g.setColor(.84,.73,.36,.20)
                g.rectangle('fill',r.x-4,y+4,r.width+8,37,3,3)
            end
            if n.unread then
                g.setColor(ACCENT);g.circle('fill',r.x+4,y+14,3)
            end
            local titleFont=font(layout.wide and 27 or 21)
            g.setFont(titleFont);g.setColor(INK)
            g.print(Text.ellipsize(n.title,r.width-22,titleFont),r.x+12,y)
            write(n.kind:lower()..' · day '..(n.day+1)..(n.unread and ' · new' or ''),
                r.x+13,y+25,r.width-17,layout.wide and 20 or 16,MUTED)
        end
    end
    if #items==0 then
        write('No notes yet.\nNew messages and tutorial lessons will be filed here.',
            r.x+10,r.y+32,r.width-15,layout.wide and 28 or 23)
    end
end

local function pageTurn(layout,turn)
    if not turn then return end
    local elapsed=love.timer.getTime()-turn.start
    if elapsed>=.4 then return false end
    local g=love.graphics
    local sprite=image('page-turn')
    local frame=math.min(3,math.floor(elapsed/.1))
    local cellW=sprite:getWidth()/4
    local quad=g.newQuad(frame*cellW,0,cellW,sprite:getHeight(),sprite:getDimensions())
    -- Anchor the animated sheet's visible lower-right edge where the paper
    -- meets the clipboard backing, including the strip's transparent margins.
    local w=layout.wide and 350 or 270
    local h=350
    local x=layout.paper.x+layout.paper.width-503*w/cellW+9
    local y=layout.paper.y+layout.paper.height-600*h/sprite:getHeight()+12
    if not turnFadeShader then
        turnFadeShader=g.newShader([[
            extern number frameIndex;
            vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screenCoords) {
                vec4 pixel=Texel(texture,uv)*color;
                number localX=uv.x*4.0-frameIndex;
                number leftFade=smoothstep(0.09,0.23,localX);
                number topFade=smoothstep(0.20,0.33,uv.y);
                pixel.a*=min(leftFade,topFade);
                return pixel;
            }
        ]])
    end
    g.setColor(1,1,1,1)
    turnFadeShader:send('frameIndex',frame)
    g.setShader(turnFadeShader)
    g.draw(sprite,quad,x,y,0,w/cellW,h/sprite:getHeight())
    g.setShader()
    return true
end

function Clipboard.draw(R,items,turn)
    local g=love.graphics;g.push('all');g.setShader()
    local layout=Clipboard.layout(R)
    local board=layout.board
    local sprite=image(layout.wide and 'clipboard-wide' or 'clipboard')
    g.setColor(.055,.065,.068,1)
    g.rectangle('fill',layout.bounds.left,layout.bounds.top,layout.bounds.width,layout.bounds.height)
    g.setColor(1,1,1,1)
    g.draw(sprite,board.x,board.y,0,board.width/sprite:getWidth(),board.height/sprite:getHeight())
    local list,detail,rects=layout.list,layout.detail,layout.rects
    write('Shop notices',list.x,142,list.width+90,layout.wide and 40 or 32)
    local t=R.state.tutorial or require('src.tutorial').new(false)
    local status=t.finished and 'Tutorial complete'
        or t.enabled and ('Tutorial: lesson '..t.step..' of '..#require('src.tutorial').steps) or 'Tutorial off'
    write(require('src.notifications').unread(R.state)..' unread  /  '..status,
        list.x,178,layout.wide and 590 or 390,layout.wide and 24 or 19,MUTED)
    action(rects.close,'Close ×',layout.wide)
    action(rects.all,'All notes',layout.wide,R.state.notificationFilter~='tutorial')
    action(rects.tutorial,'Tutorial',layout.wide,R.state.notificationFilter=='tutorial')
    local currentPage=R.state.notificationPage or 1
    listRows(R,layout,items,currentPage)
    action(rects.previous,'‹ Previous',layout.wide)
    action(rects.next,'Next ›',layout.wide)
    write(('Page %d / %d'):format(currentPage,math.max(1,math.ceil(#items/6))),
        rects.previous.x+rects.previous.width+4,543,
        rects.next.x-rects.previous.x-rects.previous.width-8,
        layout.wide and 21 or 17,MUTED,'center')
    local n=require('src.notifications').find(R.state,R.state.notificationSelection)
    if n then
        local heading=font(layout.wide and 35 or 27)
        g.setFont(heading);g.setColor(INK)
        g.print(Text.ellipsize(n.title,detail.width,heading),detail.x,detail.y)
        write(n.detail,detail.x,detail.y+43,detail.width,
            layout.wide and 25 or 19,MUTED)
        local body=layout.body
        local bodyFont=font(layout.wide and 28 or 23)
        local _,lines=bodyFont:getWrap(tostring(n.body or ''),body.width)
        local height=#lines*bodyFont:getHeight()*bodyFont:getLineHeight()
        R.state.notificationMaxScroll=math.max(0,height-body.height)
        R.state.notificationScroll=math.max(0,math.min(R.state.notificationMaxScroll,
            R.state.notificationScroll or 0))
        local sx,sy=g.transformPoint(body.x,body.y)
        local ex,ey=g.transformPoint(body.x+body.width,body.y+body.height)
        g.setScissor(sx,sy,ex-sx,ey-sy)
        g.setFont(bodyFont);g.setColor(INK)
        g.printf(n.body,body.x,body.y-R.state.notificationScroll,body.width,'left')
        g.setScissor()
        write(height>body.height and 'Scroll for the rest.' or 'Filed for you to revisit.',
            detail.x,543,detail.width-170,layout.wide and 21 or 16,MUTED)
    else
        R.state.notificationMaxScroll=0
        write('Select a note to read it.',detail.x,detail.y+34,
            detail.width,layout.wide and 30 or 24)
    end
    local turning=pageTurn(layout,turn)
    action(rects.up,'Up',layout.wide)
    action(rects.down,'Down',layout.wide)
    action(rects.toggle,t.finished and 'Tutorial complete'
        or t.enabled and 'Pause tutorial' or 'Enable tutorial',layout.wide)
    action(rects.readAll,'Mark all read',layout.wide)
    write('Close to return to your game.',detail.x,579,detail.width,
        layout.wide and 22 or 17,MUTED,'right')
    g.pop()
    return turning
end

return Clipboard
