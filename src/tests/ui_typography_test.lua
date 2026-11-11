local Test={}
function Test.run(_,check)
    local Text=require('src.screens.typography')
    local utf8=require('utf8')
    local font,fits=Text.fit('A very long client company name',18,70,24,'bold',14)
    check('ui_text_never_squeezes_below_readable_floor',Text.size(font)==14 and not fits)
    local value='Müller · Café — Christmas deliveries'
    local clipped=Text.ellipsize(value,120,font)
    check('ui_text_truncation_preserves_utf8_and_bounds',utf8.len(clipped) and font:getWidth(clipped)<=120)
    local lines,height,f=Text.lines('One line\nAnother line',300,16)
    check('ui_wrapped_text_reserves_actual_line_spacing',#lines==2 and height==f:getHeight()*(1+f:getLineHeight()))
    local legacy=love.graphics.newFont(16)
    check('ui_new_screens_use_baseline_font_metrics',Text.get(16):getWidth('CritterNet')==legacy:getWidth('CritterNet')
        and Text.get(16):getLineHeight()==legacy:getLineHeight())
    legacy:release()
    local function luminance(color)
        local function linear(v)return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
        return .2126*linear(color[1])+.7152*linear(color[2])+.0722*linear(color[3])
    end
    for _,role in ipairs({'body','muted','accent','warning'}) do
        check('ui_panel_text_contrast_'..role,(luminance(Text.colors[role])+.05)/(luminance(Text.colors.panel)+.05)>=4.5)
    end
end
return Test
