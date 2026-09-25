string.match = string.match or string.find

require '../tests/testutils.lua'
require '../ui/lobby/optimalavoid.lua'

function test_create_player_data()
    local players = CreatePlayerData({
        [3] = { PlayerName = 'Host', OwnerID = 10, Human = true, MEAN = 1600, DEV = 100 },
        [1] = { PlayerName = 'Avoided', OwnerID = 20, Human = true, MEAN = 1500, DEV = 200 },
        [2] = { PlayerName = 'AI', OwnerID = 30, Human = false, MEAN = 1400, DEV = 0 },
    }, 10, { 'Avoided', 'AI' })

    expect_equal(table.getn(players), 3)
    expect_equal(players[1].position, 1)
    expect_equal(players[1].rating, 900)
    expect_equal(players[1].isAvoided, true)
    expect_equal(players[2].position, 2)
    expect_equal(players[2].isAvoided, false)
    expect_equal(players[3].position, 3)
    expect_equal(players[3].isHost, true)
end

function test_create_player_data_defaults_and_exact_case()
    local players = CreatePlayerData({
        [1] = { PlayerName = 'PlayerOne', OwnerID = 10, Human = true },
    }, 20, { 'playerone' })

    expect_equal(players[1].rating, 0)
    expect_equal(players[1].isHost, false)
    expect_equal(players[1].isAvoided, false)
end

function test_find_host()
    local host = FindHost({
        { position = 1, isHost = false },
        { position = 2, isHost = true },
    })

    expect_equal(host.position, 2)
    expect_equal(FindHost({ { position = 1, isHost = false } }), nil)
end

function test_count_violations()
    local players = {
        { position = 1, isHost = true, isAvoided = true },
        { position = 2, isHost = false, isAvoided = true },
        { position = 3, isHost = false, isAvoided = true },
        { position = 4, isHost = false, isAvoided = false },
    }
    local setup = {
        { player = 1, team = 2 },
        { player = 2, team = 2 },
        { player = 3, team = 3 },
        { player = 4, team = 2 },
    }

    local violations, reason = CountViolations(setup, players)
    expect_equal(violations, 1)
    expect_equal(reason, nil)
end

function test_count_violations_requires_host()
    local violations, reason = CountViolations({}, {
        { position = 1, isHost = false, isAvoided = true },
    })

    expect_equal(violations, nil)
    expect_equal(reason, 'host-not-found')
end

function test_count_violations_requires_host_assignment()
    local violations, reason = CountViolations({}, {
        { position = 1, isHost = true, isAvoided = false },
    })

    expect_equal(violations, nil)
    expect_equal(reason, 'host-not-assigned')
end

function test_supported_two_team_setup()
    local supported, reason, teamSize = IsTwoTeamSetupSupported({
        [2] = { 1, 3, 5, 7 },
        [3] = { 2, 4, 6, 8 },
    })

    expect_equal(supported, true)
    expect_equal(reason, nil)
    expect_equal(teamSize, 4)
end

function test_unsupported_team_setups()
    local supported, reason = IsTwoTeamSetupSupported({
        [2] = { 1, 3 },
        [3] = { 2 },
    })
    expect_equal(supported, false)
    expect_equal(reason, 'unequal-team-sizes')

    supported, reason = IsTwoTeamSetupSupported({
        [2] = { 1 },
        [3] = { 2 },
        [4] = { 3 },
    })
    expect_equal(supported, false)
    expect_equal(reason, 'requires-two-teams')
end

local function MakePlayers(playerCount, hostIndex)
    local players = {}
    for index = 1, playerCount do
        table.insert(players, {
            position = index,
            isHost = index == hostIndex,
            isAvoided = false,
        })
    end

    return players
end

function test_enumerate_host_team_combination_counts()
    local cases = {
        { players = 2, teamSize = 1, combinations = 1 },
        { players = 4, teamSize = 2, combinations = 3 },
        { players = 6, teamSize = 3, combinations = 10 },
        { players = 8, teamSize = 4, combinations = 35 },
        { players = 10, teamSize = 5, combinations = 126 },
        { players = 12, teamSize = 6, combinations = 462 },
        { players = 14, teamSize = 7, combinations = 1716 },
        { players = 16, teamSize = 8, combinations = 6435 },
    }

    for _, case in pairs(cases) do
        local callbackCount = 0
        local combinationCount, reason = EnumerateHostTeams(
            MakePlayers(case.players, case.players),
            case.teamSize,
            function()
                callbackCount = callbackCount + 1
            end
        )

        expect_equal(combinationCount, case.combinations)
        expect_equal(callbackCount, case.combinations)
        expect_equal(reason, nil)
    end
end

function test_enumerate_host_teams_are_unique_and_complete()
    local players = MakePlayers(8, 5)
    local seen = {}
    local playerOccurrences = {}
    local hostOccurrences = 0

    local combinationCount, reason = EnumerateHostTeams(players, 4, function(hostTeam)
        expect_equal(table.getn(hostTeam), 4)
        expect_equal(hostTeam[1], 5)

        local identity = {}
        for _, playerIndex in pairs(hostTeam) do
            table.insert(identity, playerIndex)
            playerOccurrences[playerIndex] = (playerOccurrences[playerIndex] or 0) + 1
            if playerIndex == 5 then
                hostOccurrences = hostOccurrences + 1
            end
        end
        table.sort(identity)

        local key = table.concat(identity, ',')
        expect_equal(seen[key], nil)
        seen[key] = true
    end)

    expect_equal(combinationCount, 35)
    expect_equal(reason, nil)
    expect_equal(hostOccurrences, 35)
    for playerIndex = 1, 8 do
        if playerIndex ~= 5 then
            expect_equal(playerOccurrences[playerIndex], 15)
        end
    end
end

function test_enumerate_host_teams_validates_input()
    local count, reason = EnumerateHostTeams(MakePlayers(4, 1), 0, function() end)
    expect_equal(count, nil)
    expect_equal(reason, 'invalid-team-size')

    count, reason = EnumerateHostTeams(MakePlayers(4, 1), 2, nil)
    expect_equal(count, nil)
    expect_equal(reason, 'callback-required')

    count, reason = EnumerateHostTeams(MakePlayers(4, 5), 2, function() end)
    expect_equal(count, nil)
    expect_equal(reason, 'host-not-found')

    local players = MakePlayers(4, 1)
    players[2].isHost = true
    count, reason = EnumerateHostTeams(players, 2, function() end)
    expect_equal(count, nil)
    expect_equal(reason, 'multiple-hosts')
end

auto_run_unit_tests()
