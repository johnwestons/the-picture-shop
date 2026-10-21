-- Cumulative press counters preserve short taps between LAN input samples.
local Actions={bits={1,4,16,32,64,128}}
local function held(mask,bit)return math.floor((mask or 0)/bit)%2==1 end
function Actions.blank() return {0,0,0,0,0,0} end
function Actions.record(actor,mask)
    for i,bit in ipairs(Actions.bits) do
        if held(mask,bit) then actor.sequences[i]=(actor.sequences[i]+1)%65536 end
    end
end
function Actions.consume(player,input)
    input=input or {};local mask=0
    player.sequences=player.sequences or Actions.blank()
    for i,bit in ipairs(Actions.bits) do
        local pressed=held(input.buttons,bit) and not held(player.previous,bit)
        if input.sequences then
            local value=input.sequences[i]
            local delta=(value-player.sequences[i])%65536
            pressed=delta>0 and delta<32768
            if delta<32768 then player.sequences[i]=value end
        end
        if pressed and not input.suspended then mask=mask+bit end
    end
    return mask
end
function Actions.seat(packet,second,roundId)
    if packet.roundId and packet.roundId~=roundId then return nil end
    return {x=second and packet.x2 or packet.x,y=second and packet.y2 or packet.y,
        buttons=packet.suspended and 0 or (second and packet.buttons2 or packet.buttons),
        sequences=second and packet.sequences2 or packet.sequences,suspended=packet.suspended}
end
return Actions
