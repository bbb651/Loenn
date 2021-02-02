-- TODO Editing options: mode

local miniTextBox = {}

miniTextBox.name = "minitextboxTrigger"
miniTextBox.placements = {
    name = "mini_text_box",
    data = {
        dialog_id = "",
        mode = "OnPlayerEnter",
        only_once = true,
        death_count = -1
    }
}

return miniTextBox