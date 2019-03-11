local autotiler = require("autotiler")
local spriteLoader = require("sprite_loader")
local drawing = require("drawing")
local viewportHandler = require("viewport_handler")
local fileLocations = require("file_locations")
local colors = require("colors")
local tasks = require("task")
local utils = require("utils")
local atlases = require("atlases")
local entityHandler = require("entities")
local smartDrawingBatch = require("structs/smart_drawing_batch")
local drawableSprite = require("structs/drawable_sprite")
local drawableFunction = require("structs/drawable_function")

local tilesetFileFg = fileLocations.getResourceDir() .. "/XML/ForegroundTiles.xml"
local tilesetFileBg = fileLocations.getResourceDir() .. "/XML/BackgroundTiles.xml"

local tilesMetaFg = autotiler.loadTilesetXML(tilesetFileFg)
local tilesMetaBg = autotiler.loadTilesetXML(tilesetFileBg)

local triggerFontSize = 1

local tilesSpriteMetaCache = {}

local celesteRender = {}

local tilesFgDepth = -10000
local tilesBgDepth = 10000

local decalsFgDepth = -10500
local decalsBgDepth = 9000

local triggersDepth = -math.huge

local PRINT_BATCHING_DURATION = true

-- Temp
local roomCache = {}

local function getRoomBackgroundColor(room)
    local color = room.color or 0

    if color >= 0 and color < #colors.roomBackgroundColors then
        return colors.roomBackgroundColors[color + 1]

    else
        return colors.roomBackgroundDefault
    end
end

local function getRoomBorderColor(room)
    local color = room.color or 0

    if color >= 0 and color < #colors.roomBorderColors then
        return colors.roomBorderColors[color + 1]

    else
        return colors.roomBorderDefault
    end
end

local function getOrCacheTileSpriteMeta(cache, tile, texture, quad, fg)
    cache[tile] = cache[tile] or {}
    cache[tile][fg] = cache[tile][fg] or table.filled(false, {6, 15})

    local quadCache = cache[tile][fg]
    local quadX, quadY = quad[1], quad[2]
    
    if not quadCache[quadX + 1, quadY + 1] then
        local spriteMeta = atlases.gameplay[texture]
        local spritesWidth, spritesHeight = spriteMeta.image:getDimensions
        local quad = love.graphics.newQuad(spriteMeta.x - spriteMeta.offsetX + quadX * 8, spriteMeta.y - spriteMeta.offsetY + quadY * 8, 8, 8, spritesWidth, spritesHeight)

        local newSpritesMeta = table.shallowcopy(spriteMeta)
        newSpritesMeta.quad = quad

        quadCache[quadX + 1, quadY + 1] = newSpritesMeta
    end

    return quadCache[quadX + 1, quadY + 1]
end

function celesteRender.getTilesBatch(tiles, meta, fg)
    local tiles = tiles.matrix

    -- Getting upvalues
    local gameplayAtlas = atlases.gameplay
    local cache = tilesSpriteMetaCache
    local autotiler = autotiler
    local meta = meta

    local airTile = "0"
    local empty = ""
    local wildcard = "*"

    local defaultQuad = ${{0, 0}}
    local defaultSprite = ""

    local drawableSpriteType = "drawableSprite"

    local width, height = tiles:size
    local batch = smartDrawingBatch.createBatch()

    for x = 1, width do
        for y = 1, height do
            local tile = tiles[x, y]
            cache[tile] = cache[tile] or {}

            if tile ~= airTile then
                local quads, sprites = autotiler.getQuads(x, y, tiles, meta, airTile, wildcard, defaultQuad, defaultSprite)
                local quadCount = quads:len

                if quadCount > 0 then
                    local randQuad = quadCount == 1 and quads[1] or quads[math.random(1, quadCount)]
                    local texture = meta.paths[tile] or empty

                    local spriteMeta = getOrCacheTileSpriteMeta(cache, tile, texture, randQuad, fg)

                    local drawable = {
                        _type = drawableSpriteType,

                        meta = spriteMeta,

                        x = x * 8 - 8,
                        y = y * 8 - 8,

                        offsetX = 0,
                        offsetY = 0
                    }

                    batch:add(drawable)
                end
            end
        end

        coroutine.yield()
    end

    coroutine.yield(batch)
