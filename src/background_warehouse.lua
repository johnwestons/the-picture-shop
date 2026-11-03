-- Live-session clock debt and unattended warehouse cadence. No offline time,
-- invented production rates, or business state is stored here.
local Background={INTERVAL=.1,MAX_REAL_STEP=.1,MAX_GAME_STEP=1}
Background.__index=Background
local function nonnegative(value)
    value=tonumber(value) or 0
    return value==value and value<math.huge and math.max(0,value) or 0
end
function Background.new() return setmetatable({},Background):reset() end
function Background:reset(state)
    self.state=state;self.background=false;self.queue={}
    self.pendingGame,self.pendingMotion=0,0
    self.debtGame,self.debtMotion=0,0
    self.calls,self.steps,self.backgroundSteps=0,0,0
    return self
end
function Background:ensure(state)
    if self.state~=state then self:reset(state) end
end
function Background.unattended(player,remotePlayers)
    local function inShop(p)
        -- Unknown/nil scenes conservatively retain the full simulation.
        return p and p.sceneId~='home' and p.sceneId~='commute'
    end
    if inShop(player) then return false end
    for _,other in ipairs(remotePlayers or {}) do if inShop(other) then return false end end
    return true
end
function Background:clock(state,gameDt,motionDt,unattended,gameLimit)
    self:ensure(state)
    gameDt,motionDt=nonnegative(gameDt),nonnegative(motionDt)
    gameLimit=gameLimit and nonnegative(gameLimit) or math.huge
    if #self.queue==0 and gameDt<=gameLimit and (not unattended or motionDt<=Background.MAX_REAL_STEP
        and gameDt<=Background.MAX_GAME_STEP) then return gameDt,motionDt end
    if gameDt>0 or motionDt>0 then
        local last=self.queue[#self.queue]
        if last and math.abs(last.game*motionDt-gameDt*last.motion)<1e-10 then
            last.game,last.motion=last.game+gameDt,last.motion+motionDt
        else self.queue[#self.queue+1]={game=gameDt,motion=motionDt} end
        self.debtGame,self.debtMotion=self.debtGame+gameDt,self.debtMotion+motionDt
    end
    local acceptedGame,acceptedMotion=0,0
    while #self.queue>0 do
        local first=self.queue[1]
        local ratio=1
        if first.motion>0 then ratio=math.min(ratio,(Background.MAX_REAL_STEP-acceptedMotion)/first.motion) end
        if first.game>0 then ratio=math.min(ratio,(math.min(Background.MAX_GAME_STEP,gameLimit)-acceptedGame)/first.game) end
        if ratio<=1e-10 then break end
        local game,motion=first.game*ratio,first.motion*ratio
        acceptedGame,acceptedMotion=acceptedGame+game,acceptedMotion+motion
        self.debtGame,self.debtMotion=math.max(0,self.debtGame-game),math.max(0,self.debtMotion-motion)
        if ratio>=1-1e-10 then table.remove(self.queue,1)
        else first.game,first.motion=first.game-game,first.motion-motion;break end
    end
    return acceptedGame,acceptedMotion
end
function Background:flush(run,force)
    if not force and self.pendingGame<=0 and self.pendingMotion<=0 then return false end
    local game,motion=self.pendingGame,self.pendingMotion
    self.pendingGame,self.pendingMotion=0,0
    self.steps=self.steps+1
    if self.background then self.backgroundSteps=self.backgroundSteps+1 end
    return run(game,motion)==true
end
function Background:advance(state,gameDt,motionDt,run,force)
    self:ensure(state);self.calls=self.calls+1
    self.pendingGame=self.pendingGame+nonnegative(gameDt)
    self.pendingMotion=self.pendingMotion+nonnegative(motionDt)
    if force or not self.background or self.pendingMotion+1e-9>=Background.INTERVAL then
        return self:flush(run,force or not self.background)
    end
    return false
end
function Background.crossesMinute(hours,gameDt,secondsPerDay)
    local nextHours=hours+gameDt*24/secondsPerDay
    return math.floor((hours+1e-9)*60)~=math.floor((nextHours+1e-9)*60)
end
function Background:hasDebt() return self.debtGame>1e-8 or self.debtMotion>1e-8 end
function Background:stats()
    return {background=self.background,calls=self.calls,steps=self.steps,backgroundSteps=self.backgroundSteps,
        pendingGame=self.pendingGame,pendingMotion=self.pendingMotion,debtGame=self.debtGame,debtMotion=self.debtMotion}
end
return Background
