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
    check('ui_typewriter_has_navigation_symbol_fallbacks',Text.get(16):hasGlyphs('←→↑↓ · $ %'))
    local status=require('src.screens.player_status')
    local wealth={money=123456789.12,home={balanceCents=98765432100}}
    local balances=status.moneyText(wealth,318,Text.get(14,'bold'))
    check('ui_large_balances_keep_both_accounts_visible',balances:find('Home',1,true) and balances:find('Shop',1,true)
        and Text.get(14,'bold'):getWidth(balances)<=318)
    local function luminance(color)
        local function linear(v)return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
        return .2126*linear(color[1])+.7152*linear(color[2])+.0722*linear(color[3])
    end
    for _,role in ipairs({'body','muted','accent','warning'}) do
        check('ui_panel_text_contrast_'..role,(luminance(Text.colors[role])+.05)/(luminance(Text.colors.panel)+.05)>=4.5)
    end
end
return Test
