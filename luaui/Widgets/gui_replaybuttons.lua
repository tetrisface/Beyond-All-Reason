--http://springrts.com/phpbb/viewtopic.php?f=23&t=30560
local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Replay buttons",
		desc = "click buttons to change replay speed",
		author = "knorke",
		version = "1",
		date = "June 2013",
		license = "click button magic",
		layer = 10,
		enabled = true,
	}
end


-- Localized functions for performance
local mathFloor = math.floor

-- Localized Spring API for performance
local spGetGameFrame = Spring.GetGameFrame
local spGetConfigInt = Spring.GetConfigInt
local spSetConfigInt = Spring.SetConfigInt
local spGetMouseState = Spring.GetMouseState
local spGetReplayLength = Spring.GetReplayLength
local spGetGameSpeed = Spring.GetGameSpeed
local spGetViewGeometry = Spring.GetViewGeometry

local vsx, vsy = spGetViewGeometry()

local ui_opacity = Spring.GetConfigFloat("ui_opacity", 0.7)
local ui_scale = Spring.GetConfigFloat("ui_scale", 1)

local buttonWidth = 0.037
local buttonHeight = 0.033
local bWidth = buttonWidth * ui_scale
local bHeight = buttonHeight * ui_scale

local buttons = {}
local speeds = { 0.5, 1, 2, 3, 4, 6, 8, 10, 15, 20 }
local wPos = { x = 0.00, y = 0.145 }
local timeline = { x = 0.24, y = 0.022, w = 0.52, h = 0.018 }
local isPaused = false
local isActive = false
local prevIsActive = false
local sceduleUpdate = true
local widgetScale = (0.5 + (vsx * vsy / 5700000))
local replayLengthFrames = 0
local lastSkipFrame = -1
local lastSkipClock = 0
local lastRestoreFrame = -1
local lastRestoreClock = 0
local selfTestEnabled = spGetConfigInt("ReplayTimelineSelfTest", 0) == 1
local selfTestStartFrame = spGetConfigInt("ReplayTimelineSelfTestStartFrame", 30)
local selfTestTargetFrame = spGetConfigInt("ReplayTimelineSelfTestTargetFrame", 0)
local selfTestQuit = spGetConfigInt("ReplayTimelineSelfTestQuit", 0) == 1
local selfTestQuitFrame = spGetConfigInt("ReplayTimelineSelfTestQuitFrame", 0)
local selfTestTriggered = false
local selfTestReached = false
local selfTestComplete = false
local selfTestDeadlineFrame = 0
local checkpointSelfTestEnabled = spGetConfigInt("ReplayCheckpointSelfTest", 0) == 1
local checkpointSelfTestSaveFrame = spGetConfigInt("ReplayCheckpointSelfTestSaveFrame", 30)
local checkpointSelfTestLoadFrame = spGetConfigInt("ReplayCheckpointSelfTestLoadFrame", 90)
local checkpointSelfTestTargetFrame = spGetConfigInt("ReplayCheckpointSelfTestTargetFrame", 0)
local checkpointSelfTestSkipSave = spGetConfigInt("ReplayCheckpointSelfTestSkipSave", 0) == 1
local checkpointSelfTestResumeFrame = spGetConfigInt("ReplayCheckpointSelfTestResumeFrame", 0)
local checkpointSelfTestQuit = spGetConfigInt("ReplayCheckpointSelfTestQuit", 0) == 1
local checkpointSelfTestTimeoutSeconds = spGetConfigInt("ReplayCheckpointSelfTestTimeoutSeconds", 10)
local checkpointSelfTestPhase = spGetConfigInt("ReplayCheckpointSelfTestPhase", 0)
local checkpointSelfTestRequestFrame = spGetConfigInt("ReplayCheckpointSelfTestRequestFrame", 0)
local checkpointSelfTestRequestClock = os.clock()

local glBlending = gl.Blending
local glColor = gl.Color
local glRect = gl.Rect
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local GL_ONE = GL.ONE

