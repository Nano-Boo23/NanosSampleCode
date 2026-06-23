local Framework = require(game:GetService("ReplicatedStorage").Framework)

_G.Framework = Framework

Framework.Startup() --could yield a bit

Framework.Logger.startupInfo(script.Name, "Fully loaded")
