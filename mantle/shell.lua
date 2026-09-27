-- Standalone app: mantle -c ./mantle
fonts({ "CaskaydiaCove Nerd Font Propo", "Noto Sans", "Noto Color Emoji" })

local model = require("model")
model.poll()
model.start()

local build_window = require("ui")
return build_window(model)
