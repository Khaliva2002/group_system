-- ecma Group System v2 - Server (optimized)
-- SQLite + default MTA accounts (account-based identity)
-- Ranks: member(1) < co-leader(2) < leader(3) < owner(4)
--
-- PERFORMANCE RULES (keep these in all future stages):
-- 1. RAM cache is the source of truth at runtime. DB is persistence only.
-- 2. NEVER block with dbPoll(qh, timeout>0) inside an event. Only dbPoll(qh, 0)
--    inside async dbQuery callbacks (one-time load chains are OK).
-- 3. Writes are fire-and-forget dbExec + instant sync cache update.
-- 4. Only create/inviteSend need an async gap (to fetch the new row id).
--    Guard those gaps with the busy[] lock so double-clicks can't duplicate.
-- 5. No per-player loops with DB hits. Build online maps once per event.

local CREATE_COST = 2500000
local GROUP_MAX_MEMBERS = 10

local RANK_LEVEL = {member = 1, ["co-leader"] = 2, leader = 3, owner = 4}
local SETTABLE_RANKS = {member = true, ["co-leader"] = true, leader = true} -- owner can never be assigned
-- display only: DB + logic stay lowercase, messages show capitalized
local RANK_LABEL = {member = "Member", ["co-leader"] = "Co-Leader", leader = "Leader", owner = "Owner"}
local function prettyRank(r) return RANK_LABEL[r] or tostring(r) end
-- UTF-8 safe helpers for chat (byte-based #/sub would split multibyte chars)
local function utf8LenS(s)
    local _, n = tostring(s):gsub("[^\128-\191]", "")
    return n
end
local function utf8Cut(s, maxC)
    s = tostring(s)
    if utf8LenS(s) <= maxC then return s end
    local i, c = 1, 0
    while i <= #s do
        local b = s:byte(i)
        local bl = 1
        if b >= 240 then bl = 4 elseif b >= 224 then bl = 3 elseif b >= 192 then bl = 2 end
        if c + 1 > maxC then return s:sub(1, i - 1) end
        c = c + 1
        i = i + bl
    end
    return s
end

local db = nil

-- ================= RAM caches =================
local groups = {}       -- [id] = {id, name, owner, r, g, b, balance}
local groupByName = {}  -- [name] = id
local membership = {}   -- [account] = {gid, rank, joined, seen}
local groupMembers = {} -- [gid] = { [account] = rank }
local invites = {}      -- [id] = {gid, from, to}
local inviteKey = {}    -- ["gid:toAccount"] = id
local invitesTo = {}    -- [toAccount] = { [id] = true }
local busy = {}         -- lock for async gaps (create / inviteSend)
local clanChatSpam = {} -- anti-spam counters for Clan command (3 per 5s)

-- ================= helpers =================
local function getAccountNameSafe(player)
    if not isElement(player) then return nil end
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return nil end
    return getAccountName(acc)
end

local function isValidGroupName(name)
    if type(name) ~= "string" then return false, "Invalid name." end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name < 3 or #name > 10 then
        return false, "Name must be 3-10 characters."
    end
    if not name:match("^[A-Za-z0-9%[%]{}%-_%.:]+$") then
        return false, "Allowed: A-Z 0-9 []{}-_.:"
    end
    return true, name
end

local function normalizeMoneyAmount(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return nil end
    return amount
end

local function moneyOK()
    local res = getResourceFromName("money")
    return res and getResourceState(res) == "running"
end

-- cache reads (O(1), no DB)
local function getMyGroup(acc)
    local m = acc and membership[acc]
    if not m then return nil end
    local g = groups[m.gid]
    if not g then return nil end
    return g, m.rank
end

local function countMembers(gid)
    local set = groupMembers[gid]
    if not set then return 0 end
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function findPlayerByAccount(account)
    for _, p in ipairs(getElementsByType("player")) do
        if getAccountNameSafe(p) == account then return p end
    end
    return nil
end

-- account -> player element map, built once per event that needs it
local function buildOnlineMap()
    local map = {}
    for _, p in ipairs(getElementsByType("player")) do
        local pa = getAccountNameSafe(p)
        if pa then map[pa] = p end
    end
    return map
end

local function refreshClan(player)
    if not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then
        setElementData(player, "Clan", "")
        return
    end
    local g = getMyGroup(acc)
    setElementData(player, "Clan", g and g.name or "")
end

local function sendState(player)
    if not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then
        triggerClientEvent(player, "group:stateUpdate", resourceRoot, false, "You must be logged in.")
        return
    end
    local g, rank = getMyGroup(acc)
    if g then
        triggerClientEvent(player, "group:stateUpdate", resourceRoot, {
            id = g.id, name = g.name, rank = rank, owner = g.owner,
        })
    else
        triggerClientEvent(player, "group:stateUpdate", resourceRoot, false)
    end
end

-- ================= client cache push =================
-- The client keeps a memory copy of its clan + invites + global list.
-- Server pushes on every change, so panels render instantly with no loading.
local function clanSnapshotFor(acc, onlineMap)
    local m = acc and membership[acc]
    if not m then return nil end
    local g = groups[m.gid]
    if not g then return nil end
    onlineMap = onlineMap or buildOnlineMap()
    local members = {}
    for memberAcc, rank in pairs(groupMembers[m.gid] or {}) do
        local mc = membership[memberAcc] or {}
        local on = onlineMap[memberAcc] ~= nil
        table.insert(members, {
            account = memberAcc, rank = rank, online = on,
            name = on and getPlayerName(onlineMap[memberAcc]) or memberAcc,
            joined = mc.joined or 0, seen = on and getRealTime().timestamp or (mc.seen or 0),
        })
    end
    table.sort(members, function(a, b) return (a.joined or 0) < (b.joined or 0) end)
    return {
        id = g.id, name = g.name, rank = m.rank, owner = g.owner,
        color = {r = g.r, g = g.g, b = g.b}, balance = g.balance,
        members = members,
    }
end

local function myInvitesFor(acc)
    local out = {}
    for invId in pairs(invitesTo[acc] or {}) do
        local inv = invites[invId]
        local g = inv and groups[inv.gid]
        if g then
            table.insert(out, {
                id = invId, name = g.name, from = inv.from,
                members = countMembers(inv.gid), max = GROUP_MAX_MEMBERS,
            })
        end
    end
    return out
end

local function groupsSnapshot()
    local out = {}
    for _, g in pairs(groups) do
        table.insert(out, {name = g.name, members = countMembers(g.id), max = GROUP_MAX_MEMBERS})
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- push full clan snapshot to every online member of a group
local function pushClan(gid)
    local online = buildOnlineMap()
    for memberAcc in pairs(groupMembers[gid] or {}) do
        local p = online[memberAcc]
        if p then
            triggerClientEvent(p, "group:clanCache", resourceRoot, clanSnapshotFor(memberAcc, online))
        end
    end
end

-- push empty clan state (left / kicked / disbanded)
local function pushClanEmpty(player)
    if isElement(player) then
        triggerClientEvent(player, "group:clanCache", resourceRoot, false)
    end
end

-- push pending invites to one player
local function pushInvites(player, acc)
    if isElement(player) and acc then
        triggerClientEvent(player, "group:myInvitesCache", resourceRoot, myInvitesFor(acc))
    end
end

-- push global groups list to everyone (cheap: tiny table)
-- used ONLY for full sync (player join / requestState). Runtime changes
-- go through pushGroupDelta / pushGroupRemove instead (one row, not the list).
local function broadcastGroups()
    local snap = groupsSnapshot()
    for _, p in ipairs(getElementsByType("player")) do
        if isElement(p) then
            triggerClientEvent(p, "group:groupsCache", resourceRoot, snap)
        end
    end
end

-- delta broadcast: tell every client about ONE changed group row.
-- Client patches its cached list in place (same idea as clanCache pushes).
local function pushGroupDelta(gid)
    local g = groups[gid]
    if not g then return end
    local row = {name = g.name, members = countMembers(gid), max = GROUP_MAX_MEMBERS}
    for _, p in ipairs(getElementsByType("player")) do
        if isElement(p) then
            triggerClientEvent(p, "group:groupDelta", resourceRoot, row)
        end
    end
end

-- delta broadcast: a group vanished (disband) -> clients drop the row by name
local function pushGroupRemove(name)
    if not name then return end
    for _, p in ipairs(getElementsByType("player")) do
        if isElement(p) then
            triggerClientEvent(p, "group:groupDelta", resourceRoot, {name = name, remove = true})
        end
    end
end

-- ================= init (one-time async load chain) =================
local function initDB()
    db = dbConnect("sqlite", "groups.db")
    if not db then
        outputServerLog("[group_system_v2] DB connect failed")
        return false
    end
    dbExec(db, [[CREATE TABLE IF NOT EXISTS groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        owner TEXT NOT NULL,
        r INTEGER NOT NULL DEFAULT 255,
        g INTEGER NOT NULL DEFAULT 255,
        b INTEGER NOT NULL DEFAULT 255,
        balance INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
    )]])
    dbExec(db, [[CREATE TABLE IF NOT EXISTS members (
        group_id INTEGER NOT NULL,
        account TEXT UNIQUE NOT NULL,
        rank TEXT NOT NULL DEFAULT 'member',
        joined_at INTEGER NOT NULL
    )]])
    dbExec(db, [[CREATE TABLE IF NOT EXISTS invites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        from_account TEXT NOT NULL,
        to_account TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(group_id, to_account)
    )]])
    -- migrate old v1 DB (had only id/name/owner/created_at), fails silently if present
    dbExec(db, "ALTER TABLE groups ADD COLUMN r INTEGER NOT NULL DEFAULT 255")
    dbExec(db, "ALTER TABLE groups ADD COLUMN g INTEGER NOT NULL DEFAULT 255")
    dbExec(db, "ALTER TABLE groups ADD COLUMN b INTEGER NOT NULL DEFAULT 255")
    dbExec(db, "ALTER TABLE groups ADD COLUMN balance INTEGER NOT NULL DEFAULT 0")
    dbExec(db, "ALTER TABLE members ADD COLUMN last_seen INTEGER NOT NULL DEFAULT 0")
    return true
