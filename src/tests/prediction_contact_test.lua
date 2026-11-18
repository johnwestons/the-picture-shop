local Test={}
function Test.run(check)
    local P=require('src.commute.prediction')
    local Rider=require('src.commute.rider')
    local Bike=require('src.commute.motorcycle')
    local Truck=require('src.commute.delivery_truck')
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local Copy=require('src.net.shop_replication').copy
    local state=require('src.state').new()
    local world={height=function()return 0 end,supportHeight=function()return 0,'road'end,
        roads={sample=function()return 0,{width=40}end,nearest=function()return 0,{width=40}end,
            blocked=function()return false end}}
    local rider=Rider.new(103.5,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    local part={slot=1,arrived=false,rider=rider}
    local truck=Truck.new(105,100,math.pi*.5);truck.engine=false
    state.home.commute={version=1,token=51,independent=true,participants={owner=part},truck=truck}
    rider.bike.speed=8;rider.bike.damage=9
    Bike.resetHorizontal(rider.bike);Bike.resetContact(rider.bike,world)
    rider.bike.collisionContact=true;rider.bike.collisionKind='deliveryTruck';rider.bike.collisionId='player-truck-box'
    local snapshot=P.capture(part,51)
    check('prediction_active_bike_contact_captures_exact_obstacle_identity',snapshot.contact
        and snapshot.contact.kind=='deliveryTruck' and snapshot.contact.id=='player-truck-box')
    snapshot.contact.id='copied-contact'
    check('prediction_contact_checkpoint_does_not_alias_authoritative_body',rider.bike.collisionId=='player-truck-box')
    snapshot=P.capture(part,51)
    local changed=Copy(snapshot);changed.contact.id='different-truck'
    local kind=Copy(snapshot);kind.contact.kind='guardrail'
    local missing=Copy(snapshot);missing.contact=nil
    check('prediction_active_contact_identity_difference_forces_authoritative_restore',
        not P.matches(snapshot,changed) and not P.matches(snapshot,kind) and not P.matches(snapshot,missing))
    rider.bike.collisionId=17
    local numeric=P.capture(part,51);local text=Copy(numeric);text.contact.id='17'
    check('prediction_contact_identity_does_not_coerce_numeric_and_string_ids',not P.matches(numeric,text))
    rider.bike.collisionId=nil
    check('prediction_contact_retains_nil_identifier',P.capture(part,51).contact.id==nil)
    rider.bike.collisionId='player-truck-box'

    -- Exercise capture -> real wire -> session assembly -> physics restore.
    local received
    local host=Session.new();host.sessionId='contact-check';host.serverTick=6;host.idToPeer[1]={}
    host._send=function(_,_,message,payload)
        local packet,err=Protocol.encode(message,payload)
        if not packet then return false,err end
        received=assert(Protocol.decode(packet)).payload
        return true
    end
    host:_sendPredictionSnapshot({id=1,inputSequence=10,_commandStream=true},
        {getPredictionSnapshot=function()return P.capture(part,51)end})
    local client=Session.new();client.ready=true;client.localId=1;client.sessionId='contact-check'
    client:_acceptPredictionSnapshot(assert(received))
    check('prediction_contact_survives_host_wire_and_client_checkpoint_assembly',
        P.matches(snapshot,client.physicsPredictionSnapshot)
        and client.physicsPredictionSnapshot.contact.id=='player-truck-box')

    local player={id=1,homeResidentId='owner'}
    local reference={id=1,homeResidentId='owner'}
    P.ensure(player,part,51).rider.bike.collisionKind='tree'
    player._predictedCommute.rider.bike.collisionId='previous-tree'
    assert(P.restore(player,part,51,client.physicsPredictionSnapshot))
    P.step(reference,part,51,1/60,0,-.15,false,world,state)
    P.step(player,part,51,1/60,0,-.15,false,world,state)
    local body=player._predictedCommute.rider.bike
    check('prediction_continuing_authoritative_contact_does_not_charge_duplicate_damage_or_impact',
        P.matches(P.captureLocal(reference),P.captureLocal(player)) and body.damage==9 and body.impactPulse==0,
        'damage='..body.damage..' impact='..body.impactPulse)

    -- A different collider must still count as a new impact, even when every
    -- scalar in the incoming checkpoint is identical to the old contact.
    local other=Copy(snapshot);other.contact.id='different-truck'
    assert(P.restore(player,part,51,other))
    P.step(player,part,51,1/60,0,-.15,false,world,state)
    check('prediction_different_contact_still_applies_new_collision_damage',
        player._predictedCommute.rider.bike.damage>9 and player._predictedCommute.rider.bike.impactPulse>0)

    assert(P.restore(player,part,51,missing))
    check('prediction_absent_contact_clears_previous_private_identity',
        player._predictedCommute.rider.bike.collisionKind==nil and player._predictedCommute.rider.bike.collisionId==nil)
    rider.bike.collisionContact=false
    local inactive=P.capture(part,51);local stale=Copy(inactive)
    stale.contact={kind='previous',id='stale'}
    check('prediction_inactive_contact_omits_identity_and_ignores_stale_identity_in_match',
        inactive.contact==nil and P.matches(inactive,stale))
    rider.vehicle='truck';rider.truck=truck
    check('prediction_truck_checkpoint_never_carries_parked_bike_contact',P.capture(part,51).contact==nil)
end
return Test
