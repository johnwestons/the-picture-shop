function love.load()
    local count=0
    local function check(name,okay,detail)
        assert(okay,name..': '..(detail or 'failed'));count=count+1
        print('PASS '..name..' '..(detail or ''))
    end
    local tests=require('src.commute.tests.truck_braking_test')
    tests.run(check)
    require('src.commute.tests.kei_steering_test').run(check)
    local root=os.getenv('TRUCK_BRAKING_REVIEW_ROOT')
    local beforeFile=root..'/output/truck-braking-review/before_truck.lua'
    local file=io.open(beforeFile,'r')
    if file then
        file:close()
        local before=assert(loadfile(beforeFile))()
        local current=require('src.commute.delivery_truck')
        for _,model in ipairs({'box','kei'}) do
            local old=tests.stop(model,nil,before)
            local new=tests.stop(model)
            print(('STOP_40_KMH %s: %.2fm / %.2fs -> %.2fm / %.2fs'):format(
                model,old.distance,old.time,new.distance,new.time))
            local oldSlip=tests.stop(model,{slip=.2},before)
            local newSlip=tests.stop(model,{slip=.2})
            print(('LATERAL_DRIFT %s: %.3fm -> %.3fm'):format(model,oldSlip.drift,newSlip.drift))
            for _,axis in ipairs({0,-1}) do
                local a=before.new(256,256,0,'plain',model)
                local b=current.new(256,256,0,'plain',model)
                a.speed,b.speed=8,8
                for _=1,120 do
                    before.update(a,{drive=axis,steer=.35},1/120,tests.world())
                    current.update(b,{drive=axis,steer=.35},1/120,tests.world())
                end
                check(model..'_nonbraking_motion_unchanged_'..axis,
                    math.abs(a.x-b.x)+math.abs(a.z-b.z)+math.abs(a.heading-b.heading)
                        +math.abs(a.speed-b.speed)<1e-9)
            end
        end
    end
    print(('TRUCK_BRAKING_REVIEW_OK: %d checks'):format(count))
    love.event.quit()
end
function love.errorhandler(message)
    print(debug.traceback(tostring(message),2));return function()return 1 end
end
