local Test={}
function Test.run(R,check)
    local state,p=R.state,R.World.player
    state.screen="world"
    local laptop=assert(require("src.home_layouts").targets(p,state).computer)
    p.x,p.y=laptop.x,laptop.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,laptop.hoverX,laptop.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen
    check("home_guide_runtime_laptop_opens_household",state.screen=="computer" and screen.tab=="home")
    local x,y=screen.homeControlCenter("guide");screen.mousepressed(state,x,y,1)
    x,y=screen.homeGuideControlCenter("topic",3);screen.mousepressed(state,x,y,1)
    local funds=state.home.balanceCents;local count=#state.home.shopping.orders
    x,y=screen.homeGuideControlCenter("action");screen.mousepressed(state,x,y,1)
    check("home_guide_runtime_furniture_link_browses_without_ordering",screen.tab=="furniture"
        and state.home.balanceCents==funds and #state.home.shopping.orders==count)
    R.App.keypressed("escape")
    check("home_guide_runtime_close_returns_to_apartment",state.screen=="world" and p.sceneId=="home")
end
return Test
