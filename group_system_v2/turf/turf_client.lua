-- ecma Group System v2 - Turf module (client)
-- Zone HUD: translucent box under the main HUD (top-right), responsive.
-- Server pushes turf:zoneInfo on colshape enter/leave (no polling).

local zoneInfo = nil -- {gang, loyalty, money} while inside a zone, nil outside

-- same scale system as the HUD resource (design base 1920x1080)
local function getHUDScale()
    local sw, sh = guiGetScreenSize()
    return math.max(0.55, math.min(sw / 1920, sh / 1080))
end

addEvent("turf:zoneInfo", true)
addEventHandler("turf:zoneInfo", resourceRoot, function(info)
    if info and type(info) == "table" then
        zoneInfo = info
    else
        zoneInfo = nil -- left the zone
    end
end)

-- cleanup if the resource stops while standing inside a zone
addEventHandler("onClientResourceStop", resourceRoot, function()
    zoneInfo = nil
end)

addEventHandler("onClientRender", root, function()
    if not zoneInfo then return end
    local sw, sh = guiGetScreenSize()
    local S = getHUDScale()

    -- HUD box occupies top-right: 560x244, right edge at sw-20*S,
    -- its FPS/PING line ends around y = ~306*S. We sit just below it.
    local bw, bh = 340 * S, 120 * S
    local bx = sw - bw - 20 * S   -- same right margin as the HUD
    local by = 320 * S            -- just under HUD + FPS/PING line

    -- subtle translucent backdrop (readable on any map)
    dxDrawRectangle(bx, by, bw, bh, tocolor(0, 0, 0, 100))

    -- white text rows: label left, value in its own column
    local pad = 16 * S
    local lh = 30 * S
    local valX = bx + 150 * S -- values column
    local ty = by + 12 * S
    dxDrawText("Clan:",
        bx + pad, ty, valX, ty + lh,
        tocolor(255, 255, 255, 255), 1.4 * S, "default-bold", "left", "center", true)
    dxDrawText(zoneInfo.gang or "N/A",
        valX, ty, bx + bw - pad, ty + lh,
        tocolor(zoneInfo.cr or 255, zoneInfo.cg or 255, zoneInfo.cb or 255, 255), 1.4 * S, "default-bold", "left", "center", true)
    ty = ty + lh + 6 * S
    dxDrawText("Loyalty:",
        bx + pad, ty, valX, ty + lh,
        tocolor(255, 255, 255, 255), 1.4 * S, "default-bold", "left", "center", true)
    dxDrawText("%" .. tostring(zoneInfo.loyalty or 0),
        valX, ty, bx + bw - pad, ty + lh,
        tocolor(255, 255, 255, 255), 1.4 * S, "default-bold", "left", "center", true)
    ty = ty + lh + 6 * S
    dxDrawText("Money:",
        bx + pad, ty, valX, ty + lh,
        tocolor(255, 255, 255, 255), 1.4 * S, "default-bold", "left", "center", true)
    dxDrawText("$" .. tostring(zoneInfo.money or 0),
        valX, ty, bx + bw - pad, ty + lh,
        tocolor(255, 255, 255, 255), 1.4 * S, "default-bold", "left", "center", true)
end)
