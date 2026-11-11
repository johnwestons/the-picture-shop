local Book=require('src.receipt_book')
local Text=require('src.screens.typography')
local Fonts=require('src.screens.computer.fonts')
local Ink=require('src.receipt_signature')
local Component={}
local filters={{'all','ALL'},{'delivery','DELIVERY'},{'job','JOB PAY'},{'purchase','PURCHASES'},{'bill','BILLS'},{'payout','PAYOUTS'}}
local previous={x=116,y=544,width=80,height=34};local nextPage={x=248,y=544,width=80,height=34}
local up={x=750,y=544,width=38,height=30};local down={x=798,y=544,width=38,height=30}
local function filterRect(i)return {x=116+(i-1)*121,y=224,width=114,height=34}end
local function rowRect(i)return {x=116,y=264+(i-1)*46,width=212,height=42}end
local function center(r)return r.x+r.width/2,r.y+r.height/2 end
local function line(value,x,y,w,size,color)
    local g=love.graphics;local font=(size or 14)<=14 and Fonts.get('typewriter',14) or Text.get(size or 14)
    g.setFont(font);g.setColor(color or {.17,.20,.18,1})
    g.print(Text.ellipsize(tostring(value),w,font),x,y)
end
function Component.install(Runtime)
    local s=Runtime.ComputerScreen
    function Runtime.resetReceipts()
        s.receiptFilter,s.receiptPage,s.receiptDetailPage,s.selectedReceiptId='all',1,1,nil
    end
    Runtime.resetReceipts()
    local function selection(state)
        local entries=Book.list(state,s.receiptFilter)
        local pages=math.max(1,math.ceil(#entries/6))
        s.receiptPage=math.max(1,math.min(pages,s.receiptPage or 1))
        local selected
        for i=(s.receiptPage-1)*6+1,math.min(#entries,s.receiptPage*6) do
            if entries[i].id==s.selectedReceiptId then selected=entries[i] end
        end
        if not selected then
            selected=entries[(s.receiptPage-1)*6+1];s.selectedReceiptId=selected and selected.id
            s.receiptDetailPage=1
        end
        return entries,selected,pages
    end
    local function detailPages(receipt)
        local details=receipt.details
        if receipt.paidAtHours then
            details=details..'\nPaid: '..Runtime.BusinessCalendar.dateTimeTextAtHours(receipt.paidAtHours,true)
        end
        local font=Fonts.get('typewriter',14);local _,lines=font:getWrap(details,450)
        local count=receipt.signature and 5 or 9
        return lines,count,math.max(1,math.ceil(#lines/count))
    end
    function s.receiptFilterCenter(kind)
        for i,f in ipairs(filters) do if f[1]==kind then return center(filterRect(i)) end end
    end
    function s.receiptRowCenter(index)return center(rowRect(index))end
    function s.receiptPageCenter(direction)return center(direction<0 and previous or nextPage)end
    function s.receiptScroll(state,direction)
        local _,receipt=selection(state);if not receipt then return true end
        local _,_,pages=detailPages(receipt)
        s.receiptDetailPage=math.max(1,math.min(pages,(s.receiptDetailPage or 1)+direction))
        return true
    end
    function Runtime.receiptsMousepressed(state,x,y)
        for i,f in ipairs(filters) do if Runtime.contains(filterRect(i),x,y) then
            s.receiptFilter=f[1];s.receiptPage=1;s.selectedReceiptId=nil;s.receiptDetailPage=1
            selection(state)
            return {action='receipts_view'}
        end end
        local entries,_,pages=selection(state)
        for i=1,6 do if Runtime.contains(rowRect(i),x,y) then
            local receipt=entries[(s.receiptPage-1)*6+i]
            if receipt then s.selectedReceiptId=receipt.id;s.receiptDetailPage=1 end
            return {action='receipts_view'}
        end end
        if Runtime.contains(previous,x,y) or Runtime.contains(nextPage,x,y) then
            s.receiptPage=math.max(1,math.min(pages,s.receiptPage+(Runtime.contains(previous,x,y) and -1 or 1)))
            s.selectedReceiptId=nil;s.receiptDetailPage=1;return {action='receipts_view'}
        end
        if Runtime.contains(up,x,y) or Runtime.contains(down,x,y) then
            s.receiptScroll(state,Runtime.contains(up,x,y) and -1 or 1);return {action='receipts_view'}
        end
    end
    function Runtime.drawReceipts(state,px,py,twelveHourTime)
        local g=love.graphics;g.push('all')
        Runtime.panel({x=110,y=182,width=738,height=402},{.035,.06,.065,1},{.30,.50,.49,1})
        line('RECEIPT ARCHIVE',124,194,300,20,{.91,.86,.63,1})
        line('Saved with this shop  |  Payroll in Financials',430,199,405,14,{.73,.84,.79,1})
        g.setFont(Fonts.get('sans',13))
        for i,f in ipairs(filters) do
            Runtime.drawComputerButton(filterRect(i),f[2],s.receiptFilter==f[1] and 'primary' or 'secondary')
        end
        local entries,receipt,pages=selection(state)
        for i=1,6 do
            local row=entries[(s.receiptPage-1)*6+i];local rect=rowRect(i)
            if row then
                local chosen=receipt and row.id==receipt.id
                Runtime.panel(rect,chosen and {.10,.28,.29,1} or {.05,.10,.12,1},{.27,.43,.42,1},3,1)
                line(row.title,rect.x+9,rect.y+4,194,14,{.93,.96,.89,1})
                line(('$%.2f  /  %s'):format(row.amountCents/100,row.status:upper()),rect.x+9,rect.y+22,194,14,{.68,.83,.76,1})
            end
        end
        g.setFont(Fonts.get('sans',13))
        Runtime.drawComputerButton(previous,'< PREV',s.receiptPage>1 and 'secondary' or 'disabled')
        Runtime.drawComputerButton(nextPage,'NEXT >',s.receiptPage<pages and 'secondary' or 'disabled')
        line(s.receiptPage..'/'..pages,202,552,40,14,{.88,.93,.9,1})
        Runtime.panel({x=340,y=264,width=498,height=314},{.91,.88,.77,1},{.63,.60,.49,1},3,1)
        if not receipt then
            line('No receipts in this category yet.',356,290,466,16)
            g.setFont(Text.get(15));g.setColor(.25,.29,.25,1)
            g.printf('Completed payments and signed deliveries are filed here automatically.\n\nEmployee wages remain in Financials.',356,331,466,'left')
        else
            line(receipt.title,356,278,466,18)
            local when=Runtime.BusinessCalendar.dateTimeTextAtHours(receipt.atHours,twelveHourTime)
            line(('R-%05d  |  %s'):format(receipt.id,when),356,304,466,14)
            line(receipt.party..'  |  '..receipt.account,356,329,466,14)
            line((receipt.kind=='delivery' and 'DECLARED VALUE  ' or 'TOTAL  ')..('$%.2f'):format(receipt.amountCents/100),356,357,322,18)
            line(receipt.status:upper(),700,360,128,16)
            local lines,count,detailPageCount=detailPages(receipt)
            s.receiptDetailPage=math.max(1,math.min(detailPageCount,s.receiptDetailPage or 1))
            for i=1,count do
                local value=lines[(s.receiptDetailPage-1)*count+i]
                if value then line(value,356,392+(i-1)*16,466,14) end
            end
            if receipt.signature then
                Runtime.panel({x=356,y=472,width=466,height=78},{.98,.96,.88,1},{.62,.61,.51,1},0,1)
                Ink.draw(receipt.signature,{x=364,y=480,width=450,height=62})
                line('Signed by '..(receipt.signedBy or 'Recipient'),356,554,380,14)
            elseif receipt.signedBy then line('Acknowledged by '..receipt.signedBy,356,554,380,14) end
            if detailPageCount>1 then
                g.setFont(Fonts.get('sans',13))
                Runtime.drawComputerButton(up,'^',s.receiptDetailPage>1 and 'secondary' or 'disabled')
                Runtime.drawComputerButton(down,'v',s.receiptDetailPage<detailPageCount and 'secondary' or 'disabled')
            end
        end
        g.pop()
    end
end
return Component
