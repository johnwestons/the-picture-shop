local Test={}
function Test.run(check)
    local Screen=require('src.screens.delivery_signature_screen')
    local Input=require('src.input')
    local item={deliveryId='SHIP-1042',supplier='Millhaven Paper Depot',document='DELIVERY RECEIPT',
        orderState='Awaiting signature',deliveryState='At the loading bay',shipment='Paper delivery',
        quantity='10,000 sheets',category='Paper',declaredValue=2450,palletCount=2}
    local signed,saved,requested=0,0,0
    local context={state={screen='delivery_signature'},deliverySignatureScreen=Screen,
        world={player={},signDelivery=function()signed=signed+1;return true end},
        saveCurrent=function()saved=saved+1 end,isNetworkClient=function()return false end}
    Screen.enter(item)
    Input.mousepressed(760,569,1,context)
    Input.keypressed('return',context)
    check('receipt_blank_mouse_and_keyboard_cannot_sign',signed==0 and not Screen.canSign())
    Input.mousepressed(380,440,1,context)
    Input.mousereleased(380,440,1,context)
    check('receipt_click_without_a_stroke_is_not_a_signature',not Screen.canSign())
    Screen.clearInk()
    Input.mousepressed(390,456,1,context)
    for _,p in ipairs({{412,427},{403,470},{430,446},{440,455},{451,438},{463,456},{478,438},{491,454},{515,449}}) do
        Input.mousemoved(p[1],p[2],context)
    end
    check('receipt_cannot_confirm_while_drawing',not Screen.canSign() and Screen.hitTest(760,569)==nil)
    Input.mousereleased(515,449,1,context)
    check('receipt_accepts_freehand_mouse_signature',Screen.canSign() and Screen.inkLength>20)
    local directory=os.getenv('PICTURE_SHOP_RECEIVING_CAPTURE')
    if directory then
        local g=love.graphics;local canvas=require('src.tests.support.pixel_canvas')(960,678)
        g.push('all');g.setCanvas(canvas);g.origin();g.clear(.12,.16,.15,1)
        Screen.draw(nil,require('src.assets'),760,569);g.pop()
        local data=canvas:newImageData();local png=data:encode('png')
        local file=assert(io.open(directory..'/signed-receipt.png','wb'));file:write(png:getString());file:close()
        png:release();data:release();canvas:release()
    end
    Input.mousepressed(760,569,1,context)
    check('receipt_ok_completes_delivery_once',signed==1 and saved==1 and context.state.screen=='world' and Screen.item==nil)
    Screen.enter(item);context.state.screen='delivery_signature'
    local runtime={App={},Assets={},state=context.state,Input=Input,inputContext=context,
        toPointerCoordinates=function(x,y)return x/2,y/2 end}
    require('src.runtime.input_callbacks').install(runtime)
    runtime.App.touchpressed('finger-a',760,880)
    runtime.App.touchpressed('finger-b',1500,1138)
    runtime.App.touchmoved('finger-b',1100,960)
    check('receipt_second_finger_cannot_write_or_confirm',Screen.pointCount==1 and signed==1)
    runtime.App.touchmoved('finger-a',820,930)
    runtime.App.touchreleased('finger-a',840,925)
    check('receipt_touch_uses_scaled_pointer_coordinates',Screen.canSign() and Screen.strokes[1][1]==380)
    runtime.App.touchpressed('finger-b',350,1138)
    check('receipt_clear_removes_ink_and_disables_ok',not Screen.canSign() and #Screen.strokes==0)
    runtime.App.touchpressed('finger-a',760,880)
    runtime.App.touchmoved('finger-a',1900,1300)
    runtime.App.touchreleased('finger-a',1900,1300)
    local stroke=Screen.strokes[1]
    check('receipt_ink_stays_inside_signature_box',stroke[#stroke-1]<=855 and stroke[#stroke]<=490)
    context.isNetworkClient=function()return true end
    context.requestDeliverySignature=function()requested=requested+1;return true end
    runtime.App.touchpressed('finger-a',1500,1138)
    runtime.App.touchpressed('finger-a',1500,1138)
    check('receipt_guest_confirmation_locks_duplicate_requests',requested==1 and Screen.pending and #Screen.strokes>0)
    local count=Screen.pointCount
    runtime.App.mousepressed(400,450,1,true)
    check('receipt_synthetic_touch_mouse_does_not_duplicate_ink',Screen.pointCount==count)
    Screen.setPending(false)
    check('receipt_host_rejection_keeps_signature_for_retry',Screen.canSign())
    Screen.enter({deliveryId='NEXT'})
    check('receipt_new_delivery_starts_with_blank_signature',not Screen.canSign() and #Screen.strokes==0)
    Screen.clear()
    local state=require('src.state').new()
    local Driver=require('src.warehouse_delivery_driver')
    local job=assert(require('src.jobs').createOffer({id='ART-RECEIPT',company='Juniper Trail Outfitters',
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500,500}}))
    job.artwork={key='flower',displayName='Client proof'}
    state.jobs.active={job}
    Driver.start(state,job.id,'job_delivery');state.deliveryDriver.status='waiting'
    local receipt=assert(Driver.receipt(state,job.id))
    check('receipt_uses_actual_client_art_and_pallet_sprites',receipt.supplier==job.company
        and receipt.artworkKey=='flower' and #receipt.previews==2
        and receipt.previews[1].image=='loadedPaperPalletDirections')
    if directory then
        Screen.enter(receipt)
        Screen.mousepressed(390,456,1);Screen.mousemoved(420,430);Screen.mousemoved(430,465)
        Screen.mousemoved(450,449);Screen.mousemoved(480,457);Screen.mousereleased(480,457,1)
        local g=love.graphics;local canvas=require('src.tests.support.pixel_canvas')(960,678)
        g.push('all');g.setCanvas(canvas);g.origin();g.clear(.12,.16,.15,1)
        Screen.draw(nil,require('src.assets'),760,569);g.pop()
        local data=canvas:newImageData();local png=data:encode('png')
        local file=assert(io.open(directory..'/client-receipt.png','wb'));file:write(png:getString());file:close()
        png:release();data:release();canvas:release();Screen.clear()
    end
    state.money=10000
    local bought,order=require('src.procurement').buy(state,2,1,'computer');assert(bought,order)
    Driver.start(state,order.id,'vendor_delivery');state.deliveryDriver.status='waiting'
    local supply=assert(Driver.receipt(state,order.id))
    check('receipt_uses_supplier_product_art_instead_of_generic_paper',supply.previews[1].image=='vendorProductPallets'
        and supply.previews[1].quad:match('vendorProductPallet2_') and supply.supplier==order.company)
    Driver.start(state,order.shipmentId,'vendor_delivery');state.deliveryDriver.status='waiting'
    local shipment=assert(Driver.receipt(state,order.shipmentId))
    check('receipt_resolves_company_from_grouped_supplier_orders',shipment.supplier==order.company
        and shipment.previews[1].quad==supply.previews[1].quad)
    local boughtOther,other=require('src.procurement').buy(state,1,1,'computer');assert(boughtOther,other)
    assert(other.shipmentId==order.shipmentId and other.company~=order.company)
    shipment=assert(Driver.receipt(state,order.shipmentId))
    check('receipt_mixed_supplier_load_uses_freight_brand_and_both_cargo_sprites',shipment.supplier=='Millhaven Freight'
        and shipment.palletCount==2 and shipment.previews[1].quad~=shipment.previews[2].quad)
    Driver.reset(state)
end
return Test
