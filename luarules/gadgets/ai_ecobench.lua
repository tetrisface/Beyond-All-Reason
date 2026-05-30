local gadget = gadget ---@type Gadget

local modOptions = Spring.GetModOptions()

local function ToBool(value)
	return value == true or value == "1" or value == "true"
end

local enabled = ToBool(modOptions.ecobench_enabled)

function gadget:GetInfo()
	return {
		name = "EcoBench AI",
		desc = "Headless economy benchmark controller and telemetry exporter",
		author = "tetrisfaceAI, Codex",
		date = "May 2026",
		license = "GNU GPL, v2 or later",
		layer = -90,
		enabled = enabled,
	}
end

if not enabled or not gadgetHandler:IsSyncedCode() then
	return false
end

local spEcho = Spring.Echo
local spGameOver = Spring.GameOver
local spGetAllUnits = Spring.GetAllUnits
local spGetFullBuildQueue = Spring.GetFullBuildQueue
local spGetGameFrame = Spring.GetGameFrame
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamLuaAI = Spring.GetTeamLuaAI
local spGetTeamResources = Spring.GetTeamResources
local spGetTeamUnits = Spring.GetTeamUnits
local spGetTeamUnitsCounts = Spring.GetTeamUnitsCounts
local spGetUnitCommandCount = Spring.GetUnitCommandCount
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spTestBuildOrder = Spring.TestBuildOrder

local CMD_FIRE_STATE = CMD.FIRE_STATE
local CMD_MOVE = CMD.MOVE
local CMD_MOVE_STATE = CMD.MOVE_STATE
local CMD_RECLAIM = CMD.RECLAIM
local CMD_REPAIR = CMD.REPAIR

local AI_NAME = "EcoBenchAI"
local CONTROL_INTERVAL = 30
local DEFAULT_TARGET_FRAME = 21600
local DEFAULT_TELEMETRY_INTERVAL = 150

local targetFrame = tonumber(modOptions.ecobench_target_frame) or DEFAULT_TARGET_FRAME
local telemetryInterval = tonumber(modOptions.ecobench_telemetry_interval) or DEFAULT_TELEMETRY_INTERVAL

local policy = {
	energy_weight = 1.0,
	converter_weight = 1.0,
	constructor_weight = 1.0,
	factory_weight = 1.0,
	reclaim_weight = 0.2,
	energy_reserve = 0.55,
	factory_metal = 0.35,
	constructor_target = 4.0,
}

local rawPolicy = modOptions.ecobench_policy or ""
for key, value in string.gmatch(rawPolicy, "([%w_]+)=([%-%d%.]+)") do
	if policy[key] ~= nil then
		policy[key] = tonumber(value) or policy[key]
	end
end

local ecoTeams = {}
local unitsLost = {}
local gameEnding = false

local commanderDefs = {}
local constructorDefs = {}
local converterDefs = {}
local energyDefs = {}
local extractorDefs = {}
local factoryDefs = {}
local immobileBuilderDefs = {}
local mobileUnitDefs = {}
local buildOptionsByDef = {}
local buildingFootprints = {}

