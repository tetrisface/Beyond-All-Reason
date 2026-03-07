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

		-- Count units per allyteam from the actual target pool
		local poolPerAllyTeam = {}
		local totalPoolSize = 0
		local pools = GG.scavTargetPools
		if pools then
			for _, pool in pairs(pools) do
				for unitID in pairs(pool) do
					local at = GetUnitAllyTeam(unitID)
					if at and at ~= scavAllyTeamID then
						poolPerAllyTeam[at] = (poolPerAllyTeam[at] or 0) + 1
						totalPoolSize = totalPoolSize + 1
					end
				end
			end
		end

		local allyTeamsData = {}
		local activeTeams = 0

		for allyTeam, selections in pairs(selectionsPerAllyTeam) do
			activeTeams = activeTeams + 1
		end

		if activeTeams < 2 then return end

		-- Compute both naive O/E (equal weight) and weighted O/E (by pool share)
		local expectedPerTeam = totalSelections / activeTeams

		for allyTeam, selections in pairs(selectionsPerAllyTeam) do
			local oe = selections / expectedPerTeam
			local poolUnits = poolPerAllyTeam[allyTeam] or 0
			local weightedExpected = totalPoolSize > 0 and (totalSelections * poolUnits / totalPoolSize) or expectedPerTeam
			local woe = weightedExpected > 0 and (selections / weightedExpected) or 0

			allyTeamsData[tostring(allyTeam)] = {
				selections = selections,
				poolUnits = poolUnits,
				OE = math.floor(oe * 100 + 0.5) / 100,
				wOE = math.floor(woe * 100 + 0.5) / 100,
			}
		end

		local parts = {}
		parts[#parts+1] = string.format('"gameMinutes":%.1f,"gameSeconds":%d,"totalSelections":%d,"totalPoolSize":%d', gameSeconds/60, gameSeconds, totalSelections, totalPoolSize)

		local teamParts = {}
		for allyTeam, data in pairs(allyTeamsData) do
			teamParts[#teamParts+1] = string.format('"%s":{"selections":%d,"poolUnits":%d,"OE":%.2f,"wOE":%.2f}', allyTeam, data.selections, data.poolUnits, data.OE, data.wOE)
		end
		parts[#parts+1] = '"allyTeams":{' .. table.concat(teamParts, ",") .. "}"

		Spring.Echo("[SCAV_METRICS_JSON] {" .. table.concat(parts, ",") .. "}")
	end

end
