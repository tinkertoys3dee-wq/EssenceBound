local mainOrb = script.Parent
local angle = 0
local RunService = game:GetService("RunService")

RunService.RenderStepped:Connect(function()
	angle = angle + .7
	mainOrb.Rotation = angle
end)
