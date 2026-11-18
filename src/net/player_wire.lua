-- Fixed-layout wire projection only. Public player records retain their named
-- fields, full numeric precision and the existing validation rules.
local Codec=require('src.net.codec')
local Binary=require('src.net.prediction_wire')
local Wire={}
local motionFields={'x','y','velocityX','velocityY','intentX','intentY','animationDistance'}
local fields={'id','name','sceneId','resting','taskAction','motion','moving','facing','character',
    'furColorway','overallsColorway','inputSequence'}
Wire.COUNT=#fields
function Wire.pack(record)
    local motion={}
    for index,key in ipairs(motionFields)do motion[index]=record[key]end
    local bytes,err=Binary.pack(motion)
    if not bytes then return nil,err end
    local values={}
    for index,key in ipairs(fields)do
        values[index]=key=='motion'and bytes or key=='taskAction'and(record[key]or'none')or record[key]
    end
    return Codec.array(values)
end
function Wire.unpack(values)
    if not Codec.isArray(values)or #values~=Wire.COUNT then return nil end
    local count=0
    for key in pairs(values)do
        if type(key)~='number'or key%1~=0 or key<1 or key>Wire.COUNT then return nil end
        count=count+1
    end
    if count~=Wire.COUNT then return nil end
    local motion=Binary.unpack(values[6],#motionFields)
    if not motion then return nil end
    local record={}
    for index,key in ipairs(fields)do if key~='motion'then record[key]=values[index]end end
    for index,key in ipairs(motionFields)do record[key]=motion[index]end
    return record
end
return Wire
