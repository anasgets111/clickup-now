-- Standalone app: mantle -c ./mantle
fonts({ "CaskaydiaCove Nerd Font Propo", "Noto Sans", "Noto Color Emoji" })
mantle.system:configure({ interval = 60 })

local model = require("model")
timer(90000, model.poll)
model.start()

local build_window = require("ui")
return build_window(model)
