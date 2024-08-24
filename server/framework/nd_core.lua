local officers = require 'server.officers'

local function addOfficer(playerId)
    if officers.get(playerId) then return end

    local player = exports["ND_Core"]:getPlayer(playerId)
    if player and player.job == 'lspd' or 'bcso' or 'swat' or 'sahp' then
        officers.add(playerId, player.firstname, player.lastname, player.id)
        MySQL.prepare.await('INSERT INTO `mdt_profiles` (`citizenid`, `image`, `notes`, `lastActive`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `lastActive` = NOW()', { player.PlayerData.citizenid, nil, nil })
    end
end

CreateThread(function()
    for _, playerId in pairs(GetPlayers()) do
        addOfficer(tonumber(playerId))
    end
end)

RegisterNetEvent('ND:characterLoaded', function()
    addOfficer(source)
end)

AddEventHandler("ND:updateCharacter", function(character)
    local officer = officers.get(source)

    if officer then
        if character.job ~= 'lspd' or 'bcso' or 'swat' or 'sahp' then
            return officers.remove(character.source)
        end
        return
    end
    addOfficer(source)
end)

RegisterNetEvent('ND:characterUnloaded', function(source, character)
    local officer = officers.get(source)

    if officer then
        officers.remove(source)
    end
end)

local nd = {}

-- Dashboard
function nd.getAnnouncements()
    local announcements = MySQL.rawExecute.await([[
        SELECT
            a.id,
            a.contents,
            a.creator AS citizenid,
            b.charinfo,
            c.image,
            DATE_FORMAT(a.createdAt, "%Y-%m-%d %T") AS createdAt
        FROM
            `mdt_announcements` a
        LEFT JOIN
            `players` b
        ON
            b.citizenid = a.creator
        LEFT JOIN
            `mdt_profiles` c
        ON
            c.citizenid = a.creator
    ]])
    local result = {}
    for i = 1, #announcements do
        local charinfo = json.decode(announcements[i].charinfo)
        table.insert(result, { 
            id = announcements[i].id, 
            contents = announcements[i].contents,
            citizenid = announcements[i].citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            image = announcements[i].image,
            createdAt = announcements[i].createdAt
        })
    end

    return result
end

local selectWarrants = [[
    SELECT
        warrants.incidentid,
        players.citizenid,
        players.charinfo,
        DATE_FORMAT(warrants.expiresAt, "%Y-%m-%d %T") AS expiresAt,
        c.image
    FROM
        `mdt_warrants` warrants
    LEFT JOIN
        `players`
    ON
        warrants.citizenid = players.citizenid
    LEFT JOIN
        `mdt_profiles` c
    ON
        c.citizenid = players.citizenid
]]

function nd.getWarrants()
    local queryResult = MySQL.rawExecute.await(selectWarrants, {})
    local warrants = {}

    for _, v in pairs(queryResult) do
        local charinfo = json.decode(v.charinfo)
        warrants[#warrants+1] = {
            incidentid = v.incidentid,
            citizenid = v.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            expiresAt = v.expiresAt,
            image = v.image
        }
    end

    return warrants
end

function nd.getCharacterProfile(parameters)
    local result = MySQL.rawExecute.await([[
        SELECT
            a.charinfo,
            a.metadata,
            a.citizenid,
            b.image,
            b.notes,
            b.fingerprint
        FROM
            `players` a
        LEFT JOIN
            `mdt_profiles` b
        ON
            b.citizenid = a.citizenid
        WHERE
            a.citizenid = ?
    ]], parameters)?[1]
    local profile

    if result then
        local charinfo = json.decode(result.charinfo)
        local metadata = json.decode(result.metadata)

        profile = {
            citizenid = result.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            dob = charinfo.birthdate,
            phoneNumber = '', -- Get phone number, example: exports["lb-phone"]:GetEquippedPhoneNumber(result.citizenid)
            fingerprint = result.fingerprint or 'Unknown',
            notes = result.notes,
            image = result.image,
        }
    end

    return profile
