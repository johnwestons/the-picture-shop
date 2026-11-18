function love.conf(t)
 t.identity='the-picture-shop-test-enet-throttle'
 t.window=nil
 for _,name in ipairs({'window','graphics','audio','sound','joystick','mouse','keyboard','touch','video','physics'})do t.modules[name]=false end
end
