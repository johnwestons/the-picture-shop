local Colorways=require('src.rabbit_colorways')

local Test={}

function Test.run(check)
    local source=Colorways.blendShaderSource()
    local guard=source:find('#ifdef PIXEL',1,true)
    local fur=source:find('extern vec3 furTint;',1,true)
    local overalls=source:find('extern vec3 overallsTint;',1,true)
    local helper=source:find('vec4 applyRabbitColorways',1,true)
    local close=source:match('()#endif%s*$')
    check('rabbit_colorways_uniforms_are_fragment_stage_only',guard~=nil and fur~=nil and overalls~=nil
        and guard<fur and fur<overalls and close~=nil and close>overalls)
    check('rabbit_colorways_fragment_helper_stays_inside_stage_guard',helper~=nil and helper>guard and close>helper
        and source:find('vec4 effect',1,true)==nil)
end

return Test
