local refill = {}

refill.name = "refill"
refill.depth = -100
refill.placements = {
    {
        name = "one_dash",
        data = {
            twoDash = false
        }
    },
    {
        name = "two_dashes",
        data = {
            twoDash = true
        }
    }
}

function refill.texture(room, entity)
    return entity.twoDash and "objects/refillTwo/idle00" or "objects/refill/idle00"
end

return refill