--[[
	AstralForgeService (Script -> ServerScriptService)
	==================================================
	Server-authoritative crafting, persistence, daily rotation and active-boon
	lifecycle for the Astral Forge. The client chooses only a recipe id. This
	service validates unlocks and every currency, performs the transaction,
	advances permanent mastery, and owns all gameplay attributes.

	One infusion may be active at a time. Crafting a new one replaces the old
	one; recrafting the same one refreshes it from the current moment. Absolute
	Unix timestamps keep the timer honest across reconnects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AstralForgeConfig = require(ReplicatedStorage:WaitForChild("AstralForgeConfig"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local function ensureRemote(parent: Instance, className: string, name: string)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		warn(("AstralForgeService: %s exists as %s, expected %s"):format(name, existing.ClassName, className))
		existing:Destroy()
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("AstralForgeRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "AstralForgeRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local SyncRemote = ensureRemote(remotesFolder, "RemoteEvent", "ForgeSync")
local CraftFunction = ensureRemote(remotesFolder, "RemoteFunction", "CraftRecipe")
local GetStateFunction = ensureRemote(remotesFolder, "RemoteFunction", "GetForgeState")

-- =========================================================================
-- DATA + STATE
-- =========================================================================

local function getData(player: Player)
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

local function getForge(player: Player)
	local data = getData(player)
	if not data then
		return nil, nil
	end

	if type(data.Forge) ~= "table" then
		data.Forge = {}
	end
	local forge = data.Forge

	forge.ActiveRecipeId = type(forge.ActiveRecipeId) == "string" and forge.ActiveRecipeId or ""
	forge.ExpiresAt = math.max(0, math.floor(tonumber(forge.ExpiresAt) or 0))
	forge.ActiveDuration = math.max(0, math.floor(tonumber(forge.ActiveDuration) or 0))
	forge.TotalCrafts = math.max(0, math.floor(tonumber(forge.TotalCrafts) or 0))
	if type(forge.RecipeCrafts) ~= "table" then
		forge.RecipeCrafts = {}
	end
	for recipeId, count in pairs(forge.RecipeCrafts) do
		if not AstralForgeConfig.GetRecipe(recipeId) then
			forge.RecipeCrafts[recipeId] = nil
		else
			forge.RecipeCrafts[recipeId] = math.max(0, math.floor(tonumber(count) or 0))
		end
	end

	if forge.ActiveRecipeId ~= "" and not AstralForgeConfig.GetRecipe(forge.ActiveRecipeId) then
		forge.ActiveRecipeId = ""
		forge.ExpiresAt = 0
		forge.ActiveDuration = 0
	end

	return forge, data
end

local expiryGenerations = {}
local scheduledExpiryKeys = {}

local function setNeutralAttributes(player: Player)
	player:SetAttribute("ForgeActiveRecipeId", "")
	player:SetAttribute("ForgeExpiresAt", 0)
	player:SetAttribute("ForgeEssenceMultiplier", 1)
	player:SetAttribute("ForgeCritChanceBonus", 0)
	player:SetAttribute("ForgeRareWeightMultiplier", 1)
end

local function mirrorProgressionAttributes(player: Player, forge)
	local mastery = AstralForgeConfig.GetMastery(forge.TotalCrafts, forge.RecipeCrafts)
	player:SetAttribute("ForgeTotalCrafts", forge.TotalCrafts)
	player:SetAttribute("ForgeMasteryTier", mastery.Tier)
end

local function applyRecipeAttributes(player: Player, recipe, expiresAt: number)
	player:SetAttribute("ForgeActiveRecipeId", recipe.Id)
	player:SetAttribute("ForgeExpiresAt", expiresAt)
	player:SetAttribute("ForgeEssenceMultiplier", tonumber(recipe.EssenceMultiplier) or 1)
	player:SetAttribute("ForgeCritChanceBonus", tonumber(recipe.CritChanceBonus) or 0)
	player:SetAttribute("ForgeRareWeightMultiplier", tonumber(recipe.RareWeightMultiplier) or 1)
end

local function buildClientState(player: Player, forge)
	local now = os.time()
	local activeRecipe = AstralForgeConfig.GetRecipe(forge.ActiveRecipeId)
	local activeId = activeRecipe and forge.ExpiresAt > now and forge.ActiveRecipeId or ""
	local mastery, nextMastery = AstralForgeConfig.GetMastery(forge.TotalCrafts, forge.RecipeCrafts)
	local featured = AstralForgeConfig.GetFeaturedRecipe(now)

	return {
		ServerNow = now,
		FeaturedRecipeId = featured and featured.Id or "",
		SecondsUntilRotation = AstralForgeConfig.GetSecondsUntilRotation(now),
		ActiveRecipeId = activeId,
		ExpiresAt = activeId ~= "" and forge.ExpiresAt or 0,
		ActiveDuration = activeId ~= "" and math.max(1, forge.ActiveDuration) or 0,
		TotalCrafts = forge.TotalCrafts,
		RecipeCrafts = table.clone(forge.RecipeCrafts),
		MasteryTier = mastery.Tier,
		MasteryName = mastery.Name,
		MasteryDurationMultiplier = mastery.DurationMultiplier,
		NextMasteryCrafts = nextMastery and nextMastery.CraftsRequired or nil,
		Rebirths = tonumber(player:GetAttribute("Rebirths")) or 0,
	}
end

local function pushState(player: Player, forgeOverride)
	local forge = forgeOverride or getForge(player)
	if forge and player.Parent then
		SyncRemote:FireClient(player, buildClientState(player, forge))
	end
end

local function clearExpired(player: Player, expectedRecipeId: string?, expectedExpiresAt: number?, notify: boolean?)
	local forge = getForge(player)
	if not forge then
		return
	end
	if expectedRecipeId and forge.ActiveRecipeId ~= expectedRecipeId then
		return
	end
	if expectedExpiresAt and forge.ExpiresAt ~= expectedExpiresAt then
		return
	end
	if forge.ExpiresAt > os.time() then
		return
	end

	local expiredRecipe = AstralForgeConfig.GetRecipe(forge.ActiveRecipeId)
	forge.ActiveRecipeId = ""
	forge.ExpiresAt = 0
	forge.ActiveDuration = 0
	setNeutralAttributes(player)
	pushState(player, forge)

	if notify and expiredRecipe then
		NotificationService.Send(player, {
			Kind = "Info",
			Title = "Forge Flame Faded",
			Message = expiredRecipe.Name .. " has ended. Return to the Astral Forge when you're ready to infuse again.",
			Icon = "⚒",
			Key = "forge-expired",
			Duration = 4.5,
		})
	end
end

local function scheduleExpiry(player: Player, recipeId: string, expiresAt: number)
	local expiryKey = recipeId .. ":" .. tostring(expiresAt)
	if scheduledExpiryKeys[player] == expiryKey then
		return
	end

	scheduledExpiryKeys[player] = expiryKey
	expiryGenerations[player] = (expiryGenerations[player] or 0) + 1
	local generation = expiryGenerations[player]
	local delaySeconds = math.max(0, expiresAt - os.time())

	task.delay(delaySeconds + 0.1, function()
		if not player.Parent or expiryGenerations[player] ~= generation then
			return
		end
		scheduledExpiryKeys[player] = nil
		clearExpired(player, recipeId, expiresAt, true)
	end)
end

local function reconcileActiveEffect(player: Player, forge)
	local recipe = AstralForgeConfig.GetRecipe(forge.ActiveRecipeId)
	if not recipe or forge.ExpiresAt <= os.time() then
		forge.ActiveRecipeId = ""
		forge.ExpiresAt = 0
		forge.ActiveDuration = 0
		setNeutralAttributes(player)
		mirrorProgressionAttributes(player, forge)
		return
	end

	applyRecipeAttributes(player, recipe, forge.ExpiresAt)
	mirrorProgressionAttributes(player, forge)
	scheduleExpiry(player, recipe.Id, forge.ExpiresAt)
end

-- =========================================================================
-- CRAFTING
-- =========================================================================

local function fail(player: Player, message: string, title: string?, key: string?)
	NotificationService.Send(player, {
		Kind = "Warning",
		Title = title or "The Forge Refuses",
		Message = message,
		Icon = "⚒",
		Key = key or "forge-denied",
	})
	return false, message
end

GetStateFunction.OnServerInvoke = function(player: Player)
	local forge = getForge(player)
	if not forge then
		return nil
	end
	reconcileActiveEffect(player, forge)
	return buildClientState(player, forge)
end

local craftDebounce = {}
local CRAFT_DEBOUNCE_SECONDS = 0.8

CraftFunction.OnServerInvoke = function(player: Player, recipeId)
	local clockNow = os.clock()
	local previous = craftDebounce[player]
	if previous and clockNow - previous < CRAFT_DEBOUNCE_SECONDS then
		return fail(player, "The runes are still settling. Give the forge a moment.", "Forge Cooling", "forge-debounce")
	end
	craftDebounce[player] = clockNow

	local recipe = AstralForgeConfig.GetRecipe(recipeId)
	if not recipe then
		return fail(player, "That recipe does not exist.", "Unknown Recipe", "forge-invalid-recipe")
	end

	local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	if rebirths < recipe.RebirthRequired then
		return fail(
			player,
			("Reach Rebirth %d to stabilize %s."):format(recipe.RebirthRequired, recipe.Name),
			"Recipe Locked",
			"forge-rebirth-" .. recipe.Id
		)
	end

	local forge = getForge(player)
	if not forge then
		return fail(player, "Your forge records are still loading. Try again in a moment.", "Still Loading", "forge-loading")
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return fail(player, "Your Essence balances are still loading. Try again in a moment.", "Still Loading", "forge-stats-loading")
	end

	local unixNow = os.time()
	local costs = AstralForgeConfig.GetCosts(recipe, unixNow)
	local deductions = {}
	for _, definition in ipairs(EssenceConfig.Ordered) do
		local amount = tonumber(costs[definition.DataKey] or costs[definition.Name] or costs[definition.Id]) or 0
		if amount > 0 then
			local stat = leaderstats:FindFirstChild(definition.Name)
			if not stat then
				return fail(player, definition.Name .. " is still loading. Try again in a moment.", "Still Loading", "forge-currency-loading")
			end

			local current = tonumber(stat:GetAttribute("Quantity")) or 0
			if current < amount then
				local shortfall = amount - current
				return fail(
					player,
					("You need %s more %s for %s."):format(
						ProgressionConfig.FormatNumber(shortfall),
						definition.Name,
						recipe.Name
					),
					"Not Enough " .. definition.ShortName,
					"forge-shortfall-" .. definition.Id
				)
			end

			table.insert(deductions, {
				Stat = stat,
				NewQuantity = current - amount,
			})
		end
	end

	-- Every configured cost must resolve through EssenceConfig. This catches
	-- a future typo before it can silently turn a recipe free.
	local resolvedCostCount = #deductions
	local configuredCostCount = 0
	for _ in pairs(costs) do
		configuredCostCount += 1
	end
	if resolvedCostCount ~= configuredCostCount or configuredCostCount == 0 then
		warn(("AstralForgeService: recipe %s has an unresolved or empty cost table"):format(recipe.Id))
		return fail(player, "That recipe is being retuned. Try another infusion for now.", "Recipe Unavailable", "forge-cost-error")
	end

	for _, deduction in ipairs(deductions) do
		deduction.Stat:SetAttribute("Quantity", deduction.NewQuantity)
	end

	local oldRecipeId = forge.ActiveRecipeId
	local oldMastery = AstralForgeConfig.GetMastery(forge.TotalCrafts, forge.RecipeCrafts)
	forge.TotalCrafts += 1
	forge.RecipeCrafts[recipe.Id] = (tonumber(forge.RecipeCrafts[recipe.Id]) or 0) + 1

	local duration = AstralForgeConfig.GetDuration(recipe, forge.TotalCrafts, unixNow, forge.RecipeCrafts)
	forge.ActiveRecipeId = recipe.Id
	forge.ExpiresAt = unixNow + duration
	forge.ActiveDuration = duration
	applyRecipeAttributes(player, recipe, forge.ExpiresAt)
	mirrorProgressionAttributes(player, forge)
	scheduleExpiry(player, recipe.Id, forge.ExpiresAt)

	local newMastery = AstralForgeConfig.GetMastery(forge.TotalCrafts, forge.RecipeCrafts)
	local clientState = buildClientState(player, forge)
	SyncRemote:FireClient(player, clientState)

	NotificationService.Send(player, {
		Kind = "Success",
		Title = recipe.Name .. " Forged",
		Message = recipe.Benefit .. " is active for " .. ProgressionConfig.FormatDuration(duration) .. ".",
		Icon = recipe.Icon,
		Key = "forge-crafted-" .. recipe.Id,
		Duration = 4.8,
		Cooldown = 0,
	})

	return true, nil, {
		RecipeId = recipe.Id,
		Duration = duration,
		ReplacedRecipeId = oldRecipeId ~= "" and oldRecipeId ~= recipe.Id and oldRecipeId or nil,
		MasteryTierUp = newMastery.Tier > oldMastery.Tier,
		State = clientState,
	}
end

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local dataModule = player:WaitForChild("PlayerData", 30)
		if not dataModule or not player.Parent then
			return
		end

		local forge = getForge(player)
		if not forge then
			return
		end
		reconcileActiveEffect(player, forge)

		-- The client also requests state, but this catches a UI that connected
		-- first and gives live panels an immediate authoritative refresh.
		task.wait(1)
		pushState(player, forge)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player: Player)
	craftDebounce[player] = nil
	expiryGenerations[player] = nil
	scheduledExpiryKeys[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
