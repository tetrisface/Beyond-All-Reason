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
local mathMax = math.max
local mathMin = math.min

-- Localized Spring API for performance
local spGetGameFrame = Spring.GetGameFrame
local spGetConfigInt = Spring.GetConfigInt
local spSetConfigInt = Spring.SetConfigInt
local spGetMouseState = Spring.GetMouseState
local spGetReplayLength = Spring.GetReplayLength
local spGetGameSpeed = Spring.GetGameSpeed
local spGetGameState = Spring.GetGameState
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
local timeline = { x = 0.24, y = 0.045, w = 0.52, h = 0.030 }
local isPaused = false
local isActive = false
local prevIsActive = false
local sceduleUpdate = true
local widgetScale = (0.5 + (vsx * vsy / 5700000))
local replayLengthFrames = 0
local replayCheckpointFrames = {}
local replayCheckpointFramesLoaded = false
local replayCheckpointFramesLogged = false
local replayCheckpointFramesLastRefresh = -999999
local lastSkipFrame = -1
local lastSkipClock = 0
local lastRestoreFrame = -1
local lastRestoreClock = 0
local selfTestEnabled = spGetConfigInt("ReplayTimelineSelfTest", 0) == 1
local selfTestStartFrame = spGetConfigInt("ReplayTimelineSelfTestStartFrame", 30)
local selfTestTargetFrame = spGetConfigInt("ReplayTimelineSelfTestTargetFrame", 0)
local selfTestQuit = spGetConfigInt("ReplayTimelineSelfTestQuit", 0) == 1
local selfTestQuitFrame = spGetConfigInt("ReplayTimelineSelfTestQuitFrame", 0)
local checkpointTimelineJumps = spGetConfigInt("ReplayTimelineCheckpointJumps", 1) == 1
local selfTestUseCheckpoint = spGetConfigInt("ReplayTimelineSelfTestUseCheckpoint", spGetConfigInt("ReplayTimelineCheckpointJumps", 1)) == 1
local selfTestPhase = spGetConfigInt("ReplayTimelineSelfTestPhase", 0)
local selfTestResolvedTargetFrame = spGetConfigInt("ReplayTimelineSelfTestResolvedTargetFrame", 0)
local selfTestDeadlineFrame = spGetConfigInt("ReplayTimelineSelfTestDeadlineFrame", 0)
local selfTestPauseBeforeJump = spGetConfigInt("ReplayTimelineSelfTestPauseBeforeJump", 0) == 1
local selfTestPauseViaButton = spGetConfigInt("ReplayTimelineSelfTestPauseViaButton", 0) == 1
local selfTestResumeAfterReached = spGetConfigInt("ReplayTimelineSelfTestResumeAfterReached", 0) == 1
local selfTestResumeAfterReachedDone = spGetConfigInt("ReplayTimelineSelfTestResumeAfterReachedDone", 0) == 1
local selfTestViaTimelineClick = spGetConfigInt("ReplayTimelineSelfTestViaTimelineClick", 0) == 1
local selfTestPauseDelaySeconds = spGetConfigInt("ReplayTimelineSelfTestPauseDelayMs", 250) * 0.001
local selfTestTriggered = selfTestPhase >= 1
local selfTestReached = selfTestPhase >= 2
local selfTestComplete = selfTestPhase >= 3
if selfTestResolvedTargetFrame > 0 then
	selfTestTargetFrame = selfTestResolvedTargetFrame
end
local checkpointSelfTestEnabled = spGetConfigInt("ReplayCheckpointSelfTest", 0) == 1
local checkpointSelfTestSaveFrame = spGetConfigInt("ReplayCheckpointSelfTestSaveFrame", 30)
local checkpointSelfTestLoadFrame = spGetConfigInt("ReplayCheckpointSelfTestLoadFrame", 90)
local checkpointSelfTestTargetFrame = spGetConfigInt("ReplayCheckpointSelfTestTargetFrame", 0)
local checkpointSelfTestSkipSave =
	spGetConfigInt("ReplayCheckpointUseBundle", spGetConfigInt("ReplayCheckpointSelfTestSkipSave", 0)) == 1
