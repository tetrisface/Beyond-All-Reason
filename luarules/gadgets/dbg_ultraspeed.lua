local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Ultraspeed",
		desc = "Forces game speed to XXXX for headless testing",
		author = "Testing",
		layer = 0,
		enabled = true,
	}
end

local DESIRED_SPEED = 100

if not gadgetHandler:IsSyncedCode() then
	function gadget:GameFrame(frame)
		if frame == 2 then
			Spring.SendCommands("setmaxspeed " .. DESIRED_SPEED, "setminspeed " .. DESIRED_SPEED)
			Spring.Echo("[Ultraspeed] Set game speed to " .. DESIRED_SPEED .. "x")
		end
	end
end
