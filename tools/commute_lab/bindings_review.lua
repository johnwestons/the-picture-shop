local Review={}
function Review.install()
    local screen,index,waiting
    local pages={'keyboard','mouse','controller','touch','layout','capture'}
    function love.load()
        local count=0
        require('src.commute.tests.bindings_test').run(function(name,okay)assert(okay,name);count=count+1;print('PASS '..name)end)
        print('MOTORCYCLE_BINDINGS_OK '..count..' checks; preferences mocked, no game saves accessed')
        if not os.getenv('PICTURE_SHOP_BINDINGS_CAPTURE') then love.event.quit(0);return end
        love.window.setMode(960,678,{resizable=false,vsync=0})
        screen=require('src.commute.controls_screen').new({},function()return true end,function()end)
        index=1
    end
    function love.draw()
        if not screen then return end
        local page=pages[index];screen.device=(page=='layout' and 'touch' or page=='capture' and 'controller' or page)
        screen.layout=page=='layout';screen.capture=page=='capture' and 'accelerate' or nil
        screen:draw()
        if waiting then return end;waiting=true
        love.graphics.captureScreenshot(function(data)
            local bytes=data:encode('png');local file=assert(io.open(os.getenv('PICTURE_SHOP_BINDINGS_CAPTURE')..'/controls-'..page..'.png','wb'))
            file:write(bytes:getString());file:close();print('CAPTURE controls-'..page)
            index=index+1;waiting=false
            if index>#pages then screen=nil;love.event.quit(0) end
        end)
    end
end
return Review
