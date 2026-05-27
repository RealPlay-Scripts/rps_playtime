--[[
    GSRP Playtime Tracker v2.1 - Heartbeat System

    Sends a heartbeat every 30 seconds to the web API with all online players.
    The web server handles ALL session logic. No MySQL needed here.

    SETUP:
    1. Set API_URL to your web server address
    2. Set API_KEY to match FIVEM_API_KEY in your .env
    3. ensure cfrp_playtime in server.cfg
]]

-- ===== CONFIG =====
local API_URL = "https://web.goldenshoresrp.com/api/server/heartbeat"
local API_KEY = "9f86a916e2fa51e6a801451a1e621813a1b3294889adaf994ac9b2d861ffa73d"
local INTERVAL = 30  -- seconds between heartbeats

-- ===== HELPER =====
local function GetPlayerDiscordId(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, "discord:") then
            return string.gsub(id, "discord:", "")
        end
    end
    return nil
end

local function SendToAPI(url, body, callback)
    PerformHttpRequest(url, function(code, text, headers)
        if callback then callback(code, text) end
    end, 'POST', json.encode(body), {
        ['Content-Type'] = 'application/json',
        ['X-API-Key'] = API_KEY
    })
end

-- ===== HEARTBEAT LOOP =====
Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Wait for server to be ready

    while true do
        local players = {}

        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            local discordId = GetPlayerDiscordId(src)

            if discordId then
                local cash, bank = 0, 0
                local px, py, pz = 0, 0, 0

                -- Try to get money from any supported framework
                pcall(function()
                    -- QBX / QBCore
                    local player = nil
                    if GetResourceState('qbx_core') == 'started' then
                        player = exports['qbx_core']:GetPlayer(src)
                    elseif GetResourceState('qb-core') == 'started' then
                        local QBCore = exports['qb-core']:GetCoreObject()
                        player = QBCore.Functions.GetPlayer(src)
                    end
                    if player and player.PlayerData and player.PlayerData.money then
                        cash = player.PlayerData.money.cash or 0
                        bank = player.PlayerData.money.bank or 0
                    end
                end)

                pcall(function()
                    -- ESX fallback
                    if cash == 0 and GetResourceState('es_extended') == 'started' then
                        local ESX = exports['es_extended']:getSharedObject()
                        local xPlayer = ESX.GetPlayerFromId(src)
                        if xPlayer then
                            cash = xPlayer.getMoney() or 0
                            bank = xPlayer.getAccount('bank') and xPlayer.getAccount('bank').money or 0
                        end
                    end
                end)

                pcall(function()
                    local ped = GetPlayerPed(src)
                    if ped and ped ~= 0 then
                        local coords = GetEntityCoords(ped)
                        px = math.floor(coords.x or 0)
                        py = math.floor(coords.y or 0)
                        pz = math.floor(coords.z or 0)
                    end
                end)

                table.insert(players, {
                    discord_id = discordId,
                    name       = GetPlayerName(src) or "Unknown",
                    cash       = cash,
                    bank       = bank,
                    x          = px,
                    y          = py,
                    z          = pz,
                    ping       = GetPlayerPing(src) or 0,
                })
            end
        end

        SendToAPI(API_URL, { players = players }, function(code, text)
            if code == 200 then
                print(("[GSRP Playtime] Heartbeat OK — %d player(s) tracked"):format(#players))
            else
                print(("[GSRP Playtime] Heartbeat FAILED — HTTP %s | %s"):format(tostring(code), tostring(text):sub(1, 80)))
            end
        end)

        Citizen.Wait(INTERVAL * 1000)
    end
end)

print("[GSRP Playtime] Heartbeat system started — " .. API_URL)

-- ===== DISCONNECT TRACKING =====
local DISCONNECT_URL = API_URL:gsub("/heartbeat$", "/disconnect")

AddEventHandler('playerDropped', function(reason)
    local src        = source
    local discordId  = GetPlayerDiscordId(src)
    local playerName = GetPlayerName(src) or "Unknown"

    if not discordId then return end

    local cleanReason = (reason or "Unknown"):match("^%s*(.-)%s*$") or "Unknown"
    local lower        = cleanReason:lower()
    local category     = "unknown"

    if     lower:find("exiting")    or lower:find("quit")         then category = "quit"
    elseif lower:find("kicked")                                   then category = "kicked"
    elseif lower:find("banned")                                   then category = "banned"
    elseif lower:find("timed out") or lower:find("timeout")       then category = "timeout"
    elseif lower:find("connection") or lower:find("reliable")
        or lower:find("network")                                  then category = "connection"
    elseif lower:find("crash")     or lower:find("fatal")
        or lower:find("error")                                    then category = "crash"
    elseif lower:find("server shut") or lower:find("resource")
        or lower:find("restart")                                  then category = "server"
    elseif lower:find("entering")  or lower:find("new server")   then category = "switch"
    elseif lower:find("disconnected")                             then category = "quit"
    end

    local px, py, pz, ping = 0, 0, 0, 0
    pcall(function()
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            px = math.floor(coords.x or 0)
            py = math.floor(coords.y or 0)
            pz = math.floor(coords.z or 0)
        end
        ping = GetPlayerPing(src) or 0
    end)

    print(("[GSRP Playtime] DROPPED: %s (%s) — [%s] %s"):format(playerName, discordId, category, cleanReason))

    SendToAPI(DISCONNECT_URL, {
        discord_id = discordId,
        name       = playerName,
        reason     = cleanReason,
        category   = category,
        x          = px,
        y          = py,
        z          = pz,
        ping       = ping,
    }, function(code)
        if code == 200 then
            print(("[GSRP Playtime] Disconnect logged for %s"):format(playerName))
        else
            print(("[GSRP Playtime] Disconnect log FAILED — HTTP %s"):format(tostring(code)))
        end
    end)
end)
