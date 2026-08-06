local Lifecycle = {
	active = true,
	connections = {},
}

function Lifecycle:track(connection)
	table.insert(self.connections, connection)
	return connection
end

local TweenService = game:GetService("TweenService")

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		script.Parent.Position = UDim2.fromScale(0, 0)
		local tw = TweenService:Create(
			script.Parent,
			TweenInfo.new(4, Enum.EasingStyle.Linear),
			{ Position = UDim2.fromScale(0, 0.02) }
		)
		tw:Play()
		tw.Completed:Wait()
	end
end))