-- Fixed-duration commands make an acknowledgement mean "simulated through this
-- input", rather than merely "the host has received this direction".
local Component={}
local STEP=1/60
local Commands=require('src.net.movement_commands')
local MAX_HISTORY=240
-- Sub-second gaps can recover their exact commands. Longer outages abandon old
-- controls and keep neutral physics alive instead of building a stale backlog.
local RECOVERY_SECONDS=1
local function axis(value)
    value=math.max(-1,math.min(1,tonumber(value) or 0))
    return math.floor(value*1000+.5)
end
function Component.install(Runtime)
    Runtime.COMMAND_STEP=STEP
    function Runtime.Session:_sendPredictionSnapshot(player,context)
        local peer=self.idToPeer[player.id]
        if not peer or not player._commandStream or not context or not context.getPredictionSnapshot then return end
        local snapshot=context.getPredictionSnapshot(player)
        if not snapshot then return end
        local P=require('src.commute.prediction')
        for part=1,math.ceil(#snapshot.values/P.PART_VALUES) do
            local values=Runtime.Codec.array({})
            for i=(part-1)*P.PART_VALUES+1,math.min(part*P.PART_VALUES,#snapshot.values) do values[#values+1]=snapshot.values[i] end
            local okay,err=self:_send(peer,'prediction_snapshot',{sessionId=self.sessionId,serverTick=self.serverTick,
                playerId=player.id,sequence=player.inputSequence or 0,key=snapshot.key,mode=snapshot.mode,part=part,values=values,
                contact=part==1 and snapshot.contact or nil})
            if not okay then self:_queue('error',{message=err}) end
        end
    end

    function Runtime.Session:_acceptPredictionSnapshot(payload)
        if not self.ready or payload.sessionId~=self.sessionId or payload.playerId~=self.localId
            or payload.serverTick<=(self.lastPhysicsPredictionTick or -1) then return end
        local assembly=self.physicsAssembly
        if not assembly or payload.serverTick>assembly.serverTick then
            assembly={serverTick=payload.serverTick,sequence=payload.sequence,key=payload.key,mode=payload.mode,parts={}}
            self.physicsAssembly=assembly
        end
        if assembly.serverTick~=payload.serverTick or assembly.sequence~=payload.sequence
            or assembly.key~=payload.key or assembly.mode~=payload.mode then return end
        assembly.parts[payload.part]=payload.values
        if payload.part==1 then assembly.contact=payload.contact end
        local P=require('src.commute.prediction');local values={}
        for part=1,math.ceil(#P.fields[assembly.mode]/P.PART_VALUES) do
            if not assembly.parts[part] then return end
            for _,value in ipairs(assembly.parts[part]) do values[#values+1]=value end
        end
        self.physicsPredictionSnapshot={serverTick=assembly.serverTick,sequence=assembly.sequence,
            key=assembly.key,mode=assembly.mode,values=values,contact=assembly.contact}
    end
    function Runtime.Session:_queueMovementCommands(player,payload,context)
        if not payload.commands then
            player._commandStream=false;player._commandQueue=nil;player._commandBudget=0
            player._commandOutage=nil
            player.inputSequence=payload.sequence
            return
        end
        local key=context and context.predictionKey and context.predictionKey(player)
        if not key or key~=payload.commandKey then
            player._commandStream=key~=nil;player._commandQueue={}
            player.inputSequence=payload.sequence;player._lastQueuedCommand=payload.sequence
            return
        end
        local frames=type(payload.commands)=='string' and Commands.unpack(payload.commands) or payload.commands
        if not frames then return end
        if not player._commandStream or player._commandKey~=key then
            player._commandQueue={};player._lastQueuedCommand=player.inputSequence or 0
            player._commandBudget=math.min(RECOVERY_SECONDS,math.max(0,self.clock()-(player.lastInputAt or self.clock())))
            player._commandOutage=nil
        end
        player._commandStream=true;player._commandKey=key
        local queue=player._commandQueue
        local first=payload.sequence-#frames+1
        if player._commandOutage then
            -- After a long outage the host has continued neutral physics. Do
            -- not play seconds of stale throttle/steering after reconnection.
            player._commandOutage=nil;player._commandQueue={};queue=player._commandQueue
            player._lastQueuedCommand=math.max(player._lastQueuedCommand or 0,payload.sequence-3)
            player.inputSequence=math.max(player.inputSequence or 0,player._lastQueuedCommand)
            player._commandBudget=math.min(player._commandBudget or 0,3*STEP)
        end
        for index,frame in ipairs(frames) do
            local sequence=first+index-1
            if sequence>(player._lastQueuedCommand or 0) then
                queue[#queue+1]={sequence=sequence,x=frame[1]/1000,y=frame[2]/1000,boost=frame[3]==1}
                player._lastQueuedCommand=sequence
            end
        end
        -- A stalled or abusive sender cannot accumulate unbounded work.
        while #queue>MAX_HISTORY do table.remove(queue,1) end
    end

    function Runtime.Session:_stepRemoteCommands(player,dt,context)
        local key=context and context.predictionKey and context.predictionKey(player)
        if key~=player._commandKey then
            player._commandQueue={};player._commandBudget=0
            return
        end
        player._commandBudget=math.min(RECOVERY_SECONDS,(player._commandBudget or 0)+dt)
        local queue=player._commandQueue or {}
        local steps=0
        -- A fixed four-step cap permanently falls behind below 15 host FPS.
        -- Cover elapsed simulation time plus a little recovery work, while
        -- retaining the normal four-step limit and a hard 250ms work ceiling.
        local maxSteps=math.max(4,math.min(15,math.ceil(math.max(0,dt)/STEP-1e-8)+3))
        while #queue>0 and player._commandBudget+1e-8>=STEP and steps<maxSteps do
            local command=table.remove(queue,1)
            if context and context.moveRemote then
                context.moveRemote(player,STEP,command.x,command.y,command.boost)
            end
            player.inputSequence=command.sequence
            player._commandBudget=math.max(0,player._commandBudget-STEP)
            steps=steps+1
        end
        -- A connection outage must not suspend gravity, rolling or braking.
        -- These neutral steps do not acknowledge any unseen input commands.
        if #queue==0 and self.clock()-(player.lastInputAt or 0)>=RECOVERY_SECONDS then
            if not player._commandOutage then
                player._commandOutage=true
                player._commandBudget=math.min(player._commandBudget,math.max(0,dt))
            end
            if context and context.requiresPhysicsPrediction and context.requiresPhysicsPrediction(player) then
                while player._commandBudget+1e-8>=STEP and steps<maxSteps do
                    context.moveRemote(player,STEP,0,0,false)
                    player._commandBudget=math.max(0,player._commandBudget-STEP);steps=steps+1
                end
            else player._commandBudget=math.min(player._commandBudget,STEP) end
        end
    end

    function Runtime.Session:_updateClientPrediction(dt,context)
        local player=context and context.localPlayer
        local key=context and context.predictionEnabled~=false and player
            and context.predictionKey and context.predictionKey(player)
        if not key or not context.predictLocal then
            self.commandPrediction=nil
            self.commandPredictionActive=false
            if player then player._movementPredicted=false;player._predictedCommute=nil end
            return
        end
        local prediction=self.commandPrediction
        if not prediction or prediction.key~=key then
            prediction={key=key,history={},accumulator=0}
            self.commandPrediction=prediction
        end
        self.commandPredictionActive=true
        self.predictedPlayer=player
        player._movementPredicted=true
        local target=self.localTarget
        local tick=self.lastPlayerTicks[self.localId] or -1
        local physics=context.requiresPhysicsPrediction and context.requiresPhysicsPrediction(player)
        local checkpoint=physics and self.physicsPredictionSnapshot
        local acknowledged,matched
        local beforeX,beforeY=player.x,player.y
        if checkpoint and checkpoint.serverTick>(self.lastPhysicsPredictionTick or -1)
            and checkpoint.key==key and context.restorePhysicsPrediction then
            local P=require('src.commute.prediction')
            local predicted=prediction.ackSequence==checkpoint.sequence and prediction.ackCheckpoint or nil
            if not predicted then
                for _,command in ipairs(prediction.history)do
                    if command.sequence==checkpoint.sequence then predicted=command.checkpoint;break end
                end
            end
            matched=P.matches(predicted,checkpoint)
            if not matched then
                matched=P.reconcileSharedTruckFuel(player,prediction.history,predicted,checkpoint)
            end
            if matched or context.restorePhysicsPrediction(checkpoint) then
                acknowledged=checkpoint.sequence
                prediction.ackSequence=acknowledged
                prediction.ackCheckpoint=matched and predicted or checkpoint
                self.lastPhysicsPredictionTick=checkpoint.serverTick
                self.lastPredictionTick=checkpoint.serverTick
            end
        elseif not physics and target and tick>(self.lastPredictionTick or -1) then
            local targetKey=context.predictionKey(target)
            if targetKey~=key then
                Runtime.copyMotion(player,target,true)
                self.commandPrediction=nil;self.commandPredictionActive=false
                player._movementPredicted=false
                self.lastPredictionTick=tick
                return
            end
            Runtime.copyMotion(player,target,true)
            acknowledged=target.inputSequence or 0
            self.lastPredictionTick=tick
        end
        if acknowledged then
            local pending={}
            for _,command in ipairs(prediction.history) do
                if command.sequence>acknowledged then
                    if not matched then
                        context.predictLocal(STEP,command.x,command.y,command.boost,true)
                        if physics then command.checkpoint=require('src.commute.prediction').captureLocal(player)end
                    end
                    pending[#pending+1]=command
                end
            end
            prediction.history=pending
            self.lastPredictionCorrection=math.sqrt((player.x-beforeX)^2+(player.y-beforeY)^2)
        end
        prediction.accumulator=math.min(.25,prediction.accumulator+dt)
        local x,y=axis(context.inputX),axis(context.inputY)
        local boost=context.inputBoost==true
        while prediction.accumulator+1e-8>=STEP do
            prediction.accumulator=math.max(0,prediction.accumulator-STEP)
            self.inputSequence=self.inputSequence+1
            local command={sequence=self.inputSequence,x=x/1000,y=y/1000,boost=boost}
            prediction.history[#prediction.history+1]=command
            context.predictLocal(STEP,command.x,command.y,boost,false)
            if physics then command.checkpoint=require('src.commute.prediction').captureLocal(player)end
        end
        while #prediction.history>MAX_HISTORY do table.remove(prediction.history,1) end
    end

    function Runtime.Session:_movementCommandBatch()
        local prediction=self.commandPrediction
        if not self.commandPredictionActive or not prediction or #prediction.history==0 then return nil end
        return Commands.pack(prediction.history),prediction.key
    end
end
return Component