end

local function getRoomTileBatch(room, tiles, fg)
    local key = fg and "fgTiles" or "bgTiles"
    local meta = fg and tilesMetaFg or tilesMetaBg

    roomCache[room.name] = roomCache[room.name] or {}
    roomCache[room.name][key] = roomCache[room.name][key] or tasks.newTask(
        (-> celesteRender.getTilesBatch(tiles, meta, fg)),
        (task -> PRINT_BATCHING_DURATION and print(string.format("Batching '%s' in '%s' took %s ms", key, room.name, task.timeTotal * 1000)))
    )

    return roomCache[room.name][key].result
end

function celesteRender.getTilesFgBatch(room, tiles, viewport)
    return getRoomTileBatch(room, tiles, true)
end

function celesteRender.getTilesBgBatch(room, tiles, viewport)
    return getRoomTileBatch(room, tiles, false)
end

function celesteRender.drawTilesFg(room, tiles)
    local batch = celesteRender.getTilesFgBatch(room, tiles)

    if batch then
        love.graphics.draw(batch, 0, 0)
    end
end

function celesteRender.drawTilesBg(room, tiles)
    local batch = celesteRender.getTilesBgBatch()

    if batch then
        love.graphics.draw(batch, 0, 0)
    end
end

local function getDecalsBatch(decals)
    local batch = smartDrawingBatch.createBatch()

    for i, decal <- decals do
        local texture = decal.texture
        local meta = atlases.gameplay[texture]

        local x = decal.x or 0
        local y = decal.y or 0

        local scaleX = decal.scaleX or 1
        local scaleY = decal.scaleY or 1

        local drawable = drawableSprite.spriteFromTexture(texture)
        drawable:setScale(scaleX, scaleY)
        drawable:setOffset(0, 0) -- No automagicall calculations
        drawable:setPosition(
            x - meta.offsetX * scaleX - math.floor(meta.realWidth / 2) * scaleX,
            y - meta.offsetY * scaleY - math.floor(meta.realHeight / 2) * scaleY
        )

        if meta then
            batch:add(drawable)
        end

        if i % 10 == 0 then
            coroutine.yield()
        end
    end

    coroutine.yield(batch)
end

local function getRoomDecalsBatch(room, decals, fg)
    local key = fg and "decalsFg" or "decalsBg"

    roomCache[room.name] = roomCache[room.name] or {}
    roomCache[room.name][key] = roomCache[room.name][key] or tasks.newTask(
        (-> getDecalsBatch(decals)),
        (task -> PRINT_BATCHING_DURATION and print(string.format("Batching '%s' in '%s' took %s ms", key, room.name, task.timeTotal * 1000)))
    )

    return roomCache[room.name][key].result
end

function celesteRender.getDecalsFgBatch(room, decals, viewport)
    return getRoomDecalsBatch(room, decals, true)
end

function celesteRender.getDecalsBgBatch(room, decals, viewport)
    return getRoomDecalsBatch(room, decals, false)
end

function celesteRender.drawDecalsFg(room, decals)
    local batch = celesteRender.getDecalsFgBatch(room, decals)

    if batch then
        love.graphics.draw(batch, 0, 0)
    end
end

function celesteRender.drawDecalsBg(room, decals)
    local batch = celesteRender.getDecalsBgBatch(room, decals)

    if batch then
        love.graphics.draw(batch, 0, 0)
    end
end

local function getOrCreateSmartBatch(batches, key)
    batches[key] = batches[key] or smartDrawingBatch.createBatch()

    return batches[key]
