--*****************************************************************************
--* Copyright © 2026 FAForever
--*
--* Pure data helpers for the Optimal Avoid lobby team balancer.
--* This module deliberately has no dependency on lobby state or preferences.
--*****************************************************************************

---@class OptimalAvoidPlayer
---@field position number
---@field rating number
---@field playerName string
---@field isHost boolean
---@field isAvoided boolean

---Creates the player data consumed by the Optimal Avoid balancer.
---@param playerOptions table<number, PlayerData>
---@param hostOwnerID number
---@param avoidedPlayers string[]
---@return OptimalAvoidPlayer[]
function CreatePlayerData(playerOptions, hostOwnerID, avoidedPlayers)
    local avoidedSet = {}
    if type(avoidedPlayers) == 'table' then
        for _, playerName in pairs(avoidedPlayers) do
            if type(playerName) == 'string' then
                avoidedSet[playerName] = true
            end
        end
    end

    local players = {}
    for position, playerInfo in pairs(playerOptions) do
        local playerName = playerInfo.PlayerName or ''
        table.insert(players, {
            position = position,
            rating = (playerInfo.MEAN or 1500) - (playerInfo.DEV or 500) * 3,
            playerName = playerName,
            isHost = playerInfo.OwnerID == hostOwnerID,
            isAvoided = playerInfo.Human and avoidedSet[playerName] == true or false,
        })
    end

    table.sort(players, function(a, b)
        return a.position < b.position
    end)

    return players
end

---Finds the host in an Optimal Avoid player list.
---@param players OptimalAvoidPlayer[]
---@return OptimalAvoidPlayer?
function FindHost(players)
    for _, player in pairs(players) do
        if player.isHost then
            return player
        end
    end

    return nil
end

---Counts avoided players assigned to the host's team.
---@param setup table[]
---@param players OptimalAvoidPlayer[]
---@return number? violations
---@return string? errorReason
function CountViolations(setup, players)
    local playersByPosition = {}
    local hostPosition

    for _, player in pairs(players) do
        playersByPosition[player.position] = player
        if player.isHost then
            hostPosition = player.position
        end
    end

    if not hostPosition then
        return nil, 'host-not-found'
    end

    local hostTeam
    for _, assignment in pairs(setup) do
        if assignment.player == hostPosition then
            hostTeam = assignment.team
            break
        end
    end

    if hostTeam == nil then
        return nil, 'host-not-assigned'
    end

    local violations = 0
    for _, assignment in pairs(setup) do
        local player = playersByPosition[assignment.player]
        if player and not player.isHost and player.isAvoided and assignment.team == hostTeam then
            violations = violations + 1
        end
    end

    return violations, nil
end

---Checks whether a slot layout is supported by the first Optimal Avoid implementation.
---@param teams table<number, number[]>
---@return boolean supported
---@return string? errorReason
---@return number? teamSize
function IsTwoTeamSetupSupported(teams)
    local teamCount = 0
    local teamSize

    for _, slots in pairs(teams) do
        teamCount = teamCount + 1
        local size = table.getn(slots)

        if size == 0 then
            return false, 'empty-team', nil
        end

        if teamSize and size ~= teamSize then
            return false, 'unequal-team-sizes', nil
        end

        teamSize = size
    end

    if teamCount ~= 2 then
        return false, 'requires-two-teams', nil
    end

    return true, nil, teamSize
end