local checkpointSelfTestResumeFrame = spGetConfigInt("ReplayCheckpointSelfTestResumeFrame", 0)
local checkpointSelfTestQuit = spGetConfigInt("ReplayCheckpointSelfTestQuit", 0) == 1
local checkpointSelfTestTimeoutSeconds = spGetConfigInt("ReplayCheckpointSelfTestTimeoutSeconds", 10)
local checkpointSelfTestPauseBeforeLoad = spGetConfigInt("ReplayCheckpointSelfTestPauseBeforeLoad", 1) == 1
local checkpointSelfTestPrepareDelaySeconds = 0.25
local checkpointSelfTestPhase = spGetConfigInt("ReplayCheckpointSelfTestPhase", 0)
local checkpointSelfTestRequestFrame = spGetConfigInt("ReplayCheckpointSelfTestRequestFrame", 0)
local checkpointSelfTestRequestClock = os.clock()
local restoreSerialAtWidgetLoad = spGetConfigInt("ReplayCheckpointRestoreSerial", 0)
local pausedCatchupPhase = spGetConfigInt("ReplayTimelinePausedCatchupPhase", 0)
local pausedCatchupTargetFrame = spGetConfigInt("ReplayTimelinePausedCatchupTargetFrame", 0)
local pausedCatchupRequestFrame = spGetConfigInt("ReplayTimelinePausedCatchupRequestFrame", 0)
local pausedCatchupStartSerial = spGetConfigInt("ReplayTimelinePausedCatchupStartSerial", 0)
local pausedCatchupRestoreSerial = spGetConfigInt("ReplayTimelinePausedCatchupRestoreSerial", 0)
local pausedCatchupRestoreSpeedX1000 = spGetConfigInt("ReplayTimelinePausedCatchupRestoreSpeedX1000", 0)
local pausedCatchupSpeedRestored = spGetConfigInt("ReplayTimelinePausedCatchupSpeedRestored", 0) == 1
local pausedCatchupSpeedX1000 = spGetConfigInt("ReplayTimelinePausedCatchupSpeedX1000", 500)
local pausedCatchupPauseFrame = -1
local pausedCatchupStableDraws = 0
local pausedCatchupSpeedPrepareChecks = 0
local pausedCatchupPauseChecks = 0
local pausedCatchupSpeedSettleChecks = mathMax(1, spGetConfigInt("ReplayTimelinePausedCatchupSpeedSettleChecks", 300))
local pausedCatchupPauseSettleChecks = mathMax(1, spGetConfigInt("ReplayTimelinePausedCatchupPauseSettleChecks", 90))
local set_pause_button_state

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

local function replay_speed_from_x1000(speedX1000)
	return mathMax(0.1, speedX1000 * 0.001)
end

local function get_wanted_replay_speed()
	local wantedSpeed = spGetGameSpeed()
	return wantedSpeed or 1
end

local function set_config_int(name, value)
	if spSetConfigInt then
		spSetConfigInt(name, value, true)
	end
end

local function get_replay_paused()
	if spGetGameState then
		local _, _, clientPaused = spGetGameState()
		if clientPaused ~= nil then
			return clientPaused
		end
	end

	local _, _, paused = spGetGameSpeed()
	return paused
end

local function clear_paused_timeline_catchup()
	pausedCatchupPhase = 0
	pausedCatchupTargetFrame = 0
	pausedCatchupRequestFrame = 0
	pausedCatchupStartSerial = 0
	pausedCatchupRestoreSerial = 0
	pausedCatchupRestoreSpeedX1000 = 0
	pausedCatchupSpeedRestored = false
	pausedCatchupSpeedPrepareChecks = 0
	pausedCatchupPauseChecks = 0

	set_config_int("ReplayTimelinePausedCatchupPhase", 0)
	set_config_int("ReplayTimelinePausedCatchupTargetFrame", 0)
	set_config_int("ReplayTimelinePausedCatchupRequestFrame", 0)
	set_config_int("ReplayTimelinePausedCatchupStartSerial", 0)
	set_config_int("ReplayTimelinePausedCatchupRestoreSerial", 0)
	set_config_int("ReplayTimelinePausedCatchupRestoreSpeedX1000", 0)
	set_config_int("ReplayTimelinePausedCatchupSpeedRestored", 0)
end

local function set_replay_paused(paused, source)
	if Spring.SetReplayPaused then
		local accepted = Spring.SetReplayPaused(paused)
		Spring.Echo(
			"[ReplayTimelinePausedCatchup] pause-api source=" .. source ..
			" paused=" .. (paused and "1" or "0") ..
			" accepted=" .. (accepted and "1" or "0")
		)
		if accepted then
			return true
		end
	end

	Spring.Echo(
		"[ReplayTimelinePausedCatchup] pause-command source=" .. source ..
		" paused=" .. (paused and "1" or "0")
	)
	Spring.SendCommands(paused and "pause 1" or "pause 0")
	return false
end

local function restore_paused_timeline_catchup_speed(source)
	if pausedCatchupSpeedRestored or pausedCatchupRestoreSpeedX1000 <= 0 then
		return
	end

	local restoreSpeed = replay_speed_from_x1000(pausedCatchupRestoreSpeedX1000)
	setReplaySpeed(restoreSpeed)
	pausedCatchupSpeedRestored = true
	set_config_int("ReplayTimelinePausedCatchupSpeedRestored", 1)
	Spring.Echo(
		"[ReplayTimelinePausedCatchup] speed-restore source=" .. source ..
		" speed=" .. restoreSpeed
	)
