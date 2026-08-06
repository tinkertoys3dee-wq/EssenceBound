local AvatarEditorService = game:GetService("AvatarEditorService")

-- Wait for a bit so they get a chance to play (e.g., 300 seconds = 5 mins)
task.wait(300)


while true do
	pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	task.wait(300)
end