end

local function loadAllIntoCache()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, r in ipairs(rows) do
            local id = tonumber(r.id)
            groups[id] = {
                id = id, name = tostring(r.name), owner = tostring(r.owner),
                r = tonumber(r.r) or 255, g = tonumber(r.g) or 255, b = tonumber(r.b) or 255,
                balance = tonumber(r.balance) or 0,
            }
            groupByName[tostring(r.name)] = id
            groupMembers[id] = {}
        end
        dbQuery(function(qh2)
            local rows2 = dbPoll(qh2, 0) or {}
            for _, r in ipairs(rows2) do
                local gid = tonumber(r.group_id)
                local acc = tostring(r.account)
                local rank = tostring(r.rank)
                if groups[gid] then
                    membership[acc] = {gid = gid, rank = rank, joined = tonumber(r.joined_at) or 0, seen = tonumber(r.last_seen) or 0}
                    groupMembers[gid][acc] = rank
                end
            end
            dbQuery(function(qh3)
                local rows3 = dbPoll(qh3, 0) or {}
                for _, r in ipairs(rows3) do
                    local id = tonumber(r.id)
                    local gid = tonumber(r.group_id)
                    local toAcc = tostring(r.to_account)
                    if groups[gid] then
                        invites[id] = {gid = gid, from = tostring(r.from_account), to = toAcc}
                        inviteKey[gid .. ":" .. toAcc] = id
                        invitesTo[toAcc] = invitesTo[toAcc] or {}
                        invitesTo[toAcc][id] = true
                    end
                end
                for _, p in ipairs(getElementsByType("player")) do
                    refreshClan(p)
                end
                outputServerLog("[group_system_v2] cache loaded")
            end, db, "SELECT id, group_id, from_account, to_account FROM invites")
        end, db, "SELECT group_id, account, rank, joined_at, last_seen FROM members")
    end, db, "SELECT id, name, owner, r, g, b, balance FROM groups")
