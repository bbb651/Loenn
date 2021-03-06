local atlases = require("atlases")
local utils = require("utils")
local drawing = require("drawing")

local drawableSpriteStruct = {}

local drawableSpriteMt = {}
drawableSpriteMt.__index = {}

function drawableSpriteMt.__index:setJustification(justificationX, justificationY)
    self.justificationX = justificationX
    self.justificationY = justificationY

    return self
end

function drawableSpriteMt.__index:setPosition(x, y)
    self.x = x
    self.y = y

    return self
end

function drawableSpriteMt.__index:addPosition(x, y)
    self.x += x
    self.y += y

    return self
end

function drawableSpriteMt.__index:setScale(scaleX, scaleY)
    self.scaleX = scaleX
    self.scaleY = scaleY

    return self
end

function drawableSpriteMt.__index:setOffset(offsetX, offsetY)
    self.offsetX = offsetX
    self.offsetY = offsetY

    return self
end

local function setColor(target, color)
    local tableColor = utils.getColor(color)

    if tableColor then
        target.color = tableColor
    end

    return tableColor ~= nil
end

function drawableSpriteMt.__index:setColor(color)
    return setColor(self, color)
end

-- TODO - Verify that scales are correct
function drawableSpriteMt.__index:getRectangleRaw()
    local x = self.x
    local y = self.y

    local width = self.meta.width
    local height = self.meta.height

    local realWidth = self.meta.realWidth
    local realHeight = self.meta.realHeight

    local offsetX = self.offsetX or self.meta.offsetX
    local offsetY = self.offsetY or self.meta.offsetY

    local justificationX = self.justificationX
    local justificationY = self.justificationY

    local rotation = self.rotation

    local scaleX = self.scaleX
    local scaleY = self.scaleY

    local drawX = math.floor(x - (realWidth * justificationX + offsetX) * scaleX)
    local drawY = math.floor(y - (realHeight * justificationY + offsetY) * scaleY)

    drawX += (scaleX < 0 and width * scaleX or 0)
    drawY += (scaleY < 0 and height * scaleY or 0)

    local drawWidth = width * math.abs(scaleX)
    local drawHeight = height * math.abs(scaleY)

    -- TODO - Test this in more cases
    -- Assume only 90 degree angles
    if rotation and rotation ~= 0 then
        local drawOffsetX = x - drawX
        local drawOffsetY = y - drawY

        local drawOffsetXRotated = drawOffsetX * math.cos(rotation) - drawOffsetY * math.sin(rotation)
        local drawOffsetYRotated = drawOffsetX * math.sin(rotation) + drawOffsetY * math.cos(rotation)
        local widthRotated = drawWidth * math.cos(rotation) - drawHeight * math.sin(rotation)
        local heightRotated = drawWidth * math.sin(rotation) + drawHeight * math.cos(rotation)

        drawX = drawX + drawOffsetX - widthRotated * (1 - justificationX) - drawOffsetXRotated * justificationX
        drawY = drawY + drawOffsetY - heightRotated * (1 - justificationY) - drawOffsetYRotated * justificationY

        drawWidth = widthRotated
        drawHeight = heightRotated
    end

    return drawX, drawY, drawWidth, drawHeight
end

function drawableSpriteMt.__index:getRectangle()
    return utils.rectangle(self:getRectangleRaw())
end

function drawableSpriteMt.__index:drawRectangle(mode, color)
    mode = mode or "fill"

    if color then
        drawing.callKeepOriginalColor(function()
            love.graphics.setColor(color)
            love.graphics.rectangle(mode, self:getRectangleRaw())
        end)

    else
        love.graphics.rectangle(mode, self:getRectangleRaw())
    end
end

function drawableSpriteMt.__index:draw()
    local offsetX = self.offsetX or ((self.justificationX or 0.0) * self.meta.realWidth + self.meta.offsetX)
    local offsetY = self.offsetY or ((self.justificationY or 0.0) * self.meta.realHeight + self.meta.offsetY)

    if self.color and type(self.color) == "table" then
        drawing.callKeepOriginalColor(function()
            love.graphics.setColor(self.color)
            love.graphics.draw(self.meta.image, self.quad, self.x, self.y, self.rotation, self.scaleX, self.scaleY, offsetX, offsetY)
        end)

    else
        love.graphics.draw(self.meta.image, self.quad, self.x, self.y, self.rotation, self.scaleX, self.scaleY, offsetX, offsetY)
    end
end

function drawableSpriteStruct.spriteFromMeta(meta, data)
    data = data or {}

    local drawableSprite = {
        _type = "drawableSprite"
    }

    drawableSprite.x = data.x or 0
    drawableSprite.y = data.y or 0

    drawableSprite.justificationX = data.jx or data.justificationX or 0.5
    drawableSprite.justificationY = data.jy or data.justificationY or 0.5

    drawableSprite.scaleX = data.sx or data.scaleX or 1
    drawableSprite.scaleY = data.sy or data.scaleY or 1

    drawableSprite.rotation = data.r or data.rotation or 0

    drawableSprite.depth = data.depth

    drawableSprite.meta = meta
    drawableSprite.quad = meta and meta.quad or nil

    setColor(drawableSprite, data.color)

    return setmetatable(drawableSprite, drawableSpriteMt)
end

function drawableSpriteStruct.spriteFromTexture(texture, data)
    local atlas = data and data.atlas or "gameplay"
    local spriteMeta = atlases.getResource(texture, atlas)

    return drawableSpriteStruct.spriteFromMeta(spriteMeta, data)
end

return drawableSpriteStruct