local window
withdrawWindow = nil
local protocolRegistered = false
local currentItemData = {}
local currentSizeLeft = 0
local itemNameCache = {}
local searchInput
local OPCODE_SUPPLY_STASH_REQUEST = 0x28
local OPCODE_SUPPLY_STASH_SEND = 0x29
local ACTION_OPEN = 1
local ACTION_STOW_ALL = 2
local ACTION_WITHDRAW = 3

local function debugLog(message)
	return
end

local function sendSupplyRequest(action, itemId, count)
	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		debugLog("sendSupplyRequest aborted: protocolGame is nil (action=" .. tostring(action) .. ")")
		return
	end

	debugLog("sendSupplyRequest action=" .. tostring(action) .. ", itemId=" .. tostring(itemId) .. ", count=" .. tostring(count))

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_SUPPLY_STASH_REQUEST)
	msg:addU8(action)
	if action == ACTION_WITHDRAW then
		if not itemId or not count then
			return
		end

		msg:addU16(itemId)
		msg:addU32(count)
	end
	protocolGame:send(msg)
	debugLog("packet sent with opcode=" .. tostring(OPCODE_SUPPLY_STASH_REQUEST))
end

local function requestOpen()
	debugLog("requestOpen called")
	sendSupplyRequest(ACTION_OPEN)
end

local function showWindow()
	debugLog("showWindow")
	window:show()
	window:raise()
	window:focus()
	modules.game_interface.getRootPanel():focus()
	window:lock()
end

local function hideWindow()
	debugLog("hideWindow")
	window:hide()
	window:unlock()
	modules.game_interface.getRootPanel():focus()
end

local function registerProtocol()
	if protocolRegistered then
		return
	end

	debugLog("registerProtocol: registering opcode " .. tostring(OPCODE_SUPPLY_STASH_SEND))
	ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
	ProtocolGame.registerOpcode(OPCODE_SUPPLY_STASH_SEND,
        function(protocol, msg)
			local itemData = {}
			local count = msg:getU16()
			debugLog("opcode " .. tostring(OPCODE_SUPPLY_STASH_SEND) .. " received, item count=" .. tostring(count))
            for i = 1, count do
				table.insert(itemData, {msg:getU16(), msg:getU32()})
            end

			local sizeLeft = msg:getU16()
			debugLog("setup called with sizeLeft=" .. tostring(sizeLeft))
			setup(itemData, sizeLeft)
        end
    )
	protocolRegistered = true
end

local function unregisterProtocol()
	if not protocolRegistered then
		return
	end

	debugLog("unregisterProtocol: unregistering opcode " .. tostring(OPCODE_SUPPLY_STASH_SEND))
	ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
	protocolRegistered = false
end

function init()	
	debugLog("init start")
	
	-- Main stash window
	window 	   = g_ui.displayUI('supplystash')
	debugLog("UI loaded: supplystash")
	freeSlots = window:recursiveGetChildById('freeSlots')
	
	-- Selecter for charms
	itemsContainer = window:recursiveGetChildById('itemsContainer')
	supplyItems = itemsContainer:recursiveGetChildById('supplyItems')
	searchInput = window:recursiveGetChildById('searchInput')
	if searchInput then
		searchInput.onTextChange = function()
			refreshItemList()
		end
	end
	debugLog("UI refs resolved: freeSlots=" .. tostring(freeSlots ~= nil) .. ", itemsContainer=" .. tostring(itemsContainer ~= nil) .. ", supplyItems=" .. tostring(supplyItems ~= nil))
	
	connect(
        g_game,
        {
            onEnterGame = registerProtocol,
            onPendingGame = registerProtocol,
            onGameStart = registerProtocol,
            onGameEnd = unregisterProtocol
        }
    )
	
	createwithdrawWindow()
	debugLog("withdraw window created")
	
    if g_game.isOnline() then
		debugLog("game is online during init; registering protocol now")
        registerProtocol()
	else
		debugLog("game offline during init; waiting on onEnterGame/onPendingGame/onGameStart")
    end
end

function terminate()
	debugLog("terminate")
	disconnect(
        g_game,
        {
            onEnterGame = registerProtocol,
            onPendingGame = registerProtocol,
            onGameStart = registerProtocol,
            onGameEnd = unregisterProtocol
        }
    )

    unregisterProtocol()
	window:destroy()
	withdrawWindow:destroy()