end

local function addClanColumn()
    local sb = getResourceFromName("scoreboard")
    if sb and getResourceState(sb) == "running" then
        call(sb, "addScoreboardColumn", "Clan")
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    if initDB() then loadAllIntoCache() end
    addClanColumn()
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, "Clan", "")
    end
end)

addEventHandler("onResourceStart", root, function(res)
    if res and getResourceName(res) == "scoreboard" then
        call(res, "addScoreboardColumn", "Clan")
    end
end)

addEventHandler("onPlayerJoin", root, function()
    setElementData(source, "Clan", "")
end)

addEventHandler("onPlayerLogin", root, function()
    local acc = getAccountNameSafe(source)
    if acc and membership[acc] then
        local now = getRealTime().timestamp
        membership[acc].seen = now
        dbExec(db, "UPDATE members SET last_seen = ? WHERE account = ?", now, acc)
    end
    refreshClan(source)
    -- warm the client cache so F6 opens instantly
    if acc then
        local snap = clanSnapshotFor(acc)
        triggerClientEvent(source, "group:clanCache", resourceRoot, snap or false)
        pushInvites(source, acc)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    local acc = getAccountNameSafe(source)
    if acc and membership[acc] then
        local now = getRealTime().timestamp
        membership[acc].seen = now
        dbExec(db, "UPDATE members SET last_seen = ? WHERE account = ?", now, acc)
    end
    clanChatSpam[source] = nil
end)

addEventHandler("onPlayerLogout", root, function(prevAccount)
    if prevAccount and not isGuestAccount(prevAccount) then
        local acc = getAccountName(prevAccount)
        if acc and membership[acc] then
            local now = getRealTime().timestamp
            membership[acc].seen = now
            dbExec(db, "UPDATE members SET last_seen = ? WHERE account = ?", now, acc)
        end
    end
end)

-- ================= CREATE (2500000 via money resource) =================
addEvent("group:create", true)
addEventHandler("group:create", resourceRoot, function(rawName)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "You must be logged in.")
        return
    end
    if busy[acc] then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "Please wait...")
        return
    end
    local ok, nameOrMsg = isValidGroupName(rawName)
    if not ok then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, nameOrMsg)
        return
    end
    local name = nameOrMsg
    if membership[acc] then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "You are already in a group.")
        return
    end
    if groupByName[name] then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "Group name is already taken.")
        return
    end
    if not moneyOK() then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "Money system offline. Try later.")
        return
    end
    if not exports.money:hasMoney(player, CREATE_COST) then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "Not enough money (2500000 $).")
        return
    end
    if not exports.money:subMoney(player, CREATE_COST) then
        triggerClientEvent(player, "group:createResult", resourceRoot, false, "Payment failed. Try again.")
        return
    end
    busy[acc] = true
    local now = getRealTime().timestamp
    dbExec(db, "INSERT INTO groups (name, owner, r, g, b, balance, created_at) VALUES (?, ?, 255, 255, 255, 0, ?)", name, acc, now)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local gid = rows and rows[1] and tonumber(rows[1].id)
        if not gid then
            exports.money:addMoney(player, CREATE_COST) -- refund on DB failure
            busy[acc] = nil
            if isElement(player) then
                triggerClientEvent(player, "group:createResult", resourceRoot, false, "Database error. Refunded.")
            end
            return
        end
        groups[gid] = {id = gid, name = name, owner = acc, r = 255, g = 255, b = 255, balance = 0}
        groupByName[name] = gid
        groupMembers[gid] = {}
        dbExec(db, "INSERT INTO members (group_id, account, rank, joined_at) VALUES (?, ?, 'owner', ?)", gid, acc, now)
        membership[acc] = {gid = gid, rank = "owner", joined = now, seen = now}
        groupMembers[gid][acc] = "owner"
        busy[acc] = nil
        if isElement(player) then
            setElementData(player, "Clan", name)
            triggerClientEvent(player, "group:createResult", resourceRoot, true, "Group '" .. name .. "' created.")
            sendState(player)
            pushClan(gid)
            pushGroupDelta(gid) -- new clan row only, not the full list
        end
        outputServerLog("[group_system_v2] " .. acc .. " created group '" .. name .. "'")
    end, db, "SELECT id FROM groups WHERE name = ? LIMIT 1", name)
