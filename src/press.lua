local Press = { step = "idle", progress = 0, cycleTime = 2.4, sheets = 0 }
function Press.reset(state) Press.step, Press.progress, Press.sheets = "idle", 0, 0; if state then state.message = "Picture press ready. Press L to run the rollers." end end
function Press.start(state) if Press.step ~= "idle" and Press.step ~= "finished" then return false end; Press.step, Press.progress = "printing", 0; Press.sheets = Press.sheets + 1; if state then state.message = "Picture press running: feeding, inking, and delivering a finished sheet." end; return true end
function Press.update(dt) if Press.step == "printing" then Press.progress = Press.progress + dt; if Press.progress >= Press.cycleTime then Press.progress, Press.step = Press.cycleTime, "finished" end end end
function Press.keypressed(key, state) if key == "l" or key == "space" or key == "enter" then return Press.start(state) end; if key == "r" then Press.reset(state); return true end; return false end
return Press
