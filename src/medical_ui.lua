local Medical=require('src.player_medical')
local UI={}
local font,title
function UI.openClinic(R)
    local C=require('src.commute.runtime');local part=C.localPart(R)
    local site=C.world(R).sites.byId.clinic
    local r=part and part.rider
    if not r or part.interior or not site or r.gear.mounted or r.vehicle or r.ped.crash
        or (r.ped.x-site.door.x)^2+(r.ped.z-site.door.z)^2>3.6^2 then return false end
    local m,resident=Medical.get(R.state,R.World.player)
    R._medicalClinic={revision=m.revision,price=Medical.quote(resident)}
    return true
end
local function medical(R)
    if not R.state or not R.state.home or not R.World or not R.World.player
        or R.state.screen=='title' or R.state.screen=='lan' or R.state.screen=='direct' then return nil end
    return Medical.get(R.state,R.World.player)
end
function UI.modal(R)
    local m=medical(R);return m and (m.phase or m.notice) or R._medicalClinic
end
function UI.key(R,key)
    local m=medical(R)
    if not m then R._medicalClinic=nil;return false end
    if m and m.phase then return true end
    if m and m.notice then
        if key=='return' or key=='escape' or key=='e' or key=='space' then
            if R.multiplayer:isClient() then R.multiplayer:requestInteraction('homeActivity','medical:ack')
            else require('src.home_activity_controls').command(R,R.World.player,'medical:ack') end
        end
        return true
    end
    local view=R._medicalClinic
    if not view then return false end
    if key=='escape' or key=='back' then R._medicalClinic=nil
    elseif key=='return' then
        local t=R.state.home.commute
        if t then require('src.commute.runtime').request(R,('clinic:%d:%d:%d'):format(t.token,view.revision,view.price)) end
        R._medicalClinic=nil
    end
    return true
end
function UI.pointer(R,x,y,button)
    if not UI.modal(R) then return false end
    if button and button~=1 then return true end
    local m=medical(R)
    local top=m and m.notice=='grandpa' and 600 or 475
    if x>=260 and x<=700 and y>=top and y<=top+60 then return UI.key(R,'return') end
    if R._medicalClinic and x>=710 and y>=170 and y<=235 then return UI.key(R,'escape') end
    return true
end
function UI.fallen(assets,player,state,x,y,scale)
    if not assets or not Medical.blocked(state,player) then return false end
    local character=player.character or require('src.config').player.character
    local action='idle';local image,quad=assets.get(character,action,1)
    if not image then return false end
    local ax,ay=assets.getAnchor(character,action,1)
    scale=scale or require('src.config').player.drawScale*assets.getNormalization(character,action)
    love.graphics.push('all');love.graphics.setColor(1,1,1)
    if character=='rabbit-worker' then
        require('src.rabbit_colorways').draw(image,quad,x or player.x,y or player.y,math.pi*.48,
            scale,scale,ax,ay,0,0,player.furColorway,player.overallsColorway)
    else love.graphics.draw(image,quad,x or player.x,y or player.y,math.pi*.48,scale,scale,ax,ay) end
    love.graphics.pop();return true
end
function UI.draw(R)
    local m,r=medical(R);if not m then return end
    local g=love.graphics;font=font or g.newFont(17);title=title or g.newFont(27)
    g.push('all');g.origin();g.setShader();g.setScissor();g.setStencilTest();g.setFont(font)
    local ox,oy,zoom=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeUsesSafeArea())
    g.translate(ox,oy);g.scale(zoom*R.Config.baseWidth/960,zoom*R.Config.baseHeight/678)
    if m.phase=='hospital' then require('src.medical_cinematic').draw(m);g.pop();return end
    if m.phase then
        g.setColor(.02,.03,.05,.35);g.rectangle('fill',0,0,960,678)
        g.setColor(1,.84,.56);g.printf(m.phase=='rescue' and 'You collapsed. Grandpa is coming to help.'
            or ('You fainted. Recovering in %d seconds...'):format(math.ceil(m.remaining)),140,560,680,'center')
    elseif m.notice=='grandpa' then
        g.setColor(.04,.11,.12,.96);g.rectangle('fill',180,435,600,230,12)
        g.setFont(title);g.setColor(.76,.93,.80);g.print('GRANDPA',220,447)
        g.setFont(font);g.setColor(.95,.95,.89)
        local place=R.World.player.sceneId=='barn' and 'here to the barn' or 'home to recover'
        g.printf('Hey, you worked too hard and passed out. Someone called me, and I brought you '..place..'.\n\nTake care of yourself. Make sure you eat, drink, and rest.',220,487,520,'left')
        g.setColor(.16,.43,.32);g.rectangle('fill',260,600,440,48,8)
        g.setColor(1,1,1);g.printf('CONTINUE  [Enter]',270,615,420,'center')
    elseif m.notice or R._medicalClinic then
        local view=R._medicalClinic
        if view then view.price=Medical.quote(r);view.revision=m.revision end
        local heading=m.notice=='grandpa' and 'GRANDPA' or m.notice=='hospital' and 'HOSPITAL DISCHARGE'
            or m.notice=='faint' and 'TAKE A BREATHER' or 'CRITTER CLINIC'
        local body=m.notice=='grandpa' and 'Hey, you worked a little too hard out there and passed out. Someone called me, and I brought you here to the barn.\n\nTake better care of yourself. Make sure you eat, drink, and rest.'
            or m.notice=='hospital' and ('You have been treated and brought home. Eat regularly, drink water, rest, and keep clean.\n\nHospital bill: $%.2f. Outstanding medical debt: $%.2f.'):format(m.lastBillCents/100,m.debtCents/100)
            or m.notice=='faint' and 'You pushed yourself too far. Eat, drink, and rest before this gets worse. More fainting can lead to a rescue or a hospital visit.'
            or ('Urgent care and outpatient treatment\n\nInjury: %d%%   ·   Outstanding bills: $%.2f\nTreatment restores your needs and walking speed.\n\nTotal visit price: $%.2f   ·   Household funds: $%.2f'):format(m.injury,m.debtCents/100,view.price/100,R.state.home.balanceCents/100)
        g.setColor(.01,.02,.03,.72);g.rectangle('fill',0,0,960,678)
        g.setColor(.08,.16,.18);g.rectangle('fill',180,170,600,390,12)
        g.setColor(.7,.95,.82);g.setFont(title);g.printf(heading,210,195,540,'center')
        g.setColor(.95,.95,.89);g.setFont(font);g.printf(body,220,255,520,'left')
        g.setColor(.16,.43,.32);g.rectangle('fill',260,475,440,60,8)
        g.setColor(1,1,1);g.printf(view and not m.notice and 'PAY & RECEIVE CARE  [Enter]' or 'CONTINUE  [Enter]',270,495,420,'center')
        if view and not m.notice then g.print('X',740,190) end
    elseif m.injury>=30 or math.min(r.hunger,r.thirst,r.energy)<25 then
        g.setColor(.05,.06,.07,.88);g.rectangle('fill',260,565,440,32,5)
        g.setColor(1,.76,.36);g.printf(m.injury>=30 and 'INJURED · Walking 50% · Visit Critter Clinic'
            or 'LOW NEEDS · Eat, drink, and rest soon',268,572,425,'left')
    end
    g.pop()
end
return UI
