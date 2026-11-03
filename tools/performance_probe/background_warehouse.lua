return function(runtime,app,rows,output)
    local checks={}
    require("src.tests.background_warehouse_test").run({},function(name,okay,detail)
        checks[#checks+1]={name=name,pass=not not okay,detail=detail};assert(okay,name..": "..tostring(detail))
    end)
    require("src.tests.support.background_warehouse_fixture").verify(runtime,function(name,okay,detail)
        checks[#checks+1]={name=name,pass=not not okay,detail=detail};assert(okay,name..": "..tostring(detail))
    end,rows)
    local file=assert(io.open(output.."/background-checks.json","wb"))
    file:write(require("tools.performance_probe.json")(checks));file:close()
    for _,row in ipairs(rows) do if row.world_steps then
        print(string.format("BACKGROUND %s mean=%.3f p95=%.3f max=%.3f worldsteps=%d cut=%s wage=%.6f",
            row.mode,row.mean_ms,row.p95_ms,row.max_ms,row.world_steps,tostring(row.first_finished_seconds),row.earned_cents))
    end end
end
