rootWidget = g_ui.getRootWidget()
modules = package.loaded
G = G or {}

function focusRoot()
	local gameRootPanel = modules.game_interface.getRootPanel()

	if gameRootPanel then
		gameRootPanel:focus()
	end
end

local function closeTopEscapeWidget()
	if not rootWidget then
		return false
	end

	local children = rootWidget:recursiveGetChildren()

	if not children then
		return false
	end

	for i = #children, 1, -1 do
		local child = children[i]

		if child and child ~= rootWidget and child:isVisible() and child:isEnabled() and child.onEscape then
			signalcall(child.onEscape, child)
			return true
		end
	end

	return false
end

function g_ui.onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks)
	if autoRepeatTicks ~= 0 then
		return false
	end

	if keyboardModifiers == KeyboardNoModifier and keyCode == KeyEscape then
		return closeTopEscapeWidget()
	end

	return false
end

function scheduleEvent(callback, delay)
	local desc = "lua"
	local info = debug.getinfo(2, "Sl")

	if info then
		desc = info.short_src .. ":" .. info.currentline
	end

	local event = g_dispatcher.scheduleEvent(desc, callback, delay)
	event._callback = callback

	return event
end

function addEvent(callback, front)
	local desc = "lua"
	local info = debug.getinfo(2, "Sl")

	if info then
		desc = info.short_src .. ":" .. info.currentline
	end

	local event = g_dispatcher.addEvent(desc, callback, front)
	event._callback = callback

	return event
end

function cycleEvent(callback, interval)
	local desc = "lua"
	local info = debug.getinfo(2, "Sl")

	if info then
		desc = info.short_src .. ":" .. info.currentline
	end

	local event = g_dispatcher.cycleEvent(desc, callback, interval)
	event._callback = callback

	return event
end

function periodicalEvent(eventFunc, conditionFunc, delay, autoRepeatDelay)
	delay = delay or 30
	autoRepeatDelay = autoRepeatDelay or delay
	local func = nil

	function func()
		if conditionFunc and not conditionFunc() then
			func = nil

			return
		end

		eventFunc()
		scheduleEvent(func, delay)
	end

	scheduleEvent(function ()
		func()
	end, autoRepeatDelay)
end

function removeEvent(event)
	if event then
		event:cancel()

		event._callback = nil
	end
end