local RectRound, UiButton, elementCorner

local font, backgroundGuishader, buttonsList, buttonlist, active_button, bgpadding

local function seconds_to_clock(seconds)
	seconds = math.max(0, mathFloor(seconds or 0))
	local hours = mathFloor(seconds / 3600)
	local mins = mathFloor((seconds - hours * 3600) / 60)
	local secs = seconds - hours * 3600 - mins * 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, mins, secs)
	end
	return string.format("%02d:%02d", mins, secs)
end

local function add_button(x, y, text, name)
	local new_button = {}
	new_button.x = x
	new_button.y = y
	new_button.text = text
	new_button.name = name
	table.insert(buttons, new_button)
end

local function point_in_rect(x1, y1, x2, y2, px, py)
	if px > x1 and px < x2 and py > y1 and py < y2 then
		return true
	end
	return false
end

local function clicked_button(b)
	local mx, my, click = spGetMouseState()
	local mousex = mx / vsx
	local mousey = my / vsy
	for i = 1, #b, 1 do
		if click and point_in_rect(b[i].x, b[i].y, b[i].x + bWidth, b[i].y + bHeight, mousex, mousey) then
			return b[i].name, i
		end
	end

	return "NOBUTTONCLICKED"
end

local function setReplaySpeed(speed)
	Spring.SendCommands("setspeed " .. speed)
end

local function update_replay_length()
	local seconds = spGetReplayLength and spGetReplayLength()
	if seconds and seconds > 0 then
		replayLengthFrames = math.max(replayLengthFrames, mathFloor(seconds * 30))
	end
end

local function timeline_rect_pixels()
	local x1 = mathFloor((timeline.x * vsx) + 0.5)
	local y1 = mathFloor((timeline.y * vsy) + 0.5)
	local x2 = mathFloor(((timeline.x + timeline.w) * vsx) + 0.5)
	local y2 = mathFloor(((timeline.y + timeline.h) * vsy) + 0.5)
	return x1, y1, x2, y2
end

local function frame_from_timeline_x(x)
	local x1, _, x2 = timeline_rect_pixels()
	local t = (x - x1) / math.max(1, x2 - x1)
	t = math.max(0, math.min(1, t))
	return mathFloor(t * replayLengthFrames + 0.5)
end

local function jump_to_frame(targetFrame, source)
	update_replay_length()
	local currentFrame = spGetGameFrame()
	if replayLengthFrames <= 0 then
		return
	end
	targetFrame = math.max(1, math.min(replayLengthFrames, targetFrame))
	if targetFrame <= currentFrame + 1 then
		local now = os.clock()
		if targetFrame == lastRestoreFrame and now - lastRestoreClock < 0.5 then
			return
		end
		lastRestoreFrame = targetFrame
		lastRestoreClock = now
		if source ~= "self-test" then
			Spring.Echo("[Replay] Requesting checkpoint restore to frame " .. targetFrame)
		end
		Spring.SendCommands("replaycheckpoint load " .. targetFrame)
		return
	end
	local now = os.clock()
	if targetFrame == lastSkipFrame and now - lastSkipClock < 0.5 then
		return
	end
	lastSkipFrame = targetFrame
	lastSkipClock = now
	Spring.SendCommands("skip f" .. targetFrame)
end

local function self_test_target_frame(currentFrame)
	update_replay_length()
	if replayLengthFrames <= 0 then
		return 0
	end
	if selfTestTargetFrame > 0 then
		return math.max(1, math.min(replayLengthFrames, selfTestTargetFrame))
	end
	return math.max(1, math.min(replayLengthFrames, currentFrame + 300))
end

local function checkpoint_self_test_target_frame()
	if checkpointSelfTestTargetFrame > 0 then
		return math.max(1, checkpointSelfTestTargetFrame)
	end
	return math.max(1, checkpointSelfTestSaveFrame)
end

local function checkpoint_self_test_set_phase(phase)
	checkpointSelfTestPhase = phase
	if spSetConfigInt then
		spSetConfigInt("ReplayCheckpointSelfTestPhase", phase)
	end
