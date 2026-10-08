-- Short host-owned captions. Realtime poses carry one code, never long text.
local Speech={MAX_CODE=28,GREETING_SECONDS=4}
local messages={
    "Hello!","Hello!","Goodbye!","Cutting","Wrapping","Printing",
    "On break","Lunch break","To breakroom","To the cutter","To the wrapper",
    "To the press","Moving a pallet","Training","Waiting","Needs help",
    "Path blocked","Finishing up","Starting shift","Heading home",
    "Waiting for pay","Work paused","Ready to work","Preparing plate",
    "Cleaning press","Preparing wrap",
    "May I use the jack?","To the pallet jack",
}
function Speech.code(entry)
    if not entry or not entry.worker or not entry.actor or entry.actor.visible==false then return 0 end
    local a,w=entry.actor,entry.worker
    -- A guest uses the current host pose, including its caption, rather than
    -- an older assignment/activity from the reliable shop snapshot.
    if type(a.speechCode)=="number" and a.speechCode%1==0
        and a.speechCode>=0 and a.speechCode<=Speech.MAX_CODE then return a.speechCode end
    if a.greetingKind and a.greetingKind>=1 and a.greetingKind<=3 then return a.greetingKind end
    if a.phase=="leaving" then return 20 end
    if a.phase=="break" then return w.breakKind=="meal" and 8 or 7 end
    if a.phase=="break_walk" then return 9 end
    local activity=(w.activity or ""):lower()
    if activity:find("waiting for the pallet jack",1,true) then return 27 end
    if activity:find("overdue wages",1,true) then return 21 end
    if activity:find("paused",1,true) then return 22 end
    if activity:find("blocked",1,true) or activity:find("another way",1,true) then return 17 end
    if activity:find("needs player attention",1,true) or activity:find("need attention",1,true)
        or activity:find("clear the",1,true) or activity:find("training required",1,true) then return 16 end
    if a.phase=="pushing" then return 13 end
    if activity:find("walking to the pallet jack",1,true) then return 28 end
    if activity:find("waiting",1,true) or activity:find("another pallet",1,true) then return 15 end
    if activity:find("safe machine cycle",1,true) then return 18 end
    if w.carryingPalletId then return 13 end
    if w.training then return 14 end
    if a.phase=="entering" then return 19 end
    if a.phase=="working" then
        if activity:find("next print plate",1,true) then return 24 end
        if activity:find("cleaning the press",1,true) then return 25 end
        if activity:find("preparing finished pallet",1,true) then return 26 end
        local model=w.assignment and w.assignment.machineModel
        if model=="polar_115" then return 4 end
        if model=="skid_wrapper" then return 5 end
        if model=="heidelberg_10x15" then return 6 end
        return 18
    end
    if a.phase=="walking" or a.moving then
        local model=w.assignment and w.assignment.machineModel
        if model=="polar_115" then return 10 end
        if model=="skid_wrapper" then return 11 end
        if model=="heidelberg_10x15" then return 12 end
        return 19
    end
    return 23
end
function Speech.message(code) return messages[code] end
return Speech
