-- Conservative body-region lower bounds for each authored 320px cell.
-- Upper rider/helmet and handlebar pixels are excluded before material selection.
-- Sixteen corrected views use the conservative protected boundary from adjacent
-- original views. Coordinates never modify or duplicate the source artwork.
local Masks={FRAME=320}
Masks.minY={
    parked={130,130,130,130,130,130,130,130,130,130,130,130,130,130,130,130},
    mounted={137,137,101,101,101,116,116,129,129,129,118,118,113,130,130,137},
    aero={160,160,160,160,160,160,160,164,164,165,165,165,163,172,172,172},
    aeroMid={153,164,164,164,147,153,153,172,172,172,167,167,154,177,177,177},
    boost={160,160,129,129,123,134,134,159,159,159,130,130,123,137,137,160},
    boostMid={145,145,124,124,117,131,131,142,142,142,127,127,122,138,138,145},
    shift={150,150,122,122,113,120,120,149,149,149,120,120,116,132,132,150},
    shiftMid={148,148,132,132,118,128,128,151,151,151,125,125,123,140,140,148},
    impact={157,157,156,156,143,152,152,165,165,165,149,149,145,169,169,169},
    impactMid={154,161,161,161,138,159,159,166,166,166,152,152,150,161,161,161},
    turnLeft={186,186,134,137,137,140,140,165,165,165,132,136,136,159,159,186},
    turnRight={164,164,150,150,148,148,142,167,167,167,142,146,146,146,139,164},
    turnLeftMid={161,161,136,136,134,141,141,156,156,156,137,140,140,165,165,165},
    turnRightMid={164,164,147,148,148,148,147,161,161,161,147,147,142,158,158,164},
}
function Masks.lower(pose,frame)
    local row=assert(Masks.minY[pose or "parked"],"Unknown bike paint pose")
    return assert(row[frame],"Unknown bike paint frame")
end
return Masks
