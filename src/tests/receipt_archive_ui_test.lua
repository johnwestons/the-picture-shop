local Test={}
function Test.run(context,check,state)
    local screen=context.computerScreen.new({warehouseEnabled=true})
    screen.enter(state)
    local x,y=screen.dropdownCenter();screen.mousepressed(state,x,y,1)
    x,y=screen.tabCenter('receipts');screen.mousepressed(state,x,y,1)
    check('archive_computer_tab_opens_from_directory',screen.tab=='receipts')
    local function select(kind)
        local fx,fy=screen.receiptFilterCenter(kind);screen.mousepressed(state,fx,fy,1)
    end
    local function capture(name,width,height)
        local folder=os.getenv('PICTURE_SHOP_RECEIPT_CAPTURE');if not folder then return end
        local g=love.graphics;local canvas=g.newCanvas(width,height)
        g.push('all');g.setCanvas({canvas,stencil=true});g.origin();g.clear(.02,.03,.04,1)
        local scale=math.min(width/960,height/678)
        g.translate((width-960*scale)/2,(height-678*scale)/2);g.scale(scale)
        screen.draw(state,nil,nil,context.assets,true)
        g.pop();local data=canvas:newImageData();local png=data:encode('png')
        local file=assert(io.open(folder..'/'..name..'.png','wb'));file:write(png:getString());file:close()
        png:release();data:release();canvas:release()
    end
    select('delivery');capture('receipts-desktop',1440,1017)
    check('archive_delivery_filter_reopens_saved_signature',screen.selectedReceiptId==state.receipts.entries[1].id)
    select('bill');capture('receipts-bills',1440,1017)
    check('archive_bill_filter_has_own_selection',screen.selectedReceiptId~=state.receipts.entries[1].id)
    for i=1,18 do require('src.receipt_book').expense(state,'Test purchase '..i,100+i,'Local shop','Household','Purchased item') end
    select('purchase');capture('receipts-purchases',1440,1017)
    x,y=screen.receiptPageCenter(1);screen.mousepressed(state,x,y,1)
    check('archive_touch_pagination_reaches_older_documents',screen.receiptPage==2)
    local originalOS,originalDimensions,originalSafe=love.system.getOS,love.graphics.getDimensions,love.window.getSafeArea
    local okay,reason=xpcall(function()
        love.system.getOS=function()return 'Android' end
        love.graphics.getDimensions=function()return 832,384 end
        love.window.getSafeArea=function()return 0,0,832,384 end
        select('delivery');capture('receipts-phone',832,384)
        check('archive_phone_filter_and_signature_selection_share_content_transform',screen.receiptFilter=='delivery'
            and screen.selectedReceiptId==state.receipts.entries[1].id)
        select('purchase');x,y=screen.receiptPageCenter(1);screen.mousepressed(state,x,y,1)
        check('archive_phone_next_page_remains_reachable',screen.receiptPage==2)
    end,debug.traceback)
    love.system.getOS,love.graphics.getDimensions,love.window.getSafeArea=originalOS,originalDimensions,originalSafe
    assert(okay,reason)
    local calls=0;local guest=context.computerScreen.new({remoteCommand=function()calls=calls+1 end})
    guest.enter(state);guest.tab='receipts';x,y=guest.receiptFilterCenter('delivery');guest.mousepressed(state,x,y,1)
    check('archive_browsing_does_not_send_financial_mutations',calls==0)
end
return Test