end

local function set_paused_timeline_catchup_phase(phase)
	pausedCatchupPhase = phase
	set_config_int("ReplayTimelinePausedCatchupPhase", phase)
end

local function prepare_paused_timeline_catchup(targetFrame, requestFrame, source)
	if source ~= "manual" and source ~= "self-test" then
		return
	end

	local paused = get_replay_paused()
	local wantsPausedAfterJump = paused or isPaused or (source == "self-test" and selfTestPauseBeforeJump)
	if not wantsPausedAfterJump then
		clear_paused_timeline_catchup()
		return
	end

	pausedCatchupTargetFrame = targetFrame
	pausedCatchupRequestFrame = requestFrame
	pausedCatchupStartSerial = spGetConfigInt("ReplayCheckpointRestoreSerial", 0)
	pausedCatchupRestoreSerial = 0
	pausedCatchupRestoreSpeedX1000 = mathMax(1, mathFloor((get_wanted_replay_speed() * 1000) + 0.5))
	pausedCatchupSpeedRestored = false
	set_paused_timeline_catchup_phase(1)

	set_config_int("ReplayTimelinePausedCatchupTargetFrame", pausedCatchupTargetFrame)
	set_config_int("ReplayTimelinePausedCatchupRequestFrame", pausedCatchupRequestFrame)
	set_config_int("ReplayTimelinePausedCatchupStartSerial", pausedCatchupStartSerial)
	set_config_int("ReplayTimelinePausedCatchupRestoreSerial", 0)
	set_config_int("ReplayTimelinePausedCatchupRestoreSpeedX1000", pausedCatchupRestoreSpeedX1000)
	set_config_int("ReplayTimelinePausedCatchupSpeedRestored", 0)

	Spring.Echo(
		"[ReplayTimelinePausedCatchup] pending target=" .. pausedCatchupTargetFrame ..
		" request=" .. pausedCatchupRequestFrame ..
		" serial=" .. pausedCatchupStartSerial ..
		" source=" .. source ..
		" speed_paused=" .. (paused and "1" or "0") ..
		" restore_speed_x1000=" .. pausedCatchupRestoreSpeedX1000
	)
end

local function update_replay_length()
	local seconds = spGetReplayLength and spGetReplayLength()
	if seconds and seconds > 0 then
		replayLengthFrames = math.max(replayLengthFrames, mathFloor(seconds * 30))
	end
end

local function send_checkpoint_load(targetFrame)
	if Spring.LoadReplayCheckpoint then
		local accepted = Spring.LoadReplayCheckpoint(targetFrame)
		Spring.Echo("[ReplayCheckpointTimeline] api-load target=" .. targetFrame .. " accepted=" .. (accepted and "1" or "0"))
		if accepted then
			return
		end
	end
	Spring.Echo("[ReplayCheckpointTimeline] command-load target=" .. targetFrame)
	Spring.SendCommands("replaycheckpoint load " .. targetFrame)
end

local function request_checkpoint_load(targetFrame, requestFrame, source)
	source = source or "manual"
	prepare_paused_timeline_catchup(targetFrame, requestFrame, source)
	Spring.Echo(
		"[ReplayCheckpointTimeline] load-dispatch target=" .. targetFrame ..
		" request=" .. requestFrame ..
		" source=" .. source
	)
	send_checkpoint_load(targetFrame)
	return false
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

local function timeline_click_point_for_frame(targetFrame)
	update_replay_length()
	local x1, y1, x2, y2 = timeline_rect_pixels()
	local progress = targetFrame / mathMax(1, replayLengthFrames)
	local clickX = mathFloor(x1 + ((x2 - x1) * mathMax(0, mathMin(1, progress))) + 0.5)
	local clickY = mathFloor(((y1 + y2) * 0.5) + 0.5)
	return clickX, clickY, frame_from_timeline_x(clickX)
end

