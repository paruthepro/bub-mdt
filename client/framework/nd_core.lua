local NDCore = exports['ND_Core']
local nd = {}
local officer = {}

nd.loadedEvent = 'ND:characterLoaded'
nd.logoutEvent = 'ND:characterUnloaded'
nd.setGroupEvent = 'ND:updateCharacter'

function nd.getOfficerData()
    local playerData = NDCore:getPlayer()

    officer.citizenid = playerData.id
    officer.firstname = playerData.firstname
    officer.lastname = playerData.lastname
    officer.role = playerData.jobInfo.rankName

    return officer
end

function nd.notify(text, type)
    lib.notify({description = text, type = type})
end

function nd.isJobPolice()
    return NDCore:getPlayer().job == 'lspd' or 'bcso' or 'swat' or 'sahp' -- Default ND_Core jobs (Players will need to adjust accordingly!)
end

function nd.isOnDuty()
    return true
end

function nd.GetVehiclesByName()
    return false
end

function nd.getPlayerGender()
    return NDCore:getPlayer().gender == 1 and "Female" or "Male"
end

return nd
