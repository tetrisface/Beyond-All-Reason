local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Scav Targeting Metrics",
		desc = "Tracks scavenger target selection fairness across allyteams",
		author = "Testing",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not Spring.Utilities.Gametype.IsScavengers() then
	return false
end

if gadgetHandler:IsSyncedCode() then

	local GetUnitAllyTeam = Spring.GetUnitAllyTeam
	local GetGameSeconds = Spring.GetGameSeconds
	local scavAllyTeamID = Spring.Utilities.GetScavAllyTeamID()

	local selectionsPerAllyTeam = {}
	local totalSelections = 0
	local lastReportTime = 0
	local REPORT_INTERVAL = 60

	function GG.ScavTargetingMetrics(unitID)
		if not unitID then return end
		local allyTeam = GetUnitAllyTeam(unitID)
		if allyTeam and allyTeam ~= scavAllyTeamID then
			selectionsPerAllyTeam[allyTeam] = (selectionsPerAllyTeam[allyTeam] or 0) + 1
			totalSelections = totalSelections + 1
		end
	end

	function gadget:GameFrame(frame)
		local gameSeconds = GetGameSeconds()
		if gameSeconds - lastReportTime < REPORT_INTERVAL then return end
		if totalSelections == 0 then return end
		lastReportTime = gameSeconds

		local allyTeamsData = {}
		local minOE, maxOE = math.huge, 0
		local activeTeams = 0

		for allyTeam, selections in pairs(selectionsPerAllyTeam) do
			activeTeams = activeTeams + 1
		end

		if activeTeams < 2 then return end

		local expectedPerTeam = totalSelections / activeTeams

		for allyTeam, selections in pairs(selectionsPerAllyTeam) do
			local oe = selections / expectedPerTeam
			if oe < minOE then minOE = oe end
			if oe > maxOE then maxOE = oe end
			allyTeamsData[tostring(allyTeam)] = {
				selections = selections,
				OE = math.floor(oe * 100 + 0.5) / 100,
			}
		end

		local fairnessIndex = minOE > 0 and (math.floor((maxOE / minOE) * 100 + 0.5) / 100) or 0

		local parts = {}
		parts[#parts+1] = string.format('"gameSeconds":%d,"totalSelections":%d', gameSeconds, totalSelections)

		local teamParts = {}
		for allyTeam, data in pairs(allyTeamsData) do
			teamParts[#teamParts+1] = string.format('"%s":{"selections":%d,"OE":%.2f}', allyTeam, data.selections, data.OE)
		end
		parts[#parts+1] = '"allyTeams":{' .. table.concat(teamParts, ",") .. "}"
		parts[#parts+1] = string.format('"fairnessIndex":%.2f', fairnessIndex)

		Spring.Echo("[SCAV_METRICS_JSON] {" .. table.concat(parts, ",") .. "}")
	end

end
