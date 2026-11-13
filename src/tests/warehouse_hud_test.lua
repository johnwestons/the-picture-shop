local Hud=require('src.screens.warehouse_hud')
local Notices=require('src.notifications')
local Screen=require('src.screens.notifications_screen')
local Visibility=require('src.screens.hud_visibility')
local State=require('src.state')
local Settings=require('src.settings')
local Test={}
local function center(r)return r.x+r.width/2,r.y+r.height/2 end

function Test.run(_,check)
    local R={state=State.new(),World={player={sceneId='warehouse'}},
        App={settings=Settings.normalize()},Config=require('src.config')}
    R.state.screen='world'
    R.optionsAccessLayout=function()return 'world',nil end
    R.openOptions=function()R.state.screen='options';return true end
    R.returnToTitle=function()R.state.screen='title';return true end
    Hud.menuOpen=false;Hud.noticesExpanded=true

    local layout=Hud.layout()
    local x,y=center(layout.menu)
    check('warehouse_menu_icon_opens_dropdown',Hud.menuPointer(R,x,y,1) and Hud.menuOpen)
    x,y=center(Hud.menuRow(layout,1))
    check('warehouse_menu_options_opens_options',Hud.menuPointer(R,x,y,1)
        and R.state.screen=='options' and not Hud.menuOpen)
    R.state.screen='world';x,y=center(layout.menu);Hud.menuPointer(R,x,y,1)
    x,y=center(Hud.menuRow(layout,2))
    check('warehouse_menu_exit_returns_to_title',Hud.menuPointer(R,x,y,1)
        and R.state.screen=='title' and not Hud.menuOpen)
    R.state.screen='world';x,y=center(layout.menu);Hud.menuPointer(R,x,y,1)
    x,y=center(Hud.menuRow(layout,3))
    check('warehouse_menu_hides_hud',Hud.menuPointer(R,x,y,1) and not Visibility.isVisible(R))
    x,y=center(layout.menu);Hud.menuPointer(R,x,y,1)
    x,y=center(Hud.menuRow(layout,3))
    check('warehouse_menu_restores_hidden_hud',Hud.menuPointer(R,x,y,1) and Visibility.isVisible(R))

    local saved=Notices.add(R.state,'shop','JOB READY','Pallets await delivery','Load the truck.')
    x,y=center(layout.noticeToggle)
    check('warehouse_notice_preview_collapses',Screen.pointer(R,x,y,1)
        and not Hud.noticesExpanded and R.state.screen=='world')
    Screen.pointer(R,x,y,1)
    check('warehouse_notice_preview_expands',Hud.noticesExpanded)
    x,y=center(layout.noticeIcon)
    check('warehouse_notice_icon_opens_clipboard',Screen.pointer(R,x,y,1)
        and R.state.screen=='notifications' and R.state.notificationSelection==saved.id)
    Screen.close(R)

    local wide=Hud.layout({left=-254,right=1214})
    check('warehouse_wide_header_hides_stock_counts_and_keeps_calendar_clock_menu_separate',
        wide.paper==nil and wide.samples==nil
        and wide.cash.x+wide.cash.width<wide.calendar.x
        and wide.calendar.x+wide.calendar.width<wide.week.x
        and wide.clock.x+wide.clock.width<wide.menu.x
        and wide.noticePanel.x+wide.noticePanel.width<wide.menuPanel.x)
    R.World.player.sceneId='commute'
    local ride=Hud.layoutFor(R,{left=0,right=960})
    check('terrain_shared_header_combines_balances_and_keeps_calendar_clear',
        ride.cash.width>=350 and ride.cash.x+ride.cash.width<ride.calendar.x
        and ride.calendar.x+ride.calendar.width<ride.week.x
        and ride.clock.x+ride.clock.width<ride.menu.x
        and ride.noticePanel.x+ride.noticePanel.width<642)
    x,y=center(ride.menu)
    check('terrain_shared_menu_opens',Hud.menuPointer(R,x,y,1,{left=0,right=960})
        and Hud.menuOpen)
    x,y=center(Hud.menuRow(ride,1))
    check('terrain_shared_menu_options_opens_options',Hud.menuPointer(R,x,y,1,{left=0,right=960})
        and R.state.screen=='options')
    R.state.screen='world';x,y=center(ride.noticeIcon)
    check('terrain_shared_notice_opens_clipboard',Screen.pointer(R,x,y,1)
        and R.state.screen=='notifications')
    Screen.close(R)
    Hud.menuOpen=false;Hud.noticesExpanded=true
end
return Test
