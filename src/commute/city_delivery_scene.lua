-- Brief travel montage while the shop truck completes its city stops.
local Scene={}
local titleFont,bodyFont
function Scene.draw(w,h,run)
    local g=love.graphics
    titleFont=titleFont or g.newFont(22);bodyFont=bodyFont or g.newFont(16)
    local phase=love.timer.getTime()
    local left=math.max(0,(run.cutsceneEndsAtEpoch or os.time())-os.time())
    local stop=run.stops[run.stopIndex]
    g.push('all');g.setColor(.012,.022,.03,1);g.rectangle('fill',0,0,w,h)
    g.setColor(.14,.19,.20,1);g.rectangle('fill',0,h*.62,w,h*.38)
    g.setColor(.19,.29,.31,1);g.rectangle('fill',0,h*.50,w,h*.12)
    for i=0,10 do
        local x=i*130-(phase*85)%130
        local height=65+(i%4)*23
        g.setColor(.08+(i%3)*.025,.12,.15,1);g.rectangle('fill',x,h*.50-height,105,height)
        g.setColor(.69,.60,.32,.6)
        for row=1,3 do for col=1,4 do
            g.rectangle('fill',x+col*19-8,h*.50-height+row*18,7,9)
        end end
    end
    for i=0,9 do
        local x=i*170-(phase*260)%170
        g.setColor(.88,.75,.45,.82);g.rectangle('fill',x,h*.78,78,5)
    end
    g.setColor(.06,.085,.09,1);g.rectangle('fill',w*.22,h*.43,w*.43,h*.19,7)
    g.setColor(.78,.72,.58,1);g.rectangle('fill',w*.57,h*.48,w*.19,h*.14,7)
    g.setColor(.08,.11,.12,1);g.rectangle('fill',w*.61,h*.50,w*.08,h*.075,4)
    for _,x in ipairs({w*.31,w*.52,w*.66,w*.72}) do
        g.setColor(.025,.03,.03,1);g.circle('fill',x,h*.63,h*.035)
        g.setColor(.62,.59,.50,1);g.circle('fill',x,h*.63,h*.017)
    end
    g.setFont(titleFont);g.setColor(.95,.91,.77,1)
    g.printf('DELIVERING IN '..string.upper(stop and stop.city or 'Millhaven'),0,h*.20,w,'center')
    local caption=left>3 and 'Crossing the bridge into Millhaven'
        or left>1 and 'Dropping off your loaded pallets' or 'Heading back across the bridge'
    g.setFont(bodyFont);g.setColor(.72,.80,.76,1);g.printf(caption,0,h*.27,w,'center')
    g.setColor(.95,.81,.47,1)
    g.printf(left>0 and ('RETURNING IN %d'):format(math.ceil(left)) or 'WAITING FOR A CLEAR RETURN LANE',
        0,h*.86,w,'center')
    g.pop()
end
return Scene