end)

addEvent("group:requestState", true)
addEventHandler("group:requestState", resourceRoot, function()
    local player = client
    sendState(player)
    -- full cache warm so the panel renders instantly
    if isElement(player) then
        local acc = getAccountNameSafe(player)
        if acc then
            local snap = clanSnapshotFor(acc)
            triggerClientEvent(player, "group:clanCache", resourceRoot, snap or false)
            pushInvites(player, acc)
            triggerClientEvent(player, "group:groupsCache", resourceRoot, groupsSnapshot())
        end
    end
end)

-- ================= LEAVE (anyone except owner) =================
addEvent("group:leave", true)
addEventHandler("group:leave", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    local m = membership[acc]
    if not m then
        triggerClientEvent(player, "group:leaveResult", resourceRoot, false, "You are not in a group.")
        return
    end
    if m.rank == "owner" then
        triggerClientEvent(player, "group:leaveResult", resourceRoot, false, "Owner must disband the clan first.")
        return
    end
    local g = groups[m.gid]
    local gname = g and g.name or "?"
    local gid = m.gid
    dbExec(db, "DELETE FROM members WHERE account = ?", acc)
    membership[acc] = nil
    if groupMembers[gid] then groupMembers[gid][acc] = nil end
    setElementData(player, "Clan", "")
    pushClanEmpty(player)
    pushClan(gid)
    pushGroupDelta(gid) -- member count changed
    triggerClientEvent(player, "group:leaveResult", resourceRoot, true, "You left '" .. gname .. "'.")
    sendState(player)
end)

-- ================= KICK (higher rank only) =================
addEvent("group:kick", true)
addEventHandler("group:kick", resourceRoot, function(targetAccount)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc or type(targetAccount) ~= "string" then return end
    local me = membership[acc]
    if not me then
        triggerClientEvent(player, "group:kickResult", resourceRoot, false, "You are not in a group.")
        return
    end
    if targetAccount == acc then
        triggerClientEvent(player, "group:kickResult", resourceRoot, false, "You cannot kick yourself.")
        return
    end
    local tm = membership[targetAccount]
    if not tm or tm.gid ~= me.gid then
        triggerClientEvent(player, "group:kickResult", resourceRoot, false, "Target is not in your group.")
        return
    end
    if (RANK_LEVEL[me.rank] or 0) <= (RANK_LEVEL[tm.rank] or 0) then
        triggerClientEvent(player, "group:kickResult", resourceRoot, false, "You can only kick lower ranks.")
        return
    end
    local g = groups[me.gid]
    dbExec(db, "DELETE FROM members WHERE account = ?", targetAccount)
    membership[targetAccount] = nil
    if groupMembers[me.gid] then groupMembers[me.gid][targetAccount] = nil end
    local online = buildOnlineMap()
    local tp = online[targetAccount]
    if tp then
        setElementData(tp, "Clan", "")
        pushClanEmpty(tp)
        outputChatBox("You were kicked from '" .. (g and g.name or "?") .. "'.", tp, 255, 120, 120)
    end
    pushClan(me.gid)
    pushGroupDelta(me.gid) -- member count changed
    triggerClientEvent(player, "group:kickResult", resourceRoot, true, targetAccount .. " kicked.")
end)

-- ================= RANK (leader+ ; co-leader cannot promote/demote) =================
addEvent("group:setRank", true)
addEventHandler("group:setRank", resourceRoot, function(targetAccount, newRank)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc or type(targetAccount) ~= "string" or type(newRank) ~= "string" then return end
    if not SETTABLE_RANKS[newRank] then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "Rank must be Member/Co-Leader/Leader.")
        return
    end
    local me = membership[acc]
    if not me then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "You are not in a group.")
        return
    end
    local myLv = RANK_LEVEL[me.rank] or 0
    if myLv < 3 then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "Only Leader and Owner can change ranks.")
        return
    end
    if targetAccount == acc then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "You cannot change your own rank.")
        return
    end
    local tm = membership[targetAccount]
    if not tm or tm.gid ~= me.gid then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "Target is not in your group.")
        return
    end
    if tm.rank == "owner" then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "You cannot change the Owner.")
        return
    end
    if (RANK_LEVEL[tm.rank] or 0) >= myLv then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "You can only change lower ranks.")
        return
    end
    if (RANK_LEVEL[newRank] or 0) > myLv then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "You cannot grant a higher rank than yours.")
        return
    end
    if tm.rank == newRank then
        triggerClientEvent(player, "group:rankResult", resourceRoot, false, "Already " .. prettyRank(newRank) .. ".")
        return
    end
    dbExec(db, "UPDATE members SET rank = ? WHERE account = ?", newRank, targetAccount)
    tm.rank = newRank
    if groupMembers[me.gid] then groupMembers[me.gid][targetAccount] = newRank end
    pushClan(me.gid)
    triggerClientEvent(player, "group:rankResult", resourceRoot, true, targetAccount .. " is now " .. prettyRank(newRank) .. ".")
end)

