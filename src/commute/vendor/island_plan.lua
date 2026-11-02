-- Resident, deterministic terrain and habitat plan for streamed islands.
-- Heights, channels and vegetation zones depend only on the world seed and
-- absolute coordinates, so streaming order cannot change the island.
local M=require('src.commute.vendor.mathx')
local Config=require('src.commute.vendor.world_config')
local Plan={};Plan.__index=Plan

local function coastScale(self,angle)
    if self.coastSamples then
        local position=(angle/(math.pi*2)%1)*#self.coastSamples
        local index=math.floor(position)
        return M.lerp(self.coastSamples[index+1],self.coastSamples[(index+1)%#self.coastSamples+1],position-index)
    end
    local relative=angle-self.coastAxis
    local scale=1/math.sqrt((math.cos(relative)/self.coastStretch)^2+(math.sin(relative)*self.coastStretch)^2)
    for _,wave in ipairs(self.coast) do
        scale=scale+math.cos(angle*wave.frequency+wave.phase)*wave.amplitude
    end
    for _,cove in ipairs(self.coves) do
        local delta=math.abs((angle-cove.angle+math.pi)%(math.pi*2)-math.pi)
        scale=scale-cove.depth*M.smooth(1-delta/cove.width)
    end
    for _,headland in ipairs(self.headlands) do
        local delta=math.abs((angle-headland.angle+math.pi)%(math.pi*2)-math.pi)
        scale=scale+headland.height*M.smooth(1-delta/headland.width)
    end
    return math.max(.28,scale)*(self.coastFactor or 1)
end

local function segmentDistance2(segment,x,z)
    local u=segment.length2>0 and M.clamp(((x-segment.x)*segment.dx+(z-segment.z)*segment.dz)/segment.length2,0,1) or 0
    return (x-segment.x-segment.dx*u)^2+(z-segment.z-segment.dz*u)^2,u
end

local function buildShore(self)
    local samples,points={},{};local c,r=self.config.center,self.config.radius
    for i=0,1023 do
        local angle=i*math.pi*2/1024;local radius=coastScale(self,angle)
        local x,z=c+math.cos(angle)*r*radius,c+math.sin(angle)*r*radius
        -- Even the smallest supported island needs space for the family and
        -- an inland headwater; deep bays may not enter this 48 m core.
        radius=math.max(48/r,radius+(M.noise(self.seed+41,x*.009,z*.009)-.5)*.035)
        samples[i+1]=radius;points[i+1]={x=c+math.cos(angle)*r*radius,z=c+math.sin(angle)*r*radius}
    end
    self.coastSamples=samples;self.shoreBins={};self.shoreBinWidth=math.ceil(self.config.size/64)+2
    for i,a in ipairs(points) do
        local b=points[i%#points+1]
        local segment={x=a.x,z=a.z,dx=b.x-a.x,dz=b.z-a.z,length2=(b.x-a.x)^2+(b.z-a.z)^2}
        for x=math.floor((math.min(a.x,b.x)-48)/64),math.floor((math.max(a.x,b.x)+48)/64) do
            for z=math.floor((math.min(a.z,b.z)-48)/64),math.floor((math.max(a.z,b.z)+48)/64) do
                local key=z*self.shoreBinWidth+x+1
                self.shoreBins[key]=self.shoreBins[key] or {}
                self.shoreBins[key][#self.shoreBins[key]+1]=segment
            end
        end
    end
end

local function mainPoint(self,t)
    local envelope=math.sin(math.pi*t)*M.smooth((1-t)/.22)
    local angle=self.riverAngle+self.sourceBend*(1-M.smooth(t/.85))
        +self.meander*math.sin(t*math.pi*2*self.meanderFrequency+self.meanderPhase)*envelope
        +self.meander2*math.sin(t*math.pi*2*self.meanderFrequency2+self.meanderPhase2)*envelope
    local r=M.lerp(self.sourceRadius,self.outletRadius,t)
    return self.config.center+math.cos(angle)*r,self.config.center+math.sin(angle)*r
end

local function independentPoint(self,river,t)
    local envelope=math.sin(math.pi*t)
    local angle=M.lerp(river.sourceAngle,river.outletAngle,t)
        +river.bend*envelope
        +river.meander*math.sin(t*math.pi*2*river.frequency+river.phase)*envelope
    local radius=M.lerp(river.sourceRadius,river.outletRadius,t)
    return self.config.center+math.cos(angle)*radius,self.config.center+math.sin(angle)*radius
end

local function crossingPoint(self,t)
    local c,r=self.config.center,self.config.radius
    local a0,a1=self.crossingStart,self.crossingEnd
    local r0=r*coastScale(self,a0)-4;local r1=r*coastScale(self,a1)-4
    local x0,z0=c+math.cos(a0)*r0,c+math.sin(a0)*r0
    local x1,z1=c+math.cos(a1)*r1,c+math.sin(a1)*r1
    local dx,dz=x1-x0,z1-z0;local length=math.max(1,M.length(dx,dz))
    local nx,nz=-dz/length,dx/length
    local bend=self.crossingBend*math.sin(math.pi*t)
        +self.crossingSway*math.sin(math.pi*2*t)*math.sin(math.pi*t)
    return M.lerp(x0,x1,t)+nx*bend,M.lerp(z0,z1,t)+nz*bend
end
local function lakeDistance(self,lake,x,z)
    local dx,dz=x-lake.x,z-lake.z;local ca,sa=math.cos(lake.angle or 0),math.sin(lake.angle or 0)
    local d=M.length((dx*ca+dz*sa)/lake.rx,(-dx*sa+dz*ca)/lake.rz)
    local warp=(M.noise(self.seed+(lake.noiseSeed or 0),x*.045,z*.045)-.5)*.22
        +math.sin(math.atan2(dz,dx)*3+(lake.phase or 0))*.035
    return d+warp
end

local function marshDistance(self,marsh,x,z)
    local dx,dz=x-marsh.x,z-marsh.z;local ca,sa=math.cos(marsh.angle or 0),math.sin(marsh.angle or 0)
    return M.length((dx*ca+dz*sa)/marsh.rx,(-dx*sa+dz*ca)/marsh.rz)
end
local function riverPoint(river,t)
    local position=t*(#river.points-1)
    local index=math.min(math.floor(position)+1,#river.points-1)
    local a,b=river.points[index],river.points[index+1];local u=position-index+1
    return M.lerp(a.x,b.x,u),M.lerp(a.z,b.z,u),M.lerp(a.progress,b.progress,u)
end

local function segmentBins(self,points,id)
    local river=self.rivers[id]
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        local segment={x=a.x,z=a.z,dx=b.x-a.x,dz=b.z-a.z,id=river.id,
            length2=(b.x-a.x)^2+(b.z-a.z)^2,p=a.progress,pd=b.progress-a.progress,
            waterWidth=river.waterWidth or 14,valleyWidth=river.valleyWidth or 40,depth=river.depth or .9}
        river.segments[#river.segments+1]=segment
        local margin=segment.valleyWidth+8;local size=32
        local maxBin=math.floor(self.config.size/size)
        local x0,x1=math.max(0,math.floor((math.min(a.x,b.x)-margin)/size)),math.min(maxBin,math.floor((math.max(a.x,b.x)+margin)/size))
        local z0,z1=math.max(0,math.floor((math.min(a.z,b.z)-margin)/size)),math.min(maxBin,math.floor((math.max(a.z,b.z)+margin)/size))
        for bx=x0,x1 do for bz=z0,z1 do
            local key=bz*self.binWidth+bx+1
            local list=self.riverBins[key]
            if not list then list={};self.riverBins[key]=list end
            list[#list+1]=segment
        end end
    end
end
local function rebuildRivers(self)
    self.riverBins={}
    for i,river in ipairs(self.rivers) do river.segments={};segmentBins(self,river.points,i) end
end

local function buildGrid(self)
    local cells=self.config.size/Config.COARSE
    for x=0,cells do
        self.grid[x]=self.grid[x] or {}
        for z=0,cells do self.grid[x][z]=self:rawHeight(x*Config.COARSE,z*Config.COARSE) end
    end
    self.samples=(cells+1)^2
end

local function landConnectivity(self)
    local cells=self.config.size/Config.COARSE;local stride=cells+1
    local open,seen,queue={},{},{};local total=0
    for x=1,cells-1 do for z=1,cells-1 do
        if self.grid[x][z]>.28 then open[x*stride+z]=true;total=total+1 end
    end end
    local center=math.floor(self.config.center/Config.COARSE);local start=center*stride+center
    if not open[start] then return 0 end
    seen[start]=true;queue[1]=start;local head=1;local offsets={-stride,stride,-1,1}
    while head<=#queue do
        local key=queue[head];head=head+1
        for _,offset in ipairs(offsets) do
            local nextKey=key+offset
            if open[nextKey] and not seen[nextKey] then seen[nextKey]=true;queue[#queue+1]=nextKey end
        end
    end
    return #queue/total
end

function Plan.new(seed,config)
    seed=seed or 4261
    local coast={}
    for i,shape in ipairs({{1,.13},{2,.10},{3,.075},{5,.035},{9,.014}}) do
        coast[i]={frequency=shape[1],amplitude=shape[2]*(.7+M.hash(seed+501,i,29)*.6),
            phase=M.hash(seed+503,shape[1],31)*math.pi*2}
    end
    local axis=M.hash(seed+837,13,53)*math.pi*2
    local coves,headlands={},{}
    local coastCount=2+math.min(2,math.floor(M.hash(seed+813,19,25)*3))
    for i=1,coastCount do
        -- Unequal spacing and unequal depths avoid a repeated star/flower
        -- outline. One major inlet interrupts a longer asymmetric landmass.
        local angle=M.hash(seed+821,i,29)*math.pi*2
        for attempt=1,6 do
            local clear=true
            for _,cove in ipairs(coves) do
                if math.abs((angle-cove.angle+math.pi)%(math.pi*2)-math.pi)<.65 then clear=false end
            end
            if clear then break end
            angle=M.hash(seed+823,i*7+attempt,31)*math.pi*2
        end
        coves[i]={angle=angle,width=.20+M.hash(seed+827,i,31)*.25,
            depth=i==1 and (.38+M.hash(seed+829,i,37)*.28) or (.12+M.hash(seed+829,i,37)*.24)}
    end
    for i=1,2 do
        headlands[i]={angle=axis+(i-1)*math.pi+(M.hash(seed+831,i,41)-.5)*.8,
            width=.19+M.hash(seed+833,i,43)*.22,height=.12+M.hash(seed+835,i,47)*.23}
    end
    if M.hash(seed+843,17,67)>.45 then
        headlands[3]={angle=axis+(M.hash(seed+845,19,71)<.5 and -1 or 1)*math.pi/2,
            width=.24+M.hash(seed+847,23,73)*.14,height=.10+M.hash(seed+849,29,79)*.18}
    end
    local hydroRoll=M.hash(seed+1051,17,83)
    local hydrologyMode=hydroRoll<.22 and 'cross-island' or hydroRoll<.55 and 'lake-basin' or 'drainage'
    local self=setmetatable({seed=seed,config=config,grid={},hills={},routes={},coast=coast,coves=coves,headlands=headlands,
        coastAxis=axis,coastStretch=1.12+M.hash(seed+839,17,59)*.38,hydrologyMode=hydrologyMode,
        crossIslandDivide=hydrologyMode=='cross-island',
        ridges={},mountains={},forestRegions={},rivers={},riverBins={},lakes={},marshes={},binWidth=math.ceil(config.size/32)+2},Plan)
    local c,r=config.center,config.radius

    -- Estimate polar area once, then apply a broad land budget. We deliberately
    -- retain about +/- 12% size variation instead of squeezing bays into a disk.
    local area,maxRadius=0,0
    for i=0,511 do local radius=coastScale(self,i*math.pi*2/512);area=area+radius*radius;maxRadius=math.max(maxRadius,radius) end
    self.coastFactor=math.min(math.sqrt((.88+M.hash(seed+841,23,61)*.24)/(area/512)),1.82/maxRadius)
    buildShore(self)

    -- Low ridges retain the island's broad, walkable uplands.
    local ridgeBase=M.hash(seed+901,3,13)*math.pi*2
    for i=1,5 do
        local angle=ridgeBase+(i-1)*math.pi*2/5+(M.hash(seed+907,i,17)-.5)*.5
        local distance=r*coastScale(self,angle)*(.24+M.hash(seed+911,i,19)*.47)
        local ridge={x=c+math.cos(angle)*distance,z=c+math.sin(angle)*distance,
            rx=68+M.hash(seed+919,i,23)*55,rz=37+M.hash(seed+929,i,29)*30,
            angle=angle+.6+(M.hash(seed+937,i,31)-.5)*.8,
            height=1.3+M.hash(seed+941,i,37)*1.7}
        self.ridges[i]=ridge
        self.hills[i]=ridge
        local mx,mz=(c+ridge.x)*.5,(c+ridge.z)*.5
        self.routes[#self.routes+1]={c,c,mx,mz}
        self.routes[#self.routes+1]={mx,mz,ridge.x,ridge.z}
    end

    -- The original massif profile stays intact, but its systems now occupy a
    -- seeded ring across the island instead of one compact center cluster.
    local mountainScale=M.clamp(math.sqrt(r/360),.48,1.55)
    local mountainAxis=M.hash(seed+1001,7,43)*math.pi*2
    local massifCount=2+math.floor(M.hash(seed+1003,11,47)*3)
    for i=1,massifCount do
        local angle=mountainAxis+(i-1)*math.pi*2/massifCount+(M.hash(seed+1007,i,53)-.5)*.48
        local distance=r*(.27+M.hash(seed+1013,i,59)*.14)
        -- Keep systems inland even when a deep cove cuts into this arc.
        distance=math.min(distance,r*math.max(.21,coastScale(self,angle)-.35))
        local mountain={x=c+math.cos(angle)*distance,z=c+math.sin(angle)*distance,
            angle=angle+.55+(M.hash(seed+1033,i,79)-.5)*.8}
        if i==1 then
            mountain.baseRx=math.max(40,r*(.31+M.hash(seed+1033,15,79)*.055))
            mountain.baseRz=math.max(32,r*(.23+M.hash(seed+1037,17,81)*.05))
            mountain.base=mountainScale*(4+M.hash(seed+1039,19,83)*4)
            mountain.shoulderRx=math.max(30,r*(.24+M.hash(seed+1019,7,61)*.055))
            mountain.shoulderRz=math.max(24,r*(.17+M.hash(seed+1021,9,67)*.055))
            mountain.peakRx=math.max(22,r*(.070+M.hash(seed+1027,11,71)*.035))
            mountain.peakRz=math.max(18,r*(.050+M.hash(seed+1031,13,73)*.030))
            mountain.shoulder=mountainScale*(13+M.hash(seed+1047,23,89)*8)
            mountain.peak=mountainScale*(40+M.hash(seed+1049,25,91)*22)
        else
            mountain.shoulderRx=math.max(24,r*(.105+M.hash(seed+1063,i,107)*.05))
            mountain.shoulderRz=math.max(19,r*(.075+M.hash(seed+1067,i,109)*.045))
            mountain.peakRx=math.max(16,r*(.038+M.hash(seed+1069,i,113)*.026))
            mountain.peakRz=math.max(13,r*(.030+M.hash(seed+1073,i,127)*.022))
            mountain.shoulder=mountainScale*(7+M.hash(seed+1081,i,137)*6)
            mountain.peak=mountainScale*(24+M.hash(seed+1087,i,139)*19)
        end
        self.mountains[i]=mountain
    end
    -- Forest patches alternate broad dense stands and open glades. Their
    -- centers and sizes vary by seed; noise softens every boundary.
    local forestBase=M.hash(seed+953,7,41)*math.pi*2
    for i=1,8 do
        local angle=forestBase+(i-1)*math.pi/4+(M.hash(seed+957,i,43)-.5)*.35
        local distance=r*coastScale(self,angle)*(.22+M.hash(seed+967,i,47)*.50)
        self.forestRegions[i]={x=c+math.cos(angle)*distance,z=c+math.sin(angle)*distance,
            rx=r*(.12+M.hash(seed+971,i,53)*.075),rz=r*(.10+M.hash(seed+977,i,59)*.075),
            angle=angle+.4+(M.hash(seed+983,i,61)-.5)*.8,open=i%2==0}
    end

    local pondAngle=self.coastAxis+(M.hash(seed+985,5,63)-.5)*.5
    local pondRadius=math.max(36,r*coastScale(self,pondAngle)*(.38+M.hash(seed+987,7,65)*.22))
    self.pond={id='pond',type='pond',x=c+math.cos(pondAngle)*pondRadius,z=c+math.sin(pondAngle)*pondRadius,
        rx=10+M.hash(seed+989,9,67)*8,rz=8+M.hash(seed+990,9,69)*6,angle=M.hash(seed+991,11,67)*math.pi,
        noiseSeed=1091,phase=M.hash(seed+1093,13,71)*math.pi*2,depth=1.8}
    for _=1,8 do
        if self:shoreDistance(self.pond.x,self.pond.z)>=math.max(self.pond.rx,self.pond.rz)+18 then break end
        pondRadius=math.max(36,pondRadius*.85)
        self.pond.x,self.pond.z=c+math.cos(pondAngle)*pondRadius,c+math.sin(pondAngle)*pondRadius
    end
    self.lakes[1]=self.pond
    local extraLakeCount=self.hydrologyMode=='lake-basin'
        and (2+math.floor(M.hash(seed+1097,15,73)*3))
        or (1+math.floor(M.hash(seed+1099,17,79)*2))
    local lakeAxis=M.hash(seed+1101,19,81)*math.pi*2
    for i=1,extraLakeCount do
        for attempt=1,16 do
            local salt=i*37+attempt
            local angle=lakeAxis+(i-1)*math.pi*2/extraLakeCount
                +(M.hash(seed+1103,salt,83)-.5)*.62
            local radialSlot=(i-1+M.hash(seed+1109,salt,89)*.72)/extraLakeCount
            local distance=r*(.20+.48*radialSlot)
            local x,z=c+math.cos(angle)*distance,c+math.sin(angle)*distance
            local large=self.hydrologyMode=='lake-basin' and i==1
            local rx=math.max(14,r*(large and (.042+M.hash(seed+1111,salt,97)*.025)
                or (.024+M.hash(seed+1117,salt,101)*.018)))
            local rz=rx*(.52+M.hash(seed+1123,salt,103)*.40)
            local clear=self:shoreDistance(x,z)>math.max(rx,rz)+26
                and M.length(x-c,z-c)>rx+48 and self:landHeight(x,z)<13
            for _,lake in ipairs(self.lakes) do
                if M.length(x-lake.x,z-lake.z)<rx+math.max(lake.rx,lake.rz)+26 then clear=false end
            end
            if clear then
                self.lakes[#self.lakes+1]={id='lake-'..i,type='lake',x=x,z=z,rx=rx,rz=rz,
                    angle=M.hash(seed+1129,salt,107)*math.pi,noiseSeed=1133+i*19,
                    phase=M.hash(seed+1139,salt,109)*math.pi*2,depth=.8+M.hash(seed+1141,salt,113)*1.1}
                break
            end
        end
    end

    self.riverAngle=coves[1+math.min(#coves-1,math.floor(M.hash(seed+992,9,71)*#coves))].angle
    -- A deep inlet may reach almost to the nursery. Shift that outlet along
    -- the bay's edge so its watershed has enough inland length to branch.
    local outletSide=M.hash(seed+994,11,73)<.5 and -1 or 1
    for _=1,12 do
        if coastScale(self,self.riverAngle)>=.68 then break end
        self.riverAngle=self.riverAngle+outletSide*.12
    end
    self.sourceBend=(M.hash(seed+993,7,69)-.5)*1.3
    self.meander=.13+M.hash(seed+991,11,67)*.34
    self.meander2=.05+M.hash(seed+1147,19,127)*.24
    self.meanderPhase=M.hash(seed+997,13,71)*math.pi*2
    self.meanderPhase2=M.hash(seed+1151,21,131)*math.pi*2
    self.meanderFrequency=.75+M.hash(seed+998,15,73)*2.1
    self.meanderFrequency2=1.4+M.hash(seed+1153,23,137)*2.4
    self.sourceRadius=math.max(36,r*(.12+M.hash(seed+999,17,79)*.13))
    local sourceBend,meander,meander2=self.sourceBend,self.meander,self.meander2
    if self.hydrologyMode=='cross-island' then
        self.crossingStart=self.coastAxis+(M.hash(seed+1157,25,139)-.5)*.42
        self.crossingEnd=self.crossingStart+math.pi+(M.hash(seed+1163,27,149)-.5)*.24
        local a0,a1=self.crossingStart,self.crossingEnd
        local r0,r1=r*coastScale(self,a0)-4,r*coastScale(self,a1)-4
        local x0,z0=c+math.cos(a0)*r0,c+math.sin(a0)*r0
        local x1,z1=c+math.cos(a1)*r1,c+math.sin(a1)*r1
        local dx,dz=x1-x0,z1-z0;local length=math.max(1,M.length(dx,dz))
        local nx,nz=-dz/length,dx/length
        local midpointX,midpointZ=(x0+x1)*.5-c,(z0+z1)*.5-c
        local alignment=midpointX*nx+midpointZ*nz
        local sign=math.abs(alignment)>1 and (alignment<0 and -1 or 1)
            or (M.hash(seed+1167,29,151)<.5 and -1 or 1)
        self.crossingBend=sign*math.max(34,r*(.18+M.hash(seed+1171,31,157)*.08))
        self.crossingSway=(M.hash(seed+1177,33,163)-.5)*r*.045
    else
        -- Keep a monotonic outward course while retaining several independent
        -- bends instead of reducing every river to one shallow arc.
        for outletAttempt=1,24 do
            self.outletRadius=r*(coastScale(self,self.riverAngle)+.045)
            self.sourceBend,self.meander,self.meander2=sourceBend,meander,meander2
            local inland=false
            for _=1,8 do
                inland=true;local previousDistance=math.huge
                for i=0,96 do
                    local t=i/96;local x,z=mainPoint(self,t);local distance=self:shoreDistance(x,z)
                    if (t<.82 and distance<math.min(46,r*.25))
                        or (previousDistance<40 and distance>previousDistance+.25) then inland=false;break end
                    previousDistance=distance
                end
                if inland then break end
                self.sourceBend=self.sourceBend*.5;self.meander=self.meander*.5;self.meander2=self.meander2*.5
            end
            if inland or outletAttempt==24 then break end
            self.riverAngle=self.riverAngle+outletSide*.17
        end
    end
    local crossing=self.crossIslandDivide
    local mainRiver={id='river-main',segments={},points={},waterWidth=crossing and math.max(7,r*(.020+M.hash(seed+1181,35,167)*.007))
        or math.max(4,r*(.015+M.hash(seed+1187,37,173)*.008)),
        valleyWidth=crossing and r*(.052+M.hash(seed+1193,39,179)*.022)
            or math.max(25,r*(.045+M.hash(seed+1197,41,181)*.030)),
        depth=.72+M.hash(seed+1201,43,191)*.85}
    mainRiver.valleyWidth=math.max(mainRiver.waterWidth+18,mainRiver.valleyWidth)
    self.rivers[1]=mainRiver
    local main=mainRiver.points
    local pointCount=crossing and 96 or 64
    for i=0,pointCount do
        local t=i/pointCount;local x,z
        if crossing then x,z=crossingPoint(self,t) else x,z=mainPoint(self,t) end
        main[#main+1]={x=x,z=z,progress=t}
    end
    segmentBins(self,main,1)
    -- Drainage layouts build a seeded tree with independent bends and widths.
    -- Later streams can feed tributaries, and junctions meet their parent.
    -- Cross-island layouts keep the through-channel broad and easy to read.
    local branchCount=crossing and (1+math.floor(M.hash(seed+1001,19,83)*2))
        or (1+math.floor(M.hash(seed+1001,19,83)*4))
    for i=1,branchCount do
        for attempt=1,12 do
            local salt=i*31+attempt
            local parent=1
            if #self.rivers>1 and M.hash(seed+1003,salt,89)<.45 then
                parent=2+math.min(#self.rivers-2,math.floor(M.hash(seed+1007,salt,97)*(#self.rivers-1)))
            end
            local parentRiver=self.rivers[parent]
            local parentPathLength=0
            for pointIndex=2,#parentRiver.points do
                local before,point=parentRiver.points[pointIndex-1],parentRiver.points[pointIndex]
                parentPathLength=parentPathLength+M.length(point.x-before.x,point.z-before.z)
            end
            local parentProgressStart=parentRiver.points[1].progress
            local parentProgressEnd=parentRiver.points[#parentRiver.points].progress
            local parentProgressSpan=parentProgressEnd-parentProgressStart
            assert(parentPathLength>0 and parentProgressSpan>0,
                'Drainage parent must have a positive measured path and progress span')
            local joinT=.38+M.hash(seed+1009,salt,101)*.45
            if parent>1 then joinT=.5+M.hash(seed+1013,salt,103)*.38 end
            local tx,tz,progress=riverPoint(self.rivers[parent],joinT)
            local angle=math.atan2(tz-c,tx-c);local targetR=M.length(tx-c,tz-c)
            local side=self.rivers[parent].side or (M.hash(seed+1019,salt,107)<.5 and -1 or 1)
            local sourceR=math.max(36,r*.16,targetR-r*(.12+M.hash(seed+1021,salt,109)*.22))
            local offset=side*(.32+M.hash(seed+1031,salt,113)*.48)
            local bend=side*(.04+M.hash(seed+1033,salt,127)*.14)
            local tributary={id='river-branch-'..i,parent=parent,join=joinT,side=side,segments={},points={},
                waterWidth=math.max(3,r*(.006+M.hash(seed+1207,salt,193)*.005)),
                valleyWidth=math.max(16,r*(.034+M.hash(seed+1213,salt,197)*.018)),depth=.48+M.hash(seed+1217,salt,199)*.62}
            local valid=targetR-sourceR>math.min(32,r*.05)
            local previousDistance=math.huge
            for j=0,24 do
                local u=j/24
                local sweep=side*(.08+M.hash(seed+1223,salt,211)*.24)
                    *math.sin(u*math.pi*2*(1+M.hash(seed+1229,salt,223)*1.5)+M.hash(seed+1231,salt,227)*math.pi*2)
                    *math.sin(math.pi*u)
                local a=angle+offset*(1-u)+bend*math.sin(math.pi*u)+sweep
                local rr=M.lerp(sourceR,targetR,u)
                local x,z=c+math.cos(a)*rr,c+math.sin(a)*rr
                if j==24 then x,z=tx,tz end
                -- Store local path progress first. The parent mapping is based
                -- on measured geometry below so coast-to-coast channels do not
                -- require the absent radial outletRadius used by mainPoint().
                tributary.points[#tributary.points+1]={x=x,z=z,progress=u}
                if self:shoreDistance(x,z)<math.min(46,r*.25) then valid=false end
                local distance,_,nearest=self:riverDistance(x,z)
                if u<.65 and distance<math.min(46,r*.06)*(1-u*.5) then valid=false end
                if distance<46 and nearest~=self.rivers[parent].id then valid=false end
                if previousDistance<48 and distance>previousDistance+.25 then valid=false end
                previousDistance=distance
            end
            local tributaryLength=0
            for pointIndex=2,#tributary.points do
                local before,point=tributary.points[pointIndex-1],tributary.points[pointIndex]
                tributaryLength=tributaryLength+M.length(point.x-before.x,point.z-before.z)
            end
            local progressSpan=math.min(parentProgressSpan,tributaryLength/parentPathLength*parentProgressSpan)
            local startT=math.max(parentProgressStart,progress-progressSpan)
            for _,point in ipairs(tributary.points) do
                point.progress=M.lerp(startT,progress,point.progress)
            end
            if valid then
                self.rivers[#self.rivers+1]=tributary
                segmentBins(self,tributary.points,#self.rivers)
                break
            end
        end
    end

    -- Add independent watersheds with their own inland headwaters and coastal
    -- mouths. The seeded divide above remains a separate, deliberate topology.
    local independentCount=crossing and (1+math.floor(M.hash(seed+1281,49,277)*2))
        or (1+math.floor(M.hash(seed+1283,51,281)*2))
    local acceptedIndependent=0
    for i=1,independentCount do
        for attempt=1,24 do
            local salt=i*43+attempt
            local mountainIndex=1+((i-1)%#self.mountains)
            local mountain=self.mountains[mountainIndex]
            local mountainAngle=math.atan2(mountain.z-c,mountain.x-c)
            local side=M.hash(seed+1287,i,283)<.5 and -1 or 1
            if i%2==0 then side=-side end
            local outletAngle=mountainAngle+side*(.38+M.hash(seed+1289,salt,289)*.54)
                +(M.hash(seed+1291,salt,293)-.5)*.28
            for _=1,12 do
                if coastScale(self,outletAngle)>=.68 then break end
                outletAngle=outletAngle+side*.12
            end
            local sourceAngle=mountainAngle+(M.hash(seed+1293,salt,299)-.5)*.68
            local sourceRadius=math.max(36,M.length(mountain.x-c,mountain.z-c)
                +r*(M.hash(seed+1297,salt,307)-.5)*.14)
            local outletRadius=r*(coastScale(self,outletAngle)+.045)
            local river={id='river-independent-'..i,independent=true,segments={},points={},
                sourceAngle=sourceAngle,outletAngle=outletAngle,sourceRadius=sourceRadius,outletRadius=outletRadius,
                bend=(M.hash(seed+1301,salt,311)-.5)*.72,
                meander=.06+M.hash(seed+1307,salt,313)*.20,
                frequency=.7+M.hash(seed+1313,salt,317)*1.9,
                phase=M.hash(seed+1319,salt,331)*math.pi*2,
                waterWidth=math.max(4,r*(.009+M.hash(seed+1321,salt,337)*.005)),
                valleyWidth=math.max(22,r*(.038+M.hash(seed+1327,salt,347)*.022)),
                depth=.55+M.hash(seed+1333,salt,349)*.65}
            river.valleyWidth=math.max(river.waterWidth+18,river.valleyWidth)
            river.points={}
            local valid=true
            local coastMargin=math.min(42,r*.07)
            local channelGap=math.max(12,math.min(36,r*.045))
            for j=0,64 do
                local t=j/64;local x,z=independentPoint(self,river,t)
                river.points[#river.points+1]={x=x,z=z,progress=t}
                local shore=self:shoreDistance(x,z)
                if j<57 and shore<coastMargin then valid=false end
                if j<57 and self:riverDistance(x,z)<channelGap then valid=false end
            end
            if valid then
                self.rivers[#self.rivers+1]=river
                segmentBins(self,river.points,#self.rivers)
                acceptedIndependent=acceptedIndependent+1
                break
            end
        end
    end
    self.independentRiverCount=acceptedIndependent

    local marshCount=self.hydrologyMode=='lake-basin'
        and (3+math.floor(M.hash(seed+1237,45,229)*3))
        or (2+math.floor(M.hash(seed+1241,47,233)*3))
    local marshAxis=M.hash(seed+1341,53,353)*math.pi*2
    for i=1,marshCount do
        for attempt=1,18 do
            local salt=i*41+attempt
            local rx=math.max(38,r*(.075+M.hash(seed+1253,salt,251)*.045))
            local rz=rx*(.56+M.hash(seed+1259,salt,257)*.38)
            local angle=marshAxis+(i-1)*math.pi*2/marshCount
                +(M.hash(seed+1243,salt,239)-.5)*.48
            local radialSlot=(i-1+M.hash(seed+1247,salt,241)*.72)/marshCount
            local distance=r*(.18+.50*radialSlot)
            local x,z=c+math.cos(angle)*distance,c+math.sin(angle)*distance
            local associatedLake
            if self.hydrologyMode=='lake-basin' and #self.lakes>1 and i%2==0 then
                local lakeIndex=2+math.floor(M.hash(seed+1337,salt,351)*(#self.lakes-1))
                associatedLake=self.lakes[lakeIndex]
                local lakeAngle=angle+(M.hash(seed+1343,salt,359)-.5)*.55
                local offset=math.max(associatedLake.rx,associatedLake.rz)*.9+rx*.52
                x=associatedLake.x+math.cos(lakeAngle)*offset
                z=associatedLake.z+math.sin(lakeAngle)*offset
            end
            local clear=self:shoreDistance(x,z)>math.max(rx,rz)+30
                and M.length(x-c,z-c)>rx+58 and self:landHeight(x,z)<11
            for _,lake in ipairs(self.lakes) do
                local lakeGap=M.length(x-lake.x,z-lake.z)
                if lake==associatedLake then
                    if lakeGap<math.max(lake.rx,lake.rz)*.65 then clear=false end
                elseif lakeGap<rx+math.max(lake.rx,lake.rz)+24 then clear=false end
            end
            for _,other in ipairs(self.marshes) do
                if M.length(x-other.x,z-other.z)<rx+other.rx+28 then clear=false end
            end
            if clear then
                self.marshes[#self.marshes+1]={id='marsh-'..i,type='marsh',x=x,z=z,rx=rx,rz=rz,
                    angle=M.hash(seed+1261,salt,263)*math.pi,noiseSeed=1267+i*23,
                    phase=M.hash(seed+1271,salt,269)*math.pi*2,
                    complexId=associatedLake and associatedLake.id or nil}
                break
            end
        end
    end
    buildGrid(self)
    -- Most maps retain connected dry terrain. A small seed-selected subset
    -- intentionally uses a coast-to-coast waterway to create separate reaches.
    self.landConnectivity=landConnectivity(self)
    if not self.crossIslandDivide then
        while self.landConnectivity<.999 and #self.rivers>1 do
            table.remove(self.rivers);rebuildRivers(self);buildGrid(self)
            self.landConnectivity=landConnectivity(self)
        end
        if self.landConnectivity<.999 then
            -- A rare unsafe main outlet is rerouted along a broad lobe. Attempts
            -- remain seed-derived and bounded; the last uses the widest headland.
            for attempt=1,12 do
                self.riverAngle=self.coastAxis+(attempt%2)*math.pi+(M.hash(seed+1061,attempt,131)-.5)*.55
                self.sourceBend=sourceBend*.25;self.meander=meander*.5;self.meander2=meander2*.5
                if attempt==12 then
                    local widest,index=0,1
                    for i,radius in ipairs(self.coastSamples) do if radius>widest then widest,index=radius,i end end
                    self.riverAngle=(index-1)*math.pi*2/#self.coastSamples
                    self.sourceBend=0;self.meander=0;self.meander2=0
                end
                self.outletRadius=r*(coastScale(self,self.riverAngle)+.045)
                for i=0,64 do
                    local t=i/64;local x,z=mainPoint(self,t)
                    self.rivers[1].points[i+1]={x=x,z=z,progress=t}
                end
                rebuildRivers(self);buildGrid(self);self.landConnectivity=landConnectivity(self)
                if self.landConnectivity>=.999 then break end
            end
        end
    end
    self.independentRiverCount=0
    for _,river in ipairs(self.rivers) do
        if river.independent then self.independentRiverCount=self.independentRiverCount+1 end
    end
    return self
end

-- Fixed inland town preset. Its topology is authored once; only seeded terrain
-- noise and habitat fields vary if a different seed is deliberately supplied.
local function townRiverX(z)
    local offset=z-270
    return 330+math.sin(offset/61)*14+math.sin(offset/23)*4
end

function Plan:riverCenterX(z)
    if not self.town then return nil end
    return townRiverX(z)
end

function Plan.newTown(seed,config)
    seed=seed or 4261
    config=config or {size=512,center=256,radius=201}
    assert(type(config.size)=='number' and config.size%Config.COARSE==0,
        'Town size must align with the terrain coarse grid')
    local self=setmetatable({seed=seed,config=config,town=true,townPreset='inland-town-v1',
        grid={},hills={},routes={},coast={},coves={},headlands={},ridges={},mountains={},
        forestRegions={},rivers={},riverBins={},lakes={},marshes={},
        binWidth=math.ceil(config.size/32)+2,shoreBins={},
        playableBounds={x0=56,z0=56,x1=458,z1=458},
        bridgeCrossing={id='town-river-bridge',x0=290,x1=380,z=270,x=330}},Plan)

    -- Two western hill systems reuse the same ridge and mountain relief math
    -- as the island plan, placed against the fixed town coordinates.
    self.ridges={
        {x=164,z=151,rx=112,rz=43,angle=-.42,height=1.5},
        {x=218,z=367,rx=92,rz=35,angle=.36,height=1.2},
    }
    self.hills=self.ridges
    self.mountains={
        {x=132,z=150,angle=-.35,baseRx=62,baseRz=48,base=1.0,
            shoulderRx=45,shoulderRz=36,shoulder=3.0,peakRx=24,peakRz=18,peak=7.0},
        {x=211,z=368,angle=.48,baseRx=52,baseRz=39,base=.8,
            shoulderRx=35,shoulderRz=28,shoulder=2.3,peakRx=19,peakRz=15,peak=5.2},
    }
    -- Dense stands follow the western hills; open influence leaves room for
    -- the town's eastern terrace and edge parks.
    self.forestRegions={
        {x=139,z=151,rx=91,rz=70,angle=-.35,open=false},
        {x=220,z=367,rx=80,rz=64,angle=.42,open=false},
        {x=410,z=134,rx=55,rz=61,angle=-.18,open=true},
        {x=417,z=390,rx=63,rz=52,angle=.51,open=true},
        {x=74,z=302,rx=49,rz=86,angle=-.28,open=true},
    }

    local river={id='town-river',segments={},points={},waterWidth=7.5,
        valleyWidth=34,depth=1.25,waterLevel=0,flow='north-to-south'}
    self.rivers[1]=river
    for z=56,458,2 do
        river.points[#river.points+1]={x=townRiverX(z),z=z,progress=(z-56)/(458-56)}
    end
    segmentBins(self,river.points,1)
    buildGrid(self)
    return self
end

function Plan:riverDistance(x,z)
    if x<0 or z<0 or x>=self.config.size or z>=self.config.size then return math.huge,nil,nil,nil end
    local bx,bz=math.floor(x/32),math.floor(z/32)
    local list=self.riverBins[bz*self.binWidth+bx+1]
    if not list then return math.huge,nil,nil,nil end
    local best,bestProgress,bestId,bestRiver=math.huge,nil,nil,nil
    for _,s in ipairs(list) do
        local d2,u=segmentDistance2(s,x,z)
        if d2<best then best=d2;bestProgress=s.p+s.pd*u;bestId=s.id;bestRiver=s end
    end
    return math.sqrt(best),bestProgress,bestId,bestRiver
end

function Plan:isRiverAt(x,z)
    local distance,_,_,river=self:riverDistance(x,z)
    return river~=nil and distance<=river.waterWidth*1.55
        and self:landHeight(x,z)>.08 and self:height(x,z)<.04
end

function Plan:lakeAt(x,z)
    for _,lake in ipairs(self.lakes) do
        if lakeDistance(self,lake,x,z)<=1.06 then return lake end
    end
end

function Plan:marshAt(x,z)
    local best,bestMarsh=0,nil
    for _,marsh in ipairs(self.marshes) do
        local distance=marshDistance(self,marsh,x,z)
        local wetness=1-M.smooth((distance-.42)/1.30)
        if wetness>best then best,bestMarsh=wetness,marsh end
    end
    return best,bestMarsh
end

function Plan:marshWaterAt(x,z)
    local wetness=self:marshAt(x,z)
    return wetness>.16 and self:height(x,z)<.04
end

function Plan:waterIdAt(x,z)
    local lake=self:lakeAt(x,z)
    if lake and self:height(x,z)<.04 then return lake.id end
    local wetness,marsh=self:marshAt(x,z)
    if marsh and wetness>.16 and self:height(x,z)<.04 then return marsh.id end
    local distance,_,riverId,river=self:riverDistance(x,z)
    if river and distance<=river.waterWidth*1.55 and self:landHeight(x,z)>.08 and self:height(x,z)<.04 then
        return riverId
    end
end

function Plan:shoreDistance(x,z)
    if self.town then return math.huge end
    local c=self.config
    local dx,dz=x-c.center,z-c.center
    local r=M.length(dx,dz);local angle=math.atan2(dz,dx)
    local coast=c.radius*coastScale(self,angle)
    -- Euclidean bank distance bounds shore slopes even inside a deep, narrow
    -- bay; radial distance would produce steep walls on the sides of inlets.
    local distance=48
    local list=self.shoreBins[math.floor(z/64)*self.shoreBinWidth+math.floor(x/64)+1]
    if list then
        local best=distance*distance
        for _,segment in ipairs(list) do local d2=segmentDistance2(segment,x,z);best=math.min(best,d2) end
        distance=math.sqrt(best)
    end
    return r<coast and distance or -distance
end

function Plan:landHeight(x,z)
    local s,c=self.seed,self.config
    if self.town then
        local riverX=townRiverX(z)
        -- Inland terraces replace the island's shoreline height clamp. The
        -- original broad/fine noise and relief fields remain the terrain base.
        local relief=4.25+(M.noise(s+53,x*.009,z*.009)-.5)*1.8
            +(M.noise(s+67,x*.03,z*.03)-.5)*.7
        relief=relief+1.55*M.smooth((x-riverX-10)/40)
        for _,ridge in ipairs(self.ridges) do
            local rx,rz=x-ridge.x,z-ridge.z
            local ca,sa=math.cos(ridge.angle),math.sin(ridge.angle)
            local d=M.length((rx*ca+rz*sa)/ridge.rx,(-rx*sa+rz*ca)/ridge.rz)
            relief=relief+ridge.height*(1-M.smooth(d))
        end
        local broadWarp=(M.noise(s+1103,x*.035,z*.035)-.5)*.60
        local edgeWarp=(M.noise(s+1109,x*.105,z*.105)-.5)*.28
        for _,mountain in ipairs(self.mountains) do
            local dx,dz=x-mountain.x,z-mountain.z;local ca,sa=math.cos(mountain.angle),math.sin(mountain.angle)
            if mountain.baseRx then
                local base=M.length((dx*ca+dz*sa)/mountain.baseRx,(-dx*sa+dz*ca)/mountain.baseRz)
                relief=relief+mountain.base*(1-M.smooth(base))
            end
            local shoulder=M.length((dx*ca+dz*sa)/mountain.shoulderRx,(-dx*sa+dz*ca)/mountain.shoulderRz)
                *(1+broadWarp*.35)
            local peak=M.length((dx*ca+dz*sa)/mountain.peakRx,(-dx*sa+dz*ca)/mountain.peakRz)
                *(1+broadWarp+edgeWarp)
            local face=math.max(0,1-peak)
            relief=relief+mountain.shoulder*(1-M.smooth(shoulder))+mountain.peak*face^.78
        end
        return M.clamp(relief,0,Config.HEIGHT_LIMIT)
    end
    local r=M.length(x-c.center,z-c.center)
    local shore=self:shoreDistance(x,z)*.28
    local relief=1.1+M.noise(s+53,x*.009,z*.009)*3.5+M.noise(s+67,x*.03,z*.03)*1.1
    for _,ridge in ipairs(self.ridges) do
        local rx,rz=x-ridge.x,z-ridge.z
        local ca,sa=math.cos(ridge.angle),math.sin(ridge.angle)
        local d=M.length((rx*ca+rz*sa)/ridge.rx,(-rx*sa+rz*ca)/ridge.rz)
        local weight=1-M.smooth(d)
        relief=relief+ridge.height*weight
    end
    local broadWarp=(M.noise(s+1103,x*.035,z*.035)-.5)*.60
    local edgeWarp=(M.noise(s+1109,x*.105,z*.105)-.5)*.28
    for _,mountain in ipairs(self.mountains) do
        local dx,dz=x-mountain.x,z-mountain.z;local ca,sa=math.cos(mountain.angle),math.sin(mountain.angle)
        if mountain.baseRx then
            local base=M.length((dx*ca+dz*sa)/mountain.baseRx,(-dx*sa+dz*ca)/mountain.baseRz)
            relief=relief+mountain.base*(1-M.smooth(base))
        end
        local shoulder=M.length((dx*ca+dz*sa)/mountain.shoulderRx,(-dx*sa+dz*ca)/mountain.shoulderRz)
            *(1+broadWarp*.35)
        local peak=M.length((dx*ca+dz*sa)/mountain.peakRx,(-dx*sa+dz*ca)/mountain.peakRz)
            *(1+broadWarp+edgeWarp)
        local face=math.max(0,1-peak)
        relief=relief+mountain.shoulder*(1-M.smooth(shoulder))+mountain.peak*face^.78
    end
    local h=math.min(shore,relief)
    return M.clamp(M.lerp(.8,h,M.smooth((r-8)/12)),-1.2,Config.HEIGHT_LIMIT)
end

local function carveChannel(h,distance,progress,river)
    if river and distance<river.valleyWidth then
        local bed=-.42-river.depth*progress
        local channel=bed+river.depth*.60*(distance/math.max(1,river.waterWidth))^2
        local valley=math.min(h,channel)
        local bank=M.smooth((distance-river.waterWidth)/math.max(1,river.valleyWidth-river.waterWidth))
        h=M.lerp(valley,h,bank)
    end
    return h
end

function Plan:rawHeight(x,z)
    local h=self:landHeight(x,z)
    local distance,progress,_,river=self:riverDistance(x,z)
    h=carveChannel(h,distance,progress,river)
    for _,lake in ipairs(self.lakes) do
        local distance=lakeDistance(self,lake,x,z)
        h=math.min(h,(distance-1)*(lake.depth or 1.8))
    end
    for _,marsh in ipairs(self.marshes) do
        local distance=marshDistance(self,marsh,x,z)
        local wetness=1-M.smooth((distance-.42)/1.30)
        if wetness>0 then
            local pools=M.noise(self.seed+(marsh.noiseSeed or 0),x*.082,z*.082)
            local surface=.12-wetness*.25+(pools-.5)*.12
            h=math.min(h,surface)
        end
    end
    return M.clamp(h,-1.2,Config.HEIGHT_LIMIT)
end

function Plan:height(x,z)
    if x<0 or z<0 or x>=self.config.size or z>=self.config.size then return -1.2 end
    local gx,gz=x/Config.COARSE,z/Config.COARSE
    local ix,iz=math.floor(gx),math.floor(gz);local u,v=gx-ix,gz-iz
    local a,b,c,d=self.grid[ix][iz],self.grid[ix+1][iz],self.grid[ix][iz+1],self.grid[ix+1][iz+1]
    local h=M.lerp(M.lerp(a,b,u),M.lerp(c,d,u),v)
    -- A narrow tributary can fall between all four 8 m grid samples. Keep
    -- its analytical channel below the water surface after interpolation,
    -- using the existing local segment bins rather than a denser global grid.
    -- The profile only lowers terrain and rejoins it continuously at the bank.
    local distance,progress,_,river=self:riverDistance(x,z)
    h=carveChannel(h,distance,progress,river)
    local small=0
    if h>.3 then
        small=(M.noise(self.seed+83,x*.18,z*.18)-.5)*.08*M.smooth((h-.3)/.5)
        if not self.town then
            local r=M.length(x-self.config.center,z-self.config.center)
            small=small*M.smooth((r-8)/8)
        end
    end
    local fractured=0
    if h>6 then
        local crag=M.smooth((h-6)/17)
        fractured=((M.noise(self.seed+1117,x*.11,z*.11)-.5)*1.8
            +(M.noise(self.seed+1123,x*.24,z*.24)-.5)*.55)*crag
    end
    return M.clamp(h+small+fractured,-1.2,Config.HEIGHT_LIMIT)
end

function Plan:habitat(x,z)
    local moisture=M.noise(self.seed+137,x*.004,z*.004)*.62+M.noise(self.seed+139,x*.018,z*.018)*.38
    local wetland=self:marshAt(x,z)
    local riverDistance,_,_,nearbyRiver=self:riverDistance(x,z)
    moisture=M.clamp(moisture+wetland*.46+(nearbyRiver and (1-M.smooth((riverDistance-nearbyRiver.valleyWidth)/44))*.22 or 0),0,1)
    local canopy=M.smooth((M.noise(self.seed+461,x*.008,z*.008)-.32)/.48)*.72
        +M.smooth((moisture-.28)/.62)*.28
    local openInfluence,denseInfluence=0,0
    for _,region in ipairs(self.forestRegions) do
        local dx,dz=x-region.x,z-region.z;local ca,sa=math.cos(region.angle),math.sin(region.angle)
        local d=M.length((dx*ca+dz*sa)/region.rx,(-dx*sa+dz*ca)/region.rz)
        local influence=1-M.smooth((d-.72)/.42)
        if region.open then openInfluence=math.max(openInfluence,influence)
        else denseInfluence=math.max(denseInfluence,influence) end
    end
    local rockiness=0
    for _,ridge in ipairs(self.ridges) do
        local dx,dz=x-ridge.x,z-ridge.z;local ca,sa=math.cos(ridge.angle),math.sin(ridge.angle)
        local d=M.length((dx*ca+dz*sa)/ridge.rx,(-dx*sa+dz*ca)/ridge.rz)
        rockiness=math.max(rockiness,1-M.smooth((d-.10)/.78))
    end
    for _,mountain in ipairs(self.mountains) do
        local dx,dz=x-mountain.x,z-mountain.z;local ca,sa=math.cos(mountain.angle),math.sin(mountain.angle)
        local shoulder=M.length((dx*ca+dz*sa)/mountain.shoulderRx,(-dx*sa+dz*ca)/mountain.shoulderRz)
        local peak=M.length((dx*ca+dz*sa)/mountain.peakRx,(-dx*sa+dz*ca)/mountain.peakRz)
        rockiness=math.max(rockiness,.76*(1-M.smooth(shoulder)),1-M.smooth(peak))
        if mountain.baseRx then
            local base=M.length((dx*ca+dz*sa)/mountain.baseRx,(-dx*sa+dz*ca)/mountain.baseRz)
            rockiness=math.max(rockiness,.42*(1-M.smooth(base)))
        end
    end
    canopy=math.max(canopy,.78*denseInfluence)
    canopy=canopy*(1-.88*openInfluence)*(1-.62*rockiness)
    return M.clamp(canopy,0,1),M.smooth((moisture-.47)/.28),M.clamp(rockiness,0,1)
end

-- Broad plant communities reuse the island's existing coherent canopy,
-- moisture and drainage fields, so species group into patches without adding
-- per-instance biome state or extra streaming work.
function Plan:plantCommunity(x,z)
    local canopy,moisture,rockiness=self:habitat(x,z)
    local wetland=self:marshAt(x,z)
    if wetland>.22 or (self:riverDistance(x,z)<70 and moisture>.36) then return 'river-margin' end
    if canopy>.56 then return 'woodland-understory' end
    if canopy<.34 and rockiness<.58 then return 'sunny-opening' end
    return 'shrub-edge'
end

return Plan
