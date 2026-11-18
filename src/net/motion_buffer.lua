-- Remote actors render on a short, steadily advancing snapshot timeline. Input
-- prediction remains immediate for the local player; packet arrival jitter must
-- not repeatedly accelerate and brake everybody else.
local Buffer={MAX_SAMPLES=24,MAX_EXTRAPOLATION=.12}
local function clamp(value,low,high)return math.max(low,math.min(high,value))end
function Buffer.push(player,record,tick,now,interval,reset)
    local time=tick*interval
    local buffer=player._motionBuffer
    local last=buffer and buffer.samples[#buffer.samples]
    if reset or not last or now-buffer.arrived>1 then
        buffer={samples={},clock=time-.12,jitter=0,cadence=interval,elapsed=0}
        player._motionBuffer=buffer;last=nil
    end
    if last then
        local jitter=math.abs((now-buffer.arrived)-(time-last.time))
        buffer.jitter=buffer.jitter*.9+math.min(.2,jitter)*.1
        buffer.cadence=buffer.cadence*.9+math.min(.25,time-last.time)*.1
    end
    buffer.arrived=now;buffer.elapsed=0
    buffer.samples[#buffer.samples+1]={time=time,x=record.x,y=record.y,
        vx=record.velocityX or 0,vy=record.velocityY or 0}
    while #buffer.samples>Buffer.MAX_SAMPLES do table.remove(buffer.samples,1)end
end
function Buffer.sample(player,dt)
    local buffer=player._motionBuffer
    if not buffer then return nil end
    local samples=buffer.samples
    local newest=samples[#samples]
    if not newest then return nil end
    dt=math.max(0,dt)
    buffer.elapsed=buffer.elapsed+dt
    local delay=math.min(.4,.12+math.min(.12,buffer.jitter*1.5)
        +math.max(0,buffer.cadence-1/12)*1.5)
    local target=newest.time+math.min(.25,buffer.elapsed)-delay
    -- Adjust playback gently rather than jumping its clock on packet arrival.
    buffer.clock=buffer.clock+dt*(1+clamp((target-buffer.clock)*.5,-.1,.1))
    local time=buffer.clock
    while #samples>2 and samples[2].time<time do table.remove(samples,1)end
    if time<=samples[1].time then return samples[1].x,samples[1].y end
    for i=2,#samples do
        local right,left=samples[i],samples[i-1]
        if time<=right.time then
            local alpha=(time-left.time)/(right.time-left.time)
            return left.x+(right.x-left.x)*alpha,left.y+(right.y-left.y)*alpha
        end
    end
    local ahead=math.min(Buffer.MAX_EXTRAPOLATION,math.max(0,time-newest.time))
    return newest.x+newest.vx*ahead,newest.y+newest.vy*ahead
end
return Buffer