local function IsEcoBenchAI(teamID)
	local luaAI = spGetTeamLuaAI(teamID)
	return type(luaAI) == "string" and string.sub(luaAI, 1, #AI_NAME) == AI_NAME
end

local function UnitCost(unitDef)
	return math.max(1, unitDef.metalCost or unitDef.metalcost or 1)
end

local function ConverterCapacity(unitDef)
	local custom = unitDef.customParams or unitDef.customparams or {}
	return tonumber(custom.energyconv_capacity) or 0
end

local function ConverterEfficiency(unitDef)
	local custom = unitDef.customParams or unitDef.customparams or {}
	return tonumber(custom.energyconv_efficiency) or 0
end

local function IsEnergyGenerator(unitDef)
	if (unitDef.energyMake or 0) > 19 and (unitDef.energyUpkeep or 0) < 10 then
		return true
	end

	if (unitDef.windGenerator or 0) > 0 or (unitDef.tidalGenerator or 0) > 0 then
		return true
	end

	local custom = unitDef.customParams or unitDef.customparams or {}
	return custom.solar ~= nil
end

local function IsExtractor(unitDef)
	local custom = unitDef.customParams or unitDef.customparams or {}
	return (unitDef.extractsMetal or 0) > 0 or custom.metal_extractor ~= nil
end

local function BuildOptionSet(unitDef)
	if not unitDef.buildOptions or #unitDef.buildOptions == 0 then
		return nil
	end

	local options = {}
	for i = 1, #unitDef.buildOptions do
		options[unitDef.buildOptions[i]] = true
	end
	return options
end

local function InitUnitDefIndexes()
	for unitDefID, unitDef in pairs(UnitDefs) do
		if unitDef.isBuilding then
			buildingFootprints[unitDefID] = {unitDef.xsize or 4, unitDef.zsize or 4}
		end

		if unitDef.customParams and unitDef.customParams.iscommander then
			commanderDefs[unitDefID] = true
			buildingFootprints[unitDefID] = {unitDef.xsize or 4, unitDef.zsize or 4}
		end

		if unitDef.isFactory and unitDef.buildOptions and #unitDef.buildOptions > 0 then
			factoryDefs[unitDefID] = true
		elseif unitDef.isBuilder and unitDef.buildOptions and #unitDef.buildOptions > 0 then
			if unitDef.canMove then
				constructorDefs[unitDefID] = true
			else
				immobileBuilderDefs[unitDefID] = true
			end
		elseif unitDef.canMove then
			mobileUnitDefs[unitDefID] = true
		end

		if IsExtractor(unitDef) then
			extractorDefs[unitDefID] = true
		elseif ConverterCapacity(unitDef) > 0 and ConverterEfficiency(unitDef) > 0 then
			converterDefs[unitDefID] = true
		elseif IsEnergyGenerator(unitDef) then
			energyDefs[unitDefID] = true
		end

		buildOptionsByDef[unitDefID] = BuildOptionSet(unitDef)
	end
end

local function BestBuildOption(buildOptions, candidates, scoreFn)
	if not buildOptions then
		return nil
	end

	local bestDefID
	local bestScore = -math.huge
	for unitDefID in pairs(candidates) do
		if buildOptions[unitDefID] then
			local score = scoreFn(UnitDefs[unitDefID])
			if score > bestScore then
				bestDefID = unitDefID
				bestScore = score
			end
		end
	end
	return bestDefID
end

local function BestEnergy(buildOptions)
	return BestBuildOption(buildOptions, energyDefs, function(unitDef)
		local output = (unitDef.energyMake or 0) + (unitDef.windGenerator or 0) + (unitDef.tidalGenerator or 0)
		return output / UnitCost(unitDef)
	end)
end

local function BestConverter(buildOptions)
	return BestBuildOption(buildOptions, converterDefs, function(unitDef)
		return (ConverterCapacity(unitDef) * ConverterEfficiency(unitDef)) / UnitCost(unitDef)
	end)
end

local function BestConstructor(buildOptions)
	return BestBuildOption(buildOptions, constructorDefs, function(unitDef)
		return (unitDef.buildSpeed or 1) / UnitCost(unitDef)
	end)
end

local function BestFactory(buildOptions)
	return BestBuildOption(buildOptions, factoryDefs, function(unitDef)
		return 1 / UnitCost(unitDef)
	end)
end

local function BuildNear(unitID, buildingDefID)
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return false
	end

	local teamID = spGetUnitTeam(unitID)
	local units = spGetTeamUnits(teamID)
	if not units or #units == 0 then
		return false
	end

	for radiusStep = 1, 20 do
		local spacing = 96 + radiusStep * 16
		for i = 1, #units do
			local refID = units[i]
			local refDefID = spGetUnitDefID(refID)
			local footprint = refDefID and buildingFootprints[refDefID]
			if footprint then
				local refX, _, refZ = spGetUnitPosition(refID)
				if refX then
					for facing = 0, 3 do
						local offsetX = 0
						local offsetZ = 0
						if facing == 0 then
							offsetZ = footprint[2] * 8 + spacing
						elseif facing == 1 then
							offsetX = footprint[1] * 8 + spacing
						elseif facing == 2 then
							offsetZ = -footprint[2] * 8 - spacing
						else
							offsetX = -footprint[1] * 8 - spacing
						end

						local buildX = refX + offsetX
						local buildZ = refZ + offsetZ
						local buildY = spGetGroundHeight(buildX, buildZ)
						if buildY and spTestBuildOrder(buildingDefID, buildX, buildY, buildZ, facing) == 2 then
							spGiveOrderToUnit(unitID, -buildingDefID, {buildX, buildY, buildZ, facing}, {"shift"})
							return true
						end
					end
				end
			end
		end
	end

	return false
end

local function CountUnits(teamID)
	local result = {
		constructors = 0,
		factories = 0,
		energy_buildings = 0,
		converters = 0,
		extractors = 0,
		buildpower = 0,
	}

	local counts = spGetTeamUnitsCounts(teamID)
	if not counts then
		return result
	end

	for unitDefID, count in pairs(counts) do
		if type(unitDefID) == "number" and type(count) == "number" then
			local unitDef = UnitDefs[unitDefID]
			if unitDef then
				if constructorDefs[unitDefID] or commanderDefs[unitDefID] then
					result.constructors = result.constructors + count
				end
				if factoryDefs[unitDefID] then
					result.factories = result.factories + count
				end
				if energyDefs[unitDefID] then
					result.energy_buildings = result.energy_buildings + count
				end
				if converterDefs[unitDefID] then
					result.converters = result.converters + count
				end
				if extractorDefs[unitDefID] then
					result.extractors = result.extractors + count
				end
				if unitDef.isBuilder or unitDef.isFactory then
					result.buildpower = result.buildpower + count * (unitDef.buildSpeed or 0)
				end
			end
		end
	end

	return result
end

local function TeamMetrics(teamID)
	local metal, _, metalPull, metalIncome, metalExpense, _, _, _, metalExcess = spGetTeamResources(teamID, "metal")
	local energy, _, energyPull, energyIncome, energyExpense, _, _, _, energyExcess = spGetTeamResources(teamID, "energy")
	local _, _, isDead = spGetTeamInfo(teamID)
	local counts = CountUnits(teamID)

	return {
		frame = spGetGameFrame(),
		team_id = teamID,
		metal = metal or 0,
		energy = energy or 0,
		metal_pull = metalPull or 0,
		energy_pull = energyPull or 0,
		metal_income = metalIncome or 0,
		energy_income = energyIncome or 0,
		metal_expense = metalExpense or 0,
		energy_expense = energyExpense or 0,
		metal_excess = metalExcess or 0,
		energy_excess = energyExcess or 0,
		constructors = counts.constructors,
		factories = counts.factories,
		energy_buildings = counts.energy_buildings,
		converters = counts.converters,
		extractors = counts.extractors,
		buildpower = counts.buildpower,
		units_lost = unitsLost[teamID] or 0,
		alive = not isDead,
	}
end

local function JsonBool(value)
	return value and "true" or "false"
end

local function EmitTelemetry(teamID)
	local metrics = TeamMetrics(teamID)
	spEcho(string.format(
		'[EcoBench] {"frame":%d,"team_id":%d,"metal":%.3f,"energy":%.3f,"metal_income":%.3f,"energy_income":%.3f,"metal_expense":%.3f,"energy_expense":%.3f,"metal_excess":%.3f,"energy_excess":%.3f,"constructors":%d,"factories":%d,"energy_buildings":%d,"converters":%d,"extractors":%d,"buildpower":%.3f,"units_lost":%d,"alive":%s}',
		metrics.frame,
		metrics.team_id,
		metrics.metal,
		metrics.energy,
		metrics.metal_income,
		metrics.energy_income,
		metrics.metal_expense,
		metrics.energy_expense,
		metrics.metal_excess,
		metrics.energy_excess,
		metrics.constructors,
		metrics.factories,
		metrics.energy_buildings,
		metrics.converters,
		metrics.extractors,
		metrics.buildpower,
		metrics.units_lost,
		JsonBool(metrics.alive)
	))
end

local function ReclaimOrRepair(unitID)
	local x = Game.mapSizeX * 0.5
	local z = Game.mapSizeZ * 0.5
	local y = spGetGroundHeight(x, z) or 0
	if policy.reclaim_weight >= 0.5 then
		spGiveOrderToUnit(unitID, CMD_RECLAIM, {x, y, z, math.max(Game.mapSizeX, Game.mapSizeZ)}, 0)
	else
		spGiveOrderToUnit(unitID, CMD_REPAIR, {x, y, z, math.max(Game.mapSizeX, Game.mapSizeZ)}, 0)
	end
end

local function BuilderActionScore(action, metrics)
	if action == "factory" then
		local factoryNeed = metrics.factories == 0 and 4 or 0.25
		local metalRatio = metrics.metal / 10000
		return policy.factory_weight * (factoryNeed + metalRatio - policy.factory_metal)
	elseif action == "energy" then
		local energySurplus = metrics.energy_income - metrics.energy_expense
		local shortage = math.max(0, 250 - energySurplus) / 250
		return policy.energy_weight * (1 + shortage)
	elseif action == "converter" then
		local energyRatio = metrics.energy / 10000
		local surplus = math.max(0, metrics.energy_income - metrics.energy_expense) / 500
		if energyRatio < policy.energy_reserve then
			return -math.huge
		end
		return policy.converter_weight * (0.5 + surplus + energyRatio)
	elseif action == "constructor" then
		local wanted = 2 + metrics.factories * policy.constructor_target
		return policy.constructor_weight * math.max(0, wanted - metrics.constructors)
	elseif action == "reclaim" then
		return policy.reclaim_weight
	end

	return -math.huge
end

local function ControlBuilder(unitID, unitDefID, metrics)
	local buildOptions = buildOptionsByDef[unitDefID]
	if not buildOptions then
		ReclaimOrRepair(unitID)
		return
	end

	local choices = {
		{action = "factory", unitDefID = BestFactory(buildOptions)},
		{action = "energy", unitDefID = BestEnergy(buildOptions)},
		{action = "converter", unitDefID = BestConverter(buildOptions)},
	}

	local bestUnitDefID
	local bestScore = BuilderActionScore("reclaim", metrics)
	for i = 1, #choices do
		local choice = choices[i]
		if choice.unitDefID then
			local score = BuilderActionScore(choice.action, metrics)
			if score > bestScore then
				bestUnitDefID = choice.unitDefID
				bestScore = score
			end
		end
	end

	if bestUnitDefID and BuildNear(unitID, bestUnitDefID) then
		return
	end

	ReclaimOrRepair(unitID)
end

local function ControlFactory(unitID, unitDefID, metrics)
	if #spGetFullBuildQueue(unitID) >= 4 then
		return
	end

	local buildOptions = buildOptionsByDef[unitDefID]
	if not buildOptions then
		return
	end

	local constructorDefID = BestConstructor(buildOptions)
	if constructorDefID and BuilderActionScore("constructor", metrics) > 0 then
		local x, y, z = spGetUnitPosition(unitID)
		if x then
			spGiveOrderToUnit(unitID, -constructorDefID, {x, y, z, 0}, 0)
		end
	end
end

local function ControlTeam(teamID)
	local units = spGetTeamUnits(teamID)
	if not units then
		return
	end

	local metrics = TeamMetrics(teamID)
	for i = 1, #units do
		local unitID = units[i]
		local unitDefID = spGetUnitDefID(unitID)
		if unitDefID and spGetUnitCommandCount(unitID) == 0 then
			if commanderDefs[unitDefID] or constructorDefs[unitDefID] or immobileBuilderDefs[unitDefID] then
				ControlBuilder(unitID, unitDefID, metrics)
			elseif factoryDefs[unitDefID] then
				ControlFactory(unitID, unitDefID, metrics)
			elseif mobileUnitDefs[unitDefID] then
				local allUnits = spGetAllUnits()
				local target = allUnits and allUnits[1]
				if target then
					local x, y, z = spGetUnitPosition(target)
					if x then
						spGiveOrderToUnit(unitID, CMD_MOVE, {x, y, z}, 0)
					end
				end
			end
		end
	end
end

function gadget:Initialize()
	InitUnitDefIndexes()

	local teams = spGetTeamList()
	for i = 1, #teams do
		local teamID = teams[i]
		if IsEcoBenchAI(teamID) then
			ecoTeams[#ecoTeams + 1] = teamID
			unitsLost[teamID] = 0
			spEcho("[EcoBench] team registered: " .. teamID)
		end
	end

	if #ecoTeams == 0 then
		spEcho("[EcoBench] no EcoBenchAI teams found; disabling")
		gadgetHandler:RemoveGadget(self)
	end
end

function gadget:GameFrame(frame)
	if gameEnding then
		return
	end

	if frame >= targetFrame then
		for i = 1, #ecoTeams do
			EmitTelemetry(ecoTeams[i])
		end
		gameEnding = true
		local _, _, _, _, _, allyTeamID = spGetTeamInfo(ecoTeams[1])
		spGameOver({allyTeamID or 0})
		return
	end

	if frame % telemetryInterval == 0 then
		for i = 1, #ecoTeams do
			EmitTelemetry(ecoTeams[i])
		end
	end

	if frame % CONTROL_INTERVAL == 0 then
		for i = 1, #ecoTeams do
			ControlTeam(ecoTeams[i])
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam)
	if not IsEcoBenchAI(unitTeam) then
		return
	end

	spGiveOrderToUnit(unitID, CMD_FIRE_STATE, {2}, 0)
	spGiveOrderToUnit(unitID, CMD_MOVE_STATE, {2}, 0)
end

function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	if not IsEcoBenchAI(unitTeam) then
		return
	end

	spGiveOrderToUnit(unitID, CMD_FIRE_STATE, {2}, 0)
	spGiveOrderToUnit(unitID, CMD_MOVE_STATE, {2}, 0)
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if unitsLost[unitTeam] ~= nil then
		unitsLost[unitTeam] = unitsLost[unitTeam] + 1
	end
end

function gadget:TeamDied(teamID)
	if unitsLost[teamID] ~= nil then
		EmitTelemetry(teamID)
	end
end