end

-- Profiles
local selectProfiles = [[
    SELECT
        nd_characters.charid,
        nd_characters.firstname,
        nd_characters.lastname,
        nd_characters.dob,
        profile.image
    FROM
        nd_characters
    LEFT JOIN
        mdt_profiles profile
    ON
        profile.citizenid = players.charid
]]

function nd.getAllProfiles()
    local profilesResult = MySQL.rawExecute.await(selectProfiles, {})
    local profiles = {}

    for _, v in pairs(profilesResult) do
        profiles[#profiles+1] = {
            citizenid = v.charid,
            firstname = v.firstname,
            lastname = v.lastname,
            dob = v.dob,
            image = v.image,
        }
    end

    return profiles
end

function nd.getDriverPoints(citizenid)
    local result = MySQL.rawExecute.await('SELECT SUM(COALESCE(points, 0) * COALESCE(count, 1)) AS total_points FROM mdt_incidents_charges WHERE citizenid = ?', { citizenid })?[1]
    if (result.total_points) then return result.total_points end

    return 0
end

function nd.isProfileWanted(citizenid)
    local response = MySQL.rawExecute.await('SELECT * FROM `mdt_warrants` WHERE `citizenid` = ?', {
        citizenid
    })
    
    return response[1] and true or false
end

function nd.getVehiclesForProfile(parameters)
    local vehicles = MySQL.rawExecute.await('SELECT `plate`, `vehicle` FROM `nd_vehicles` WHERE `owner` = ?', parameters) or {}
    return vehicles
end

function nd.getLicenses(id)
    local result = MySQL.rawExecute.await([[
    SELECT
        metadata
    FROM
        nd_characters
    WHERE
        charid = ?
    ]], { id })?[1]
    local metadata = json.decode(result.metadata)
    return metadata.licences
end

function nd.getJobs(parameters)
    local result = MySQL.rawExecute.await([[
        SELECT
            groups
        FROM
            nd_characters
        WHERE
            charid = ?
    ]], parameters)?[1]
    local job = json.decode(result.job)
    local jobs = {}

    table.insert(jobs, { job = job, gradeLabel = job.rankName })
    return jobs
end

-- Still needs implementation
function nd.getProperties(parameters)
    local properties = {}

    return properties
end

function nd.getOfficersInvolved(parameters)
    local queryResult = MySQL.rawExecute.await([[
        SELECT
            nd_characters.charid,
            nd_characters.firstname,
            nd_characters.lastname,
            nd_characters.dob,
            profile.callSign
        FROM
            mdt_incidents_officers officer
        LEFT JOIN
            nd_characters
        ON
            nd_characters.charid = officer.citizenid
        LEFT JOIN
            mdt_profiles profile
        ON 
            nd_characters.charid = profile.citizenid
        WHERE
            incidentid = ?
    ]], parameters)

    local officers = {}

    for _, v in pairs(queryResult) do
        local charinfo = json.decode(v.charinfo)
        officers[#officers+1] = {
            citizenid = v.charid,
            firstname = v.firstname,
            lastname = v.lastname,
            callsign = v.callSign,
        }
    end

    return officers
end

function nd.getOfficersInvolvedReport(parameters)
    local queryResult = MySQL.rawExecute.await([[
        SELECT
            nd_characters.charid,
            nd_characters.firstname,
            nd_characters.lastname,
            profile.callSign
        FROM
            mdt_reports_officers officer
        LEFT JOIN
            nd_characters
        ON
            nd_characters.charid = officer.citizenid
        LEFT JOIN
            mdt_profiles profile
        ON 
            nd_characters.charid = profile.citizenid
        WHERE
            reportid = ?
    ]], parameters)

    local officers = {}

    for _, v in pairs(queryResult) do
        local charinfo = json.decode(v.charinfo)
        officers[#officers+1] = {
            citizenid = v.citizenid,
            firstname = v.firstname,
            lastname = v.lastname,
            callsign = v.callSign,
        }
    end

    return officers