-- ================= COLOR (leader + owner, stored rgb) =================
addEvent("group:setColor", true)
addEventHandler("group:setColor", resourceRoot, function(r, g, b)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    r, g, b = math.floor(tonumber(r) or -1), math.floor(tonumber(g) or -1), math.floor(tonumber(b) or -1)
    if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then
        triggerClientEvent(player, "group:colorResult", resourceRoot, false, "Invalid color (0-255).")
        return
    end
    local mem = membership[acc]
    if not mem then
        triggerClientEvent(player, "group:colorResult", resourceRoot, false, "You are not in a group.")
        return
    end
    if (RANK_LEVEL[mem.rank] or 0) < 3 then
        triggerClientEvent(player, "group:colorResult", resourceRoot, false, "Only Leader and Owner can change color.")
        return
    end
    local gr = groups[mem.gid]
    if not gr then return end
    dbExec(db, "UPDATE groups SET r = ?, g = ?, b = ? WHERE id = ?", r, g, b, mem.gid)
    gr.r, gr.g, gr.b = r, g, b
    pushClan(mem.gid)
    -- turf module recolors every zone owned by this clan (same resource, server-side event)
    triggerEvent("group:clanColorChanged", resourceRoot, gr.name, r, g, b)
    triggerClientEvent(player, "group:colorResult", resourceRoot, true, "Color updated.")
end)

-- ================= DISBAND (owner only, bank money deleted) =================
addEvent("group:disband", true)
addEventHandler("group:disband", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    local m = membership[acc]
    if not m then
        triggerClientEvent(player, "group:disbandResult", resourceRoot, false, "You are not in a group.")
        return
    end
    if m.rank ~= "owner" then
        triggerClientEvent(player, "group:disbandResult", resourceRoot, false, "Only the Owner can disband.")
        return
    end
    local gid = m.gid
    local g = groups[gid]
    local gname = g and g.name or "?"
    local membersSet = groupMembers[gid] or {}
    dbExec(db, "DELETE FROM invites WHERE group_id = ?", gid)
    dbExec(db, "DELETE FROM members WHERE group_id = ?", gid)
    dbExec(db, "DELETE FROM groups WHERE id = ?", gid)
    -- clear caches
    for memberAcc in pairs(membersSet) do membership[memberAcc] = nil end
    for invId, inv in pairs(invites) do
        if inv.gid == gid then
            invites[invId] = nil
            inviteKey[inv.gid .. ":" .. inv.to] = nil
            if invitesTo[inv.to] then invitesTo[inv.to][invId] = nil end
        end
    end
    groupMembers[gid] = nil
    groups[gid] = nil
    groupByName[gname] = nil
    local online = buildOnlineMap()
    for memberAcc in pairs(membersSet) do
        local p = online[memberAcc]
        if p then
            setElementData(p, "Clan", "")
            pushClanEmpty(p)
            if p ~= player then
                outputChatBox("Your clan '" .. gname .. "' was disbanded.", p, 255, 120, 120)
            end
        end
    end
    pushGroupRemove(gname) -- drop the row everywhere, no full list resend
    triggerClientEvent(player, "group:disbandResult", resourceRoot, true, "Clan '" .. gname .. "' deleted.")
    sendState(player)
    outputServerLog("[group_system_v2] " .. acc .. " disbanded '" .. gname .. "'")
end)

-- ================= INVITES =================
-- eligible targets: online, logged in, no group (single member scan, no DB)
addEvent("group:inviteTargets", true)
addEventHandler("group:inviteTargets", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    local me = membership[acc]
    if not me or (RANK_LEVEL[me.rank] or 0) < 2 then
        triggerClientEvent(player, "group:inviteTargets", resourceRoot, false, "Only Co-Leader and above can invite.")
        return
    end
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= player then
            local pa = getAccountNameSafe(p)
            if pa and not membership[pa] then
                table.insert(list, {player = p, name = getPlayerName(p)})
            end
        end
    end
    triggerClientEvent(player, "group:inviteTargets", resourceRoot, true, list)
end)

addEvent("group:inviteSend", true)
addEventHandler("group:inviteSend", resourceRoot, function(targetPlayer)
    local player = client
    if not player or not isElement(player) then return end
    if not isElement(targetPlayer) or getElementType(targetPlayer) ~= "player" then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Invalid target.")
        return
    end
    local acc = getAccountNameSafe(player)
    local tAcc = getAccountNameSafe(targetPlayer)
    if not acc then return end
    if not tAcc then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Target must be logged in.")
        return
    end
    if targetPlayer == player then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "You cannot invite yourself.")
        return
    end
    local me = membership[acc]
    if not me or (RANK_LEVEL[me.rank] or 0) < 2 then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Only Co-Leader and above can invite.")
        return
    end
    if membership[tAcc] then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Target is already in a group.")
        return
    end
    local gid = me.gid
    local g = groups[gid]
    if not g then return end
    if countMembers(gid) >= GROUP_MAX_MEMBERS then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Group is full (10/10).")
        return
    end
    local key = gid .. ":" .. tAcc
    if inviteKey[key] then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Invite already pending. Ignored.")
        return
    end
    if busy[key] then
        triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Please wait...")
        return
    end
    busy[key] = true
    local now = getRealTime().timestamp
    dbExec(db, "INSERT INTO invites (group_id, from_account, to_account, created_at) VALUES (?, ?, ?, ?)", gid, acc, tAcc, now)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local invId = rows and rows[1] and tonumber(rows[1].id)
        busy[key] = nil
        if not invId then
            if isElement(player) then
                triggerClientEvent(player, "group:inviteResult", resourceRoot, false, "Database error.")
            end
            return
        end
        invites[invId] = {gid = gid, from = acc, to = tAcc}
        inviteKey[key] = invId
        invitesTo[tAcc] = invitesTo[tAcc] or {}
        invitesTo[tAcc][invId] = true
        if isElement(player) and isElement(targetPlayer) then
            triggerClientEvent(player, "group:inviteResult", resourceRoot, true, "Invite sent to " .. getPlayerName(targetPlayer) .. ".")
            triggerClientEvent(targetPlayer, "group:inviteReceived", resourceRoot, {
                id = invId, group = g.name, from = acc,
                members = countMembers(gid), max = GROUP_MAX_MEMBERS,
            })
            pushInvites(targetPlayer, tAcc)
            outputChatBox("Clan invite: '" .. g.name .. "' from " .. acc .. " (" .. countMembers(gid) .. "/" .. GROUP_MAX_MEMBERS .. "). Open F6 > Invites.", targetPlayer, 0, 128, 255)
        end
    end, db, "SELECT id FROM invites WHERE group_id = ? AND to_account = ? LIMIT 1", gid, tAcc)
