local Manifest=require("src.arcade_frontier.first_person_weapon_manifest")
local Actions=require("src.arcade_frontier.first_person_weapon_actions")

local Views={}

function Views.new(loadImage,fileExists,newQuad)
    assert(type(loadImage)=="function","first-person weapon views require an image loader")
    local valid,issues=Manifest.validate()
    assert(valid,"invalid first-person weapon manifest: "..table.concat(issues,"; "))

    local cache={weapon=nil,images={},unavailable={},actionImage=nil,actionQuads=nil,actionUnavailable=false,
        adsActionImage=nil,adsActionQuads=nil,adsActionUnavailable=false}

    function cache:release()
        for _,image in pairs(self.images) do
            if image and image.release then pcall(image.release,image) end
        end
        if self.actionImage and self.actionImage.release then pcall(self.actionImage.release,self.actionImage) end
        if self.adsActionImage and self.adsActionImage.release then pcall(self.adsActionImage.release,self.adsActionImage) end
        self.images={}
        self.unavailable={}
        self.actionImage=nil
        self.actionQuads=nil
        self.actionUnavailable=false
        self.adsActionImage=nil
        self.adsActionQuads=nil
        self.adsActionUnavailable=false
        self.weapon=nil
    end

    function cache:get(weapon,state)
        if self.weapon~=weapon then
            self:release()
            self.weapon=weapon
        end
        local entry=Manifest.weapons[weapon]
        if not entry then return nil end
        local file=entry.views[state or "hip"]
        if not file then return nil end
        if self.unavailable[file] then return nil end
        if self.images[file] then return self.images[file] end
        if fileExists and not fileExists(file) then self.unavailable[file]=true; return nil end
        local image=loadImage(file)
        if image then
            if image.setFilter then pcall(image.setFilter,image,"nearest","nearest") end
            self.images[file]=image
        else
            self.unavailable[file]=true
        end
        return image
    end

    function cache:anchor(weapon)
        return Manifest.anchorFor(weapon)
    end

    function cache:actionFrame(weapon,frame)
        if self.weapon~=weapon then
            self:release()
            self.weapon=weapon
        end
        local file=Manifest.actionAtlasFor(weapon)
        if not file or self.actionUnavailable then return nil end
        if not self.actionImage then
            if fileExists and not fileExists(file) then self.actionUnavailable=true; return nil end
            self.actionImage=loadImage(file)
            if not self.actionImage then self.actionUnavailable=true; return nil end
            if self.actionImage.setFilter then pcall(self.actionImage.setFilter,self.actionImage,"nearest","nearest") end
            local width,height=self.actionImage:getDimensions()
            local cellWidth,cellHeight=width/3,height/2
            if math.abs(cellWidth-Actions.frameSize)>1 or math.abs(cellHeight-Actions.frameSize)>1 then
                self.actionUnavailable=true
                if self.actionImage.release then pcall(self.actionImage.release,self.actionImage) end
                self.actionImage=nil
                return nil
            end
            if type(newQuad)=="function" then
                self.actionQuads={}
                for index=1,6 do
                    local column=(index-1)%3
                    local row=math.floor((index-1)/3)
                    self.actionQuads[index]=newQuad(column*cellWidth,row*cellHeight,cellWidth,cellHeight,width,height)
                end
            end
        end
        local index=math.max(1,math.min(6,math.floor(tonumber(frame) or 1)))
        local quad=self.actionQuads and self.actionQuads[index]
        if not quad then return nil end
        return self.actionImage,quad,Actions.frameSize,Actions.frameSize
    end

    function cache:adsActionFrame(weapon,frame)
        if self.weapon~=weapon then
            self:release()
            self.weapon=weapon
        end
        local file=Manifest.adsActionAtlasFor(weapon)
        if not file or self.adsActionUnavailable then return nil end
        if not self.adsActionImage then
            if fileExists and not fileExists(file) then self.adsActionUnavailable=true; return nil end
            self.adsActionImage=loadImage(file)
            if not self.adsActionImage then self.adsActionUnavailable=true; return nil end
            if self.adsActionImage.setFilter then pcall(self.adsActionImage.setFilter,self.adsActionImage,"nearest","nearest") end
            local width,height=self.adsActionImage:getDimensions()
            local cellWidth,cellHeight=width/2,height/2
            if width%2~=0 or height%2~=0 or cellWidth<1 or cellHeight<1 then
                self.adsActionUnavailable=true
                if self.adsActionImage.release then pcall(self.adsActionImage.release,self.adsActionImage) end
                self.adsActionImage=nil
                return nil
            end
            if type(newQuad)=="function" then
                self.adsActionQuads={}
                for index=1,4 do
                    local column=(index-1)%2
                    local row=math.floor((index-1)/2)
                    self.adsActionQuads[index]=newQuad(column*cellWidth,row*cellHeight,cellWidth,cellHeight,width,height)
                end
            end
        end
        local index=math.max(1,math.min(4,math.floor(tonumber(frame) or 1)))
        local quad=self.adsActionQuads and self.adsActionQuads[index]
        if not quad then return nil end
        local width,height=self.adsActionImage:getDimensions()
        return self.adsActionImage,quad,width/2,height/2
    end

    function cache:states(weapon)
        local entry=Manifest.weapons[weapon]
        return entry and entry.views or nil
    end

    return cache
end

return Views