end

local function getEntityBatchTaskFunc(room, entities, viewport, registeredEntities)
    local batches = {}

    for i, entity <- entities do
        local name = entity._name
        local handler = registeredEntities[name]

        if handler then
            local defaultDepth = type(handler.depth) == "function" and handler.depth(room, entity, viewport) or handler.depth or 0

            if handler.sprite then
                local sprites = handler.sprite(room, entity, viewport)

                if sprites then
                    local spriteCount = sprites.len and sprites:len or #sprites

                    if spriteCount == 0 and utils.typeof(sprites) == "drawableSprite" then
                        local batch = getOrCreateSmartBatch(batches, sprites.depth or defaultDepth)
                        batch:add(sprites)

                    else
                        for i, sprite <- sprites do
                            if utils.typeof(sprite) == "drawableSprite" then
                                local batch = getOrCreateSmartBatch(batches, sprite.depth or defaultDepth)
                                batch:add(sprite)
                            end
                        end
                    end
                end
            end

            if handler.draw then
                local batch = getOrCreateSmartBatch(batches, defaultDepth)
                batch:add(drawableFunction.fromFunction(handler.draw, room, entity, viewport))
            end

            if i % 10 == 0 then
                coroutine.yield()
            end
        end
    end

    coroutine.yield(batches)
end

function celesteRender.getEntityBatch(room, entities, viewport, forceRedraw)
    local registeredEntities = registeredEntities or entityHandler.registeredEntities
    
    roomCache[room.name] = roomCache[room.name] or {}

    if forceRedraw and roomCache[room.name].entities.result ~= nil then
        roomCache[room.name].entities = nil
    end

    roomCache[room.name].entities = roomCache[room.name].entities or tasks.newTask(
        (-> getEntityBatchTaskFunc(room, entities, viewport, registeredEntities)),
        (task -> PRINT_BATCHING_DURATION and print(string.format("Batching 'entities' in '%s' took %s ms", room.name, task.timeTotal * 1000)))
    )

    return roomCache[room.name].entities.result
end

local function getTriggerBatchTaskFunc(room, triggers, viewport)
    local font = love.graphics.getFont()
    local batch = smartDrawingBatch.createBatch()

    for i, trigger <- triggers do
        local func = function()
            local name = trigger._name or ""
            local displayName = utils.humanizeVariableName(name)

            local x = trigger.x or 0
            local y = trigger.y or 0

            local width = trigger.width or 16
            local height = trigger.height or 16

            love.graphics.setColor(colors.triggerColor)
            
            love.graphics.rectangle("line", x, y, width, height)
            love.graphics.rectangle("fill", x, y, width, height)

            love.graphics.setColor(colors.triggerTextColor)

            local longest, lines = font:getWrap(displayName, width)
            local textHeight = #lines * (font:getHeight() * font:getLineHeight())

            local offsetX = 0
            local offsetY = (textHeight - height) / 2

            love.graphics.printf(displayName, x, y, width, "center", 0, triggerFontSize, triggerFontSize, offsetX, offsetY)
            
            love.graphics.setColor(colors.default)
        end

        batch:add(drawableFunction.fromFunction(func))

        if i % 10 == 0 then
            coroutine.yield()
        end
    end

    coroutine.yield(batch)
end

function celesteRender.getTriggerBatch(room, triggers, viewport, forceRedraw)
    roomCache[room.name] = roomCache[room.name] or {}

    if forceRedraw and roomCache[room.name].triggers.result ~= nil then
        roomCache[room.name].triggers = nil
    end

    roomCache[room.name].triggers = roomCache[room.name].triggers or tasks.newTask(
        (-> getTriggerBatchTaskFunc(room, triggers, viewport)),
        (task -> PRINT_BATCHING_DURATION and print(string.format("Batching 'triggers' in '%s' took %s ms", room.name, task.timeTotal * 1000)))
    )

    return roomCache[room.name].triggers.result
