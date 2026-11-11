return function(check)
    local L=require('src.commute.local_lights')
    local H=require('src.commute.headlight')
    local V=require('src.video_settings')
    local previous={lights=L.lights,blockers=L.blockers,night=L.night,video=V.current,world=L.world,fixtures=L.fixtures,slots=L.slots,lastTime=L.lastTime}
    local shader=love.graphics.newShader(love.filesystem.read('src/commute/perspective.glsl')..[[
    vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel) {
        vec2 p=(uv-.5)*8.0;
        return vec4(riderLight(localLighting(vec3(0.0),p,0.0),p,0.0),1.0);
    }]])
    local canvas=love.graphics.newCanvas(64,64)
    local camera={centerX=0,centerZ=0}
    local white=love.graphics.newImage(love.image.newImageData(1,1))
    L.lights={{0,3,0,8,0,0}};L.night=1;L.blockers={}
    local function sample()
        H.send(shader,camera,{})
        love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
        love.graphics.setShader(shader);love.graphics.setColor(1,1,1)
        love.graphics.draw(white,0,0,0,64,64)
        love.graphics.pop()
        local pixels=canvas:newImageData();local r=pixels:getPixel(48,32);pixels:release();return r
    end
    local lit=sample();check('night lamp illuminates surface',lit>.1)
    L.blockers={{1.5,0,0,.32,.32,1.65,0}}
    local blocked=sample();check('actor blocks local light',blocked<lit*.3)
    V.apply({dynamicShadows=false})
    check('shadow option preserves light',sample()>lit*.9)
    L.night=0;check('daytime switches stationary lamps off',sample()==0)
    local bike={x=0,z=0,h=0,heading=0}
    local bx=H.position(bike);check('motorcycle lamp at nose',math.abs(bx-.72)<.001)
    L.trucks[bike]=true;bike.model='box'
    local tx=H.position(bike);check('truck lamps moved to front fascia',math.abs(tx-3.29)<.001)
    local range=H.parameters(bike);check('headlight range preserved',range==11)
    local sent={};H.send({hasUniform=function()return false end,send=function(_,k,v)sent[k]=v end},camera,bike)
    check('truck paired lamps',sent.rideLightSeparation>.8)
    L.trucks[bike]=nil;H.send({hasUniform=function()return false end,send=function(_,k,v)sent[k]=v end},camera,bike)
    check('motorcycle single lamp',sent.rideLightSeparation==0)
    local world={supportHeight=function()return 0 end}
    L.world=world;L.fixtures={};L.slots={};L.lastTime=nil;local actors={}
    for i=6,1,-1 do
        L.fixtures[#L.fixtures+1]={i,3,0,8,0,0}
        actors[#actors+1]={actor={x=i,z=0,h=0}}
    end
    L.prepare({world=world,clock=0},camera,actors,0)
    check('new lamps begin dark',L.lights[1][7]==0)
    L.prepare({world=world,clock=.1},camera,actors,0)
    check('lamps fade in gradually',L.lights[1][7]>0 and L.lights[1][7]<.3)
    check('local lighting work capped',#L.lights==4 and #L.blockers==4)
    check('nearest casters win',L.blockers[1][1]==1 and L.blockers[4][1]==4)
    camera.yaw=180;camera.firstPerson=true
    L.prepare({world=world,clock=.1},camera,actors,0)
    check('camera angle preserves selected lamps',L.lights[1][1]==1 and L.lights[4][1]==4)
    local before=L.lights[1][7]
    camera.centerX=100
    L.prepare({world=world,clock=.15},camera,actors,0)
    check('departing lamps fade out before replacement',#L.lights==4 and L.lights[1][7]>0 and L.lights[1][7]<before)
    L.release(world);check('local lights release world reference',L.world==nil)
    local silhouette=love.graphics.newShader(love.filesystem.read('src/commute/perspective.glsl')..[[
    vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel) {
        float h=(1.0-uv.y)*2.0,z=(uv.x-.5)*1.3;
        float light=localVisibility(vec3(-4,h,z),vec3(4,h,z));return vec4(light,light,light,1);
    }]])
    silhouette:send('localBlockerCount',1)
    silhouette:send('localBlockerBase',{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0})
    silhouette:send('localBlockerSize',{.9,.48,1.85,1},{0,0,0,0},{0,0,0,0},{0,0,0,0})
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.setShader(silhouette)
    love.graphics.setColor(1,1,1);love.graphics.draw(white,0,0,0,64,64);love.graphics.pop()
    local pixels=canvas:newImageData()
    check('character shadow has gap between legs',pixels:getPixel(32,55)>.9 and pixels:getPixel(39,55)<.2)
    check('character shadow has head rather than square shoulders',pixels:getPixel(32,19)<.2 and pixels:getPixel(51,19)>.9)
    check('character shadow includes ears',pixels:getPixel(40,9)<.2)
    pixels:release();silhouette:release()
    L.world,L.fixtures=previous.world,previous.fixtures
    L.slots,L.lastTime=previous.slots,previous.lastTime
    L.lights,L.blockers,L.night=previous.lights,previous.blockers,previous.night;V.apply(previous.video)
    shader:release();canvas:release();white:release()
end
