local M=require('src.commute.vendor.mathx')
local Variants={forms={
    oak={key='understory',file='oak-understory-v2.png',salt=117},
    pine={key='open',file='pine-open-v2.png',salt=131},
    bramble={key='open',file='bramble-open-v2.png',salt=149},
    grass={key='sparse',file='grass-sparse-v2.png',salt=163},
    redbud={key='understory',file='redbud-understory-v2.png',salt=179},
    dogwood={key='understory',file='dogwood-understory-v2.png',salt=191},
    sumac={key='open',file='sumac-open-v2.png',salt=199},
    blueberry={key='open',file='blueberry-open-v2.png',salt=211},
}}
function Variants.pick(seed,id,kind)
    local form=Variants.forms[kind]
    if not form or not id then return nil end
    if M.hash((seed or 4261)+743,id,form.salt)<.42 then return form.key end
    return nil
end
return Variants
