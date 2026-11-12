# Reference-inspired display font atlases

These two transparent PNGs are single-row bitmap font atlases sized for LÖVE's `love.graphics.newImageFont`. Their glyph order is `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789`. The image font supplies a regular space automatically; the 26 capitals, 26 lowercase letters, and 10 numerals are all present.

The preview sheets show the complete set and a short sample. Each atlas is 132 px em-height in a 224 px canvas, so it can be rendered sharply at large sizes and scaled down with linear filtering.

## Load in LÖVE

```lua
local glyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local base = "assets/fonts/reference-inspired/"

local fonts = {
    groovySlab = love.graphics.newImageFont(base .. "groove_slab.png", glyphs, 2),
    arcadeFlash = love.graphics.newImageFont(base .. "arcade_flash.png", glyphs, 3),
}

for _, font in pairs(fonts) do
    font:setFilter("linear", "linear")
end

love.graphics.setFont(fonts.groovySlab)
love.graphics.push()
love.graphics.translate(32, 32)
love.graphics.scale(0.25) -- 224px atlas height becomes a 56px display font.
love.graphics.print("The Picture Shop 0123456789", 0, 0)
love.graphics.pop()
```

Call `love.graphics.setFont` with either font to switch styles. The atlases are artwork and can be used directly in the game; no system font installation is needed at runtime.

## Styles

- **Groovy Slab** — plump, dark 1970s slab serif with warm ink depth, following the first reference.
- **Arcade Flash** — chunky yellow arcade display letters with red and cyan print plates, following the third reference.

The reference images were used as visual direction. The sets have been redrawn as complete, original atlas artwork using the installed Cooper Black and Bauhaus 93 type styles as construction bases. The included PowerShell generator can recreate the sheets on a Windows machine with those typefaces installed.
