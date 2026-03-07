local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Ultraspeed",
		desc = "Forces game speed to 20x for headless testing",
		author = "Testing",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then

	local applied = false

	function gadget:Update()
		if applied then
			gadgetHandler:RemoveGadget(self)
			return
		end
		if Spring.GetGameFrame() > 0 then
			Spring.SendCommands("setmaxspeed 100", "speed 20")
			Spring.Echo("[Ultraspeed] Set game speed to 20x")
			applied = true
		end
	end

end