end

local function checkpoint_self_test_mark_complete()
	checkpoint_self_test_set_phase(5)
	if checkpointSelfTestQuit then
		Spring.SendCommands("quitforce")
	end
end

local function checkpoint_self_test_game_frame(frame)
	if not checkpointSelfTestEnabled or checkpointSelfTestPhase >= 5 then
		return false
	end

	local targetFrame = checkpoint_self_test_target_frame()

	if checkpointSelfTestPhase <= 0 and checkpointSelfTestSkipSave and frame >= checkpointSelfTestLoadFrame then
		if targetFrame >= frame then
			Spring.Echo("[ReplayCheckpointTest] failed current=" .. frame .. " target=" .. targetFrame .. " reason=no-backward-target")
			checkpoint_self_test_mark_complete()
			return true
		end

		checkpointSelfTestRequestFrame = frame
		checkpointSelfTestRequestClock = os.clock()
		if spSetConfigInt then
			spSetConfigInt("ReplayCheckpointSelfTestRequestFrame", checkpointSelfTestRequestFrame)
		end
		checkpoint_self_test_set_phase(2)
		isPaused = true
		if buttons[#buttons] then
			buttons[#buttons].text = "  >>"
			sceduleUpdate = true
		end
		Spring.Echo("[ReplayCheckpointTest] prerecorded current=" .. frame .. " target=" .. targetFrame)
		Spring.Echo("[ReplayCheckpointTest] load current=" .. frame .. " target=" .. targetFrame)
		Spring.SendCommands("pause 1")
		Spring.SendCommands("replaycheckpoint load " .. targetFrame)
		return true
	end

	if checkpointSelfTestPhase <= 0 and frame >= checkpointSelfTestSaveFrame then
		checkpoint_self_test_set_phase(1)
		Spring.Echo("[ReplayCheckpointTest] save current=" .. frame .. " target=" .. targetFrame)
		Spring.SendCommands("replaycheckpoint save -y")
		return true
	end

	if checkpointSelfTestPhase == 1 and frame >= checkpointSelfTestLoadFrame then
		if targetFrame >= frame then
			Spring.Echo("[ReplayCheckpointTest] failed current=" .. frame .. " target=" .. targetFrame .. " reason=no-backward-target")
			checkpoint_self_test_mark_complete()
			return true
		end

		checkpointSelfTestRequestFrame = frame
		checkpointSelfTestRequestClock = os.clock()
		if spSetConfigInt then
			spSetConfigInt("ReplayCheckpointSelfTestRequestFrame", checkpointSelfTestRequestFrame)
		end
		checkpoint_self_test_set_phase(2)
		isPaused = true
		if buttons[#buttons] then
			buttons[#buttons].text = "  >>"
			sceduleUpdate = true
		end
		Spring.Echo("[ReplayCheckpointTest] load current=" .. frame .. " target=" .. targetFrame)
		Spring.SendCommands("pause 1")
		Spring.SendCommands("replaycheckpoint load " .. targetFrame)
		return true
	end

	if checkpointSelfTestPhase == 4 and checkpointSelfTestResumeFrame > 0 and frame >= checkpointSelfTestResumeFrame then
		local _, _, paused = spGetGameSpeed()
		Spring.Echo(
			"[ReplayCheckpointTest] resumed current=" .. frame ..
			" target=" .. targetFrame ..
			" request=" .. checkpointSelfTestRequestFrame ..
			" resume=" .. checkpointSelfTestResumeFrame ..
			" paused=" .. (paused and "1" or "0")
		)
		checkpoint_self_test_mark_complete()
		return true
	end

	return checkpointSelfTestPhase == 2 or checkpointSelfTestPhase == 4
end

local function checkpoint_self_test_update()
	if not checkpointSelfTestEnabled or (checkpointSelfTestPhase ~= 2 and checkpointSelfTestPhase ~= 4) then
		return
	end

	local currentFrame = spGetGameFrame()
	local targetFrame = checkpoint_self_test_target_frame()
	local _, _, paused = spGetGameSpeed()

	if checkpointSelfTestPhase == 2 and currentFrame <= targetFrame + 1 and paused then
		local elapsed = os.clock() - checkpointSelfTestRequestClock
		Spring.Echo(
			"[ReplayCheckpointTest] restored current=" .. currentFrame ..
			" target=" .. targetFrame ..
			" request=" .. checkpointSelfTestRequestFrame ..
			" paused=1 elapsed=" .. string.format("%.2f", elapsed)
		)
		if checkpointSelfTestResumeFrame > targetFrame + 1 then
			checkpointSelfTestRequestClock = os.clock()
			checkpoint_self_test_set_phase(4)
			isPaused = false
			if buttons[#buttons] then
				buttons[#buttons].text = "  ||"
				sceduleUpdate = true
			end
			Spring.Echo(
				"[ReplayCheckpointTest] resume-start current=" .. currentFrame ..
				" target=" .. targetFrame ..
				" request=" .. checkpointSelfTestRequestFrame ..
				" resume=" .. checkpointSelfTestResumeFrame
			)
			Spring.SendCommands("pause 0")
			return
		end
		checkpoint_self_test_mark_complete()
		return
	end

	if os.clock() - checkpointSelfTestRequestClock > checkpointSelfTestTimeoutSeconds then
		local reason = "timeout"
		if checkpointSelfTestPhase == 4 then
			reason = "resume-timeout"
		end
		Spring.Echo(
			"[ReplayCheckpointTest] failed current=" .. currentFrame ..
			" target=" .. targetFrame ..
			" request=" .. checkpointSelfTestRequestFrame ..
			" paused=" .. (paused and "1" or "0") ..
			" reason=" .. reason
		)
		checkpoint_self_test_mark_complete()
	end
end

local function draw_timeline()
	update_replay_length()
	if replayLengthFrames <= 0 then
		return
	end

	local currentFrame = spGetGameFrame()
	local progress = math.max(0, math.min(1, currentFrame / replayLengthFrames))
	local x1, y1, x2, y2 = timeline_rect_pixels()
	local fillX = mathFloor(x1 + (x2 - x1) * progress + 0.5)
	local markerW = math.max(2, mathFloor(2 * ui_scale + 0.5))

	glColor(0, 0, 0, ui_opacity * 0.78)
	glRect(x1 - bgpadding, y1 - bgpadding, x2 + bgpadding, y2 + bgpadding)
	glColor(0.13, 0.14, 0.15, ui_opacity)
	glRect(x1, y1, x2, y2)
	glColor(0.20, 0.72, 0.92, 0.88)
	glRect(x1, y1, fillX, y2)
	glColor(1, 1, 1, 0.9)
	glRect(fillX - markerW, y1 - bgpadding * 0.25, fillX + markerW, y2 + bgpadding * 0.25)
	glColor(1, 1, 1, 1)

	font:Begin()
	font:SetTextColor(1, 1, 1, 0.92)
	font:SetOutlineColor(0, 0, 0, 0.8)
	font:Print(
		seconds_to_clock(currentFrame / 30) .. " / " .. seconds_to_clock(replayLengthFrames / 30),
		x2 + mathFloor(8 * ui_scale + 0.5),
		y1 + mathFloor((y2 - y1) * 0.5 + 0.5),
		mathFloor(12 * ui_scale + 0.5),
		"vo"
	)
	font:End()
end

local function draw_buttons(b)
	font:Begin()
	font:SetTextColor(1, 1, 1, 1)
	font:SetOutlineColor(0, 0, 0, 0.7)
	for i = 1, #b do
		UiButton(mathFloor((b[i].x * vsx) + 0.5), mathFloor((b[i].y * vsy) + 0.5), mathFloor(((b[i].x + bWidth) * vsx) + 0.5), mathFloor(((b[i].y + bHeight) * vsy) + 0.5), 0,1,1,0, 1,1,1,1, nil, { 0, 0, 0, ui_opacity }, { 0.2, 0.2, 0.2, ui_opacity }, bgpadding * 0.5)
		font:Print(b[i].text, mathFloor((b[i].x * vsx) + 0.5), mathFloor(((b[i].y + bHeight / 2) * vsy) + 0.5), mathFloor((0.0115 * vsx) + 0.5), 'vo')
	end
	font:End()
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	widgetScale = (0.5 + (vsx * vsy / 5700000))
	sceduleUpdate = true

	bHeight = buttonHeight * ui_scale
	bWidth = buttonWidth * ui_scale

	bgpadding = WG.FlowUI.elementPadding
	elementCorner = WG.FlowUI.elementCorner

	RectRound = WG.FlowUI.Draw.RectRound
	UiButton = WG.FlowUI.Draw.Button

	font = WG['fonts'].getFont(2, 1.6)
end

function widget:Initialize()
	widget:ViewResize()
	if not Spring.IsReplay() then
		widgetHandler:RemoveWidget()
		return
	end

	local dy = 0
	for i = 1, #speeds do
		dy = dy + bHeight
		add_button(wPos.x, wPos.y + dy, "  " .. speeds[i] .. "x", speeds[i])
	end
	dy = dy + bHeight
	add_button(wPos.x, wPos.y, (spGetGameFrame() > 0 and "  ||" or "  skip"), "playpauseskip")
end

function widget:Shutdown()
	if WG['guishader'] then
		WG['guishader'].DeleteDlist('replaybuttons')
	end
	gl.DeleteList(buttonsList)
end



function widget:DrawScreen()
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	if not isActive then
		if WG['guishader'] and prevIsActive ~= isActive then
			WG['guishader'].RemoveDlist('replaybuttons')
		end
		return
	end

	if sceduleUpdate then
		sceduleUpdate = false
		if buttonsList then
			gl.DeleteList(buttonsList)
		end
		buttonsList = gl.CreateList(draw_buttons, buttons)

		local dy = (#speeds + 1) * bHeight
		if backgroundGuishader then
			gl.DeleteList(backgroundGuishader)
		end
		backgroundGuishader = gl.CreateList(function()
			RectRound(mathFloor((wPos.x * vsx) + 0.5), mathFloor((wPos.y * vsy) + 0.5), mathFloor(((wPos.x + bWidth) * vsx) + 0.5),  mathFloor(((wPos.y + dy) * vsy) + 0.5), elementCorner, 0, 1, 1, 0)
		end)
	end
	
	if WG['guishader'] and isActive and prevIsActive ~= isActive then
		WG['guishader'].InsertDlist(backgroundGuishader, 'replaybuttons')
	end

	if buttonsList then
		gl.CallList(buttonsList)
	end
	draw_timeline()
	local mousex, mousey, buttonstate = spGetMouseState()
	local b = buttons
	local topbutton = #buttons-1
	font:Begin()
	font:SetTextColor(1, 1, 1, 1)
	font:SetOutlineColor(0, 0, 0, 0.7)
	if point_in_rect(b[#buttons].x, b[#buttons].y, b[topbutton].x + bWidth, b[topbutton].y + bHeight, mousex / vsx, mousey / vsy) then

		for i = 1, #b do
			if point_in_rect(b[i].x, b[i].y, b[i].x + bWidth, b[i].y + bHeight, mousex / vsx, mousey / vsy) or i == active_button then

				glBlending(GL_SRC_ALPHA, GL_ONE)
				RectRound(mathFloor((b[i].x * vsx) + 0.5), mathFloor((b[i].y * vsy) + 0.5), mathFloor(((b[i].x + bWidth) * vsx) + 0.5), mathFloor(((b[i].y + bHeight) * vsy) + 0.5), bgpadding * 0.5, 0,1,1,0, { 0.3, 0.3, 0.3, buttonstate and 0.25 or 0.15 }, { 1, 1, 1, buttonstate and 0.25 or 0.15 })
				glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

				font:Print(b[i].text, mathFloor((b[i].x * vsx) + 0.5), mathFloor(((b[i].y + bHeight / 2) * vsy) + 0.5), mathFloor((0.0115 * vsx) + 0.5), 'vo')
				break
			end
		end
	end
	font:End()
end

function widget:MousePress(x, y, button)
	if not isActive then
		return
	end

	if button == 1 then
		local x1, y1, x2, y2 = timeline_rect_pixels()
		if point_in_rect(x1, y1, x2, y2, x, y) then
			jump_to_frame(frame_from_timeline_x(x))
			return true
		end
	end

	local cb, i = clicked_button(buttons)
	if cb == "playpauseskip" then
		if spGetGameFrame() > 1 then
			isPaused = not isPaused
			Spring.SendCommands('pause '..(isPaused and '1' or '0'))
			buttons[i].text = (isPaused and '  >>' or '  ||')
		else
			Spring.SendCommands("skip 1")
			buttons[i].text = "  ||"
		end
		sceduleUpdate = true
		return true
    elseif cb ~= "NOBUTTONCLICKED" then
        setReplaySpeed(speeds[i])
        sceduleUpdate = true
        return true
    end
end

function widget:Update(dt)
	prevIsActive = isActive
	isActive = #Spring.GetSelectedUnits() == 0
	checkpoint_self_test_update()
end

function widget:GameFrame(frame)
	if checkpoint_self_test_game_frame(frame) then
		return
	end

	if not selfTestEnabled or selfTestComplete then
		return
	end

	if not selfTestTriggered and frame >= selfTestStartFrame then
		local targetFrame = self_test_target_frame(frame)
		if targetFrame <= frame + 1 then
			Spring.Echo("[ReplayTimelineTest] failed current=" .. frame .. " target=" .. targetFrame .. " reason=no-forward-target")
			selfTestReached = true
			selfTestComplete = true
			if selfTestQuit then
				Spring.SendCommands("quitforce")
			end
			return
		end

		selfTestTriggered = true
		selfTestTargetFrame = targetFrame
		selfTestDeadlineFrame = targetFrame + 300
		Spring.Echo("[ReplayTimelineTest] start current=" .. frame .. " target=" .. targetFrame .. " length=" .. replayLengthFrames)
		jump_to_frame(targetFrame, "self-test")
		return
	end

	if selfTestTriggered and not selfTestReached and frame >= selfTestTargetFrame and selfTestTargetFrame > 0 then
		selfTestReached = true
		Spring.Echo("[ReplayTimelineTest] reached current=" .. frame .. " target=" .. selfTestTargetFrame)
		if selfTestQuit and (selfTestQuitFrame <= frame or selfTestQuitFrame <= 0) then
			selfTestComplete = true
			Spring.SendCommands("quitforce")
		elseif selfTestQuit then
			Spring.Echo("[ReplayTimelineTest] continue current=" .. frame .. " target=" .. selfTestTargetFrame .. " quit_frame=" .. selfTestQuitFrame)
		else
			selfTestComplete = true
		end
		return
	end

	if selfTestReached and selfTestQuit and selfTestQuitFrame > 0 and frame >= selfTestQuitFrame then
		selfTestComplete = true
		Spring.Echo("[ReplayTimelineTest] post-target current=" .. frame .. " target=" .. selfTestTargetFrame .. " quit_frame=" .. selfTestQuitFrame)
		Spring.SendCommands("quitforce")
		return
	end

	if selfTestTriggered and selfTestDeadlineFrame > 0 and frame > selfTestDeadlineFrame then
		selfTestReached = true
		selfTestComplete = true
		Spring.Echo("[ReplayTimelineTest] failed current=" .. frame .. " target=" .. selfTestTargetFrame .. " reason=deadline")
		if selfTestQuit then
			Spring.SendCommands("quitforce")
		end
	end
end

function widget:GameStart()
	widget:ViewResize()
	buttons[#buttons].text = "  ||"
end
