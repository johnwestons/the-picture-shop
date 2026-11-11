-- Approved job-desk layout: real render/input checks, including overflow tickets.
local Test = {}
function Test.run(context, check)
    local Jobs = require('src.jobs')
    local Fonts = require('src.screens.computer.fonts')
    local screen = context.computerScreen.new()
    local state = context.State.new()
    for index = 1, 6 do
        local job = assert(Jobs.createOffer({id='REVIEW-'..index,company='Millhaven Community Theatre',
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500,500,500}}))
        Jobs.accept(job); job.status='in_production'; job.delivery={status='received'}
        state.jobs.active[index] = job
    end
    screen.enter(state)
    local selected = screen.mousepressed(state,257,498,1)
    check('job_review_fifth_row_click_matches_visible_card',selected and selected.job.id=='REVIEW-5')
    local page = screen.mousepressed(state,360,567,1)
    check('job_review_next_inside_browser_reaches_sixth_job',page and page.action=='page' and screen.selectedJobId=='REVIEW-6')
    page = screen.mousepressed(state,152,567,1)
    check('job_review_previous_inside_browser_returns_first_job',page and page.action=='page' and screen.selectedJobId=='REVIEW-1')
    local job = state.jobs.active[1]
    local layout = screen.jobDetailLayout(job,state)
    check('job_review_three_pallet_ticket_fits_without_scroll',layout.scrollMax==0 and layout.tableBottom<layout.actionTop)
    check('job_review_values_use_larger_typewriter_and_labels_sans',
        layout.valueFont==Fonts.get('typewriter',15) and layout.labelFont==Fonts.get('sans',13))
    local partial = screen.jobDetailLayout({sourceSize={width=10,height=15},finishedSize={width=7,height=10},
        packaging='boxed',quote={totalSheets=1500},pallets={{number=1},{number=2},{number=3},{number=4},{number=5}}})
    check('job_review_partial_layout_fixture_is_supported',partial.tableBottom>partial.tableY)
    for i, row in ipairs(layout.rows) do
        local _, lines = layout.valueFont:getWrap(row.value or row.text,row.width-row.labelWidth)
        check('job_review_wrapping_matches_render_font_'..i,row.height==#lines*layout.valueFont:getHeight()
            and (not layout.rows[i+1] or row.y+row.height<layout.rows[i+1].y))
    end
    local g = love.graphics
    local originalFont, printText, printWrapped, drawImage = g.getFont(), g.print, g.printf, g.draw
    local seen = {}
    local draws = {}
    local function remember(text,x,y)
        if type(text)=='string' then seen[text]={font=g.getFont(),x=x,y=y} end
    end
    local canvas = g.newCanvas(960,678)
    g.push('all'); g.setCanvas({canvas,stencil=true});g.origin();g.clear()
    g.print=function(text,x,y,...) remember(text,x,y);return printText(text,x,y,...) end
    g.printf=function(text,x,y,...) remember(text,x,y);return printWrapped(text,x,y,...) end
    g.draw=function(image,...)
        if image==context.assets.images.critterNetSprites then
            local args={...};draws[#draws+1]={quad=args[1],x=args[2],y=args[3],sx=args[5],sy=args[6]}
        end
        return drawImage(image,...)
    end
    local okay, err = xpcall(function()screen.draw(state,nil,nil,context.assets,true)end,debug.traceback)
    local afterFont=g.getFont()
    g.print,g.printf,g.draw=printText,printWrapped,drawImage;g.pop();canvas:release()
    assert(okay,err)
    check('job_review_keeps_url_and_job_id_font',seen['www.thecritternet.com/job-desk/active'].font==originalFont
        and seen['REVIEW-1'].font==originalFont)
    check('job_review_types_header_and_preserves_balance_font',seen['PICTURE SHOP JOB DESK'].font==Fonts.get('typewriter',14)
        and seen['CASH'].font==Fonts.get('typewriter',14)
        and seen[require('src.screens.ui').money(state.money)].font==originalFont)
    check('job_review_metric_labels_lowered_inside_green_bar',seen['CASH'].y==42 and seen['A/R'].y==42 and seen['REP'].y==42)
    local displayDate='THURSDAY, JANUARY 1, 2026'
    local timeText=require('src.business_calendar').timeText(state,true)
    local displayedDate, displayedTime=seen[displayDate],seen[timeText]
    check('job_review_clock_has_full_weekday_date_and_time',displayedDate and displayedTime
        and displayedDate.font==displayedTime.font and displayedDate.font:getHeight()>=15
        and displayedDate.x>=536 and displayedDate.x+displayedDate.font:getWidth(displayDate)
            < displayedTime.x and displayedTime.x+displayedTime.font:getWidth(timeText)<=861)
    local sprite=draws[1]
    check('job_review_three_paw_animation_covers_toolbar',sprite and sprite.y==58
        and sprite.x>=685 and sprite.x<=708 and sprite.sx*384>=159 and sprite.sx*384<=179
        and math.abs(sprite.sy*256-88)<0.01)
    local getTime=love.timer.getTime
    local frames={}
    g.draw=function(image,...)
        if image==context.assets.images.critterNetSprites then
            local args={...};frames[#frames+1]={quad=args[1],x=args[2],width=args[5]*384}
        end
        return drawImage(image,...)
    end
    local animationOkay, animationError=xpcall(function()
        local buffer=g.newCanvas(960,678)
        g.push('all');g.setCanvas({buffer,stencil=true})
        for _,time in ipairs({0,0.3,0.6,0.9}) do
            love.timer.getTime=function() return time end
            screen.draw(state,nil,nil,context.assets,true)
        end
        g.pop();buffer:release()
    end,debug.traceback)
    g.draw=drawImage;love.timer.getTime=getTime
    assert(animationOkay,animationError)
    check('job_review_three_paw_sprite_animates_between_frames',#frames==4
        and frames[1].quad~=frames[2].quad and frames[2].quad~=frames[3].quad
        and frames[3].quad~=frames[4].quad)
    local sourceCenters={{97,321.5},{99,302},{78,277},{52,260}}
    local aligned=#frames==4
    for index, frame in ipairs(frames) do
        local source=sourceCenters[index]
        local left=frame.x+frame.width*source[1]/384
        local right=frame.x+frame.width*source[2]/384
        aligned=aligned and math.abs(left-731)<=3 and math.abs(right-824)<=3
    end
    check('job_review_every_animation_frame_aligns_with_baked_paws',aligned)
    check('job_review_does_not_leak_font_to_other_ui',afterFont==originalFont)
    check('job_review_removes_overlay_back_label',not seen.BACK)
    job.stockSpec={description=string.rep('Heavy uncoated customer stock with special handling. ',6)}
    job.spoiledSheets=75;job.spoilCost=20;job.replacementSkids=1;job.replacementSheets=500
    job.press={colors=4,colorSequence={'Warm Red','Process Blue','Metallic Gold','Black'},actual={impressions=1575,spoilage=75}}
    layout=screen.jobDetailLayout(job,state)
    check('job_review_long_ticket_has_bounded_scroll',layout.scrollMax>0 and layout.viewBottom<layout.actionTop)
    local changed=screen.mousepressed(state,530,522,1)
    check('job_review_touch_down_scrolls_ticket',changed and changed.action=='job_scroll' and screen.jobScroll>0)
    for _=1,40 do screen.wheelmoved(state,0,-1) end
    layout=screen.jobDetailLayout(job,state)
    check('job_review_scroll_reaches_final_pallet_without_covering_action',layout.scroll==layout.scrollMax
        and layout.tableBottom-layout.scroll+4<=layout.viewBottom)
    changed=screen.mousepressed(state,458,522,1)
    check('job_review_touch_up_scrolls_ticket',changed and changed.action=='job_scroll' and screen.jobScroll<layout.scrollMax)
    local actionX,actionY=screen.completeCenter()
    local action=screen.mousepressed(state,actionX,actionY,1)
    check('job_review_action_stays_clickable_while_scrolled',action and action.action=='completion_blocked')
    screen.mousepressed(state,257,300,1)
    layout=screen.jobDetailLayout(state.jobs.active[2],state)
    check('job_review_selecting_other_job_resets_scroll',screen.selectedJobId=='REVIEW-2' and layout.scroll==0)
    local completed=require('src.screens.gui_projection').copy(state.jobs.active[2])
    completed.id='REVIEW-DONE';completed.status='completed'
    state.jobs.completed={completed}
    screen.tab='completed';screen.selectedJobId=completed.id
    layout=screen.jobDetailLayout(completed,state)
    check('job_review_completed_uses_contained_ticket_and_action',layout.actionTop==546
        and screen.promotionButtonCenter()==736 and layout.tableBottom<layout.actionTop)
    local promoX,promoY=screen.promotionButtonCenter()
    local promo=screen.mousepressed(state,promoX,promoY,1)
    check('job_review_completed_promo_still_opens_email',promo and promo.action=='promotion_compose' and screen.tab=='email')
    local inbound=require('src.screens.gui_projection').copy(state.jobs.active[2])
    inbound.id='REVIEW-INBOUND';inbound.status='awaiting_delivery'
    inbound.delivery={status='scheduled',route={originCity='Millhaven City',originLocation='Freight Yard'}}
    state.jobs.active={inbound}
    screen.tab='deliveries';screen.selectedJobId=inbound.id
    check('job_review_delivery_tracker_keeps_selection',screen.rowCenter(1)>0
        and screen.mousepressed(state,257,234,1).job.id=='REVIEW-INBOUND')
    screen.tab='email';screen.promoJobId=nil
    local folder=screen.mousepressed(state,324,232,1)
    check('critter_net_contained_email_archive_control_works',folder and folder.action=='email_folder'
        and screen.emailFolder=='archive')
    folder=screen.mousepressed(state,180,232,1)
    check('critter_net_contained_email_inbox_control_works',folder and folder.action=='email_folder'
        and screen.emailFolder=='inbox')
    screen.tab='financials';screen.financialSection='overview'
    local fx,fy=screen.financialSectionCenter('bills')
    local section=screen.mousepressed(state,fx,fy,1)
    check('critter_net_contained_financial_tab_works',section and section.action=='financials_view'
        and screen.financialSection=='bills')
    screen.tab='www';screen.cartOpen=false
    local wx,wy=screen.wwwSiteCenter(2)
    local website=screen.mousepressed(state,wx,wy,1)
    check('critter_net_contained_supplier_tab_works',website and website.action=='www_site'
        and screen.wwwSite==2)
    local cx,cy=screen.cartButtonCenter()
    local cart=screen.mousepressed(state,cx,cy,1)
    check('critter_net_contained_cart_button_works',cart and cart.action=='cart_opened' and screen.cartOpen)
    screen.cart={{name='Test paper',quantity=1,price=30,kind='supply',categoryIndex=1,itemIndex=1}}
    local removed=screen.mousepressed(state,765,264,1)
    check('critter_net_contained_cart_remove_works',removed and removed.action=='cart_item_removed'
        and #screen.cart==0)
    screen.tab='hiring'
    local hiringX,hiringY=require('src.screens.hiring_screen').buttonCenter('staff')
    local hiring=screen.mousepressed(state,31.6+hiringX*.956,17.4+hiringY*.9054,1)
    check('critter_net_contained_hiring_tab_works',hiring and hiring.action=='hiring_view'
        and screen.hiring.section=='staff')
    screen.tab='schedule'
    local scheduleX,scheduleY=require('src.screens.schedule_screen').buttonCenter('history')
    local schedule=screen.mousepressed(state,31.7+scheduleX*.932,21.1+scheduleY*.908,1)
    check('critter_net_contained_schedule_tab_works',schedule and schedule.action=='schedule_view'
        and screen.schedule.view=='history')
    screen.tab='radio'
    local radio=screen.mousepressed(state,33.6+733*.932,21.5+423*.887,1)
    check('critter_net_contained_radio_control_works',radio and radio.action=='radio_control'
        and radio.control=='mute')
    screen.mousepressed(state,33.6+733*.932,21.5+423*.887,1)
    local Book=require('src.receipt_book')
    state.receipts=Book.new()
    for index=1,7 do Book.add(state,{kind='delivery',title='Review receipt '..index,
        details='Wrapped pallet '..index,amountCents=1000}) end
    screen.tab='receipts';screen.receiptFilter='all';screen.receiptPage=1
    local receiptX,receiptY=screen.receiptPageCenter(1)
    local receiptPage=screen.mousepressed(state,receiptX,receiptY,1)
    check('critter_net_contained_receipt_paging_works',receiptPage
        and receiptPage.action=='receipts_view' and screen.receiptPage==2)
    screen.tab='active'
    local close=screen.mousepressed(state,836,56,1)
    check('job_review_sprite_x_closes_computer',close and close.action=='close')
    local oldBack=screen.mousepressed(state,780,80,1)
    check('job_review_old_back_area_no_longer_closes_computer',not oldBack or oldBack.action~='close')
end
return Test