local function refresh_replay_checkpoint_frames(currentFrame)
	if replayCheckpointFramesLoaded or not Spring.GetReplayCheckpoints then
		return
	end

	if currentFrame - replayCheckpointFramesLastRefresh < 30 then
		return
	end

	replayCheckpointFramesLastRefresh = currentFrame
	local frames = Spring.GetReplayCheckpoints()
	if type(frames) ~= "table" or #frames <= 0 then
		return
	end

	replayCheckpointFrames = frames
	replayCheckpointFramesLoaded = true

	if not replayCheckpointFramesLogged then
		replayCheckpointFramesLogged = true
		Spring.Echo(
			"[ReplayTimelineCheckpoints] loaded count=" .. #replayCheckpointFrames ..
			" first=" .. replayCheckpointFrames[1] ..
			" last=" .. replayCheckpointFrames[#replayCheckpointFrames]
		)
	end
end

local function jump_to_frame(targetFrame, source)
	update_replay_length()
	local currentFrame = spGetGameFrame()
	if replayLengthFrames <= 0 then
		return
	end
	targetFrame = math.max(1, math.min(replayLengthFrames, targetFrame))
	local useCheckpoint = targetFrame <= currentFrame + 1 or
		(checkpointTimelineJumps and (source ~= "self-test" or selfTestUseCheckpoint))
	if useCheckpoint then
		local now = os.clock()
		if targetFrame == lastRestoreFrame and now - lastRestoreClock < 0.5 then
			return
		end
		lastRestoreFrame = targetFrame
		lastRestoreClock = now
		if source == "self-test" then
			Spring.Echo("[ReplayTimelineTest] checkpoint-request current=" .. currentFrame .. " target=" .. targetFrame)
		else
			Spring.Echo("[Replay] Requesting checkpoint restore to frame " .. targetFrame .. " from frame " .. currentFrame)
		end
		request_checkpoint_load(targetFrame, currentFrame, source or "manual")
		return
	end
	local now = os.clock()
	if targetFrame == lastSkipFrame and now - lastSkipClock < 0.5 then
		return
	end
	lastSkipFrame = targetFrame
	lastSkipClock = now
	if source == "self-test" then
		Spring.Echo("[ReplayTimelineTest] skip-request current=" .. currentFrame .. " target=" .. targetFrame)
	end
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

local function timeline_self_test_set_phase(phase)
	selfTestPhase = phase
	selfTestTriggered = phase >= 1
	selfTestReached = phase >= 2
	selfTestComplete = phase >= 3
	if spSetConfigInt then
		spSetConfigInt("ReplayTimelineSelfTestPhase", phase)
	end
end

local function timeline_self_test_set_target(targetFrame, deadlineFrame)
	selfTestTargetFrame = targetFrame
	selfTestDeadlineFrame = deadlineFrame
	if spSetConfigInt then
		spSetConfigInt("ReplayTimelineSelfTestResolvedTargetFrame", targetFrame)
		spSetConfigInt("ReplayTimelineSelfTestDeadlineFrame", deadlineFrame)
	end
end

local function timeline_self_test_fail(currentFrame, targetFrame, reason)
	timeline_self_test_set_phase(3)
	Spring.Echo("[ReplayTimelineTest] failed current=" .. currentFrame .. " target=" .. targetFrame .. " reason=" .. reason)
	if selfTestQuit then
		Spring.SendCommands("quitforce")
	end
end

local timelineSelfTestPendingJump = false
local timelineSelfTestRequestClock = os.clock()

set_pause_button_state = function(paused)
	isPaused = paused
	if buttons[#buttons] then
		buttons[#buttons].text = paused and "  >>" or "  ||"
		sceduleUpdate = true
	end
end

local function set_replay_pause_from_button(paused)
	set_pause_button_state(paused)
	set_replay_paused(paused, "manual-button")
end

local function timeline_self_test_dispatch_jump(currentFrame, targetFrame)
	if not selfTestViaTimelineClick then
		jump_to_frame(targetFrame, "self-test")
		return
	end

	local clickX, clickY, clickFrame = timeline_click_point_for_frame(targetFrame)
	Spring.Echo(
		"[ReplayTimelineTest] timeline-click current=" .. currentFrame ..
		" target=" .. targetFrame ..
		" click_frame=" .. clickFrame ..
		" x=" .. clickX ..
		" y=" .. clickY ..
		" active=" .. (isActive and "1" or "0")
	)
	if clickFrame ~= targetFrame then
		timeline_self_test_fail(currentFrame, targetFrame, "timeline-click-frame-quantization")
		return
	end
	if not widget:MousePress(clickX, clickY, 1, "self-test") then
		timeline_self_test_fail(currentFrame, targetFrame, "timeline-click-not-handled")
	end
end

local function timeline_self_test_quit_or_defer()
	timeline_self_test_set_phase(3)
	Spring.SendCommands("quitforce")
end

local function timeline_self_test_resume_after_reached()
	if not selfTestResumeAfterReached or selfTestResumeAfterReachedDone or not selfTestReached or selfTestComplete then
		return
	end

	local currentFrame = spGetGameFrame()
	local paused = get_replay_paused()
	selfTestResumeAfterReachedDone = true
	set_config_int("ReplayTimelineSelfTestResumeAfterReachedDone", 1)

	if not paused then
		Spring.Echo(
			"[ReplayTimelineTest] resume-after-reached current=" .. currentFrame ..
			" target=" .. selfTestTargetFrame ..
			" paused=0 already=1"
		)
		return
	end

	set_pause_button_state(false)
	set_replay_paused(false, "self-test-after-reached")
	Spring.Echo(
		"[ReplayTimelineTest] resume-after-reached current=" .. currentFrame ..
		" target=" .. selfTestTargetFrame ..
		" paused=1"
	)
end

local function timeline_self_test_mark_reached(frame, paused)
	timeline_self_test_set_phase(2)
	Spring.Echo(
		"[ReplayTimelineTest] reached current=" .. frame ..
		" target=" .. selfTestTargetFrame ..
		" paused=" .. (paused and "1" or "0")
	)
	if selfTestQuit and (selfTestQuitFrame <= frame or selfTestQuitFrame <= 0) then
		timeline_self_test_quit_or_defer()
	elseif selfTestQuit then
		Spring.Echo("[ReplayTimelineTest] continue current=" .. frame .. " target=" .. selfTestTargetFrame .. " quit_frame=" .. selfTestQuitFrame)
	else
		timeline_self_test_set_phase(3)
	end
end

local function timeline_paused_catchup_blocks_reached()
	return pausedCatchupPhase > 0 and pausedCatchupTargetFrame == selfTestTargetFrame
end

local function complete_paused_timeline_catchup(currentFrame, paused)
	local targetFrame = pausedCatchupTargetFrame
	local restoreFrame = spGetConfigInt("ReplayCheckpointRestoreFrame", -1)
	Spring.Echo(
		"[ReplayTimelinePausedCatchup] complete current=" .. currentFrame ..
		" target=" .. targetFrame ..
		" restore=" .. restoreFrame ..
		" paused=" .. (paused and "1" or "0")
	)
	clear_paused_timeline_catchup()

	if selfTestPauseBeforeJump and selfTestTriggered and not selfTestReached and selfTestTargetFrame == targetFrame then
		timeline_self_test_mark_reached(currentFrame, paused)
	end
end

local function fail_paused_timeline_catchup(reason, currentFrame, paused, detail)
	local targetFrame = pausedCatchupTargetFrame
	local restoreFrame = spGetConfigInt("ReplayCheckpointRestoreFrame", -1)
	Spring.Echo(
		"[ReplayTimelinePausedCatchup] failed current=" .. currentFrame ..
		" target=" .. targetFrame ..
		" restore=" .. restoreFrame ..
		" paused=" .. (paused and "1" or "0") ..
		" reason=" .. reason ..
		(detail or "")
	)
	clear_paused_timeline_catchup()

	if selfTestTriggered and not selfTestComplete and selfTestTargetFrame == targetFrame then
		timeline_self_test_set_phase(3)
		Spring.Echo(
			"[ReplayTimelineTest] failed current=" .. currentFrame ..
			" target=" .. targetFrame ..
			" reason=paused-catchup-" .. reason
		)
		if selfTestQuit then
			Spring.SendCommands("quitforce")
		end
	end
end

local function update_paused_timeline_catchup()
	if pausedCatchupPhase <= 0 or pausedCatchupTargetFrame <= 0 then
		return false
	end

	local currentFrame = spGetGameFrame()
	local restoreSerial = spGetConfigInt("ReplayCheckpointRestoreSerial", 0)
	local restoreFrame = spGetConfigInt("ReplayCheckpointRestoreFrame", -1)
	local restoreTargetFrame = spGetConfigInt("ReplayCheckpointRestoreTargetFrame", -1)
	local speedPaused = get_replay_paused()

	if pausedCatchupPhase == 1 then
		if restoreSerial <= pausedCatchupStartSerial or restoreTargetFrame ~= pausedCatchupTargetFrame then
			return true
		end

		pausedCatchupRestoreSerial = restoreSerial
		set_config_int("ReplayTimelinePausedCatchupRestoreSerial", pausedCatchupRestoreSerial)

		if currentFrame >= pausedCatchupTargetFrame then
			Spring.Echo(
				"[ReplayTimelinePausedCatchup] skipped current=" .. currentFrame ..
				" target=" .. pausedCatchupTargetFrame ..
				" restore=" .. restoreFrame ..
				" paused=" .. (speedPaused and "1" or "0")
			)
			clear_paused_timeline_catchup()
			return false
		end

		set_paused_timeline_catchup_phase(2)
		pausedCatchupSpeedPrepareChecks = 0
		Spring.Echo(
			"[ReplayTimelinePausedCatchup] speed-prepare current=" .. currentFrame ..
			" target=" .. pausedCatchupTargetFrame ..
			" restore=" .. restoreFrame ..
			" span=" .. (pausedCatchupTargetFrame - currentFrame) ..
			" paused=1" ..
			" speed_paused=" .. (speedPaused and "1" or "0") ..
			" catchup_speed=" .. replay_speed_from_x1000(pausedCatchupSpeedX1000)
		)
		setReplaySpeed(replay_speed_from_x1000(pausedCatchupSpeedX1000))
		return true
	end

	if pausedCatchupPhase == 2 then
		local catchupSpeed = replay_speed_from_x1000(pausedCatchupSpeedX1000)
		local wantedSpeed = get_wanted_replay_speed()
		pausedCatchupSpeedPrepareChecks = pausedCatchupSpeedPrepareChecks + 1
		if wantedSpeed > catchupSpeed + 0.01 and pausedCatchupSpeedPrepareChecks < pausedCatchupSpeedSettleChecks then
			return true
		end
		if wantedSpeed > catchupSpeed + 0.01 then
			fail_paused_timeline_catchup(
				"speed-settle-timeout",
				currentFrame,
				speedPaused,
				" wanted_speed=" .. wantedSpeed ..
				" catchup_speed=" .. catchupSpeed ..
				" checks=" .. pausedCatchupSpeedPrepareChecks
			)
			return true
		end

		set_paused_timeline_catchup_phase(3)
		Spring.Echo(
			"[ReplayTimelinePausedCatchup] start current=" .. currentFrame ..
			" target=" .. pausedCatchupTargetFrame ..
			" restore=" .. restoreFrame ..
			" span=" .. (pausedCatchupTargetFrame - currentFrame) ..
			" paused=1" ..
			" speed_paused=" .. (speedPaused and "1" or "0") ..
			" catchup_speed=" .. catchupSpeed ..
			" wanted_speed=" .. wantedSpeed
		)
		set_pause_button_state(false)
		set_replay_paused(false, "catchup-start")
		return true
	end

	if pausedCatchupPhase == 3 then
		if currentFrame < pausedCatchupTargetFrame then
			return true
		end

		set_paused_timeline_catchup_phase(4)
		pausedCatchupPauseFrame = currentFrame
		pausedCatchupStableDraws = 0
		pausedCatchupPauseChecks = 0
		set_pause_button_state(true)
		local accepted = set_replay_paused(true, "catchup-target")
		if accepted then
			restore_paused_timeline_catchup_speed("catchup-target")
		end
		Spring.Echo(
			"[ReplayTimelinePausedCatchup] pause-request current=" .. currentFrame ..
			" target=" .. pausedCatchupTargetFrame ..
			" speed_paused=" .. (speedPaused and "1" or "0")
		)
		return true
	end

	if pausedCatchupPhase == 4 then
		pausedCatchupPauseChecks = pausedCatchupPauseChecks + 1
		if currentFrame == pausedCatchupPauseFrame then
			pausedCatchupStableDraws = pausedCatchupStableDraws + 1
		else
			pausedCatchupPauseFrame = currentFrame
			pausedCatchupStableDraws = 0
		end

		if speedPaused then
			restore_paused_timeline_catchup_speed("catchup-stable")
		end

		if not speedPaused and pausedCatchupPauseChecks < pausedCatchupPauseSettleChecks then
			return true
		end
		if not speedPaused then
			fail_paused_timeline_catchup(
				"pause-settle-timeout",
				currentFrame,
				false,
				" checks=" .. pausedCatchupPauseChecks ..
				" stable_draws=" .. pausedCatchupStableDraws
			)
			return true
		end

		complete_paused_timeline_catchup(currentFrame, true)
		return true
	end

	clear_paused_timeline_catchup()
	return false
end

local function timeline_self_test_update_paused_jump()
	if not selfTestEnabled or selfTestComplete then
		return
	end
	if timelineSelfTestPendingJump then
		local currentFrame = spGetGameFrame()
		local paused = get_replay_paused()
		if os.clock() - timelineSelfTestRequestClock >= selfTestPauseDelaySeconds then
			timelineSelfTestPendingJump = false
			Spring.Echo(
				"[ReplayTimelineTest] jump-dispatch current=" .. currentFrame ..
				" target=" .. selfTestTargetFrame ..
				" paused=" .. (paused and "1" or "0")
			)
			timeline_self_test_dispatch_jump(currentFrame, selfTestTargetFrame)
		end
	elseif selfTestPauseBeforeJump and selfTestTriggered and not selfTestReached and selfTestTargetFrame > 0 then
		if timeline_paused_catchup_blocks_reached() then
			return
		end
		local currentFrame = spGetGameFrame()
		if currentFrame >= selfTestTargetFrame then
			local restoreSerial = spGetConfigInt("ReplayCheckpointRestoreSerial", 0)
			if restoreSerial > 0 and restoreSerialAtWidgetLoad <= 0 then
				return
			end
			local paused = get_replay_paused()
			timeline_self_test_mark_reached(currentFrame, paused)
		end
	end
end

local function checkpoint_self_test_prepare_load(frame, targetFrame)
	checkpointSelfTestRequestClock = os.clock()
	checkpoint_self_test_set_phase(3)
	isPaused = checkpointSelfTestPauseBeforeLoad
	if buttons[#buttons] then
		buttons[#buttons].text = checkpointSelfTestPauseBeforeLoad and "  >>" or "  ||"
		sceduleUpdate = true
	end
	Spring.Echo(
		"[ReplayCheckpointTest] prepare-load current=" .. frame ..
		" target=" .. targetFrame ..
		" paused=" .. (checkpointSelfTestPauseBeforeLoad and "1" or "0")
	)
	if checkpointSelfTestPauseBeforeLoad then
		Spring.SendCommands("pause 1")
	end
end

local function checkpoint_self_test_game_frame(frame)
	if not checkpointSelfTestEnabled or checkpointSelfTestPhase >= 5 then
		return false
	end

	local targetFrame = checkpoint_self_test_target_frame()

	if checkpointSelfTestPhase <= 0 and checkpointSelfTestSkipSave and frame >= checkpointSelfTestLoadFrame then
		Spring.Echo("[ReplayCheckpointTest] prerecorded current=" .. frame .. " target=" .. targetFrame)
		checkpoint_self_test_prepare_load(frame, targetFrame)
		return true
	end

	if checkpointSelfTestPhase <= 0 and frame >= checkpointSelfTestSaveFrame then
		checkpoint_self_test_set_phase(1)
		Spring.Echo("[ReplayCheckpointTest] save current=" .. frame .. " target=" .. targetFrame)
		Spring.SendCommands("replaycheckpoint save -y")
		return true
	end

	if checkpointSelfTestPhase == 1 and frame >= checkpointSelfTestLoadFrame then
		checkpoint_self_test_prepare_load(frame, targetFrame)
		return true
	end

	if checkpointSelfTestPhase == 4 and checkpointSelfTestResumeFrame > 0 and frame >= checkpointSelfTestResumeFrame then
		local paused = get_replay_paused()
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

	return checkpointSelfTestPhase == 2 or checkpointSelfTestPhase == 3 or checkpointSelfTestPhase == 4
end

local function checkpoint_self_test_update()
	if not checkpointSelfTestEnabled or (checkpointSelfTestPhase ~= 2 and checkpointSelfTestPhase ~= 3 and checkpointSelfTestPhase ~= 4) then
		return
	end

	local currentFrame = spGetGameFrame()
	local targetFrame = checkpoint_self_test_target_frame()
	local paused = get_replay_paused()

	if checkpointSelfTestPhase == 3 then
		if os.clock() - checkpointSelfTestRequestClock < checkpointSelfTestPrepareDelaySeconds then
			return
		end

		checkpointSelfTestRequestFrame = currentFrame
		checkpointSelfTestRequestClock = os.clock()
		if spSetConfigInt then
			spSetConfigInt("ReplayCheckpointSelfTestRequestFrame", checkpointSelfTestRequestFrame)
		end
		checkpoint_self_test_set_phase(2)
		Spring.Echo(
			"[ReplayCheckpointTest] load current=" .. currentFrame ..
			" target=" .. targetFrame ..
			" paused=" .. (checkpointSelfTestPauseBeforeLoad and "1" or "0")
		)
		request_checkpoint_load(targetFrame, checkpointSelfTestRequestFrame, "checkpoint-self-test")
		return
	end

	if checkpointSelfTestPhase == 2 and currentFrame <= targetFrame + 1 then
		local elapsed = os.clock() - checkpointSelfTestRequestClock
		Spring.Echo(
			"[ReplayCheckpointTest] restored current=" .. currentFrame ..
			" target=" .. targetFrame ..
			" request=" .. checkpointSelfTestRequestFrame ..
			" paused=" .. (checkpointSelfTestPauseBeforeLoad and "1" or "0") ..
			" elapsed=" .. string.format("%.2f", elapsed)
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
			if checkpointSelfTestPauseBeforeLoad then
				Spring.SendCommands("pause 0")
			end
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
	refresh_replay_checkpoint_frames(currentFrame)

	glColor(0, 0, 0, ui_opacity * 0.78)
	glRect(x1 - bgpadding, y1 - bgpadding, x2 + bgpadding, y2 + bgpadding)
	glColor(0.13, 0.14, 0.15, ui_opacity)
	glRect(x1, y1, x2, y2)
	glColor(0.20, 0.72, 0.92, 0.88)
	glRect(x1, y1, fillX, y2)
	if replayCheckpointFramesLoaded then
		local tickW = mathMax(1, mathFloor(2 * ui_scale + 0.5))
		for i = 1, #replayCheckpointFrames do
			local frame = replayCheckpointFrames[i]
			if frame >= 0 and frame <= replayLengthFrames then
				local tickX = mathFloor(x1 + ((x2 - x1) * frame / replayLengthFrames) + 0.5)
				local passed = frame <= currentFrame
				if passed then
					glColor(0.86, 0.92, 1.0, 0.56)
				else
					glColor(1.0, 0.72, 0.24, 0.64)
				end
				glRect(tickX - tickW, y1 - bgpadding * 0.45, tickX + tickW, y2 + bgpadding * 0.45)
			end
		end
	end
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
	update_paused_timeline_catchup()
	timeline_self_test_update_paused_jump()
	if not isActive then
		if WG['guishader'] and prevIsActive ~= isActive then
			WG['guishader'].RemoveDlist('replaybuttons')
		end
		timeline_self_test_resume_after_reached()
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
	timeline_self_test_resume_after_reached()
end

function widget:MousePress(x, y, button, source)
	if not isActive then
		return
	end

	if button == 1 then
		local x1, y1, x2, y2 = timeline_rect_pixels()
		if point_in_rect(x1, y1, x2, y2, x, y) then
			jump_to_frame(frame_from_timeline_x(x), source)
			return true
		end
	end

	local cb, i = clicked_button(buttons)
	if cb == "playpauseskip" then
		if spGetGameFrame() > 1 then
			local nextPaused = not isPaused
			set_replay_pause_from_button(nextPaused)
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
	update_paused_timeline_catchup()
	timeline_self_test_update_paused_jump()
	timeline_self_test_resume_after_reached()
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
		local useCheckpoint = checkpointTimelineJumps and selfTestUseCheckpoint
		if targetFrame <= frame + 1 and not useCheckpoint then
			timeline_self_test_fail(frame, targetFrame, "no-forward-target")
			return
		end
		if selfTestViaTimelineClick then
			local _, _, clickFrame = timeline_click_point_for_frame(targetFrame)
			targetFrame = clickFrame
			if targetFrame <= 0 then
				timeline_self_test_fail(frame, targetFrame, "timeline-click-target")
				return
			end
		end

		timeline_self_test_set_target(targetFrame, mathMax(frame, targetFrame) + 300)
		timeline_self_test_set_phase(1)
		local paused = get_replay_paused()
		Spring.Echo(
			"[ReplayTimelineTest] start current=" .. frame ..
			" target=" .. targetFrame ..
			" length=" .. replayLengthFrames ..
			" paused=" .. (paused and "1" or "0")
		)
		if selfTestPauseBeforeJump then
			if selfTestPauseViaButton then
				set_replay_pause_from_button(true)
			else
				set_pause_button_state(true)
				set_replay_paused(true, "self-test-before-jump")
			end
			timelineSelfTestPendingJump = true
			timelineSelfTestRequestClock = os.clock()
			Spring.Echo(
				"[ReplayTimelineTest] pause-request current=" .. frame ..
				" target=" .. targetFrame ..
				" via_button=" .. (selfTestPauseViaButton and "1" or "0")
			)
			return
		end
		timeline_self_test_dispatch_jump(frame, targetFrame)
		return
	end

	if selfTestTriggered and not selfTestReached and frame >= selfTestTargetFrame and selfTestTargetFrame > 0 then
		-- Backward paused self-tests start past the target; do not count the
		-- pre-dispatch frame as reached before the timeline click actually runs.
		if timelineSelfTestPendingJump then
			return
		end
		if timeline_paused_catchup_blocks_reached() then
			return
		end
		local paused = get_replay_paused()
		timeline_self_test_mark_reached(frame, paused)
		return
	end

	if selfTestReached and selfTestQuit and selfTestQuitFrame > 0 and frame >= selfTestQuitFrame then
		Spring.Echo("[ReplayTimelineTest] post-target current=" .. frame .. " target=" .. selfTestTargetFrame .. " quit_frame=" .. selfTestQuitFrame)
		timeline_self_test_quit_or_defer()
		return
	end

	if selfTestTriggered and not selfTestReached and not timeline_paused_catchup_blocks_reached() and selfTestDeadlineFrame > 0 and frame > selfTestDeadlineFrame then
		timeline_self_test_fail(frame, selfTestTargetFrame, "deadline")
	end
end

function widget:GameStart()
	widget:ViewResize()
	buttons[#buttons].text = "  ||"
end
