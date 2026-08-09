--[[
	TutorialStarterGiftService (Script -> ServerScriptService)
	=============================================================
	Grants a small, one-time, guaranteed essence gift the moment a
	player reaches the tutorial's Upgrades step -- specifically so they
	can actually afford to buy their first upgrade during the tutorial,
	instead of being shown a menu they don't yet have enough essence to
	use at all. A single tutorial-step-1 collection is nowhere near
	root_awakening's 15-essence cost, so without this, the Upgrades step
	was pure narration: point at a menu, say what it does, click Next.
	Same fix, same reasoning, as the tutorial's own orb-collect step --
	"shown a menu" and "actually did the thing" are very different in
	whether it sticks, and a player who can't even try what they're
	being shown is unlikely to come back and try it later unprompted.

	One-time per player, server-validated -- the client (Tutorial.
	client.luau) can only ever ASK for the gift; this is the only thing
	that actually grants it, for a fixed amount that's never taken from
	the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Comfortably covers root_awakening (15 essence, the tree's always-
-- available root) with room to explore a second cheap option too.
local STARTER_GIFT_AMOUNT = 50

local function ensureRemote(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local RequestGiftRemote = ensureRemote(remotesFolder, "RemoteEvent", "RequestTutorialStarterGift")

local function getData(player)
	local module = player:FindFirstChild("PlayerData")
	if not module then
		return nil
	end
	local ok, data = pcall(require, module)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return data
end

RequestGiftRemote.OnServerEvent:Connect(function(player)
	local data = getData(player)
	if not data then
		return
	end

	-- Re-derived from server-owned data, never trusted from the client:
	-- a forged repeat request just hits this same check and gets nothing.
	if data.SeenTutorialStarterGift == true then
		return
	end
	data.SeenTutorialStarterGift = true

	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("Earth Essence")
	if not stat then
		return
	end

	local current = tonumber(stat:GetAttribute("Quantity")) or 0
	stat:SetAttribute("Quantity", current + STARTER_GIFT_AMOUNT)
	data.TotalEssenceGathered = (tonumber(data.TotalEssenceGathered) or 0) + STARTER_GIFT_AMOUNT
end)