end

function nd.getCitizensInvolvedReport(parameters)
    local queryResult = MySQL.rawExecute.await([[
        SELECT
            nd_characters.charid,
            nd_characters.firstname,
            nd_characters.lastname,
            nd_characters.dob
        FROM
            mdt_reports_citizens officer
        LEFT JOIN
            nd_characters
        ON
            nd_characters.charid = officer.citizenid
        LEFT JOIN
            mdt_profiles profile
        ON 
            nd_characters.charid = profile.citizenid
        WHERE
            reportid = ?
    ]], parameters)

    local citizens = {}

    for _, v in pairs(queryResult) do
        local charinfo = json.decode(v.charinfo)
        citizens[#citizens+1] = {
            firstname = v.firstname,
            lastname = v.lastname,
            citizenid = v.charid,
            dob = v.dob
        }
    end

    return citizens
end

function nd.getCriminalsInvolved(parameters)
    local queryResult = MySQL.rawExecute.await([[
        SELECT DISTINCT
            criminal.citizenid,
            criminal.reduction,
            nd_characters.charid,
            nd_characters.firstname,
            nd_characters.lastname,
            DATE_FORMAT(criminal.warrantExpiry, "%Y-%m-%d") AS warrantExpiry,
            criminal.processed,
            criminal.pleadedGuilty
        FROM
            mdt_incidents_criminals criminal
        LEFT JOIN
            nd_characters
        ON
            nd_characters.charid = criminal.citizenid
        WHERE
            incidentid = ?
    ]], parameters)

    local involvedCriminals = {}

    for _, v in pairs(queryResult) do
        local charinfo = json.decode(v.charinfo)
        involvedCriminals[#involvedCriminals+1] = {
            citizenid = v.charid,
            firstname = v.firstname,
            lastname = v.lastname,
            reduction = v.reduction,
            warrantExpiry = v.warrantExpiry,
            processed = v.processed,
            pleadedGuilty = v.pleadedGuilty
        }
    end

    return involvedCriminals
end

function nd.getCriminalCharges(parameters)
  return MySQL.rawExecute.await([[
      SELECT
          citizenid,
          charge as label,
          type,
          time,
          fine,
          count,
          points
      FROM
          mdt_incidents_charges
      WHERE
          incidentid = ?
      GROUP BY
          charge, citizenid
  ]], parameters)
end

function nd.getOfficers()
local NDCore = exports["ND_Core"]
local lspd = NDCore:getPlayers("job", "lspd", true)
local bcso = NDCore:getPlayers("job", "bcso", true)
local sahp = NDCore:getPlayers("job", "sahp", true)
local swat = NDCore:getPlayers("job", "swat", true)
    for i=1, #lspd and #bcso and #sahp and #swat do
        local officers = lspd[i] and bcso[i] and sahp[i] and swat[i]
        return officers
    end
end

local selectOfficersForRoster = [[
    SELECT
        mdt_profiles.id,
        players.charinfo,
        players.citizenid,
        player_groups.group AS `group`,
        player_groups.grade,
        mdt_profiles.image,
        mdt_profiles.callSign,
        mdt_profiles.apu,
        mdt_profiles.air,
        mdt_profiles.mc,
        mdt_profiles.k9,
        mdt_profiles.fto,
        DATE_FORMAT(mdt_profiles.lastActive, "%Y-%m-%d %T") AS formatted_lastActive
    FROM
        player_groups
    LEFT JOIN
        players
    ON
        player_groups.citizenid = players.citizenid
    LEFT JOIN
        mdt_profiles
    ON
        players.citizenid = mdt_profiles.citizenid
    WHERE
        player_groups.group IN ("police")
]]

