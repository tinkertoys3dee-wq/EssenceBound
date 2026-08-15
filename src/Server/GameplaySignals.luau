--[[
	GameplaySignals (ModuleScript -> ServerScriptService)
	====================================================
	One server-only source of truth for accepted gameplay actions.

	Several progression systems used to listen to the raw client remotes in
	parallel with OrbClickManager. A valid-looking event could therefore move a
	quest, journey goal, or wheel ticket even when the economy handler rejected
	the same request. It also meant every new metric had to duplicate the entire
	validation boundary and hope it stayed in sync.

	OrbClickManager is the only publisher. It fires these signals only AFTER a
	click consumes orb energy successfully or a collection has been validated and
	credited. Consumers can observe; none can grant or forge an accepted action.
]]

local GameplaySignals = {}

local clickAccepted = Instance.new("BindableEvent")
clickAccepted.Name = "ClickAccepted"

local collectionAccepted = Instance.new("BindableEvent")
collectionAccepted.Name = "CollectionAccepted"

function GameplaySignals.OnClickAccepted(callback)
	return clickAccepted.Event:Connect(callback)
end

function GameplaySignals.OnCollectionAccepted(callback)
	return collectionAccepted.Event:Connect(callback)
end

-- Publisher methods intentionally use an underscore prefix: gameplay systems
-- should subscribe through the public On* helpers; only OrbClickManager calls
-- these after its authoritative checks and grant path have completed.
function GameplaySignals._FireClickAccepted(player: Player, payload)
	if player and player.Parent then
		clickAccepted:Fire(player, payload or {})
	end
end

function GameplaySignals._FireCollectionAccepted(player: Player, payload)
	if player and player.Parent then
		collectionAccepted:Fire(player, payload or {})
	end
end

return GameplaySignals
