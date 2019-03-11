local xml2lua = require("xml2lua.xml2lua")
local utils = require("utils")

local autotiler = {}

local function convertMaskString(s)
    local res = table.filled(0, {3, 3})
    local raw = s:gsub("x", "2")
    local rows = $(raw):split("-")

    for y, row <- rows do
        local rowValues = $(row):map(v -> tonumber(v))

        for x, value <- rowValues do
            res[x, y] = value
        end
    end

    return res
end

local function checkMask(adjacent, mask)
    for i = 1, 9 do
        if mask[i] ~= 2 then
            if adjacent[i] ~= (mask[i] == 1) then
                return false
            end
        end
    end

    return true
end

local function checkTile(value, target, ignore, air, wildcard)
    if ignore then
        return not (target == air or ignore[target] or (ignore[wildcard] and value ~= target))
    end

    return target ~= air
end

-- Unrolled
local function checkMaskFromTiles(mask, a, b, c, d, e, f, g, h, i)
    return not (
        mask[1] ~= 2 and a ~= (mask[1] == 1) or
        mask[2] ~= 2 and b ~= (mask[2] == 1) or
        mask[3] ~= 2 and c ~= (mask[3] == 1) or
        mask[4] ~= 2 and d ~= (mask[4] == 1) or
        mask[5] ~= 2 and e ~= (mask[5] == 1) or
        mask[6] ~= 2 and f ~= (mask[6] == 1) or
        mask[7] ~= 2 and g ~= (mask[7] == 1) or
        mask[8] ~= 2 and h ~= (mask[8] == 1) or
        mask[9] ~= 2 and i ~= (mask[9] == 1)
    )
end

local function getTile(tiles, x, y)
    return tiles:get(" ", x, y)
end

local function checkPadding(tiles, x, y)
    local airTile = "0"

    return getTile(tiles, x - 2, y) == airTile or getTile(tiles, x + 2, y) == airTile or getTile(tiles, x, y - 2) == airTile or getTile(tiles, x, y + 2) == airTile
end

local function sortByScore(masks)
    local res = masks

    -- TODO - TBI
    -- Is this needed?

    return res
end

local function getPaddingOrCenterQuad(x, y, tile, tiles, meta, defaultQuad, defaultSprite)
    if checkPadding(tiles, x, y) then
        local padding = meta.padding[tile]

        return padding:len > 0 and padding or defaultQuad, defaultSprite

    else
        local center = meta.center[tile]
        
        return center:len > 0 and center or defaultQuad, defaultSprite
    end
end

local function getMaskQuads(masks, adjacent)
    if masks then
        for i, maskData <- masks do
            if checkMask(adjacent, maskData.mask) then
                return true, maskData.quads, maskData.sprites
            end
        end
    end

    return false, nil, nil
end

local function getMaskQuadsFromTiles(x, y, masks, tiles, tile, ignore, air, wildcard)
    if masks then
        local checkTile = checkTile

        local a, b, c = checkTile(tile, tiles:get(tile, x - 1, y - 1), ignore, air, wildcard), checkTile(tile, tiles:get(tile, x + 0, y - 1), ignore, air, wildcard), checkTile(tile, tiles:get(tile, x + 1, y - 1), ignore, air, wildcard)
        local d, e, f = checkTile(tile, tiles:get(tile, x - 1, y + 0), ignore, air, wildcard), checkTile(tile, tile, ignore, air, wildcard), checkTile(tile, tiles:get(tile, x + 1, y + 0), ignore, air, wildcard)
        local g, h, i = checkTile(tile, tiles:get(tile, x - 1, y + 1), ignore, air, wildcard), checkTile(tile, tiles:get(tile, x + 0, y + 1), ignore, air, wildcard), checkTile(tile, tiles:get(tile, x + 1, y + 1), ignore, air, wildcard)

        for i, maskData <- masks do
            if checkMaskFromTiles(maskData.mask, a, b, c, d, e, f, g, h, i) then
                return true, maskData.quads, maskData.sprites
            end
        end
    end

    return false, nil, nil
end

function autotiler.getQuads(x, y, tiles, meta, airTile, wildcard, defaultQuad, defaultSprite)
    local tile = tiles[x, y]

    local masks = meta.masks[tile]
    local ignore = meta.ignores[tile]

    local matches, quads, sprites = getMaskQuadsFromTiles(x, y, masks, tiles, tile, ignore, airTile, wildcard)

    if matches then
        return quads, sprites

    else
        return getPaddingOrCenterQuad(x, y, tile, tiles, meta, defaultQuad, defaultSprite)
    end
end

-- TODO - TBI, see if its actually worth it
function autotiler.getAllQuads(tiles, meta)
    local width, height = tiles:size
    local res = table.filled(false, {width, height})

    return res
end

local function convertTileString(s)
    local res = $()
    local parts = $(s):split(";")

    for i, part <- parts do
        local numbers = $(part):split(",")

        res += {
            tonumber(numbers[1]),
            tonumber(numbers[2])
        }
    end

    return res
end

function autotiler.loadTilesetXML(fn)
    local handler = require("xml2lua.xmlhandler.tree")
    local parser = xml2lua.parser(handler)
    local xml = utils.stripByteOrderMark(utils.readAll(fn, "rb"))

    parser:parse(xml)

    local paths = {}
    local masks = {}
    local padding = {}
    local center = {}
    local ignores = {}

    -- TODO - sort tilesets that copy others to the end?
    -- Is this needed?

    for i, tileset <- handler.root.Data.Tileset do
        local id = tileset._attr.id
        local path = tileset._attr.path
        local copy = tileset._attr.copy
        local ignore = tileset._attr.ignores

        paths[id] = "tilesets/" .. path

        if ignore then
            -- TODO - Check assumption, none of the XML files have mutliple ignores without wildcard
            ignores[id] = table.flip($(ignore):split(";"))
        end

        padding[id] = copy and $(table.shallowcopy(padding[copy]())) or $()
        center[id] = copy and $(table.shallowcopy(center[copy]())) or $()
        masks[id] = copy and $(table.shallowcopy(masks[copy]())) or $()

        currentMasks = $()

        for j, child <- tileset.set or {} do
            local attrs = child._attr or child

            local mask = attrs.mask
            local tiles = attrs.tiles or ""
            local sprites = attrs.sprites or ""

            if mask == "padding" then
                padding[id] = convertTileString(tiles)

            elseif mask == "center" then
                center[id] = convertTileString(tiles)

            else
                currentMasks += {
                    mask = convertMaskString(mask),
                    quads = convertTileString(tiles),
                    sprites = sprites
                }
            end
        end

        if currentMasks:len > 0 then
            masks[id] = sortByScore(currentMasks)
        end
    end

    return {
        paths = paths,
        masks = masks,
        center = center,
        padding = padding,
        ignores = ignores
    }
end

return autotiler