function nd.fetchRoster()
    local query = selectOfficersForRoster
    local queryResult = MySQL.rawExecute.await(query)
    local rosterOfficers = {}
    local lspd = NDCore.getPlayers("job", "lspd", true)
    local bcso = NDCore.getPlayers("job", "bcso", true)
    local sahp = NDCore.getPlayers("job", "sahp", true)
    local swat = NDCore.getPlayers("job", "swat", true)

    local job = exports.qbx_core:GetJob('police')

    for _, v in pairs(queryResult) do
        local charinfo = json.decode(v.charinfo)
        rosterOfficers[#rosterOfficers+1] = {
            citizenid = v.citizenid,
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            callsign = v.callSign,
            image = v.image,
            title = job.grades[v.grade].name,
            apu = v.apu,
            air = v.air,
            mc = v.mc,
            k9 = v.k9,
            fto = v.fto,
            lastActive = v.formatted_lastActive
        }
    end
    return false -- rosterOfficers
end

local selectCharacters = [[
    SELECT
        charid
    FROM
        nd_characters
]]

function nd.getCharacters()
    local queryResult = MySQL.rawExecute.await(selectCharacters)
    local characters = {}

    for _, v in pairs(queryResult) do
        characters[#characters+1] = {
            citizenid = v.citizenid,
            firstname = v.firstname,
            lastname = v.lastname,
            dob = v.dob,
        }
    end
    return characters
end

local selectVehicles = [[
    SELECT
        plate
    FROM
        nd_vehicles
]]

function nd.getVehicles()
  return MySQL.rawExecute.await(selectVehicles)
end

local selectVehicle = [[
    SELECT
        nd_vehicles.owner,
        nd_vehicles.plate,
        nd_vehicles.id,
        nd_vehicles.properties,
        mdt_vehicles.notes,
        mdt_vehicles.image,
        mdt_vehicles.known_information
    FROM
        nd_vehicles
    LEFT JOIN
        mdt_vehicles
    ON
        mdt_vehicles.plate = nd_vehicles.plate
    WHERE
        nd_vehicles.plate = ?
]]

local player = [[
    SELECT
        nd_characters.charid,
    FROM
        nd_characters
    LEFT JOIN
        nd_vehicles
    ON
        nd_characters.charid = nd_vehicles.owner
    WHERE
        nd_vehicles.plate = ?
]]

function nd.getVehicle(plate)
    local response = MySQL.rawExecute.await(selectVehicle, {plate})?[1]
    local response2 = MySQL.rawExecute.await(player, {plate})?[1]
    local data = {
        plate = response.plate,
        vehicle = response.vehicle,
        mods = response.properties,
        notes = response.notes,
        image = response.image,
        known_information = response.known_information,
        owner = response2.firstname .. " " .. response2.lastname .. ' (' .. response2.charid .. ')'
    }
    return data
end

function nd.hireOfficer(data)
    local PlayerToHire = MySQL.rawExecute.await(player, {plate})?[1]
    exports.qbx_core:AddPlayerToJob(data.citizenid, 'police', 1)

    local success = MySQL.prepare.await('INSERT INTO `mdt_profiles` (`citizenid`, `callsign`, `lastActive`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `callsign` = ?, `lastActive` = ?', { data.citizenid, data.callsign, os.date("%Y-%m-%d %H:%M:%S"), data.callsign, os.date("%Y-%m-%d %H:%M:%S") })

    return success
end

function nd.fireOfficer(citizenId)
    exports.qbx_core:RemovePlayerFromJob(citizenId, 'police')
    MySQL.prepare.await('UPDATE `mdt_profiles` SET `callsign` = ? WHERE `citizenid` = ?', { nil, citizenId })

    return true
end

function nd.setOfficerRank(data)
    exports.qbx_core:AddPlayerToJob(data.citizenId, 'police', data.grade)

    return true
end


return nd