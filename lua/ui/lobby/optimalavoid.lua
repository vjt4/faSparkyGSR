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

---Enumerates every possible host-team composition exactly once.
---Each composition contains indices into `players`, with the host index first.
---The callback must not mutate the supplied player list.
---@param players OptimalAvoidPlayer[]
---@param teamSize number
---@param callback fun(hostTeam: number[])
---@return number? combinationCount
---@return string? errorReason
function EnumerateHostTeams(players, teamSize, callback)
    if type(callback) ~= 'function' then
        return nil, 'callback-required'
    end

    local playerCount = table.getn(players)
    if type(teamSize) ~= 'number' or teamSize < 1 or teamSize > playerCount or teamSize ~= math.floor(teamSize) then
        return nil, 'invalid-team-size'
    end

    local hostIndex
    for index = 1, playerCount do
        local player = players[index]
        if player.isHost then
            if hostIndex then
                return nil, 'multiple-hosts'
            end
            hostIndex = index
        end
    end

    if not hostIndex then
        return nil, 'host-not-found'
    end

    local candidates = {}
    for index = 1, playerCount do
        if index ~= hostIndex then
            table.insert(candidates, index)
        end
    end

    local selected = { hostIndex }
    local combinationCount = 0
    local teammatesNeeded = teamSize - 1

    local function emitCombination()
        local hostTeam = {}
        for index = 1, table.getn(selected) do
            hostTeam[index] = selected[index]
        end

        callback(hostTeam)
        combinationCount = combinationCount + 1
    end

    local function choose(candidateStart, remaining)
        if remaining == 0 then
            emitCombination()
            return
        end

        local lastCandidate = table.getn(candidates) - remaining + 1
        for candidateIndex = candidateStart, lastCandidate do
            table.insert(selected, candidates[candidateIndex])
            choose(candidateIndex + 1, remaining - 1)
            table.remove(selected)
        end
    end

    choose(1, teammatesNeeded)

    return combinationCount, nil
end

---Compares candidates using only deterministic, inexpensive values.
---@param candidateA table
---@param candidateB table
---@return boolean
local function IsCheapCandidateBetter(candidateA, candidateB)
    if candidateA.ratingDifference ~= candidateB.ratingDifference then
        return candidateA.ratingDifference < candidateB.ratingDifference
    end

    for index = 1, table.getn(candidateA.hostTeam) do
        local playerA = candidateA.hostTeam[index]
        local playerB = candidateB.hostTeam[index]
        if playerA ~= playerB then
            return playerA < playerB
        end
    end

    return false
end

---Inserts a candidate into its sorted, bounded violation bucket.
---@param shortlists table<number, table[]>
---@param candidate table
---@param limitPerViolation number
local function InsertShortlistCandidate(shortlists, candidate, limitPerViolation)
    local bucket = shortlists[candidate.avoidViolations]
    if not bucket then
        bucket = {}
        shortlists[candidate.avoidViolations] = bucket
    end

    local insertAt = table.getn(bucket) + 1
    for index, existingCandidate in pairs(bucket) do
        if IsCheapCandidateBetter(candidate, existingCandidate) then
            insertAt = index
            break
        end
    end

    table.insert(bucket, insertAt, candidate)
    if table.getn(bucket) > limitPerViolation then
        table.remove(bucket)
    end
end

---Enumerates and shortlists team compositions using inexpensive rating sums.
---The returned table is indexed by the number of avoided players on the host's team.
---@param players OptimalAvoidPlayer[]
---@param teamSize number
---@param limitPerViolation number
---@return table<number, table[]>? shortlists
---@return number? combinationCount
---@return string? errorReason
function BuildShortlists(players, teamSize, limitPerViolation)
    if type(limitPerViolation) ~= 'number'
        or limitPerViolation < 1
        or limitPerViolation ~= math.floor(limitPerViolation)
    then
        return nil, nil, 'invalid-shortlist-limit'
    end

    local totalRating = 0
    for _, player in pairs(players) do
        totalRating = totalRating + player.rating
    end

    local shortlists = {}
    local combinationCount, errorReason = EnumerateHostTeams(players, teamSize, function(hostTeam)
        local hostTeamRating = 0
        local avoidViolations = 0

        for _, playerIndex in pairs(hostTeam) do
            local player = players[playerIndex]
            hostTeamRating = hostTeamRating + player.rating
            if not player.isHost and player.isAvoided then
                avoidViolations = avoidViolations + 1
            end
        end

        InsertShortlistCandidate(shortlists, {
            hostTeam = hostTeam,
            avoidViolations = avoidViolations,
            ratingDifference = math.abs(hostTeamRating - (totalRating - hostTeamRating)),
        }, limitPerViolation)
    end)

    if not combinationCount then
        return nil, nil, errorReason
    end

    return shortlists, combinationCount, nil
end

---Compares candidates after full quality scoring.
---@param candidateA table
---@param candidateB table
---@return boolean
local function IsQualityCandidateBetter(candidateA, candidateB)
    if candidateA.avoidViolations ~= candidateB.avoidViolations then
        return candidateA.avoidViolations < candidateB.avoidViolations
    end

    if candidateA.quality ~= candidateB.quality then
        return candidateA.quality > candidateB.quality
    end

    return IsCheapCandidateBetter(candidateA, candidateB)
end

---Selects the best shortlisted candidate within five percentage points of baseline quality.
---@param shortlists table<number, table[]>
---@param baselineQuality number
---@param qualityFunction fun(candidate: table): number
---@return table? bestCandidate
---@return number? minimumQuality
---@return string? errorReason
function SelectBest(shortlists, baselineQuality, qualityFunction)
    if type(shortlists) ~= 'table' then
        return nil, nil, 'invalid-shortlists'
    end

    if type(baselineQuality) ~= 'number' then
        return nil, nil, 'invalid-baseline-quality'
    end

    if type(qualityFunction) ~= 'function' then
        return nil, nil, 'quality-function-required'
    end

    local minimumQuality = math.max(0, baselineQuality - 5)
    local bestCandidate

    for _, bucket in pairs(shortlists) do
        for _, candidate in pairs(bucket) do
            local quality = qualityFunction(candidate)
            if type(quality) ~= 'number' then
                return nil, minimumQuality, 'invalid-candidate-quality'
            end

            if quality >= minimumQuality then
                local scoredCandidate = {
                    hostTeam = candidate.hostTeam,
                    avoidViolations = candidate.avoidViolations,
                    ratingDifference = candidate.ratingDifference,
                    quality = quality,
                }

                if not bestCandidate or IsQualityCandidateBetter(scoredCandidate, bestCandidate) then
                    bestCandidate = scoredCandidate
                end
            end
        end
    end

    if not bestCandidate then
        return nil, minimumQuality, 'no-eligible-candidate'
    end

    return bestCandidate, minimumQuality, nil
end