end)

-- pending invites of caller (table: id, clan, from, members, max)
addEvent("group:invitesList", true)
addEventHandler("group:invitesList", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    local out = {}
    for invId in pairs(invitesTo[acc] or {}) do
        local inv = invites[invId]
        local g = inv and groups[inv.gid]
        if g then
            table.insert(out, {
                id = invId, name = g.name, from = inv.from,
                members = countMembers(inv.gid), max = GROUP_MAX_MEMBERS,
            })
        end
    end
    triggerClientEvent(player, "group:invitesList", resourceRoot, out)
end)

-- accept: must be group-less; clears ALL other pending invites
addEvent("group:inviteAccept", true)
addEventHandler("group:inviteAccept", resourceRoot, function(inviteId)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    inviteId = tonumber(inviteId)
    if not inviteId then return end
    if busy[acc] then
        triggerClientEvent(player, "group:inviteAcceptResult", resourceRoot, false, "Please wait...")
        return
    end
    if membership[acc] then
        triggerClientEvent(player, "group:inviteAcceptResult", resourceRoot, false, "You are already in a group.")
        return
    end
    local inv = invites[inviteId]
    if not inv or inv.to ~= acc then
        triggerClientEvent(player, "group:inviteAcceptResult", resourceRoot, false, "Invite no longer valid.")
        return
    end
    local g = groups[inv.gid]
    if not g then
        triggerClientEvent(player, "group:inviteAcceptResult", resourceRoot, false, "Clan no longer exists.")
        return
    end
    if countMembers(inv.gid) >= GROUP_MAX_MEMBERS then
        triggerClientEvent(player, "group:inviteAcceptResult", resourceRoot, false, "Group is full (10/10).")
        return
    end
    local now = getRealTime().timestamp
    dbExec(db, "INSERT INTO members (group_id, account, rank, joined_at) VALUES (?, ?, 'member', ?)", inv.gid, acc, now)
    dbExec(db, "DELETE FROM invites WHERE to_account = ?", acc) -- accepting one clears the rest
    membership[acc] = {gid = inv.gid, rank = "member", joined = now, seen = now}
    groupMembers[inv.gid][acc] = "member"
    for otherId in pairs(invitesTo[acc] or {}) do
        local o = invites[otherId]
        if o then inviteKey[o.gid .. ":" .. acc] = nil end
        invites[otherId] = nil
    end
    invitesTo[acc] = nil
    setElementData(player, "Clan", g.name)
    triggerClientEvent(player, "group:inviteAcceptResult", resourceRoot, true, "You joined '" .. g.name .. "'.")
    pushClan(inv.gid)
    pushInvites(player, acc)
    pushGroupDelta(inv.gid) -- member count changed
    sendState(player)
end)

addEvent("group:inviteDecline", true)
addEventHandler("group:inviteDecline", resourceRoot, function(inviteId)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    inviteId = tonumber(inviteId)
    if not inviteId then return end
    local inv = invites[inviteId]
    if not inv or inv.to ~= acc then return end
    dbExec(db, "DELETE FROM invites WHERE id = ?", inviteId)
    invites[inviteId] = nil
    inviteKey[inv.gid .. ":" .. acc] = nil
    if invitesTo[acc] then invitesTo[acc][inviteId] = nil end
    pushInvites(player, acc)
    triggerClientEvent(player, "group:inviteDeclineResult", resourceRoot, true, "Invite declined.")
end)

-- ================= BANK (balance in groups.balance) =================
addEvent("group:bankBalance", true)
addEventHandler("group:bankBalance", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    local m = membership[acc]
    if not m then
        triggerClientEvent(player, "group:bankBalance", resourceRoot, false, "You are not in a group.")
        return
    end
    local g = groups[m.gid]
    triggerClientEvent(player, "group:bankBalance", resourceRoot, true, g and g.balance or 0)
end)

