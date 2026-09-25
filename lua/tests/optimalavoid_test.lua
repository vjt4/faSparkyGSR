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

auto_run_unit_tests()
