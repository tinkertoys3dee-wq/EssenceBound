local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))

-- Compatibility view for the Studio-authored Index tooltip. The real
-- catalog lives in EssenceConfig; deriving this table prevents a newly
-- added essence from silently missing the Index again.
local EssenceDatas = {}
for _, definition in ipairs(EssenceConfig.Ordered) do
	EssenceDatas[definition.Name] = {
		Rarity = definition.RarityName,
		Description = definition.Description,
		Color = definition.Color,
		Glyph = definition.Glyph,
	}
end

return EssenceDatas
