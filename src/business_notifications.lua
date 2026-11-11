local Calendar=require('src.business_calendar')
local Hours=require('src.business_hours')
local Notices=require('src.notifications')
local Guide={}
Guide.weekendBody='Industrial customers, suppliers, job calls, job emails, and new delivery dispatches run Monday-Friday, 09:00-20:00. Industrial receiving is closed on Saturday and Sunday. Missed deliveries wait for the next business opening.\n\nYou may stay in the shop to cut, print, and wrap existing pallets. To close for the weekend, finish any machine cycle, park the pallet jacks and forklift, finish the current truck visit, close the loading bays, and let staff finish leaving. Use the front entrance and choose CLOSE SHOP & LEAVE.\n\nExplore town or go to your apartment. Grocery stores and gas stations keep their daily opening hours on weekends. At home you can cook, rest, set an alarm, or sleep until Monday. Aim to return before the 08:00 employee shift; customer business opens at 09:00.'
function Guide.update(feedback)
    local state=feedback.context.state
    if not state.calendar then return end
    local now=Calendar.absoluteHours(state);local day=math.floor(now/24)
    local weekday=Hours.weekday(day);local hour=now%24
    local title,detail,key
    if weekday==5 and hour>=18 and hour<Hours.CLOSE_HOUR then
        title='FRIDAY: CLOSING SOON';detail='Closes at 20:00. Prepare to head home.'
        key='business:friday:'..day
    elseif weekday>=6 or weekday==5 and hour>=Hours.CLOSE_HOUR then
        title='CLOSED FOR WEEKEND';detail='Finish pallets, or close up and go home.'
        key='business:weekend:'..(day+5-weekday)
    end
    if key and not Notices.findKey(state,key) then
        feedback:enqueue('calendar',title,detail,Guide.weekendBody,key)
    end
    local balance=state.bills and tonumber(state.bills.balance) or 0
    local billKey=('business:bills:%d:%d'):format(state.calendar.year or 2026,state.calendar.month or 1)
    if balance>0 and not Notices.findKey(state,billKey) then
        feedback:enqueue('calendar','SHOP BILL DUE',
            ('$%d due. Open Finances on CritterNet.'):format(balance),
            ('The shop has $%d in bills due. Review and pay them from the office computer.'):format(balance),billKey)
    end
end
return Guide
