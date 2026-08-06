--[[
    Ensures PotionTimerService starts up as soon as the server boots,
    even if no other script requires it right away.

    Place this Script in ServerScriptService, alongside PotionTimerService
    (as a sibling ModuleScript).
]]

require(script.Parent:WaitForChild("PotionTimerService"))