end

function celesteRender.drawTriggers(room, triggers, viewport)
    local batch = celesteRender.getTriggerBatch(room, triggers, viewport)

    batch:draw()
end

local depthBatchingFunctions = {
    {"Background Tiles", "tilesBg", celesteRender.getTilesBgBatch, tilesBgDepth},
    {"Background Decals", "decalsBg", celesteRender.getDecalsBgBatch, decalsBgDepth},
    {"Entities", "entities", celesteRender.getEntityBatch},
    {"Foreground Tiles", "tilesFg", celesteRender.getTilesFgBatch, tilesFgDepth},
    {"Foreground Decals", "decalsFg", celesteRender.getDecalsFgBatch, decalsFgDepth},
    {"Triggers", "triggers", celesteRender.getTriggerBatch, triggersDepth}
}

function celesteRender.getRoomBatches(room, viewport)
    roomCache[room.name] = roomCache[room.name] or {}

    if not roomCache[room.name].complete then
        local depthBatches = {}
        local done = true

        for i, data <- depthBatchingFunctions do
            local description, key, func, depth = unpack(data)
            local batches = func(room, room[key], viewport)

            if batches then
                if depth then
                    depthBatches[depth] = batches

                else
                    for depth, batch <- batches do
                        depthBatches[depth] = batch
                    end
                end

            else
                done = false
            end
        end

        -- Not done, but all the tasks have been started
        -- Attempt to render other rooms while we wait
        if not done then
            return
        end

        local orderedBatches = $()

        for depth, batches <- depthBatches do
            orderedBatches += {depth, batches}
        end

        orderedBatches := sortby(v -> v[1])
        orderedBatches := reverse
        orderedBatches := map(v -> v[2])

        roomCache[room.name].complete = orderedBatches
    end

    return roomCache[room.name].complete
end

function celesteRender.drawRoom(room, viewport)
    local roomX = room.x or 0
    local roomY = room.y or 0

    local width = room.width or 40 * 8
    local height = room.height or 23 * 8

    local backgroundColor = getRoomBackgroundColor(room)
    local borderColor = getRoomBorderColor(room)

    love.graphics.push()

    love.graphics.translate(math.floor(-viewport.x), math.floor(-viewport.y))
    love.graphics.scale(viewport.scale, viewport.scale)
    love.graphics.translate(roomX, roomY)

    love.graphics.setColor(backgroundColor)
    love.graphics.rectangle("fill", 0, 0, width, height)

    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", 0, 0, width, height)

    love.graphics.setColor(colors.default)

    local orderedBatches = celesteRender.getRoomBatches(room, viewport)

    if orderedBatches then
        for depth, batch <- orderedBatches do
            batch:draw()
        end
    end

    love.graphics.pop()
end

function celesteRender.drawFiller(filler, viewport)
    local x = filler.x * 8
    local y = filler.y * 8

    local width = filler.width * 8
    local height = filler.height * 8

    love.graphics.push()

    love.graphics.translate(math.floor(-viewport.x), math.floor(-viewport.y))
    love.graphics.scale(viewport.scale, viewport.scale)
    love.graphics.translate(x, y)

    love.graphics.setColor(colors.fillerColor)
    love.graphics.rectangle("fill", 0, 0, width, height)

    love.graphics.setColor(colors.default)

    love.graphics.pop()
end

function celesteRender.drawMap(map)
    if map.result then
        local map = map.result
        local viewport = viewportHandler.viewport

        if viewport.visible then
            for i, room <- map.rooms do
                if viewportHandler.roomVisible(room, viewport) then
                    celesteRender.drawRoom(room, viewport)
                end
            end

            for i, filler <- map.fillers do
                -- TODO - Don't draw out of view fillers
                -- ... Even though checking if they are out of view is probably more expensive than drawing it
                celesteRender.drawFiller(filler, viewport)
            end
        end
    end
end

return celesteRender