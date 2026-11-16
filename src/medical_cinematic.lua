-- Shares the delivery journey's bridge, city, camera cuts, and return shot.
local Scene=require('src.commute.city_delivery_scene')
local Text=require('src.screens.typography')
local Medical=require('src.player_medical')
local Cinematic={}
local art={}
function art:drawSprite(_,_,angle,x,y,zoom)
    local g=love.graphics
    g.push('all');g.translate(x,y);g.scale(zoom*.78*(angle>math.pi and -1 or 1),zoom*.78)
    g.setColor(.87,.91,.88);g.rectangle('fill',-130,-122,180,100,8)
    g.polygon('fill',50,-102,100,-102,130,-62,130,-22,50,-22)
    g.setColor(.24,.43,.48);g.polygon('fill',60,-94,93,-94,116,-62,60,-62)
    g.setColor(.65,.78,.76);g.polygon('fill',63,-91,90,-91,76,-65,63,-65)
    g.setColor(.10,.48,.32);g.rectangle('fill',-70,-102,18,55);g.rectangle('fill',-88,-84,55,18)
    g.rectangle('fill',-130,-38,260,9)
    g.setColor(.35,.43,.44);g.rectangle('line',54,-58,70,29,2);g.rectangle('fill',64,-54,13,3)
    g.setColor(.95,.83,.51);g.rectangle('fill',122,-48,8,12)
    g.setColor(.43,.13,.10);g.rectangle('fill',-130,-46,5,10)
    g.setColor(.27,.32,.33);g.rectangle('fill',-133,-26,266,7,2)
    for _,wheel in ipairs({-95,87}) do
        g.setColor(.04,.05,.06);g.circle('fill',wheel,-20,24)
        g.setColor(.55,.62,.62);g.circle('fill',wheel,-20,11)
        g.setColor(.20,.25,.26);g.circle('fill',wheel,-20,4)
    end
    local flash=math.floor(love.timer.getTime()*8)%2==0
    g.setColor(.23,.29,.30);g.rectangle('fill',36,-118,39,5)
    g.setColor(flash and .16 or .85,.26,flash and .95 or .18);g.rectangle('fill',40,-116,31,8,2)
    g.pop()
end
local function hospital(g,w)
    g.setColor(.42,.47,.45);g.rectangle('fill',0,377,w,86)
    g.setColor(.66,.72,.66);g.rectangle('fill',w*.5-300,225,600,230)
    g.setColor(.33,.46,.45);g.rectangle('fill',w*.5-305,218,610,12)
    for i=-2,2 do
        g.setColor(.26,.41,.43);g.rectangle('fill',w*.5+i*105-35,252,70,55)
        g.setColor(.71,.79,.70);g.rectangle('fill',w*.5+i*105-2,252,4,55)
    end
    g.setColor(.12,.29,.29);g.rectangle('fill',w*.5-65,345,130,110)
    g.setColor(.32,.52,.53);g.rectangle('fill',w*.5-58,350,54,98);g.rectangle('fill',w*.5+4,350,54,98)
    g.setColor(.08,.38,.28);g.rectangle('fill',w*.5-235,316,470,30)
    g.setFont(Text.get(18,'bold'));g.setColor(.94,.94,.81);g.printf('MILLHAVEN CITY HOSPITAL',w*.5-235,321,470,'center')
end
function Cinematic.draw(m)
    love.graphics.setColor(.035,.09,.11);love.graphics.rectangle('fill',0,0,960,678)
    local run={cutsceneStartedAtEpoch=0,cutsceneEndsAtEpoch=Medical.HOSPITAL_SECONDS}
    Scene.draw(960,678,run,{model='ambulance'},art,Medical.HOSPITAL_SECONDS-m.remaining,{
        destination=hospital,
        captions=function(g,w,_,shot)
            g.setColor(.035,.09,.11,.98);g.rectangle('fill',0,0,w,148);g.rectangle('fill',0,587,w,91)
            g.setFont(Text.get(14,'bold'));g.setColor(.68,.84,.75);g.print('EMERGENCY MEDICAL CARE',48,37)
            g.setFont(Text.get(32,'bold'));g.setColor(.95,.90,.77);g.print('MILLHAVEN CITY',48,67)
            g.setFont(Text.get(16));g.print(shot.id=='bridge' and 'Ambulance transport'
                or shot.id=='dock' and 'Hospital treatment and rehydration' or 'Returning to your apartment',48,115)
            g.setFont(Text.get(18));g.print(('Hospital visit %d  ·  Bill $%.2f'):format(m.hospitalVisits,m.lastBillCents/100),48,607)
            g.setFont(Text.get(13));g.setColor(.68,.80,.76);g.print('Take time to eat, drink, and rest after discharge.',48,639)
            g.setColor(.25,.34,.33);g.rectangle('fill',730,643,180,3)
            g.setColor(.68,.84,.75);g.rectangle('fill',730,643,180*shot.progress,3)
        end})
end
return Cinematic
