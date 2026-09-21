-- ecma Group System v2 - Client (F6 modern panel, responsive)
-- Responsive: all sizes derive from UI scale S (design base 1600x900).
-- S = min(sw/1600, sh/900) clamped to [0.62, 1.0]. Recomputed on resolution change.
local sw, sh = guiGetScreenSize()

local S = 1
local function updateScale()
    S = math.min(sw / 1600, sh / 900)
    if S > 1 then S = 1 end
    if S < 0.62 then S = 0.62 end
end
updateScale()

local panelVisible = false
local inGroup = false
local myGroup = nil -- {name, rank, owner}
local currentTab = "home" -- home | members | invites | bank | list

-- Groups list (pushed by server, max 10 per group)
local GROUP_MAX_MEMBERS = 10
local groupsListData = {}
-- Invites received (pushed by server: {id, name, from, members, max})
local invitesListData = {}
-- Own clan snapshot (pushed by server: {id, name, rank, owner, color, balance, members})
local clanCache = nil
-- Members of my group (filled by server: {account, name, rank, joined, seen, online})
local membersListData = nil
-- Members selection + actions + notify line
local selectedMemberAccount = nil
local membersRowRects = {}
local memActRects = {}
local membersNotifyMsg = ""
local membersNotifyColor = {150, 160, 180}
local membersNotifyUntil = 0
local RANK_ORDER = {"member", "co-leader", "leader"}
local function membersNotify(msg, r, g, b)
    membersNotifyMsg = msg or ""
    membersNotifyColor = {r or 150, g or 160, b or 180}
    membersNotifyUntil = getTickCount() + 4000
end
-- Bank (الميزانيه) state: right-side popup with balance + settings/withdraw/deposit
local bankBalance = nil
local bankMode = "main" -- "main" | "deposit" | "withdraw"
local bankInput = ""
local bankInputFocused = false
local rBankClose = nil
local bankRects = {}
local bankNotifyMsg = ""
local bankNotifyColor = {150, 160, 180}
local bankNotifyUntil = 0
local function bankNotify(msg, r, g, b)
    bankNotifyMsg = msg or ""
    bankNotifyColor = {r or 150, g or 160, b or 180}
    bankNotifyUntil = getTickCount() + 4000
end
-- Turf color picker (opens above members popup)
local colorPickerOpen = false
local colR, colG, colB = "255", "255", "255"
local colFocus = nil -- "r" | "g" | "b"
local rColorClose = nil
local colorPickerRects = {}
local function applyColor()
    local r, g, b = tonumber(colR), tonumber(colG), tonumber(colB)
    if not r or not g or not b or r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then
        membersNotify("Enter 0-255 for R, G and B.", 255, 200, 100)
        return
    end
    triggerServerEvent("group:setColor", resourceRoot, math.floor(r), math.floor(g), math.floor(b))
end
local function findListedMember(acc)
    if membersListData then
        for _, m in ipairs(membersListData) do
            if m.account == acc then return m end
        end
    end
    return nil
end
local function membersDoRank(up)
    if not selectedMemberAccount then
        membersNotify("Select a member first.", 255, 200, 100)
        return
    end
    local row = findListedMember(selectedMemberAccount)
    if not row then
        membersNotify("Preview row - not a real member.", 255, 200, 100)
        return
    end
    if row.rank == "owner" then
        membersNotify("You cannot change the owner.", 255, 120, 120)
        return
    end
    local idx = 1
    for i, r in ipairs(RANK_ORDER) do
        if r == row.rank then idx = i break end
    end
    local ni = up and idx + 1 or idx - 1
    if ni < 1 or ni > #RANK_ORDER then
        membersNotify(up and "Already at highest promotable rank." or "Already at lowest rank.", 255, 200, 100)
        return
    end
    triggerServerEvent("group:setRank", resourceRoot, selectedMemberAccount, RANK_ORDER[ni])
end
local function membersDoKick()
    if not selectedMemberAccount then
        membersNotify("Select a member first.", 255, 200, 100)
        return
    end
    local row = findListedMember(selectedMemberAccount)
    if not row then
        membersNotify("Preview row - not a real member.", 255, 200, 100)
        return
    end
    if row.rank == "owner" then
        membersNotify("You cannot kick the owner.", 255, 120, 120)
        return
    end
    triggerServerEvent("group:kick", resourceRoot, selectedMemberAccount)
end
local function doBankConfirm()
    local amt = math.floor(tonumber(bankInput) or 0)
    if amt <= 0 then
        bankNotify("Enter a valid amount.", 255, 200, 100)
        return
    end
    if bankMode == "deposit" then
        triggerServerEvent("group:deposit", resourceRoot, amt)
    elseif bankMode == "withdraw" then
        triggerServerEvent("group:withdraw", resourceRoot, amt)
    else
        return
    end
    bankNotify("Processing...", 150, 180, 255)
end
-- Close rects for the square popups (updated each frame)
local rListClose = nil
local rInvitesClose = nil
local rMembersClose = nil

-- Create form state
local groupNameInput = ""
local inputFocused = false
local statusMsg = ""
local statusColor = {200, 200, 200}
local statusUntil = 0

-- Delete clan (owner only, button sits in the top slot where Create sits)
local rDelete = nil
local deleteConfirmOpen = false
local deleteInput = ""
local deleteInputFocused = false
local rDeleteClose = nil
local deleteModalRects = {}

-- Clan chat (key i): native chatbox bound to server command "Clan".
-- Exactly like chat resource's U/Local: always bound, engine opens the REAL input.
-- Server drops outsiders' messages silently. Never unbound except on resource stop.
local function bindClanChatKey()
    unbindKey("i", "down", "chatbox", "Clan")
    bindKey("i", "down", "chatbox", "Clan")
end
local function unbindClanChatKey()
    unbindKey("i", "down", "chatbox", "Clan")
end

-- Layout - narrow panel, vertical rows (base units scaled by S)
local PW, PH = 460 * S, 560 * S
local PX = (sw - PW) / 2
local PY = (sh - PH) / 2

-- Rects (computed relative to PX/PY)
local rClose, rInput, rCreate
local rBtnMembers, rBtnInvites, rBtnBank, rBtnList
local rSepY = 0

local function computeRects()
    PW, PH = 460 * S, 560 * S
    PX = (sw - PW) / 2
    PY = (sh - PH) / 2
    rClose = {PX + PW - 46 * S, PY + 14 * S, 32 * S, 28 * S}
    -- top row: input + create side by side inside narrow width
    rInput = {PX + 24 * S, PY + 132 * S, 258 * S, 42 * S}
    rCreate = {PX + 24 * S + 258 * S + 10 * S, PY + 132 * S, 140 * S, 42 * S}
    -- delete clan: small button inside the in-group header, right side with margin
    local delW, delH = 110 * S, 36 * S
    rDelete = {PX + PW - 24 * S - delW - 10 * S, PY + 84 * S + (64 * S - delH) / 2, delW, delH}
    -- vertical stack: one button per row
    local bw = PW - 48 * S
    local bh = 58 * S
    local by0 = PY + 212 * S
    rBtnMembers = {PX + 24 * S, by0, bw, bh}
    rBtnInvites = {PX + 24 * S, by0 + bh + 10 * S, bw, bh}
    rBtnBank = {PX + 24 * S, by0 + (bh + 10 * S) * 2, bw, bh}
    -- thin separator + groups list button below bank
    rSepY = by0 + (bh + 10 * S) * 3 + 2 * S
    rBtnList = {PX + 24 * S, rSepY + 12 * S, bw, bh}
end
computeRects()
addEventHandler("onClientRestore", root, function()
    sw, sh = guiGetScreenSize()
    updateScale()
    computeRects()
end)

local function setStatus(msg, r, g, b)
    statusMsg = msg or ""
    statusColor = {r or 200, g or 200, b or 200}
    statusUntil = getTickCount() + 4000
end

