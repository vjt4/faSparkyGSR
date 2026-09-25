string.match = string.match or string.find
debug.allocatedsize = debug.allocatedsize or function() return 0 end

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

local function ExpectTeam(team, expected)
    expect_equal(table.getn(team), table.getn(expected))
    for index = 1, table.getn(expected) do
        expect_equal(team[index], expected[index])
    end
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

function test_build_shortlists_scores_and_buckets_candidates()
    local players = {
        { position = 1, rating = 100, isHost = true, isAvoided = false },
        { position = 2, rating = 90, isHost = false, isAvoided = true },
        { position = 3, rating = 60, isHost = false, isAvoided = false },
        { position = 4, rating = 50, isHost = false, isAvoided = true },
    }

    local shortlists, combinationCount, reason = BuildShortlists(players, 2, 10)
    expect_equal(combinationCount, 3)
    expect_equal(reason, nil)

    expect_equal(table.getn(shortlists[0]), 1)
    ExpectTeam(shortlists[0][1].hostTeam, { 1, 3 })
    expect_equal(shortlists[0][1].ratingDifference, 20)

    expect_equal(table.getn(shortlists[1]), 2)
    ExpectTeam(shortlists[1][1].hostTeam, { 1, 4 })
    expect_equal(shortlists[1][1].ratingDifference, 0)
    ExpectTeam(shortlists[1][2].hostTeam, { 1, 2 })
    expect_equal(shortlists[1][2].ratingDifference, 80)
end

function test_build_shortlists_enforces_each_bucket_limit()
    local players = {
        { position = 1, rating = 100, isHost = true, isAvoided = false },
        { position = 2, rating = 90, isHost = false, isAvoided = true },
        { position = 3, rating = 60, isHost = false, isAvoided = false },
        { position = 4, rating = 50, isHost = false, isAvoided = true },
    }

    local shortlists = BuildShortlists(players, 2, 1)
    expect_equal(table.getn(shortlists[0]), 1)
    expect_equal(table.getn(shortlists[1]), 1)
    ExpectTeam(shortlists[1][1].hostTeam, { 1, 4 })
end

function test_build_shortlists_empty_and_complete_avoid_lists()
    local players = MakePlayers(4, 1)
    for index, player in pairs(players) do
        player.rating = 100 - index
    end

    local shortlists = BuildShortlists(players, 2, 10)
    expect_equal(table.getn(shortlists[0]), 3)
    expect_equal(shortlists[1], nil)

    for index = 2, 4 do
        players[index].isAvoided = true
    end

    shortlists = BuildShortlists(players, 2, 10)
    expect_equal(shortlists[0], nil)
    expect_equal(table.getn(shortlists[1]), 3)
end

function test_build_shortlists_bounds_eight_v_eight_output()
    local players = MakePlayers(16, 16)
    for index, player in pairs(players) do
        player.rating = 2000 - index * 50
        player.isAvoided = math.mod(index, 2) == 0 and not player.isHost
    end

    local shortlists, combinationCount, reason = BuildShortlists(players, 8, 50)
    expect_equal(combinationCount, 6435)
    expect_equal(reason, nil)

    local shortlistedCount = 0
    for _, bucket in pairs(shortlists) do
        assert(table.getn(bucket) <= 50)
        shortlistedCount = shortlistedCount + table.getn(bucket)
    end

    assert(shortlistedCount <= 400)
end

function test_build_shortlists_uses_deterministic_tie_breaker()
    local players = {
        { position = 1, rating = 100, isHost = true, isAvoided = false },
        { position = 2, rating = 100, isHost = false, isAvoided = false },
        { position = 3, rating = 100, isHost = false, isAvoided = false },
        { position = 4, rating = 100, isHost = false, isAvoided = false },
    }

    local shortlists = BuildShortlists(players, 2, 2)
    ExpectTeam(shortlists[0][1].hostTeam, { 1, 2 })
    ExpectTeam(shortlists[0][2].hostTeam, { 1, 3 })
end

function test_build_shortlists_validates_limit()
    local shortlists, combinationCount, reason = BuildShortlists(MakePlayers(4, 1), 2, 0)
    expect_equal(shortlists, nil)
    expect_equal(combinationCount, nil)
    expect_equal(reason, 'invalid-shortlist-limit')
end

auto_run_unit_tests()
