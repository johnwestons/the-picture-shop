-- Procedural first-person stand-ins for props whose isometric art does not
-- read correctly from eye level. Third person continues to use the authored
-- 64-view sprites.
local P = {}
local format = {
    {"VertexPosition", "float", 2},
    {"WorldHeight", "float", 1},
    {"VertexTexCoord", "float", 2},
}

local function shade(color, amount)
    return {color[1] * amount, color[2] * amount, color[3] * amount}
end

local faceShade = {0.62, 1.0, 0.78, 0.68, 0.88, 0.73}
local faces = {
    {1, 2, 3, 4}, {5, 8, 7, 6}, {1, 5, 6, 2},
    {2, 6, 7, 3}, {3, 7, 8, 4}, {4, 8, 5, 1},
}

local function build(item, white)
    if item.fpModel then
        for _, part in ipairs(item.fpModel.parts) do part.mesh:release() end
    end
    local batches = {}
    local modelScale = item.visualScale or 1
    local modelBaseHeight = item.baseHeight or 0
    local function append(color, vertices)
        local key = string.format("%.3f/%.3f/%.3f", color[1], color[2], color[3])
        local batch = batches[key]
        if not batch then batch = {color = color, vertices = {}}; batches[key] = batch end
        for _, v in ipairs(vertices) do batch.vertices[#batch.vertices + 1] = v end
    end
    local function worldPoint(x, z, h)
        x,z=x*modelScale,z*modelScale
        h=modelBaseHeight+(h-modelBaseHeight)*modelScale
        return {x,z,h}
    end
    local function box(x, z, width, depth, bottom, height, color, rotation)
        local points = {}
        local rotation = rotation or 0
        local rc, rs = math.cos(rotation), math.sin(rotation)
        for _, h in ipairs({bottom, bottom + height}) do
            for _, p in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
                local px, pz = p[1] * width * .5, p[2] * depth * .5
                points[#points + 1] = worldPoint(x + rc * px - rs * pz,
                    z + rs * px + rc * pz, h)
            end
        end
        for faceIndex, face in ipairs(faces) do
            local vertices = {}
            for _, index in ipairs({1,2,3,1,3,4}) do
                local p = points[face[index]]
                vertices[#vertices + 1] = {p[1], p[2], p[3], 0, 0}
            end
            append(shade(color, faceShade[faceIndex]), vertices)
        end
    end
    local function bevelBox(x, z, width, depth, bottom, height, color, bevel)
        bevel = math.min(bevel or .06, width * .2, depth * .2, height * .2)
        local points = {}
        for _, p in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
            points[#points + 1] = worldPoint(x + p[1] * width * .5,
                z + p[2] * depth * .5, bottom)
        end
        for _, p in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
            points[#points + 1] = worldPoint(x + p[1] * (width * .5 - bevel),
                z + p[2] * (depth * .5 - bevel), bottom + height - bevel)
        end
        for faceIndex, face in ipairs(faces) do
            if faceIndex ~= 2 then
                local vertices = {}
                for _, index in ipairs({1,2,3,1,3,4}) do
                    local p = points[face[index]]
                    vertices[#vertices + 1] = {p[1],p[2],p[3],0,0}
                end
                append(shade(color, faceShade[faceIndex]), vertices)
            end
        end
        local cap = {}
        for _, index in ipairs({5,6,7,5,7,8}) do
            local p = points[index]
            cap[#cap + 1] = {p[1],p[2],p[3],0,0}
        end
        append(shade(color, 1.04), cap)
    end
    local function turntableBox(x, z, width, depth, bottom, height, color, rotation)
        local c, s = math.cos(rotation), math.sin(rotation)
        box(x * c - z * s, x * s + z * c, width, depth,
            bottom, height, color, rotation)
    end
    local function cylinderY(x, z, radius, bottom, height, color, segments)
        segments = segments or 16
        for i = 0, segments - 1 do
            local a0, a1 = i * math.pi * 2 / segments, (i + 1) * math.pi * 2 / segments
            local x0, z0 = x + math.cos(a0) * radius, z + math.sin(a0) * radius
            local x1, z1 = x + math.cos(a1) * radius, z + math.sin(a1) * radius
            local p0, p1 = worldPoint(x0, z0, bottom), worldPoint(x1, z1, bottom)
            local p2, p3 = worldPoint(x1, z1, bottom + height), worldPoint(x0, z0, bottom + height)
            local side = shade(color, .70 + .25 * math.max(0, math.cos((a0 + a1) * .5)))
            append(side, {{p0[1],p0[2],p0[3],0,0},{p1[1],p1[2],p1[3],0,0},
                {p2[1],p2[2],p2[3],0,0},{p0[1],p0[2],p0[3],0,0},
                {p2[1],p2[2],p2[3],0,0},{p3[1],p3[2],p3[3],0,0}})
            local centerBottom = worldPoint(x, z, bottom)
            local centerTop = worldPoint(x, z, bottom + height)
            append(shade(color, .58), {{centerBottom[1],centerBottom[2],centerBottom[3],0,0},
                {p1[1],p1[2],p1[3],0,0},{p0[1],p0[2],p0[3],0,0}})
            append(shade(color, 1.08), {{centerTop[1],centerTop[2],centerTop[3],0,0},
                {p3[1],p3[2],p3[3],0,0},{p2[1],p2[2],p2[3],0,0}})
        end
    end
    local function cylinderZ(x, z, radius, centerY, depth, color, segments)
        segments = segments or 12
        for i = 0, segments - 1 do
            local a0, a1 = i * math.pi * 2 / segments, (i + 1) * math.pi * 2 / segments
            local p0 = worldPoint(x + math.cos(a0) * radius, z - depth * .5, centerY + math.sin(a0) * radius)
            local p1 = worldPoint(x + math.cos(a1) * radius, z - depth * .5, centerY + math.sin(a1) * radius)
            local p2 = worldPoint(x + math.cos(a1) * radius, z + depth * .5, centerY + math.sin(a1) * radius)
            local p3 = worldPoint(x + math.cos(a0) * radius, z + depth * .5, centerY + math.sin(a0) * radius)
            local side = shade(color, .72 + .23 * math.max(0, math.cos((a0 + a1) * .5)))
            append(side, {{p0[1],p0[2],p0[3],0,0},{p1[1],p1[2],p1[3],0,0},
                {p2[1],p2[2],p2[3],0,0},{p0[1],p0[2],p0[3],0,0},
                {p2[1],p2[2],p2[3],0,0},{p3[1],p3[2],p3[3],0,0}})
            local front = worldPoint(x, z + depth * .5, centerY)
            append(shade(color, 1.05), {{front[1],front[2],front[3],0,0},
                {p3[1],p3[2],p3[3],0,0},{p2[1],p2[2],p2[3],0,0}})
            local back = worldPoint(x, z - depth * .5, centerY)
            append(shade(color, .62), {{back[1],back[2],back[3],0,0},
                {p1[1],p1[2],p1[3],0,0},{p0[1],p0[2],p0[3],0,0}})
        end
    end
    local function cylinderX(x, z, length, radius, centerY, color, segments)
        segments = segments or 16
        for i = 0, segments - 1 do
            local a0, a1 = i * math.pi * 2 / segments, (i + 1) * math.pi * 2 / segments
            local p0 = worldPoint(x - length * .5, z + math.cos(a0) * radius, centerY + math.sin(a0) * radius)
            local p1 = worldPoint(x + length * .5, z + math.cos(a0) * radius, centerY + math.sin(a0) * radius)
            local p2 = worldPoint(x + length * .5, z + math.cos(a1) * radius, centerY + math.sin(a1) * radius)
            local p3 = worldPoint(x - length * .5, z + math.cos(a1) * radius, centerY + math.sin(a1) * radius)
            local side = shade(color, .72 + .23 * math.max(0, math.cos((a0 + a1) * .5)))
            append(side, {{p0[1],p0[2],p0[3],0,0},{p1[1],p1[2],p1[3],0,0},
                {p2[1],p2[2],p2[3],0,0},{p0[1],p0[2],p0[3],0,0},
                {p2[1],p2[2],p2[3],0,0},{p3[1],p3[2],p3[3],0,0}})
            local left = worldPoint(x - length * .5, z, centerY)
            local right = worldPoint(x + length * .5, z, centerY)
            append(shade(color, .62), {{left[1],left[2],left[3],0,0},
                {p3[1],p3[2],p3[3],0,0},{p0[1],p0[2],p0[3],0,0},
                {right[1],right[2],right[3],0,0},{p1[1],p1[2],p1[3],0,0},
                {p2[1],p2[2],p2[3],0,0}})
        end
    end
    local function palletBase(x,z,bottom)
        local wood,lightWood={.43,.25,.12},{.65,.42,.21}
        for _,offset in ipairs({-.43,0,.43}) do
            box(x+offset,z, .15,.94,bottom+.08,.12,wood)
            box(x+offset,z-.36,.17,.18,bottom,.08,lightWood)
            box(x+offset,z+.36,.17,.18,bottom,.08,lightWood)
        end
        for dz=-.48,.481,.16 do
            box(x,z+dz,1.17,.105,bottom+.20,.07,lightWood)
            box(x,z+dz+.052,1.17,.012,bottom+.27,.009,shade(wood,.76))
        end
    end
    local function palletContents(style,x,z,bottom,includeBase,isWrapped)
        local wood={.43,.25,.12}
        if includeBase then palletBase(x,z,bottom) end
        local loadBottom=bottom+(includeBase and .27 or 0)
        local function filmWrap(width,depth,height)
            local film={.48,.70,.72}
            for band=.08,height-.04,.19 do
                box(x,z-depth*.5,width,.018,loadBottom+band,.065,film)
                box(x,z+depth*.5,width,.018,loadBottom+band,.065,film)
                box(x-width*.5,z,.018,depth,loadBottom+band,.065,film)
                box(x+width*.5,z,.018,depth,loadBottom+band,.065,film)
            end
        end
        if style=="boxed" or style=="wrapped_boxed" then
            local carton,tape={.58,.36,.19},{.84,.68,.40}
            for level=0,1 do
                for row=0,1 do for col=0,1 do
                    local px=x+(col-.5)*.43+(level%2)*.04
                    local pz=z+(row-.5)*.40
                    local py=loadBottom+level*.34
                    box(px,pz,.40,.37,py,.32,carton)
                    box(px,pz-.188,.035,.012,py+.03,.27,tape)
                    box(px,pz,.35,.012,py+.305,.012,shade(carton,1.2))
                end end
            end
            if isWrapped or style=="wrapped_boxed" then filmWrap(1.08,.82,.66) end
            return
        end
        if style=="vendor_press" then
            local crate={.22,.29,.25}
            for row=0,1 do for col=0,1 do
                local px=x+(col-.5)*.48
                local pz=z+(row-.5)*.43
                box(px,pz,.43,.39,loadBottom,.44,crate)
                box(px,pz-.198,.37,.012,loadBottom+.18,.035,{.82,.70,.35})
                for can=0,1 do
                    cylinderY(px+(can-.5)*.14,pz,.055,loadBottom+.44,.24,
                        ({ {.13,.15,.16},{.60,.19,.08},{.16,.36,.46} })[can+1],12)
                end
            end end
            if isWrapped then filmWrap(.96,.86,.68) end
            return
        end
        if style=="vendor_equipment" then
            local case,dark={.30,.34,.30},{.10,.12,.12}
            for row=0,1 do for col=0,1 do
                local px=x+(col-.5)*.47
                local pz=z+(row-.5)*.43
                bevelBox(px,pz,.43,.38,loadBottom,.36,case,.035)
                box(px,pz-.196,.25,.014,loadBottom+.20,.045,{.86,.58,.12})
                box(px,pz,.18,.08,loadBottom+.36,.045,dark)
            end end
            box(x,z-.12,.88,.12,loadBottom+.40,.12,{.50,.53,.50})
            if isWrapped then filmWrap(.96,.84,.52) end
            return
        end
        if style=="vendor_packaging" then
            local carton,tape={.64,.43,.25},{.88,.72,.43}
            for level=0,1 do for row=0,1 do for col=0,1 do
                local px=x+(col-.5)*.43
                local pz=z+(row-.5)*.40
                local py=loadBottom+level*.33
                box(px,pz,.40,.37,py,.31,carton)
                box(px,pz-.188,.032,.012,py+.025,.26,tape)
            end end end
            for _,px in ipairs({x-.40,x+.40}) do
                cylinderY(px,z+.31,.115,loadBottom,.82,{.71,.78,.77},20)
                cylinderY(px,z+.31,.045,loadBottom-.01,.84,{.28,.33,.33},16)
            end
            if isWrapped then filmWrap(1.08,.88,.91) end
            return
        end
        if style=="paper" or style=="wrapped" or style=="vendor_paper" then
            local paper,side={.88,.88,.83},{.70,.73,.70}
            for level=0,2 do
                for col=0,2 do
                    local px=x+(col-1)*.37+(level%2)*.025
                    local py=loadBottom+level*.27
                    box(px,z,.34,.78,py,.25,paper)
                    box(px,z-.396,.33,.012,py+.02,.20,side)
                    for seam=1,2 do
                        box(px,z-.404,.31,.008,py+.04+seam*.055,.008,
                            style=="vendor_paper" and {.56,.28,.18} or shade(paper,.90))
                    end
                end
            end
            if style=="wrapped" then
                for _,dz in ipairs({-.405,.405}) do
                    box(x,z+dz,1.06,.018,loadBottom+.04,.67,{.46,.69,.70})
                end
                box(x-.535,z,.018,.78,loadBottom+.04,.67,{.46,.69,.70})
                box(x+.535,z,.018,.78,loadBottom+.04,.67,{.46,.69,.70})
            elseif style=="vendor_paper" then
                box(x,z-.414,1.04,.014,loadBottom+.07,.045,{.71,.20,.13})
            end
            if isWrapped and style~="wrapped" then filmWrap(1.08,.82,.79) end
            return
        end
        -- The default load is a low ream stack for legacy paper pallets.
        local paper={.87,.87,.82}
        for level=0,2 do for col=0,2 do
            local px=x+(col-1)*.37
            box(px,z,.34,.78,loadBottom+level*.27,.25,paper)
            box(px,z-.397,.33,.012,loadBottom+.02+level*.27,.20,shade(paper,.83))
        end end
        for _,px in ipairs({x-.50,x+.50}) do box(px,z,.04,.75,loadBottom,.70,wood) end
    end
    local function cutterDoor(x, width, height, color)
        box(x, -.683, width, .025, .20, height, color)
        box(x, -.701, width * .86, .012, .26, .012, shade(color, 1.20))
        box(x + width * .34, -.711, .035, .018, .53, .09, {.68,.70,.68})
    end
    local function pixelWord(label, x, z, bottom, pixel, color)
        local glyphs = {
            P={"110","101","110","100","100"},
            O={"111","101","101","101","111"},
            L={"100","100","100","100","111"},
            A={"010","101","111","101","101"},
            R={"110","101","110","101","101"},
        }
        local advance = pixel * 4
        for letter = 1, #label do
            local glyph = glyphs[label:sub(letter,letter)]
            if glyph then
                for row = 1, 5 do
                    for col = 1, 3 do
                        if glyph[row]:sub(col,col) == "1" then
                            box(x + (letter - 1) * advance + (col - 1) * pixel,
                                z, pixel * .82, .014,
                                bottom + (5 - row) * pixel, pixel * .82, color)
                        end
                    end
                end
            end
        end
    end

    if item.id == "cutter" then
        local charcoal, dark = {.16,.18,.19}, {.055,.065,.07}
        local warmWhite, steel, bed = {.84,.84,.79}, {.48,.53,.53}, {.67,.69,.67}
        local yellow, red = {.96,.66,.04}, {.83,.055,.035}
        local cutterStroke = item.working and math.sin((item.actionPhase or 0) * math.pi) * .50 or 0
        -- Low service cabinet, separated access doors, kick trim and leveling feet.
        bevelBox(0, 0, 2.16, 1.34, .13, .71, charcoal, .055)
        box(0, -.018, 2.19, 1.37, .07, .10, dark)
        for _, x in ipairs({-.69,0,.69}) do cutterDoor(x,.63,.46,steel) end
        for _, x in ipairs({-1.0,1.0}) do
            box(x, -.70, .045, .018, .19, .50, dark)
            box(x, .45, .15, .18, .03, .10, dark)
            cylinderY(x, .48, .06, .02, .06, steel, 12)
        end
        box(0, -.694, 2.02, .018, .77, .035, steel)
        -- Broad polished feed table with extension leaves, seams, gauges and stops.
        bevelBox(0, -.20, 2.82, 1.70, .84, .11, steel, .035)
        bevelBox(0, -.20, 2.73, 1.62, .95, .045, bed, .012)
        box(-1.48, -.18, .20, 1.38, .84, .08, steel)
        box(1.48, -.18, .20, 1.38, .84, .08, steel)
        for x = -1.30, 1.31, .22 do
            box(x, -.20, .012, 1.50, .998, .006, shade(steel,.72))
            box(x, -.965, .018, .08, 1.003, .014, {.76,.77,.73})
        end
        for _, z in ipairs({-.88,.48}) do
            box(0,z,2.55,.028,1.003,.018,shade(steel,.78))
        end
        -- Rear table fence, paired guide rails and the moving paper back-gauge.
        box(0, .56, 2.62, .08, 1.00, .12, dark)
        box(0, .51, 2.44, .025, 1.12, .025, {.76,.77,.72})
        for _, x in ipairs({-.83,.83}) do
            box(x, .44, .07, .34, 1.00, .28, steel)
            box(x, .28, .035, .04, 1.28, .25, dark)
            box(x, .26, .11, .10, 1.52, .07, warmWhite)
        end
        -- White cutter bridge and side cheeks form a recognizable guarded throat.
        bevelBox(0, .18, 2.14, .64, 1.39, .39, warmWhite, .11)
        bevelBox(0, .18, 2.08, .66, 1.75, .08, steel, .025)
        bevelBox(-.97, .14, .34, .72, 1.03, .80, warmWhite, .06)
        bevelBox(.97, .14, .34, .72, 1.03, .80, warmWhite, .06)
        box(-.97, -.235, .38, .04, 1.23, .31, steel)
        box(.97, -.235, .38, .04, 1.23, .31, steel)
        -- Actual cutter opening, yellow safety beam and individually segmented blade guard.
        box(0, -.168, 1.60, .075, 1.15 - cutterStroke, .20, dark)
        box(0, -.218, 1.80, .06, 1.34 - cutterStroke, .085, yellow)
        box(0, -.224, 1.56, .025, 1.12 - cutterStroke, .20, {.10,.12,.13})
        for x = -.72, .73, .105 do
            box(x, -.244, .044, .025, 1.12 - cutterStroke, .18, {.13,.15,.16})
            box(x, -.26, .025, .012, 1.33 - cutterStroke, .045, {.22,.23,.22})
        end
        -- Raised operator console: LCD, bezel, physical keys and emergency stop.
        bevelBox(0, -.184, .72, .09, 1.54, .35, steel, .035)
        bevelBox(0, -.238, .57, .025, 1.64, .19, dark, .012)
        box(-.055, -.255, .40, .018, 1.67, .12, {.06,.15,.18})
        box(-.07, -.267, .26, .012, 1.69, .055, {.18,.68,.72})
        box(.25, -.257, .10, .014, 1.68, .08,
            item.working and {.98,.53,.08} or {.28,.72,.32})
        pixelWord("POLAR", -.98, -.155, 1.65, .022, {.16,.19,.19})
        for _, x in ipairs({-.88,.88}) do
            cylinderZ(x,-.238,.022,1.69,.018,{.30,.32,.31},10)
        end
        for row = 0, 1 do for col = 0, 2 do
            cylinderZ(.18 + col*.12, -.263, .026, 1.51 + row*.065, .025,
                col==0 and {.80,.12,.07} or {.16,.20,.21}, 10)
        end end
        box(.49, -.21, .18, .16, 1.48, .22, dark)
        cylinderZ(.49,-.303,.067,1.60,.06,red,16)
        cylinderZ(.49,-.34,.084,1.52,.025,yellow,16)
        bevelBox(-.97,-.98,.30,.24,.04,.07,dark,.02)
        box(-.97,-.98,.19,.17,.11,.035,steel)
        -- Side ventilation, fasteners and drive rollers expose useful machine detail.
        for side=-1,1,2 do
            for h=.28,.61,.09 do box(side*1.087,-.32,.016,.32,h,.025,dark) end
            for z=-.48,.32,.40 do cylinderY(side*.86,z,.024,.80,.026,steel,8) end
        end
        for _, z in ipairs({-.22,.02,.26}) do cylinderX(0,z,1.70,.045,1.04,dark,16) end
        box(0, .61, 2.38, .045, 1.02, .045, steel)
        item.fpDimensions = {width=3.02, depth=1.72, height=1.83}
    elseif item.id == "stock" or item.id == "pallet" then
        palletContents(item.palletType or "paper",0,0,item.baseHeight or 0,true,item.wrapped)
        item.fpDimensions = {width=1.24, depth=1.10, height=1.24}
    elseif item.id == "forklift" then
        local yellow,lightYellow={.82,.52,.08},{.96,.69,.14}
        local dark,steel,tire={.11,.14,.15},{.43,.49,.49},{.045,.055,.055}
        local forkHeight=math.max(0,math.min(1,item.forkHeight or 0))*.68
        bevelBox(0,-.40,.92,.83,.20,.62,yellow,.09)
        box(0,-.81,.72,.045,.30,.32,dark)
        for _,x in ipairs({-.27,-.15,-.03,.09,.21,.33}) do
            box(x,-.836,.035,.018,.34,.20,steel)
        end
        box(0,-.02,.86,.83,.23,.20,dark)
        box(0,-.02,.76,.74,.42,.075,steel)
        for _,z in ipairs({-.48,.35}) do
            for _,x in ipairs({-.49,.49}) do
                cylinderX(x,z,.20,.22,.22,tire,20)
                cylinderX(x+(x<0 and .105 or -.105),z,.018,.105,.22,steel,16)
                cylinderX(x+(x<0 and .12 or -.12),z,.012,.045,.22,dark,12)
            end
        end
        box(0,-.35,.48,.45,.60,.10,{.08,.10,.10})
        bevelBox(0,-.57,.48,.14,.68,.48,dark,.035)
        box(0,-.15,.045,.06,.48,.44,steel)
        cylinderZ(0,-.15,.17,.92,.035,dark,16)
        box(-.30,-.06,.06,.24,.25,.12,steel)
        box(.30,-.06,.06,.24,.25,.12,steel)
        for _,x in ipairs({-.43,.43}) do
            box(x,-.05,.075,.085,.74,1.22,yellow)
            box(x,-.05,.10,.10,1.91,.12,dark)
            box(x,-.05,.11,.12,1.92,.045,lightYellow)
        end
        box(0,-.05,.93,.11,1.95,.12,dark)
        box(0,-.05,.84,.09,2.01,.055,yellow)
        for _,x in ipairs({-.43,.43}) do
            box(x,.43,.11,.15,.24,1.86,dark)
            box(x+(x<0 and .08 or -.08),.43,.035,.17,.30,1.73,steel)
        end
        box(0,.46,.70,.16,.51,1.24,steel)
        cylinderY(0,.37,.073,.57,.73,{.64,.68,.65},16)
        box(0,.57,.88,.13,forkHeight+.10,.20,dark)
        box(0,.59,.78,.06,forkHeight+.30,.035,lightYellow)
        for _,x in ipairs({-.30,.30}) do
            box(x,.96,.13,1.10,forkHeight,.09,steel)
            box(x,1.48,.13,.11,forkHeight,.12,{.58,.63,.62})
        end
        box(0,-.61,.13,.14,1.76,.20,yellow)
        cylinderY(0,-.61,.09,1.94,.18,{.84,.12,.06},14)
        if item.cargoType then palletContents(item.cargoType,0,1.00,forkHeight+.09,true,item.cargoWrapped) end
        item.fpDimensions={width=1.45,depth=2.65,height=2.14}
    elseif item.id == "palletJack" then
        local steel,blue,dark={.49,.55,.54},{.18,.30,.32},{.075,.09,.09}
        bevelBox(0,-.34,.52,.48,.09,.18,blue,.035)
        box(0,-.36,.40,.20,.25,.10,steel)
        cylinderY(0,-.34,.15,.23,.17,{.33,.38,.38},20)
        box(-.29,.36,.12,1.38,.075,.065,steel)
        box(.29,.36,.12,1.38,.075,.065,steel)
        for _,x in ipairs({-.29,.29}) do
            box(x,1.02,.15,.13,.06,.11,{.65,.68,.65})
            cylinderX(x,1.02,.14,.075,.055,dark,14)
        end
        cylinderX(0,-.39,.39,.15,.15,dark,20)
        cylinderX(0,-.39,.25,.075,.15,steel,16)
        box(0,-.50,.10,.16,.28,.40,blue)
        box(-.055,-.50,.018,.055,.55,.50,steel)
        box(.055,-.50,.018,.055,.55,.50,steel)
        box(0,-.50,.23,.065,1.03,.10,dark)
        box(-.16,-.50,.07,.13,1.04,.07,{.16,.18,.17})
        box(.16,-.50,.07,.13,1.04,.07,{.16,.18,.17})
        box(.20,-.36,.18,.10,.32,.035,{.80,.13,.08})
        if item.cargoType then palletContents(item.cargoType,0,.43,.14,true,item.cargoWrapped) end
        item.fpDimensions={width=1.03,depth=1.88,height=1.18}
    elseif item.id == "wrapper" then
        local blue, blueLight = {.12,.32,.50}, {.19,.43,.63}
        local steel, dark, white = {.55,.59,.59}, {.075,.09,.11}, {.89,.89,.84}
        local loadRotation = item.loadRotation or 0
        local carriageLift = item.wrapping
            and .45 * (.5 - .5 * math.cos((item.actionPhase or 0) * math.pi * 2)) or 0
        -- Wide welded base and brushed-metal turntable with concentric lip.
        box(0,0,1.14,1.15,.06,.15,blue)
        box(0,0,1.08,1.08,.20,.035,dark)
        cylinderY(0,-.04,.48,.22,.075,steel,32)
        cylinderY(0,-.04,.43,.295,.018,{.72,.73,.70},32)
        cylinderY(0,-.04,.39,.313,.008,{.45,.48,.48},32)
        -- Tall rear mast, recessed vertical track and top cable cover.
        bevelBox(-.32,.34,.21,.23,.21,1.57,blue,.035)
        box(-.32,.205,.075,.035,.31,1.34,dark)
        box(-.32,.202,.035,.018,.38,1.20,{.76,.79,.77})
        box(-.32,.34,.27,.29,1.72,.12,blueLight)
        bevelBox(-.32,.34,.31,.32,1.82,.055,dark,.014)
        -- Moving carriage, visible roller hardware and a full-height film roll.
        bevelBox(-.06,.34,.39,.32,.99 + carriageLift,.42,blue,.035)
        box(-.06,.505,.43,.08,1.38 + carriageLift,.07,blueLight)
        box(-.06,.553,.37,.018,1.43 + carriageLift,.025,dark)
        box(.06,.49,.33,.11,1.18 + carriageLift,.11,steel)
        cylinderY(.15,.62,.14,1.02 + carriageLift,.52,white,24)
        cylinderY(.15,.62,.055,.99 + carriageLift,.58,{.18,.21,.22},20)
        cylinderY(.15,.62,.075,.99 + carriageLift,.045,steel,20)
        cylinderY(.15,.62,.075,1.53 + carriageLift,.045,steel,20)
        box(.15,.542,.16,.018,.52 + carriageLift,.48,{.73,.83,.83})
        cylinderX(-.48,-.18,.42,.105,.25,dark,20)
        cylinderX(-.48,-.18,.27,.067,.25,steel,16)
        box(-.48,-.18,.45,.36,.14,.12,dark)
        -- Control box, blue housing, display and physical status buttons.
        bevelBox(.40,.43,.30,.21,1.28,.48,blueLight,.025)
        bevelBox(.40,.552,.22,.025,1.51,.16,dark,.01)
        box(.37,.569,.13,.012,1.54,.09,{.11,.51,.62})
        for i=0,2 do cylinderZ(.31+i*.065,.574,.019,1.36,.025,
            ({red or {.80,.08,.05},yellow or {.95,.67,.08},
                item.wrapping and {.98,.53,.08} or {.12,.68,.23}})[i+1],10) end
        box(.31,.34,.32,.38,.22,.08,dark)
        box(.31,.34,.18,.21,.30,.08,blueLight)
        -- A loaded paper skid makes the film path and wrapping action legible.
        for _, x in ipairs({-.22, 0, .22}) do
            turntableBox(x, -.04, .11, .60, .495, .09, {.42,.27,.13}, loadRotation)
        end
        for z = -.27, .25, .13 do
            turntableBox(0, z, .64, .10, .585, .075, {.60,.42,.23}, loadRotation)
        end
        local paper, side = {.88,.88,.82}, {.71,.74,.71}
        for level = 0, 2 do
            for column = 0, 1 do
                local x = column == 0 and -.16 or .16
                turntableBox(x, -.04, .29, .25, .66 + level * .20, .19, paper, loadRotation)
                turntableBox(x, -.171, .27, .014, .68 + level * .20, .16, side, loadRotation)
                for sheet = 1, 2 do
                    turntableBox(x, -.181, .24, .006, .68 + level * .20 + sheet * .055,
                        .008, {.82,.83,.79}, loadRotation)
                end
            end
        end
        local filmBands = item.wrapped and 4 or item.wrapping
            and math.floor((item.actionPhase or 0) * 4 + .5) or 0
        for band = 1, filmBands do
            local bottom = .72 + (band - 1) * .18
            local film = {.49,.70,.72}
            turntableBox(0, -.205, .54, .018, bottom, .105, film, loadRotation)
            turntableBox(0, .125, .54, .018, bottom, .105, film, loadRotation)
            turntableBox(-.27, -.04, .018, .33, bottom, .105, film, loadRotation)
            turntableBox(.27, -.04, .018, .33, bottom, .105, film, loadRotation)
        end
        item.fpDimensions = {width=1.14, depth=1.15, height=1.88}
    end

    local parts = {}
    for _, batch in pairs(batches) do
        local mesh = love.graphics.newMesh(format, batch.vertices, "triangles", "static")
        mesh:setTexture(white)
        parts[#parts + 1] = {mesh=mesh, color=batch.color}
    end
    item.fpModel = {parts=parts,
        animationFrame=math.floor((item.actionPhase or 0) * 12 + .5),
        working=item.working == true, wrapping=item.wrapping == true,
        wrapped=item.wrapped == true, modelKey=item.modelKey,
        forkHeight=item.forkHeight, cargoType=item.cargoType, baseHeight=item.baseHeight,
        cargoWrapped=item.cargoWrapped}
    item.fpModel.visualScale=item.visualScale
end

function P.draw(item, white, shader)
    local model = item.fpModel
    local animationFrame = math.floor((item.actionPhase or 0) * 12 + .5)
    if not model or model.animationFrame ~= animationFrame
        or model.working ~= (item.working == true)
        or model.wrapping ~= (item.wrapping == true)
        or model.wrapped ~= (item.wrapped == true)
        or model.modelKey ~= item.modelKey or model.forkHeight ~= item.forkHeight
        or model.cargoType ~= item.cargoType or model.baseHeight ~= item.baseHeight
        or model.visualScale ~= item.visualScale or model.cargoWrapped ~= item.cargoWrapped then
        build(item, white)
        model = item.fpModel
    end
    shader:send("modelYaw",(item.rotation or 0)+(item.id=="cutter" and math.pi or 0))
    shader:send("modelPosition",{item.worldX,item.worldZ})
    for _, part in ipairs(model.parts) do
        love.graphics.setColor(part.color[1], part.color[2], part.color[3], 1)
        love.graphics.draw(part.mesh)
    end
    shader:send("modelYaw",0)
    shader:send("modelPosition",{0,0})
    love.graphics.setColor(1,1,1,1)
end

function P.supports(item)
    return item and (item.id == "cutter" or item.id == "stock" or item.id == "pallet"
        or item.id == "wrapper" or item.id == "forklift" or item.id == "palletJack")
end

return P