local function isMouseIn(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    if not cx then return false end
    cx, cy = cx * sw, cy * sh
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function formatSeen(seen, online)
    if online then return "Online" end
    seen = tonumber(seen) or 0
    if seen <= 0 then return "-" end
    local diff = getRealTime().timestamp - seen
    if diff < 0 then diff = 0 end
    if diff < 60 then return "Just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

-- display only: internal rank keys stay lowercase (member/co-leader/leader/owner)
local RANK_LABEL = {member = "Member", ["co-leader"] = "Co-Leader", leader = "Leader", owner = "Owner"}
local function formatRank(rank)
    return RANK_LABEL[rank] or tostring(rank)
end

local function togglePanel(state)
    if state == nil then state = not panelVisible end
    panelVisible = state
    showCursor(panelVisible)
    if panelVisible then
        inputFocused = false
        -- reset to home synchronously so stale members/invites/list popup
        -- doesn't render one frame before server stateUpdate arrives
        currentTab = "home"
        colorPickerOpen = false
        colFocus = nil
        deleteConfirmOpen = false
        deleteInput = ""
        deleteInputFocused = false
        -- lock player interaction while panel is open: no chat, no shooting, no movement
        guiSetInputEnabled(true)
        showChat(false)
        toggleAllControls(false, true, false)
        triggerServerEvent("group:requestState", resourceRoot)
    else
        inputFocused = false
        selectedMemberAccount = nil
        deleteConfirmOpen = false
        deleteInput = ""
        deleteInputFocused = false
        -- restore interaction
        guiSetInputEnabled(false)
        showChat(true)
        toggleAllControls(true)
    end
end
bindKey("F6", "down", function() togglePanel() end)
addCommandHandler("gpanel", function() togglePanel() end)
addCommandHandler("group", function() togglePanel(true) end)
-- Clan chat key is bound at resource start and removed at resource stop (like chat's U).

-- ================= CLAN FRIENDLY FIRE (client-side only) =================
-- Same-clan players cannot damage each other. The "non.case" element-data
-- flag on either side opts out (can kill and be killed). Reserved for now.
-- Server is intentionally NOT involved.
addEventHandler("onClientPlayerDamage", localPlayer, function(attacker)
    if not isElement(attacker) or getElementType(attacker) ~= "player" then return end
    if attacker == localPlayer then return end -- self damage always applies
    if getElementData(localPlayer, "non.case") == true then return end
    if getElementData(attacker, "non.case") == true then return end
    local myClan = (myGroup and myGroup.name) or getElementData(localPlayer, "Clan")
    if type(myClan) ~= "string" or myClan == "" then return end
    local atkClan = getElementData(attacker, "Clan")
    if type(atkClan) == "string" and atkClan ~= "" and atkClan == myClan then
        cancelEvent()
    end
end)

-- Server listeners
addEvent("group:stateUpdate", true)
addEventHandler("group:stateUpdate", resourceRoot, function(groupOrFalse, errMsg)
    if groupOrFalse then
        inGroup = true
        myGroup = groupOrFalse
        currentTab = "home"
    else
        inGroup = false
        myGroup = nil
        if errMsg then setStatus(errMsg, 255, 120, 120) end
    end
end)

addEvent("group:createResult", true)
addEventHandler("group:createResult", resourceRoot, function(success, msg)
    if success then
        setStatus(msg, 80, 220, 130)
        groupNameInput = ""
        inputFocused = false
    else
        setStatus(msg, 255, 120, 120)
    end
end)

addEvent("group:membersList", true)
addEventHandler("group:membersList", resourceRoot, function(success, listOrMsg)    if success then
        membersListData = listOrMsg or {}
        local still = false
        for _, m in ipairs(membersListData) do
            if m.account == selectedMemberAccount then still = true break end
        end
        if not still then selectedMemberAccount = nil end
    else
        membersListData = {}
        setStatus(tostring(listOrMsg or "Failed to load members."), 255, 120, 120)
    end
end)

addEvent("group:groupsList", true)
addEventHandler("group:groupsList", resourceRoot, function(list)
    groupsListData = list or {}
end)

addEvent("group:kickResult", true)
addEventHandler("group:kickResult", resourceRoot, function(success, msg)
    if success then
        membersNotify(tostring(msg or "Kicked."), 90, 220, 140)
        selectedMemberAccount = nil
        -- list refreshes via pushed clanCache, no request needed
    else
        membersNotify(tostring(msg or "Kick failed."), 255, 120, 120)
    end
end)

addEvent("group:rankResult", true)
addEventHandler("group:rankResult", resourceRoot, function(success, msg)
    if success then
        membersNotify(tostring(msg or "Rank updated."), 90, 220, 140)
        -- list refreshes via pushed clanCache, no request needed
    else
        membersNotify(tostring(msg or "Rank change failed."), 255, 120, 120)
    end
end)

-- Pushed caches: panels render from memory instantly, no loading waits
addEvent("group:clanCache", true)
addEventHandler("group:clanCache", resourceRoot, function(snap)
    if snap then
        inGroup = true
        myGroup = {name = snap.name, rank = snap.rank, owner = snap.owner}
        clanCache = snap
        if snap.balance then bankBalance = tonumber(snap.balance) or 0 end
        membersListData = snap.members or {}
        local still = false
        for _, m in ipairs(membersListData) do
            if m.account == selectedMemberAccount then still = true break end
        end
        if not still then selectedMemberAccount = nil end
    else
        inGroup = false
        myGroup = nil
        clanCache = nil
        membersListData = {}
        selectedMemberAccount = nil
        bankBalance = nil
        bankMode = "main"
        if currentTab == "members" or currentTab == "bank" then
            currentTab = "home"
        end
    end
end)

addEvent("group:myInvitesCache", true)
addEventHandler("group:myInvitesCache", resourceRoot, function(list)
    invitesListData = list or {}
end)

addEvent("group:groupsCache", true)
addEventHandler("group:groupsCache", resourceRoot, function(list)
    groupsListData = list or {}
end)

-- Delta sync: one group row changed server-side. Patch the cached list in
-- place (add / update / remove) instead of waiting for a full resend.
-- groupsListData stays a plain array sorted by name, exactly as the full
-- snapshot produces it - the render code never knows the difference.
addEvent("group:groupDelta", true)
addEventHandler("group:groupDelta", resourceRoot, function(row)
    if type(row) ~= "table" or type(row.name) ~= "string" then return end
    local idx = nil
    for i, g in ipairs(groupsListData) do
        if g.name == row.name then idx = i break end
    end
    if row.remove then
        if idx then table.remove(groupsListData, idx) end
        return
    end
    if idx then
        groupsListData[idx].members = row.members
        groupsListData[idx].max = row.max
    else
        table.insert(groupsListData, {name = row.name, members = row.members, max = row.max})
        table.sort(groupsListData, function(a, b) return a.name < b.name end)
    end
end)

addEvent("group:leaveResult", true)
addEventHandler("group:leaveResult", resourceRoot, function(success, msg)
    if success then
        membersNotify(tostring(msg or "Left."), 90, 220, 140)
        currentTab = "home"
        triggerServerEvent("group:requestState", resourceRoot)
    else
        membersNotify(tostring(msg or "Leave failed."), 255, 120, 120)
    end
end)

addEvent("group:colorResult", true)
addEventHandler("group:colorResult", resourceRoot, function(success, msg)
    if success then
        membersNotify(tostring(msg or "Color updated."), 90, 220, 140)
        colorPickerOpen = false
        colFocus = nil
    else
        membersNotify(tostring(msg or "Color change failed."), 255, 120, 120)
    end
end)

addEvent("group:bankBalance", true)
addEventHandler("group:bankBalance", resourceRoot, function(success, balanceOrMsg)
    if success then
        bankBalance = tonumber(balanceOrMsg) or 0
    else
        bankNotify(tostring(balanceOrMsg or "Failed to load balance."), 255, 120, 120)
    end
end)

addEvent("group:depositResult", true)
addEventHandler("group:depositResult", resourceRoot, function(success, msg, newBalance)
    if success then
        if newBalance then bankBalance = tonumber(newBalance) or bankBalance end
        bankMode = "main"
        bankInput = ""
        bankInputFocused = false
        bankNotify(tostring(msg or "Deposited."), 90, 220, 140)
    else
        bankNotify(tostring(msg or "Deposit failed."), 255, 120, 120)
    end
end)

addEvent("group:withdrawResult", true)
addEventHandler("group:withdrawResult", resourceRoot, function(success, msg, newBalance)
    if success then
        if newBalance then bankBalance = tonumber(newBalance) or bankBalance end
        bankMode = "main"
        bankInput = ""
        bankInputFocused = false
        bankNotify(tostring(msg or "Withdrew."), 90, 220, 140)
    else
        bankNotify(tostring(msg or "Withdraw failed."), 255, 120, 120)
    end
end)

addEvent("group:disbandResult", true)
addEventHandler("group:disbandResult", resourceRoot, function(success, msg)
    if success then
        deleteConfirmOpen = false
        deleteInput = ""
        deleteInputFocused = false
        currentTab = "home"
        setStatus(tostring(msg or "Clan deleted."), 90, 220, 140)
    else
        setStatus(tostring(msg or "Delete failed."), 255, 120, 120)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindClanChatKey() -- always bound like chat's U; server filters outsiders
    triggerServerEvent("group:requestState", resourceRoot)
end)

-- Restore controls if resource stops while panel open
addEventHandler("onClientResourceStop", resourceRoot, function()
    showCursor(false)
    guiSetInputEnabled(false)
    showChat(true)
    toggleAllControls(true)
    unbindClanChatKey()
end)

-- Input handling (max 10, strict charset: A-Z a-z 0-9 []{}-_.:)
local GROUP_MAX_LEN = 10
local function isAllowedGroupChar(char)
    return char:match("^[A-Za-z0-9%[%]{}%-_%.:]$") ~= nil
end
-- UTF-8 safe helpers: byte-based #/sub splits multibyte chars (e.g. Arabic)
-- leaving invisible garbage that blocks typing and breaks rendering
local function utf8Len(s)
    local _, n = tostring(s):gsub("[^\128-\191]", "")
    return n
end
local function utf8RemoveLast(s)
    if s == "" then return "" end
    local i = #s
    while i > 1 do
        local b = s:byte(i)
        if b >= 128 and b < 192 then i = i - 1 else break end
    end
    return s:sub(1, i - 1)
end
addEventHandler("onClientCharacter", root, function(char)
    if not panelVisible or not inputFocused or inGroup then return end
    if not isAllowedGroupChar(char) then return end -- block anything else, don't print
    if #groupNameInput < GROUP_MAX_LEN then
        groupNameInput = groupNameInput .. char
    end
end)

-- RGB digits for color picker (numbers only, max 3 chars)
addEventHandler("onClientCharacter", root, function(char)
    if not panelVisible or not colorPickerOpen or currentTab ~= "members" then return end
    if not colFocus then return end
    if not char:match("^[0-9]$") then return end
    local cur = colFocus == "r" and colR or (colFocus == "g" and colG or colB)
    if #cur >= 3 then return end
    cur = cur .. char
    if colFocus == "r" then colR = cur
    elseif colFocus == "g" then colG = cur
    else colB = cur end
end)

-- Bank amount digits (numbers only, max 10 chars)
addEventHandler("onClientCharacter", root, function(char)
    if not panelVisible or currentTab ~= "bank" then return end
    if bankMode ~= "deposit" and bankMode ~= "withdraw" then return end
    if not bankInputFocused then return end
    if not char:match("^[0-9]$") then return end
    if #bankInput < 10 then
        bankInput = bankInput .. char
    end
end)

-- Delete-clan confirm input: free typing, no creation-style restrictions (exact match decides)
addEventHandler("onClientCharacter", root, function(char)
    if not panelVisible or not deleteConfirmOpen or not deleteInputFocused then return end
    if not inGroup or not myGroup or myGroup.rank ~= "owner" then return end
    if utf8Len(deleteInput) < 32 then
        deleteInput = deleteInput .. char
    end
end)

addEventHandler("onClientKey", root, function(key, down)
    if not panelVisible then return end
    if not down then return end
    if key == "backspace" and inputFocused and not inGroup then
        groupNameInput = groupNameInput:sub(1, #groupNameInput - 1)
        cancelEvent()
    elseif key == "backspace" and currentTab == "bank" and bankInputFocused
        and (bankMode == "deposit" or bankMode == "withdraw") then
        bankInput = bankInput:sub(1, #bankInput - 1)
        cancelEvent()
    elseif key == "backspace" and deleteConfirmOpen and deleteInputFocused then
        deleteInput = utf8RemoveLast(deleteInput)
        cancelEvent()
    elseif key == "backspace" and colorPickerOpen and currentTab == "members" and colFocus then
        if colFocus == "r" then colR = colR:sub(1, #colR - 1)
        elseif colFocus == "g" then colG = colG:sub(1, #colG - 1)
        else colB = colB:sub(1, #colB - 1) end
        cancelEvent()
    elseif key == "escape" and panelVisible then
        if deleteConfirmOpen then
            deleteConfirmOpen = false
            deleteInput = ""
            deleteInputFocused = false
        elseif colorPickerOpen then
            colorPickerOpen = false
            colFocus = nil
        elseif currentTab == "bank" and bankMode ~= "main" then
            bankMode = "main"
            bankInput = ""
            bankInputFocused = false
        else
            togglePanel(false)
        end
        cancelEvent()
    end
end)

addEventHandler("onClientClick", root, function(btn, state)
    if not panelVisible or btn ~= "left" or state ~= "down" then return end

    -- Close main panel
    if isMouseIn(rClose[1], rClose[2], rClose[3], rClose[4]) then
        togglePanel(false)
        return
    end

    -- Delete-clan confirm modal: exclusive while open (main X still works above)
    if deleteConfirmOpen then
        if rDeleteClose and isMouseIn(rDeleteClose[1], rDeleteClose[2], rDeleteClose[3], rDeleteClose[4]) then
            deleteConfirmOpen = false
            deleteInput = ""
            deleteInputFocused = false
            return
        end
        if deleteModalRects.input and isMouseIn(deleteModalRects.input[1], deleteModalRects.input[2], deleteModalRects.input[3], deleteModalRects.input[4]) then
            deleteInputFocused = true
            return
        end
        if deleteModalRects.delete and isMouseIn(deleteModalRects.delete[1], deleteModalRects.delete[2], deleteModalRects.delete[3], deleteModalRects.delete[4]) then
            if inGroup and myGroup and myGroup.rank == "owner" and deleteInput == tostring(myGroup.name) then
                triggerServerEvent("group:disband", resourceRoot)
                setStatus("Deleting clan...", 150, 180, 255)
            end
            return
        end
        if deleteModalRects.close and isMouseIn(deleteModalRects.close[1], deleteModalRects.close[2], deleteModalRects.close[3], deleteModalRects.close[4]) then
            deleteConfirmOpen = false
            deleteInput = ""
            deleteInputFocused = false
            return
        end
        return -- swallow other clicks while confirm open
    end

    -- X inside square members list: closes members only
    if currentTab == "members" and rMembersClose and isMouseIn(rMembersClose[1], rMembersClose[2], rMembersClose[3], rMembersClose[4]) then
        currentTab = "home"
        return
    end

    -- X inside square groups list: closes the list only (toggle stays)
    if currentTab == "list" and rListClose and isMouseIn(rListClose[1], rListClose[2], rListClose[3], rListClose[4]) then
        currentTab = "home"
        return
    end

    -- X inside square invites list: closes invites only
    if currentTab == "invites" and rInvitesClose and isMouseIn(rInvitesClose[1], rInvitesClose[2], rInvitesClose[3], rInvitesClose[4]) then
        currentTab = "home"
        return
    end

    -- Groups List: always enabled - toggle square list (data pushed, renders instantly)
    if isMouseIn(rBtnList[1], rBtnList[2], rBtnList[3], rBtnList[4]) then
        if currentTab == "list" then
            currentTab = "home"
        else
            currentTab = "list"
        end
        return
    end

    -- Invites: always enabled - toggle small square list on the left
    if isMouseIn(rBtnInvites[1], rBtnInvites[2], rBtnInvites[3], rBtnInvites[4]) then
        if currentTab == "invites" then
            currentTab = "home"
        else
            currentTab = "invites"
        end
        return
    end

    -- Color picker modal: only picker controls work while open (main X still works above)
    if currentTab == "members" and colorPickerOpen and colorPickerRects.r then
        local cr = colorPickerRects
        if rColorClose and isMouseIn(rColorClose[1], rColorClose[2], rColorClose[3], rColorClose[4]) then
            colorPickerOpen = false
            colFocus = nil
            return
        end
        if isMouseIn(cr.r[1], cr.r[2], cr.r[3], cr.r[4]) then colFocus = "r" return end
        if isMouseIn(cr.g[1], cr.g[2], cr.g[3], cr.g[4]) then colFocus = "g" return end
        if isMouseIn(cr.b[1], cr.b[2], cr.b[3], cr.b[4]) then colFocus = "b" return end
        if isMouseIn(cr.apply[1], cr.apply[2], cr.apply[3], cr.apply[4]) then applyColor() return end
        return -- swallow other clicks while picker open
    end

    -- Members popup: row selection (real + preview rows)
    -- click same row again = deselect, click away from rows/actions = deselect
    if currentTab == "members" and membersRowRects then
        for _, rr in ipairs(membersRowRects) do
            if isMouseIn(rr.x, rr.y, rr.w, rr.h) then
                if selectedMemberAccount == rr.account then
                    selectedMemberAccount = nil
                else
                    selectedMemberAccount = rr.account
                end
                return
            end
        end
        -- action buttons
        if memActRects.promote and isMouseIn(memActRects.promote[1], memActRects.promote[2], memActRects.promote[3], memActRects.promote[4]) then
            membersDoRank(true)
            return
        end
        if memActRects.demote and isMouseIn(memActRects.demote[1], memActRects.demote[2], memActRects.demote[3], memActRects.demote[4]) then
            membersDoRank(false)
            return
        end
        if memActRects.give and isMouseIn(memActRects.give[1], memActRects.give[2], memActRects.give[3], memActRects.give[4]) then
            membersNotify("Give money coming soon.", 150, 180, 255)
            return
        end
        if memActRects.kick and isMouseIn(memActRects.kick[1], memActRects.kick[2], memActRects.kick[3], memActRects.kick[4]) then
            membersDoKick()
            return
        end
        if memActRects.color and isMouseIn(memActRects.color[1], memActRects.color[2], memActRects.color[3], memActRects.color[4]) then
            if colorPickerOpen then
                colorPickerOpen = false
                colFocus = nil
            else
                colorPickerOpen = true
                colFocus = nil
                local cc = clanCache and clanCache.color
                colR = tostring(cc and tonumber(cc.r) or 255)
                colG = tostring(cc and tonumber(cc.g) or 255)
                colB = tostring(cc and tonumber(cc.b) or 255)
            end
            return
        end
        if memActRects.leave and isMouseIn(memActRects.leave[1], memActRects.leave[2], memActRects.leave[3], memActRects.leave[4]) then
            triggerServerEvent("group:leave", resourceRoot)
            membersNotify("Leaving group...", 150, 180, 255)
            return
        end
        -- clicked inside members context but missed rows and actions: clear selection
        -- (fall through so main tab buttons still work)
        selectedMemberAccount = nil
    end

    -- X inside bank popup: closes bank only
    if currentTab == "bank" and rBankClose and isMouseIn(rBankClose[1], rBankClose[2], rBankClose[3], rBankClose[4]) then
        currentTab = "home"
        bankMode = "main"
        return
    end

    -- Bank popup controls (fall through to main tab buttons on miss)
    if currentTab == "bank" and inGroup then
        if bankMode == "main" then
            if bankRects.deposit and isMouseIn(bankRects.deposit[1], bankRects.deposit[2], bankRects.deposit[3], bankRects.deposit[4]) then
                bankMode = "deposit"
                bankInput = ""
                bankInputFocused = true
                return
            end
            if bankRects.withdraw and isMouseIn(bankRects.withdraw[1], bankRects.withdraw[2], bankRects.withdraw[3], bankRects.withdraw[4]) then
                bankMode = "withdraw"
                bankInput = ""
                bankInputFocused = true
                return
            end
            if bankRects.settings and isMouseIn(bankRects.settings[1], bankRects.settings[2], bankRects.settings[3], bankRects.settings[4]) then
                bankNotify("Settings coming soon.", 150, 180, 255)
                return
            end
        else
            if bankRects.input and isMouseIn(bankRects.input[1], bankRects.input[2], bankRects.input[3], bankRects.input[4]) then
                bankInputFocused = true
                return
            end
            if bankRects.confirm and isMouseIn(bankRects.confirm[1], bankRects.confirm[2], bankRects.confirm[3], bankRects.confirm[4]) then
                doBankConfirm()
                return
            end
            if bankRects.back and isMouseIn(bankRects.back[1], bankRects.back[2], bankRects.back[3], bankRects.back[4]) then
                bankMode = "main"
                bankInput = ""
                bankInputFocused = false
                return
            end
        end
        bankInputFocused = false
    end

    if not inGroup then
        -- Input focus
        if isMouseIn(rInput[1], rInput[2], rInput[3], rInput[4]) then
            inputFocused = true
            return
        else
            inputFocused = false
        end
        -- Create (real server creation)
        if isMouseIn(rCreate[1], rCreate[2], rCreate[3], rCreate[4]) then
            local name = groupNameInput:gsub("^%s+", ""):gsub("%s+$", "")
            if #name < 3 or #name > 10 then
                setStatus("Enter a group name (3-10 characters).", 255, 200, 100)
                return
            end
            triggerServerEvent("group:create", resourceRoot, name)
            groupNameInput = ""
            inputFocused = false
            setStatus("Creating group...", 150, 180, 255)
            return
        end
        -- Disabled buttons: swallow clicks (invites stays enabled, handled above)
        if isMouseIn(rBtnMembers[1], rBtnMembers[2], rBtnMembers[3], rBtnMembers[4])
        or isMouseIn(rBtnBank[1], rBtnBank[2], rBtnBank[3], rBtnBank[4]) then
            setStatus("Create a group first to unlock this.", 255, 200, 100)
            return
        end
    else
        inputFocused = false
        -- DELETE CLAN (owner only, top slot where Create sits): opens confirm modal
        if myGroup and myGroup.rank == "owner" and rDelete and isMouseIn(rDelete[1], rDelete[2], rDelete[3], rDelete[4]) then
            deleteConfirmOpen = true
            deleteInput = ""
            deleteInputFocused = true
            return
        end
        -- MEMBERS: toggle left popup (data pushed, renders instantly)
        if isMouseIn(rBtnMembers[1], rBtnMembers[2], rBtnMembers[3], rBtnMembers[4]) then
            if currentTab == "members" then
                currentTab = "home"
            else
                currentTab = "members"
            end
            return
        elseif isMouseIn(rBtnBank[1], rBtnBank[2], rBtnBank[3], rBtnBank[4]) then
            currentTab = "bank"
            bankMode = "main"
            bankInput = ""
            bankInputFocused = false
            bankBalance = nil
            triggerServerEvent("group:bankBalance", resourceRoot)
            return
        end
    end
end)

-- ================= DRAW =================
-- One button per row: title left, desc left-below, status badge right. No overlapping.
local function drawRoundedButton(x, y, w, h, label, sub, enabled, hover, accent)
    local bg = enabled and (hover and tocolor(38, 43, 56, 255) or tocolor(30, 35, 46, 255))
        or tocolor(24, 26, 33, 220)
    dxDrawRectangle(x, y, w, h, bg)
    if enabled and accent then
        dxDrawRectangle(x, y, 3 * S, h, tocolor(0, 128, 255, 255))
    end
    -- title (top-left, clipped)
    local tc = enabled and tocolor(235, 238, 245, 255) or tocolor(110, 118, 135, 255)
    dxDrawText(label, x + 16 * S, y + 8 * S, x + w - 90 * S, y + 28 * S, tc, 1.0 * S, "default-bold", "left", "top", true)
    -- desc (below title, clipped, single line)
    if sub then
        dxDrawText(sub, x + 16 * S, y + 30 * S, x + w - 90 * S, y + 50 * S, tocolor(120, 130, 150, 255), 1.0 * S, "default", "left", "top", true)
    end
    -- right badge (no overlap with left text: reserved 90px)
    if enabled then
        dxDrawText(">", x + w - 34 * S, y, x + w - 14 * S, y + h, tocolor(130, 140, 160, 255), 1.2 * S, "default-bold", "center", "center")
    else
        local bx, bw2 = x + w - 78 * S, 64 * S
        dxDrawRectangle(bx, y + (h - 22 * S) / 2, bw2, 22 * S, tocolor(45, 52, 66, 255))
        dxDrawText("LOCKED", bx, y + (h - 22 * S) / 2, bx + bw2, y + (h - 22 * S) / 2 + 22 * S, tocolor(120, 128, 145, 255), 0.85 * S, "default-bold", "center", "center")
    end
end

-- Small action button for members popup bottom bar
local function drawSmallBtn(x, y, w, h, label)
    local hover = isMouseIn(x, y, w, h)
    dxDrawRectangle(x, y, w, h, hover and tocolor(38, 43, 56, 255) or tocolor(30, 35, 46, 255))
    dxDrawRectangle(x, y + h - 2 * S, w, 2 * S, tocolor(0, 128, 255, 255))
    dxDrawText(label, x + 4 * S, y, x + w - 4 * S, y + h, tocolor(235, 238, 245, 255), 0.9 * S, "default-bold", "center", "center", true)
end

-- Bank popup row: title + sub with left accent
local function drawBankRow(r, title, sub)
    local hov = isMouseIn(r[1], r[2], r[3], r[4])
    dxDrawRectangle(r[1], r[2], r[3], r[4], hov and tocolor(38, 43, 56, 255) or tocolor(30, 35, 46, 255))
    dxDrawRectangle(r[1], r[2], 3 * S, r[4], tocolor(0, 128, 255, 255))
    dxDrawText(title, r[1] + 14 * S, r[2] + 5 * S, r[1] + r[3] - 14 * S, r[2] + 24 * S, tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "top", true)
    dxDrawText(sub, r[1] + 14 * S, r[2] + 24 * S, r[1] + r[3] - 14 * S, r[2] + r[4] - 4 * S, tocolor(120, 130, 150, 255), 0.9 * S, "default", "left", "top", true)
end

-- Bank popup on the RIGHT (own function: keeps main render under Lua's 60-upvalue limit)
local function drawBankPopup()
    if currentTab == "bank" and inGroup then
        local BW, BH = 340 * S, 330 * S
        local BX = PX + PW + 10 * S
        if BX + BW > sw - 10 then
            BX = PX - BW - 10 * S
            if BX < 10 then BX = (sw - BW) / 2 end
        end
        local BY = PY + 80 * S
        rBankClose = {BX + BW - 40 * S, BY + 8 * S, 28 * S, 28 * S}
        dxDrawRectangle(BX, BY, BW, BH, tocolor(15, 17, 23, 250))
        dxDrawRectangle(BX, BY, BW, 44 * S, tocolor(21, 24, 32, 255))
        dxDrawRectangle(BX, BY + 44 * S, BW, 2 * S, tocolor(0, 128, 255, 255))
        dxDrawText("الميزانيه", BX + 14 * S, BY, BX + BW - 54 * S, BY + 44 * S, tocolor(255, 255, 255, 255), 1.1 * S, "default-bold", "left", "center", true)
        local bhx = isMouseIn(rBankClose[1], rBankClose[2], rBankClose[3], rBankClose[4])
        dxDrawRectangle(rBankClose[1], rBankClose[2], rBankClose[3], rBankClose[4], bhx and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
        dxDrawText("X", rBankClose[1], rBankClose[2], rBankClose[1] + rBankClose[3], rBankClose[2] + rBankClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")
        -- balance box
        local balY, balH = BY + 54 * S, 50 * S
        dxDrawRectangle(BX + 10 * S, balY, BW - 20 * S, balH, tocolor(28, 32, 42, 255))
        dxDrawRectangle(BX + 10 * S, balY, 3 * S, balH, tocolor(0, 200, 120, 255))
        local bal = bankBalance
        if bal == nil and clanCache and clanCache.balance then bal = tonumber(clanCache.balance) end
        local balTxt = (bal == nil) and "Loading..." or (tostring(bal) .. " $")
        dxDrawText("رصيد الكلان", BX + 22 * S, balY + 5 * S, BX + BW - 14 * S, balY + 24 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
        dxDrawText(balTxt, BX + 22 * S, balY + 22 * S, BX + BW - 14 * S, balY + balH - 4 * S, tocolor(120, 230, 160, 255), 1.1 * S, "default-bold", "left", "top", true)
        bankRects = {}
        local noteH = 22 * S
        local noteY = BY + BH - 12 * S - noteH
        if bankMode == "main" then
            local bY, bH = balY + balH + 10 * S, 46 * S
            bankRects.deposit = {BX + 10 * S, bY, BW - 20 * S, bH}
            bankRects.withdraw = {BX + 10 * S, bY + bH + 8 * S, BW - 20 * S, bH}
            bankRects.settings = {BX + 10 * S, bY + (bH + 8 * S) * 2, BW - 20 * S, bH}
            drawBankRow(bankRects.deposit, "ايداع", "إضافة فلوس لرصيد الكلان")
            drawBankRow(bankRects.withdraw, "سحب", "Owner فقط")
            drawBankRow(bankRects.settings, "اعدادات", "قريباً")
        else
            local labY = balY + balH + 10 * S
            dxDrawText(bankMode == "deposit" and "مبلغ الإيداع:" or "مبلغ السحب:", BX + 14 * S, labY, BX + BW - 14 * S, labY + 20 * S,
                tocolor(150, 160, 180, 255), 1.0 * S, "default-bold", "left", "top", true)
            local inY, inH = labY + 22 * S, 42 * S
            bankRects.input = {BX + 10 * S, inY, BW - 20 * S, inH}
            local dfoc = bankInputFocused
            dxDrawRectangle(BX + 10 * S, inY, BW - 20 * S, inH, tocolor(28, 32, 42, 255))
            dxDrawRectangle(BX + 10 * S, inY + inH - 2 * S, BW - 20 * S, 2 * S,
                dfoc and tocolor(0, 128, 255, 255) or tocolor(55, 62, 80, 255))
            if bankInput == "" then
                dxDrawText("0", BX + 22 * S, inY, BX + BW - 22 * S, inY + inH,
                    tocolor(100, 108, 125, 255), 1.0 * S, "default", "left", "center", true)
            else
                local caret = dfoc and ((getTickCount() % 1000 < 500) and "|" or "") or ""
                dxDrawText(bankInput .. caret, BX + 22 * S, inY, BX + BW - 22 * S, inY + inH,
                    tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "center", true)
            end
            local cY, cH = inY + inH + 8 * S, 42 * S
            local cW = (BW - 20 * S - 8 * S) / 2
            bankRects.confirm = {BX + 10 * S, cY, cW, cH}
            bankRects.back = {BX + 10 * S + cW + 8 * S, cY, cW, cH}
            local chov = isMouseIn(bankRects.confirm[1], cY, cW, cH)
            dxDrawRectangle(bankRects.confirm[1], cY, cW, cH, chov and tocolor(40, 150, 255, 255) or tocolor(0, 128, 255, 255))
            dxDrawText("تأكيد", bankRects.confirm[1], cY, bankRects.confirm[1] + cW, cY + cH,
                tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center", true)
            local khov = isMouseIn(bankRects.back[1], cY, cW, cH)
            dxDrawRectangle(bankRects.back[1], cY, cW, cH, khov and tocolor(38, 43, 56, 255) or tocolor(30, 35, 46, 255))
            dxDrawText("رجوع", bankRects.back[1], cY, bankRects.back[1] + cW, cY + cH,
                tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "center", "center", true)
        end
        if bankNotifyMsg ~= "" and getTickCount() < bankNotifyUntil then
            dxDrawText(bankNotifyMsg, BX + 14 * S, noteY, BX + BW - 14 * S, noteY + noteH,
                tocolor(bankNotifyColor[1], bankNotifyColor[2], bankNotifyColor[3], 255), 0.9 * S, "default-bold", "left", "center", true)
        else
            dxDrawText(bankMode == "main" and "اختر عملية." or "اكتب المبلغ ثم تأكيد.", BX + 14 * S, noteY, BX + BW - 14 * S, noteY + noteH,
                tocolor(90, 95, 110, 255), 0.9 * S, "default", "left", "center", true)
        end
    else
        rBankClose = nil
        bankRects = {}
    end
end

addEventHandler("onClientRender", root, function()
    if not panelVisible then return end

    -- dim background
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 110))

    -- main panel
    dxDrawRectangle(PX, PY, PW, PH, tocolor(15, 17, 23, 250))
    -- top header bar
    dxDrawRectangle(PX, PY, PW, 62 * S, tocolor(21, 24, 32, 255))
    dxDrawRectangle(PX, PY + 62 * S, PW, 2 * S, tocolor(0, 128, 255, 255))

    -- title: BY ECMA above, then GROUP SYSTEM, then subtitle (separate bands, no overlap)
    dxDrawText("BY ECMA", PX + 24 * S, PY + 4 * S, PX + PW - 70 * S, PY + 16 * S, tocolor(0, 128, 255, 255), 0.85 * S, "default-bold", "left", "top", true)
    dxDrawText("GROUP SYSTEM", PX + 24 * S, PY + 15 * S, PX + PW - 70 * S, PY + 37 * S, tocolor(255, 255, 255, 255), 1.2 * S, "default-bold", "left", "top", true)
    local subHeader = "Create your crew"
    if inGroup and myGroup then
        subHeader = tostring(myGroup.name) .. " | " .. formatRank(myGroup.rank)
    end
    dxDrawText(subHeader, PX + 24 * S, PY + 38 * S, PX + PW - 70 * S, PY + 56 * S, tocolor(130, 140, 160, 255), 1.0 * S, "default", "left", "top", true)

    -- close
    local ch = isMouseIn(rClose[1], rClose[2], rClose[3], rClose[4])
    dxDrawRectangle(rClose[1], rClose[2], rClose[3], rClose[4], ch and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
    dxDrawText("X", rClose[1], rClose[2], rClose[1] + rClose[3], rClose[2] + rClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")

    if not inGroup then
        -- CREATE SECTION (single row, no overlap)
        dxDrawText("GROUP NAME", rInput[1], rInput[2] - 24 * S, rInput[1] + 200 * S, rInput[2] - 6 * S, tocolor(150, 160, 180, 255), 1.0 * S, "default-bold", "left", "center", true)

        local ifocus = inputFocused
        dxDrawRectangle(rInput[1], rInput[2], rInput[3], rInput[4], tocolor(28, 32, 42, 255))
        dxDrawRectangle(rInput[1], rInput[2] + rInput[4] - 2 * S, rInput[3], 2 * S,
            ifocus and tocolor(0, 128, 255, 255) or tocolor(55, 62, 80, 255))

        local display = groupNameInput
        if display == "" then
            dxDrawText("e.g. ECMA", rInput[1] + 12 * S, rInput[2], rInput[1] + rInput[3] - 12 * S, rInput[2] + rInput[4],
                tocolor(100, 108, 125, 255), 1.0 * S, "default", "left", "center", true)
        else
            local caret = ifocus and ((getTickCount() % 1000 < 500) and "|" or "") or ""
            dxDrawText(display .. caret, rInput[1] + 12 * S, rInput[2], rInput[1] + rInput[3] - 12 * S, rInput[2] + rInput[4],
                tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "center", true)
        end

        -- Create button
        local cHover = isMouseIn(rCreate[1], rCreate[2], rCreate[3], rCreate[4])
        local _trimmed = groupNameInput:gsub("^%s+", ""):gsub("%s+$", "")
        local canCreate = #_trimmed >= 3 and #_trimmed <= 10
        local cBg = canCreate and (cHover and tocolor(40, 150, 255, 255) or tocolor(0, 128, 255, 255))
            or tocolor(45, 52, 66, 255)
        dxDrawRectangle(rCreate[1], rCreate[2], rCreate[3], rCreate[4], cBg)
        -- Word on top, price inside the same button below it (no overlap)
        dxDrawText("CREATE", rCreate[1], rCreate[2] + 5 * S, rCreate[1] + rCreate[3], rCreate[2] + 23 * S,
            canCreate and tocolor(255, 255, 255, 255) or tocolor(120, 128, 145, 255), 1.0 * S, "default-bold", "center", "top", true)
        dxDrawText("2500000 $", rCreate[1], rCreate[2] + 22 * S, rCreate[1] + rCreate[3], rCreate[2] + rCreate[4] - 3 * S,
            canCreate and tocolor(255, 255, 255, 220) or tocolor(100, 106, 120, 255), 0.9 * S, "default", "center", "top", true)
    else
        -- IN GROUP HEADER (two separate lines)
        local isOwner = myGroup and myGroup.rank == "owner"
        local txtRight = (isOwner and rDelete) and (rDelete[1] - 8 * S) or (PX + PW - 30 * S)
        dxDrawRectangle(PX + 24 * S, PY + 84 * S, PW - 48 * S, 64 * S, tocolor(28, 32, 42, 255))
        dxDrawRectangle(PX + 24 * S, PY + 84 * S, 3 * S, 64 * S, tocolor(0, 128, 255, 255))
        dxDrawText("You are in: " .. tostring(myGroup.name), PX + 38 * S, PY + 90 * S, txtRight, PY + 112 * S,
            tocolor(255, 255, 255, 255), 1.1 * S, "default-bold", "left", "top", true)
        dxDrawText("Rank: " .. formatRank(myGroup.rank), PX + 38 * S, PY + 114 * S, txtRight, PY + 134 * S,
            tocolor(130, 140, 160, 255), 1.0 * S, "default", "left", "top", true)
        -- DELETE CLAN (owner only, small button inside header on the right)
        if isOwner and rDelete then
            local dHov = isMouseIn(rDelete[1], rDelete[2], rDelete[3], rDelete[4])
            dxDrawRectangle(rDelete[1], rDelete[2], rDelete[3], rDelete[4],
                dHov and tocolor(150, 50, 50, 255) or tocolor(110, 35, 35, 255))
            dxDrawRectangle(rDelete[1], rDelete[2] + rDelete[4] - 2 * S, rDelete[3], 2 * S, tocolor(220, 70, 70, 255))
            dxDrawText("DELETE CLAN", rDelete[1], rDelete[2], rDelete[1] + rDelete[3], rDelete[2] + rDelete[4],
                tocolor(255, 210, 210, 255), 0.9 * S, "default-bold", "center", "center", true)
        end
    end

    -- TAB BUTTONS: vertical stack, one per row (invites always enabled for receiving)
    local enabled = inGroup
    drawRoundedButton(rBtnMembers[1], rBtnMembers[2], rBtnMembers[3], rBtnMembers[4],
        "MEMBERS", "Manage crew", enabled, isMouseIn(rBtnMembers[1], rBtnMembers[2], rBtnMembers[3], rBtnMembers[4]), currentTab == "members" and enabled)
    drawRoundedButton(rBtnInvites[1], rBtnInvites[2], rBtnInvites[3], rBtnInvites[4],
        "INVITES", "Send / accept", true, isMouseIn(rBtnInvites[1], rBtnInvites[2], rBtnInvites[3], rBtnInvites[4]), currentTab == "invites")
    drawRoundedButton(rBtnBank[1], rBtnBank[2], rBtnBank[3], rBtnBank[4],
        "BANK", "Money & logs", enabled, isMouseIn(rBtnBank[1], rBtnBank[2], rBtnBank[3], rBtnBank[4]), currentTab == "bank" and enabled)

    -- Thin separator line below Bank, then Groups List button (old content box removed)
    dxDrawRectangle(PX + 24 * S, rSepY, PW - 48 * S, 2 * S, tocolor(55, 62, 80, 255))
    drawRoundedButton(rBtnList[1], rBtnList[2], rBtnList[3], rBtnList[4],
        "GROUPS LIST", "Browse all groups", true, isMouseIn(rBtnList[1], rBtnList[2], rBtnList[3], rBtnList[4]), currentTab == "list")

    -- Square groups list popup (name left, members/max right)
    if currentTab == "list" then
        local LW, LH = 300 * S, 340 * S
        local LX = PX + PW + 10 * S
        if LX + LW > sw - 10 then
            LX = PX - LW - 10 * S
            if LX < 10 then LX = (sw - LW) / 2 end
        end
        local LY = PY + 60 * S
        rListClose = {LX + LW - 40 * S, LY + 8 * S, 28 * S, 28 * S}
        dxDrawRectangle(LX, LY, LW, LH, tocolor(15, 17, 23, 250))
        dxDrawRectangle(LX, LY, LW, 44 * S, tocolor(21, 24, 32, 255))
        dxDrawRectangle(LX, LY + 44 * S, LW, 2 * S, tocolor(0, 128, 255, 255))
        dxDrawText("GROUPS", LX + 14 * S, LY, LX + LW - 54 * S, LY + 44 * S, tocolor(255, 255, 255, 255), 1.1 * S, "default-bold", "left", "center", true)
        -- X closes list only
        local lh = isMouseIn(rListClose[1], rListClose[2], rListClose[3], rListClose[4])
        dxDrawRectangle(rListClose[1], rListClose[2], rListClose[3], rListClose[4], lh and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
        dxDrawText("X", rListClose[1], rListClose[2], rListClose[1] + rListClose[3], rListClose[2] + rListClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")

        local rowY = LY + 54 * S
        local rowH = 34 * S
        for i, g in ipairs(groupsListData) do
            if rowY + rowH > LY + LH - 8 * S then break end
            dxDrawRectangle(LX + 10 * S, rowY, LW - 20 * S, rowH, tocolor(28, 32, 42, 255))
            -- name left (clipped, max 10 chars already)
            dxDrawText(tostring(g.name), LX + 20 * S, rowY, LX + LW - 80 * S, rowY + rowH, tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "center", true)
            -- count right: members / max
            local cnt = tonumber(g.members) or 0
            local full = cnt >= GROUP_MAX_MEMBERS
            dxDrawText(cnt .. "/" .. GROUP_MAX_MEMBERS, LX + LW - 70 * S, rowY, LX + LW - 14 * S, rowY + rowH,
                full and tocolor(255, 120, 120, 255) or tocolor(130, 200, 150, 255), 1.0 * S, "default-bold", "right", "center", true)
            rowY = rowY + rowH + 6 * S
        end
        if #groupsListData == 0 then
            dxDrawText("No groups yet.", LX + 14 * S, LY + 60 * S, LX + LW - 14 * S, LY + LH - 10 * S, tocolor(120, 130, 150, 255), 1.0 * S, "default-bold", "center", "center", true)
        end
    else
        rListClose = nil
    end

    -- Small square invites popup on the LEFT (table: CLAN | FROM | MEMBERS)
    if currentTab == "invites" then
        local IW, IH = 360 * S, 260 * S
        local IX = PX - IW - 10 * S
        if IX < 10 then
            IX = PX + PW + 10 * S
            if IX + IW > sw - 10 then IX = (sw - IW) / 2 end
        end
        local IY = PY + 80 * S
        rInvitesClose = {IX + IW - 40 * S, IY + 8 * S, 28 * S, 28 * S}
        dxDrawRectangle(IX, IY, IW, IH, tocolor(15, 17, 23, 250))
        dxDrawRectangle(IX, IY, IW, 44 * S, tocolor(21, 24, 32, 255))
        dxDrawRectangle(IX, IY + 44 * S, IW, 2 * S, tocolor(0, 128, 255, 255))
        dxDrawText("INVITES", IX + 14 * S, IY, IX + IW - 54 * S, IY + 44 * S, tocolor(255, 255, 255, 255), 1.1 * S, "default-bold", "left", "center", true)
        local ih = isMouseIn(rInvitesClose[1], rInvitesClose[2], rInvitesClose[3], rInvitesClose[4])
        dxDrawRectangle(rInvitesClose[1], rInvitesClose[2], rInvitesClose[3], rInvitesClose[4], ih and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
        dxDrawText("X", rInvitesClose[1], rInvitesClose[2], rInvitesClose[1] + rInvitesClose[3], rInvitesClose[2] + rInvitesClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")

        -- Table header (separate bands, no overlap)
        local hY = IY + 52 * S
        dxDrawText("CLAN", IX + 20 * S, hY, IX + 140 * S, hY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
        dxDrawText("FROM", IX + 145 * S, hY, IX + 255 * S, hY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
        dxDrawText("MEMBERS", IX + 260 * S, hY, IX + IW - 14 * S, hY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "right", "top", true)

        local iRowY = hY + 22 * S
        local iRowH = 34 * S
        for _, inv in ipairs(invitesListData) do
            if iRowY + iRowH > IY + IH - 8 * S then break end
            dxDrawRectangle(IX + 10 * S, iRowY, IW - 20 * S, iRowH, tocolor(28, 32, 42, 255))
            -- col 1: clan name (clipped)
            dxDrawText(tostring(inv.name), IX + 20 * S, iRowY, IX + 140 * S, iRowY + iRowH, tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "center", true)
            -- col 2: inviter (clipped)
            dxDrawText(tostring(inv.from or "-"), IX + 145 * S, iRowY, IX + 255 * S, iRowY + iRowH, tocolor(180, 190, 205, 255), 1.0 * S, "default", "left", "center", true)
            -- col 3: count/max right
            local cnt = tonumber(inv.members) or 0
            dxDrawText(cnt .. "/" .. GROUP_MAX_MEMBERS, IX + 260 * S, iRowY, IX + IW - 14 * S, iRowY + iRowH,
                tocolor(130, 200, 150, 255), 1.0 * S, "default-bold", "right", "center", true)
            iRowY = iRowY + iRowH + 6 * S
        end
        if #invitesListData == 0 then
            dxDrawText("No invites yet.", IX + 14 * S, IY + 80 * S, IX + IW - 14 * S, IY + IH - 10 * S, tocolor(120, 130, 150, 255), 1.0 * S, "default-bold", "center", "center", true)
        end
    else
        rInvitesClose = nil
    end

    -- Bank popup on the RIGHT (own function: keeps main render under 60-upvalue limit)
    drawBankPopup()

    -- Members popup on the LEFT (seniority order: oldest first)
    -- Table: NAME | RANK | LAST SEEN | STATUS - online green, offline red
    if currentTab == "members" then
        local MW, MH = 560 * S, 500 * S
        local MX = PX - MW - 10 * S
        if MX < 10 then
            MX = PX + PW + 10 * S
            if MX + MW > sw - 10 then MX = (sw - MW) / 2 end
        end
        local MY = PY + 40 * S
        rMembersClose = {MX + MW - 40 * S, MY + 8 * S, 28 * S, 28 * S}
        dxDrawRectangle(MX, MY, MW, MH, tocolor(15, 17, 23, 250))
        dxDrawRectangle(MX, MY, MW, 44 * S, tocolor(21, 24, 32, 255))
        dxDrawRectangle(MX, MY + 44 * S, MW, 2 * S, tocolor(0, 128, 255, 255))
        dxDrawText("MEMBERS", MX + 14 * S, MY, MX + MW - 54 * S, MY + 44 * S, tocolor(255, 255, 255, 255), 1.1 * S, "default-bold", "left", "center", true)
        local mh = isMouseIn(rMembersClose[1], rMembersClose[2], rMembersClose[3], rMembersClose[4])
        dxDrawRectangle(rMembersClose[1], rMembersClose[2], rMembersClose[3], rMembersClose[4], mh and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
        dxDrawText("X", rMembersClose[1], rMembersClose[2], rMembersClose[1] + rMembersClose[3], rMembersClose[2] + rMembersClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")

        -- Table header (separate bands, no overlap)
        local tY = MY + 52 * S
        dxDrawText("NAME", MX + 20 * S, tY, MX + 170 * S, tY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
        dxDrawText("RANK", MX + 175 * S, tY, MX + 275 * S, tY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
        dxDrawText("LAST SEEN", MX + 280 * S, tY, MX + 390 * S, tY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
        dxDrawText("STATUS", MX + 395 * S, tY, MX + MW - 14 * S, tY + 18 * S, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "right", "top", true)

        local mRowY = tY + 22 * S
        local mRowH = 32 * S
        -- bottom bar: 5 action buttons + LEAVE row + notify line
        local actH, noteH = 36 * S, 22 * S
        local noteY = MY + MH - 12 * S - noteH
        local leaveY = noteY - 8 * S - actH
        local actY = leaveY - 8 * S - actH
        local rowsBottom = actY - 8 * S
        membersRowRects = {}
        if membersListData == nil then
            dxDrawText("Loading...", MX + 14 * S, mRowY, MX + MW - 14 * S, rowsBottom, tocolor(120, 130, 150, 255), 1.0 * S, "default-bold", "center", "center", true)
        else
            if #membersListData == 0 then
                dxDrawText("No members.", MX + 14 * S, mRowY, MX + MW - 14 * S, rowsBottom, tocolor(120, 130, 150, 255), 1.0 * S, "default-bold", "center", "center", true)
            end
            for _, mem in ipairs(membersListData) do
                if mRowY + mRowH > rowsBottom then break end
                local on = mem.online and true or false
                dxDrawRectangle(MX + 10 * S, mRowY, MW - 20 * S, mRowH,
                    on and tocolor(24, 68, 44, 255) or tocolor(68, 30, 30, 255))
                -- selected row highlight
                if mem.account and mem.account == selectedMemberAccount then
                    dxDrawRectangle(MX + 10 * S, mRowY, MW - 20 * S, 2 * S, tocolor(0, 128, 255, 255))
                    dxDrawRectangle(MX + 10 * S, mRowY + mRowH - 2 * S, MW - 20 * S, 2 * S, tocolor(0, 128, 255, 255))
                    dxDrawRectangle(MX + 10 * S, mRowY, 2 * S, mRowH, tocolor(0, 128, 255, 255))
                    dxDrawRectangle(MX + MW - 12 * S, mRowY, 2 * S, mRowH, tocolor(0, 128, 255, 255))
                end
                table.insert(membersRowRects, {account = mem.account, x = MX + 10 * S, y = mRowY, w = MW - 20 * S, h = mRowH})
                dxDrawText(tostring(mem.name), MX + 20 * S, mRowY, MX + 170 * S, mRowY + mRowH, tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "center", true)
                dxDrawText(formatRank(mem.rank), MX + 175 * S, mRowY, MX + 275 * S, mRowY + mRowH, tocolor(180, 190, 205, 255), 1.0 * S, "default", "left", "center", true)
                dxDrawText(formatSeen(mem.seen, on), MX + 280 * S, mRowY, MX + 390 * S, mRowY + mRowH, tocolor(150, 160, 180, 255), 1.0 * S, "default", "left", "center", true)
                dxDrawText(on and "Online" or "Offline", MX + 395 * S, mRowY, MX + MW - 14 * S, mRowY + mRowH,
                    on and tocolor(90, 220, 140, 255) or tocolor(255, 120, 120, 255), 1.0 * S, "default-bold", "right", "center", true)
                mRowY = mRowY + mRowH + 6 * S
            end
        end
        -- 5 action buttons: PROMOTE | DEMOTE | GIVE MONEY | KICK | TURF COLOR
        local abw = (MW - 20 * S - 8 * S * 4) / 5
        local abx = MX + 10 * S
        memActRects = {
            promote = {abx, actY, abw, actH},
            demote = {abx + (abw + 8 * S), actY, abw, actH},
            give = {abx + (abw + 8 * S) * 2, actY, abw, actH},
            kick = {abx + (abw + 8 * S) * 3, actY, abw, actH},
            color = {abx + (abw + 8 * S) * 4, actY, abw, actH},
        }
        drawSmallBtn(memActRects.promote[1], memActRects.promote[2], abw, actH, "PROMOTE")
        drawSmallBtn(memActRects.demote[1], memActRects.demote[2], abw, actH, "DEMOTE")
        drawSmallBtn(memActRects.give[1], memActRects.give[2], abw, actH, "GIVE MONEY")
        drawSmallBtn(memActRects.kick[1], memActRects.kick[2], abw, actH, "KICK")
        drawSmallBtn(memActRects.color[1], memActRects.color[2], abw, actH, "TURF COLOR")
        -- LEAVE GROUP row (acts on yourself, no selection needed)
        memActRects.leave = {abx, leaveY, MW - 20 * S, actH}
        local lvHov = isMouseIn(abx, leaveY, MW - 20 * S, actH)
        dxDrawRectangle(abx, leaveY, MW - 20 * S, actH, lvHov and tocolor(90, 40, 40, 255) or tocolor(66, 30, 30, 255))
        dxDrawRectangle(abx, leaveY + actH - 2 * S, MW - 20 * S, 2 * S, tocolor(220, 70, 70, 255))
        dxDrawText("LEAVE GROUP", abx + 4 * S, leaveY, abx + MW - 20 * S - 4 * S, leaveY + actH, tocolor(255, 200, 200, 255), 0.9 * S, "default-bold", "center", "center", true)
        -- notify line
        if membersNotifyMsg ~= "" and getTickCount() < membersNotifyUntil then
            dxDrawText(membersNotifyMsg, MX + 14 * S, noteY, MX + MW - 14 * S, noteY + noteH,
                tocolor(membersNotifyColor[1], membersNotifyColor[2], membersNotifyColor[3], 255), 0.9 * S, "default-bold", "left", "center", true)
        else
            dxDrawText("Select a member, then choose an action.", MX + 14 * S, noteY, MX + MW - 14 * S, noteY + noteH,
                tocolor(90, 95, 110, 255), 0.9 * S, "default", "left", "center", true)
        end
        -- Turf color picker above members popup: RGB inputs + live preview square
        if colorPickerOpen then
            local CW, CH = 560 * S, 140 * S
            local CX = MX
            local CY = MY - CH - 10 * S
            if CY < 10 then
                CY = MY + MH + 10 * S
                if CY + CH > sh - 10 then CY = (sh - CH) / 2 end
            end
            rColorClose = {CX + CW - 40 * S, CY + 8 * S, 28 * S, 28 * S}
            dxDrawRectangle(CX, CY, CW, CH, tocolor(15, 17, 23, 250))
            dxDrawRectangle(CX, CY, CW, 44 * S, tocolor(21, 24, 32, 255))
            dxDrawRectangle(CX, CY + 44 * S, CW, 2 * S, tocolor(0, 128, 255, 255))
            dxDrawText("TURF COLOR", CX + 14 * S, CY, CX + CW - 54 * S, CY + 44 * S, tocolor(255, 255, 255, 255), 1.1 * S, "default-bold", "left", "center", true)
            local cch = isMouseIn(rColorClose[1], rColorClose[2], rColorClose[3], rColorClose[4])
            dxDrawRectangle(rColorClose[1], rColorClose[2], rColorClose[3], rColorClose[4], cch and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
            dxDrawText("X", rColorClose[1], rColorClose[2], rColorClose[1] + rColorClose[3], rColorClose[2] + rColorClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")
            -- R/G/B boxes + preview square + APPLY in one row
            local boxW = 90 * S
            local rowCY = CY + 44 * S + 14 * S + 16 * S
            local boxH = 44 * S
            local bx0 = CX + 10 * S
            local bxx = {bx0, bx0 + (boxW + 10 * S), bx0 + (boxW + 10 * S) * 2}
            colorPickerRects = {
                r = {bxx[1], rowCY, boxW, boxH},
                g = {bxx[2], rowCY, boxW, boxH},
                b = {bxx[3], rowCY, boxW, boxH},
            }
            local vals = {colR, colG, colB}
            local tags = {"R", "G", "B"}
            local keys = {"r", "g", "b"}
            for i = 1, 3 do
                local bxi = bxx[i]
                dxDrawText(tags[i], bxi, rowCY - 16 * S, bxi + boxW, rowCY, tocolor(130, 140, 160, 255), 0.9 * S, "default-bold", "left", "top", true)
                local foc = colFocus == keys[i]
                dxDrawRectangle(bxi, rowCY, boxW, boxH, tocolor(28, 32, 42, 255))
                dxDrawRectangle(bxi, rowCY + boxH - 2 * S, boxW, 2 * S,
                    foc and tocolor(0, 128, 255, 255) or tocolor(55, 62, 80, 255))
                local v = vals[i]
                if v == "" then v = foc and "|" or "0-255" end
                dxDrawText(v, bxi + 8 * S, rowCY, bxi + boxW - 8 * S, rowCY + boxH,
                    vals[i] == "" and tocolor(100, 108, 125, 255) or tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "center", "center", true)
            end
            -- live preview square (currently chosen color)
            local pr = math.min(255, math.max(0, tonumber(colR) or 0))
            local pg = math.min(255, math.max(0, tonumber(colG) or 0))
            local pb = math.min(255, math.max(0, tonumber(colB) or 0))
            local pvx = bxx[3] + boxW + 10 * S
            dxDrawRectangle(pvx, rowCY, boxH, boxH, tocolor(pr, pg, pb, 255))
            dxDrawRectangle(pvx, rowCY, boxH, 2 * S, tocolor(200, 205, 215, 180))
            dxDrawRectangle(pvx, rowCY + boxH - 2 * S, boxH, 2 * S, tocolor(200, 205, 215, 180))
            -- APPLY fills the rest
            local apx = pvx + boxH + 10 * S
            local apw = CX + CW - 10 * S - apx
            colorPickerRects.apply = {apx, rowCY, apw, boxH}
            local ahov = isMouseIn(apx, rowCY, apw, boxH)
            dxDrawRectangle(apx, rowCY, apw, boxH, ahov and tocolor(40, 150, 255, 255) or tocolor(0, 128, 255, 255))
            dxDrawText("APPLY", apx, rowCY, apx + apw, rowCY + boxH, tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center", true)
        else
            rColorClose = nil
            colorPickerRects = {}
        end
    else
        rMembersClose = nil
    end

    -- Delete-clan confirm modal (owner only): type exact clan name + Delete / Close
    if deleteConfirmOpen and inGroup and myGroup and myGroup.rank == "owner" then
        local DW, DH = 400 * S, 270 * S
        local DX = (sw - DW) / 2
        local DY = (sh - DH) / 2
        dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 140))
        rDeleteClose = {DX + DW - 40 * S, DY + 8 * S, 28 * S, 28 * S}
        dxDrawRectangle(DX, DY, DW, DH, tocolor(15, 17, 23, 252))
        dxDrawRectangle(DX, DY, DW, 44 * S, tocolor(21, 24, 32, 255))
        dxDrawRectangle(DX, DY + 44 * S, DW, 2 * S, tocolor(220, 70, 70, 255))
        dxDrawText("DELETE CLAN", DX + 14 * S, DY, DX + DW - 54 * S, DY + 44 * S, tocolor(255, 150, 150, 255), 1.1 * S, "default-bold", "left", "center", true)
        local dch = isMouseIn(rDeleteClose[1], rDeleteClose[2], rDeleteClose[3], rDeleteClose[4])
        dxDrawRectangle(rDeleteClose[1], rDeleteClose[2], rDeleteClose[3], rDeleteClose[4], dch and tocolor(220, 70, 70, 255) or tocolor(35, 40, 52, 255))
        dxDrawText("X", rDeleteClose[1], rDeleteClose[2], rDeleteClose[1] + rDeleteClose[3], rDeleteClose[2] + rDeleteClose[4], tocolor(255, 255, 255, 255), 1.0 * S, "default-bold", "center", "center")
        local cname = tostring(myGroup.name)
        dxDrawText("This will permanently delete '" .. cname .. "'.", DX + 14 * S, DY + 52 * S, DX + DW - 14 * S, DY + 74 * S,
            tocolor(255, 180, 180, 255), 1.0 * S, "default-bold", "left", "top", true)
        dxDrawText("Type the clan name to confirm:", DX + 14 * S, DY + 78 * S, DX + DW - 14 * S, DY + 98 * S,
            tocolor(150, 160, 180, 255), 1.0 * S, "default", "left", "top", true)
        local inX, inY, inW, inH = DX + 14 * S, DY + 102 * S, DW - 28 * S, 42 * S
        deleteModalRects.input = {inX, inY, inW, inH}
        local dfoc = deleteInputFocused
        dxDrawRectangle(inX, inY, inW, inH, tocolor(28, 32, 42, 255))
        dxDrawRectangle(inX, inY + inH - 2 * S, inW, 2 * S,
            dfoc and tocolor(220, 70, 70, 255) or tocolor(55, 62, 80, 255))
        if deleteInput == "" then
            dxDrawText(cname, inX + 12 * S, inY, inX + inW - 12 * S, inY + inH,
                tocolor(100, 108, 125, 255), 1.0 * S, "default", "left", "center", true)
        else
            local caret = dfoc and ((getTickCount() % 1000 < 500) and "|" or "") or ""
            dxDrawText(deleteInput .. caret, inX + 12 * S, inY, inX + inW - 12 * S, inY + inH,
                tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "left", "center", true)
        end
        local btnY, btnH = DY + DH - 14 * S - 42 * S, 42 * S
        local btnW = (DW - 28 * S - 10 * S) / 2
        local delX, cloX = DX + 14 * S, DX + 14 * S + btnW + 10 * S
        deleteModalRects.delete = {delX, btnY, btnW, btnH}
        deleteModalRects.close = {cloX, btnY, btnW, btnH}
        local match = deleteInput == cname
        local dhov = isMouseIn(delX, btnY, btnW, btnH)
        dxDrawRectangle(delX, btnY, btnW, btnH,
            match and (dhov and tocolor(200, 60, 60, 255) or tocolor(150, 45, 45, 255)) or tocolor(45, 52, 66, 255))
        dxDrawText("DELETE", delX, btnY, delX + btnW, btnY + btnH,
            match and tocolor(255, 255, 255, 255) or tocolor(120, 128, 145, 255), 1.0 * S, "default-bold", "center", "center", true)
        local chov = isMouseIn(cloX, btnY, btnW, btnH)
        dxDrawRectangle(cloX, btnY, btnW, btnH, chov and tocolor(38, 43, 56, 255) or tocolor(30, 35, 46, 255))
        dxDrawText("CLOSE", cloX, btnY, cloX + btnW, btnY + btnH, tocolor(235, 238, 245, 255), 1.0 * S, "default-bold", "center", "center", true)
    else
        rDeleteClose = nil
        deleteModalRects = {}
    end

    -- status / footer (single line, clipped)
    if statusMsg ~= "" and getTickCount() < statusUntil then
        dxDrawText(statusMsg, PX + 24 * S, PY + PH - 30 * S, PX + PW - 24 * S, PY + PH - 10 * S,
            tocolor(statusColor[1], statusColor[2], statusColor[3], 255), 1.0 * S, "default-bold", "left", "center", true)
    else
        dxDrawText("F6 open / close", PX + 24 * S, PY + PH - 30 * S, PX + PW - 24 * S, PY + PH - 10 * S,
            tocolor(90, 95, 110, 255), 1.0 * S, "default", "right", "center", true)
    end
end)