-- deposit: any member, cash -> clan bank
addEvent("group:deposit", true)
addEventHandler("group:deposit", resourceRoot, function(amount)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    amount = normalizeMoneyAmount(amount)
    if not amount then
        triggerClientEvent(player, "group:depositResult", resourceRoot, false, "Invalid amount.")
        return
    end
    local m = membership[acc]
    if not m then
        triggerClientEvent(player, "group:depositResult", resourceRoot, false, "You are not in a group.")
        return
    end
    local g = groups[m.gid]
    if not g then return end
    if not moneyOK() then
        triggerClientEvent(player, "group:depositResult", resourceRoot, false, "Money system offline.")
        return
    end
    if not exports.money:hasMoney(player, amount) then
        triggerClientEvent(player, "group:depositResult", resourceRoot, false, "Not enough cash.")
        return
    end
    if not exports.money:subMoney(player, amount) then
        triggerClientEvent(player, "group:depositResult", resourceRoot, false, "Payment failed.")
        return
    end
    dbExec(db, "UPDATE groups SET balance = balance + ? WHERE id = ?", amount, m.gid)
    g.balance = g.balance + amount
    pushClan(m.gid)
    triggerClientEvent(player, "group:depositResult", resourceRoot, true, "Deposited " .. amount .. " $.", g.balance)
end)

-- withdraw: owner only, bank -> cash
addEvent("group:withdraw", true)
addEventHandler("group:withdraw", resourceRoot, function(amount)
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    amount = normalizeMoneyAmount(amount)
    if not amount then
        triggerClientEvent(player, "group:withdrawResult", resourceRoot, false, "Invalid amount.")
        return
    end
    local m = membership[acc]
    if not m then
        triggerClientEvent(player, "group:withdrawResult", resourceRoot, false, "You are not in a group.")
        return
    end
    if m.rank ~= "owner" then
        triggerClientEvent(player, "group:withdrawResult", resourceRoot, false, "Only the Owner can withdraw.")
        return
    end
    local g = groups[m.gid]
    if not g then return end
    if g.balance < amount then
        triggerClientEvent(player, "group:withdrawResult", resourceRoot, false, "Not enough clan balance.")
        return
    end
    if not moneyOK() then
        triggerClientEvent(player, "group:withdrawResult", resourceRoot, false, "Money system offline.")
        return
    end
    dbExec(db, "UPDATE groups SET balance = balance - ? WHERE id = ?", amount, m.gid)
    g.balance = g.balance - amount
    if not exports.money:addMoney(player, amount) then
        dbExec(db, "UPDATE groups SET balance = balance + ? WHERE id = ?", amount, m.gid) -- revert
        g.balance = g.balance + amount
        triggerClientEvent(player, "group:withdrawResult", resourceRoot, false, "Withdraw failed. Reverted.")
        return
    end
    pushClan(m.gid)
    triggerClientEvent(player, "group:withdrawResult", resourceRoot, true, "Withdrew " .. amount .. " $.", g.balance)
end)

