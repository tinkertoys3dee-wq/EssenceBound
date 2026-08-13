local EPMService = {}

-- This table holds the session tracking data so any script can access it
EPMService.ActiveSessions = {}

-- Start a fresh measurement window from the player's current balances. Offline
-- rewards are applied shortly after joining, so adjusting individual starting
-- values is vulnerable to lifecycle/order mistakes. Resnapshotting every
-- balance after the complete grant makes the post-grant state the authoritative
-- baseline and guarantees that none of the welcome-back lump sum enters EPM.
function EPMService.resetBaseline(player)
	local session = EPMService.ActiveSessions[player.UserId]
	local playerDataModule = player:FindFirstChild("PlayerData")
	if not session or not playerDataModule then return false end

	local ok, data = pcall(require, playerDataModule)
	if not ok or not data or not data.Essences then return false end

	for essenceName, essence in pairs(data.Essences) do
		session.StartingEssences[essenceName] = essence.Quantity
	end
	session.JoinTime = os.time()
	return true
end

--=== EPM
function EPMService.getEPM(player)
	local session = EPMService.ActiveSessions[player.UserId]
	if not session then return end -- Absolute fallback

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return session.SavedEPM end

	local data = require(player:WaitForChild("PlayerData"))

	local currentEPM = {}
	for name, essence in pairs(data.Essences) do

		local currentEssence = leaderstats[essence.DisplayName]:GetAttribute("Quantity")
		local essenceGained = currentEssence - session["StartingEssences"][name]

		local minutesPlayed = (os.time() - session.JoinTime) / 60

		-- If they've been playing for less than 2 minutes, the session average is too volatile.
		-- Fall back to their historical saved average.
		if minutesPlayed < 1 then
			return session.SavedEPM
		end
		-- Otherwise, calculate their real-time session average
		-- Solar is a mythic endgame currency. Reusing the legacy 50/minimum
		-- floor would turn a single discovery into thousands of free Solar
		-- after one offline cap and erase every Solar-priced capstone. It can
		-- still be harvested while away, but at a restrained 1/min floor.
		local measuredEPM = math.floor(essenceGained / minutesPlayed)
		if name == "SolarEssence" then
			-- A bounded window also prevents a one-time wheel/daily payout from
			-- becoming the player's permanent offline Solar production rate.
			currentEPM[name] = math.clamp(measuredEPM, 1, 6)
		else
			currentEPM[name] = math.max(measuredEPM, 50)
		end
	end
	-- Return the current average, with a rarity-appropriate safety floor.
	return currentEPM
end

return EPMService