end

function toggle()
	debugLog("toggle called; window visible=" .. tostring(window and window:isVisible() or false))
	if window:isVisible() then
		hideWindow()
	else
		requestOpen()
	end
end

function createwithdrawWindow()
	if withdrawWindow then return end
	withdrawWindow = g_ui.displayUI('withdraw')
	withdrawWindow:hide()
	debugLog("withdraw window UI loaded")
end

function withdrawHide()
	withdrawWindow:hide()
end	

function placeholder()
	refreshItemList()
end

function stowAll()
	debugLog("stowAll clicked")
	sendSupplyRequest(ACTION_STOW_ALL)
end

function emptyItemList()
	while supplyItems:getChildCount() > 0 do
		local child = supplyItems:getLastChild()
		child:destroy()
	end
end

local function getItemDisplayName(itemId)
	itemId = tonumber(itemId) or 0
	if itemNameCache[itemId] then
		return itemNameCache[itemId]
	end

	local name
	if Item and Item.create then
		local okItem, item = pcall(function()
			return Item.create(itemId)
		end)
		if okItem and item then
			local okMarket, marketData = pcall(function()
				return item:getMarketData()
			end)
			if okMarket and marketData and marketData.name and marketData.name ~= "" then
				name = marketData.name
			end

			if not name and item.getName then
				local okName, itemName = pcall(function()
					return item:getName()
				end)
				if okName and itemName and itemName ~= "" then
					name = itemName
				end
			end
		end
	end

	name = name or ("Item " .. tostring(itemId))
	itemNameCache[itemId] = name
	return name
end

local function itemMatchesSearch(itemId, name)
	if not searchInput then
		return true
	end

	local text = searchInput:getText()
	if not text or text == "" then
		return true
	end

	text = text:lower()
	return name:lower():find(text, 1, true) ~= nil or tostring(itemId):find(text, 1, true) ~= nil
end

local function openWithdrawWindow(itemId, amount)
	hideWindow()
	withdrawWindow:show()
	withdrawWindow:raise()
	withdrawWindow:focus()
	withdrawWindow:unlock()
	modules.game_interface.getRootPanel():focus()

	withdrawWindow.item:setItemId(itemId)
	withdrawWindow.count:setText(1)
	withdrawWindow.countScrollBar:setMinimum(1)
	withdrawWindow.countScrollBar:setMaximum(amount)
	withdrawWindow.countScrollBar:setValue(1)
	withdrawWindow.countScrollBar.onValueChange = function(widget, value)
		withdrawWindow.count:setText(value)
	end

	local buttonCancel = withdrawWindow:recursiveGetChildById('buttonCancel')
	buttonCancel.onClick = function(self)
		withdrawHide()
		requestOpen()
	end

	local okButton = withdrawWindow:recursiveGetChildById('buttonOk')
	okButton.onClick = function(self)
		local count = tonumber(withdrawWindow:recursiveGetChildById('count'):getText()) or 0
		sendSupplyRequest(ACTION_WITHDRAW, itemId, count)
		withdrawHide()
		modules.game_interface.getRootPanel():focus()
	end
end

function refreshItemList()
	if not supplyItems then
		return
	end

	emptyItemList()
	for i = 1, #currentItemData do
		local itemId = currentItemData[i][1]
		local amount = currentItemData[i][2]
		local name = getItemDisplayName(itemId)
		if itemMatchesSearch(itemId, name) then
			local row = g_ui.createWidget('StashItem', supplyItems)
			row.index = i
			row:setId("stashItem" .. i)
			row.categoryId = i
			row:setItemId(itemId)
			row:setTooltip(name)

			local countText = row:recursiveGetChildById('count')
			countText:setText(tostring(amount))

			row.onClick = function(self)
				openWithdrawWindow(itemId, amount)
			end
		end
	end

	if freeSlots then
		freeSlots:setText("Free slots: " .. currentSizeLeft)
	end
end

function setup(itemData, sizeLeft)
	itemData = itemData or {}
	debugLog("setup start: items=" .. tostring(#itemData) .. ", sizeLeft=" .. tostring(sizeLeft))
	showWindow()
	currentItemData = itemData
	currentSizeLeft = sizeLeft or 0
	refreshItemList()
end