-- ================= CLAN CHAT (key i -> native chatbox -> command "Clan") =================
-- Same pattern as chat resource's U/Local and old group_system's i/GroupChat:
-- the engine opens the REAL chat input, Enter executes this command with the text.
-- Outsiders are ignored silently, as if never sent.
addCommandHandler("Clan", function(player, _, ...)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    local acc = getAccountNameSafe(player)
    local m = acc and membership[acc]
    local g = m and groups[m.gid]
    if not g then return end
    if isPlayerMuted(player) then
        outputChatBox("#FF0000[Clan] #FFFFFFYou are muted", player, 255, 255, 255, true)
        return
    end
    local raw = table.concat({ ... }, " ")
    local msg = raw:gsub("#%x%x%x%x%x%x", ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then return end
    msg = utf8Cut(msg, 90)
    if not clanChatSpam[player] then
        clanChatSpam[player] = 0
        setTimer(function(p) clanChatSpam[p] = nil end, 5000, 1, player)
    end
    if clanChatSpam[player] >= 3 then
        outputChatBox("*** Don't Spam! ***", player, 255, 0, 0)
        return
    end
    clanChatSpam[player] = clanChatSpam[player] + 1
    local nick = getPlayerName(player):gsub("#%x%x%x%x%x%x", "")
    local text = "#009999*(Clan) #FFFFFF" .. nick .. " : " .. msg
    local online = buildOnlineMap()
    for memberAcc in pairs(groupMembers[m.gid] or {}) do
        local p = online[memberAcc]
        if p then
            outputChatBox(text, p, 255, 255, 255, true)
        end
    end
end)

-- ================= LISTS (all from cache, zero DB hits) =================
addEvent("group:groupsList", true)
addEventHandler("group:groupsList", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local out = {}
    for _, g in pairs(groups) do
        table.insert(out, {name = g.name, members = countMembers(g.id), max = GROUP_MAX_MEMBERS})
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    triggerClientEvent(player, "group:groupsList", resourceRoot, out)
end)

addEvent("group:membersList", true)
addEventHandler("group:membersList", resourceRoot, function()
    local player = client
    if not player or not isElement(player) then return end
    local acc = getAccountNameSafe(player)
    if not acc then return end
    local m = membership[acc]
    if not m then
        triggerClientEvent(player, "group:membersList", resourceRoot, false, "You are not in a group.")
        return
    end
    local online = buildOnlineMap()
    local out = {}
    for memberAcc, rank in pairs(groupMembers[m.gid] or {}) do
        local mc = membership[memberAcc] or {}
        local on = online[memberAcc] ~= nil
        table.insert(out, {
            account = memberAcc, rank = rank,
            online = on,
            name = on and getPlayerName(online[memberAcc]) or memberAcc,
            joined = mc.joined or 0, seen = on and getRealTime().timestamp or (mc.seen or 0),
        })
    end
    -- seniority: oldest member first
    table.sort(out, function(a, b) return (a.joined or 0) < (b.joined or 0) end)
    triggerClientEvent(player, "group:membersList", resourceRoot, true, out)
end)

-- ================= TEST API for grpTestMod (Console ACL only) =================
-- Lets the test resource assign accounts to clans through this resource's own
-- connection + RAM cache (no direct DB access, no restart needed).
local TEST_RANKS = {member = true, ["co-leader"] = true, leader = true, owner = true}

local function isConsoleAllowedSrc(src)
    if not isElement(src) then return true end -- server console / non-player caller
    if getElementType(src) ~= "player" then return true end
    local acc = getPlayerAccount(src)
    if not acc or isGuestAccount(acc) then return false end
    local grp = aclGetGroup("Console")
    if not grp then return false end
    return isObjectInACLGroup("user." .. getAccountName(acc), grp)
end

function testGetClan(accName)
    local m = accName and membership[accName]
    if not m then return nil end
    local g = groups[m.gid]
    return g and g.name or nil
end

function testListClans()
    return groupsSnapshot()
end

function testSetClan(adminPlayer, accName, rank, clanName)
    if not isConsoleAllowedSrc(adminPlayer) then return false, "Console ACL only." end
    if type(accName) ~= "string" or accName == "" then return false, "Invalid account." end
    if not TEST_RANKS[rank] then rank = "member" end
    if type(clanName) ~= "string" or clanName == "" then return false, "Invalid clan." end
    if not getAccount(accName) then return false, "Account '" .. accName .. "' does not exist." end
    local gid = nil
    for id, g in pairs(groups) do
        if g.name:lower() == clanName:lower() then
            gid = id
            clanName = g.name -- real stored spelling
            break
        end
    end
    if not gid then return false, "Clan '" .. clanName .. "' does not exist." end
    local g = groups[gid]
    local cur = membership[accName]
    local now = getRealTime().timestamp
    if cur and cur.gid == gid then
        dbExec(db, "UPDATE members SET rank = ? WHERE account = ?", rank, accName)
        cur.rank = rank
        groupMembers[gid][accName] = rank
        pushClan(gid)
        return true, "'" .. accName .. "' rank set to " .. prettyRank(rank) .. " in '" .. g.name .. "'."
    end
    if cur and cur.rank == "owner" then
        return false, "'" .. accName .. "' owns another clan. Disband it first."
    end
    if rank == "owner" then
        for mAcc in pairs(groupMembers[gid] or {}) do
            local mm = membership[mAcc]
            if mm and mm.rank == "owner" and mAcc ~= accName then
                return false, "'" .. g.name .. "' already has an Owner (" .. mAcc .. ")."
            end
        end
    end
    if countMembers(gid) >= GROUP_MAX_MEMBERS then
        return false, "Clan '" .. g.name .. "' is full (10/10)."
    end
    local oldGid = cur and cur.gid or nil
    if cur then
        dbExec(db, "DELETE FROM members WHERE account = ?", accName)
        membership[accName] = nil
        if groupMembers[oldGid] then groupMembers[oldGid][accName] = nil end
    end
    dbExec(db, "INSERT INTO members (group_id, account, rank, joined_at) VALUES (?, ?, ?, ?)", gid, accName, rank, now)
    membership[accName] = {gid = gid, rank = rank, joined = now, seen = now}
    groupMembers[gid][accName] = rank
    local online = buildOnlineMap()
    local p = online[accName]
    if p then setElementData(p, "Clan", g.name) end
    if oldGid then pushClan(oldGid) end
    pushClan(gid)
    if oldGid and oldGid ~= gid then pushGroupDelta(oldGid) end -- old clan count changed
    pushGroupDelta(gid)
    return true, "'" .. accName .. "' added to '" .. g.name .. "' as " .. prettyRank(rank) .. "."
end

-- ================= exports declared in meta.xml =================
-- Real clan turf color from RAM cache (used by turf module for radar color).
function getGroupTurfColor(player)
    if not isElement(player) then return 255, 255, 255 end
    local acc = getPlayerAccount(player)
    if not acc or isGuestAccount(acc) then return 255, 255, 255 end
    local m = membership[getAccountName(acc)]
    local g = m and groups[m.gid]
    if not g then return 255, 255, 255 end
    return g.r or 255, g.g or 255, g.b or 255
end

-- Clan color by name (used by turf module for the HUD gang color).
function getClanColor(clanName)
    if type(clanName) ~= "string" then return 255, 255, 255 end
    local gid = groupByName[clanName]
    local g = gid and groups[gid]
    if not g then return 255, 255, 255 end
    return g.r or 255, g.g or 255, g.b or 255
end

-- ================= stub exports declared in meta.xml =================

function getGroupChatColor(player)
    return 255, 255, 255
end

function getGroupChatTagColor(player)
    return 0, 128, 255
end

function getGroupTurfPoints(player)
    return 0
end

function setGroupTurfPoints(player, points)
    return false
end

function isAccountBlocked(accountName)
    return false
end

function isSerialBlocked(serial)
    return false
end
