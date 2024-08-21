simpleTransport = {}
simpleTransport.transportPilotNames = {"JOLLY-1", "JOLLY-2", "SANDY-1", "SANDY-2", "GATOR-1",
                                       "GATOR-2"}
simpleTransport.pickupGroupNames =
    {"PEDRO-1", "PEDRO-2", "PEDRO-3", "PEDRO-4", "PEDRO-5", "PEDRO-6"}
simpleTransport.pickupGroups = {}

local MAX_PICKUP_DSTANCE = 50
local MENU_POLL_INTERVAL = 10
local SPAWN_UNIT_SPACING = 8

local _sf = string.format

local distance = function(obj1, obj2)
    local p1 = obj1:getPoint()
    local p2 = obj2:getPoint()
    local delta = mist.vec.sub(p1, p2)
    return mist.vec.mag(delta)
end

local initPickupGroups = function()
    for _, groupName in pairs(simpleTransport.pickupGroupNames) do
        local group = Group.getByName(groupName)

        if group then
            table.insert(simpleTransport.pickupGroups, group:getName())
        end
    end
end

local isInAir = function(unit)
    local isPlayer = unit:getPlayerName() ~= nil
    local speed = mist.vec.mag(unit:getVelocity())
    -- CTLD seems to think that DCS can report that the player is 
    -- in the air even when they're actually on the ground.
    -- So even if DCS reports that the player is in the air, CTLD
    -- checks the unit's speed, and if it's less than 0.05 m/s,
    -- then it says that the unit is on the ground
    return unit:inAir() or (isPlayer and speed >= 0.05)
end

local findGroupInMiz = function(groupName)
    local countryList = env.mission.coalition.blue.country
    for _, country in ipairs(countryList) do
        local vehicle = country.vehicle
        local vehicleGroups = vehicle.group
        for _, vehicleGroup in ipairs(vehicleGroups) do
            if vehicleGroup.name == groupName then
                return {
                    group = vehicleGroup,
                    country = country
                }
            end
        end
    end
end

local findUnitInList = function(unitName, unitList)
    for _, unit in ipairs(unitList) do
        if unit.name == unitName then
            return unit
        end
    end
end

local makeGroupData = function(groupName)
    return {
        ["visible"] = false,
        ["hidden"] = false,
        ["units"] = {},
        ["name"] = groupName,
        ["task"] = {}
    }
end

local makeUnit = function(unitName, unitType)
    return {
        ["y"] = 0,
        ["type"] = unitType,
        ["name"] = unitName,
        ["heading"] = 0,
        ["playerCanDrive"] = true,
        ["skill"] = "Excellent",
        ["x"] = 0

    }
end

local printGroupDetails = function(groupDetails)
    env.info("group info: ")
    env.info(_sf("country: ", groupDetails.country))
    env.info(_sf("name: %s", tostring(groupDetails.groupData.name)))
    env.info(_sf("visible: %s", tostring(groupDetails.groupData.visible)))
    env.info(_sf("taskSelected: %s", tostring(groupDetails.groupData.taskSelected)))
    env.info(_sf("hidden: %s", tostring(groupDetails.groupData.hidden)))
    env.info("Units:")

    for _, unit in ipairs(groupDetails.groupData.units) do
        env.info(_sf("name: %s", tostring(unit.name)))
        env.info(_sf("playerCanDrive: %s", tostring(unit.playerCanDrive)))
        env.info(_sf("skill: %s", tostring(unit.skill)))
        env.info(_sf("coldAtStart: %s", tostring(unit.coldAtStart)))
        env.info(_sf("type: %s", tostring(unit.type)))
    end
end

local collectGroupDetails = function(groupObj)
    local mizGroupInfo = findGroupInMiz(groupObj:getName())

    local mizUnits

    if mizGroupInfo then
        mizUnits = mizGroupInfo.group.units
    end

    local groupData
    if mizGroupInfo then
        groupData = mist.utils.deepCopy(mizGroupInfo.group)
        groupData.units = {}
    else
        groupData = makeGroupData(groupObj:getName())
    end
    local units = groupObj:getUnits()

    for _, unit in ipairs(units) do
        if unit:getLife() > 0 then
            local mizUnit = mizUnits and findUnitInList(unit:getName(), mizUnits)
            if mizUnit then
                table.insert(groupData.units, mizUnit)
            else
                table.insert(groupData, makeUnit)
            end
        end
    end

    local country
    if units and units[1] then
        country = units[1]:getCountry()
    end

    local groupDetails = {
        ["groupName"] = groupObj:getName(),
        ["side"] = groupObj:getCoalition(),
        ["country"] = country,
        ["groupData"] = groupData
    }

    -- printGroupDetails(groupDetails)
    return groupDetails
end

simpleTransport.trackedGroups = {}
function simpleTransport.trackedGroups:isTracked(groupId)
    return self[groupId]
end

function simpleTransport.trackedGroups:add(groupId)
    self[groupId] = true
end

function simpleTransport.trackedGroups:remove(groupId)
    self[groupId] = false
end

local sendMsgToUnit = function(unit, msg, time)
    if not time then
        time = 10
    end
    trigger.action.outTextForUnit(unit:getID(), msg, time)
end

simpleTransport.transportedUnits = {}
function simpleTransport.transportedUnits:add(playerUnit, groupToTransport)
    local playerUnitId = playerUnit:getID()
    local details = collectGroupDetails(groupToTransport)
    self[playerUnitId] = details
    groupToTransport:destroy()
end

function simpleTransport.transportedUnits:get(playerUnit)
    local playerUnitId = playerUnit:getID()
    return self[playerUnitId]
end

function simpleTransport.transportedUnits:remove(playerUnit)
    local playerUnitId = playerUnit:getID()
    local info = self[playerUnitId]
    self[playerUnitId] = nil
    return info
end

local getMinDistanceInGroup = function(groupName, playerUnit)
    local minDistInGroup = 1.0e10
    local group = Group.getByName(groupName)

    local units = group and group:getUnits()
    if not units then
        return nil
    end

    for _, unit in pairs(units) do
        local isAlive = unit:getLife() > 0
        local dist = distance(playerUnit, unit)
        if isAlive and dist < minDistInGroup then
            minDistInGroup = dist
        end
    end
    return minDistInGroup
end

local findNearestGroupMatching = function(playerUnit, groupNames)
    local playerLoc = playerUnit:getPoint()
    local minDist = 1.0e10
    local group = nil

    local loopBody = function(groupName)
        local dist = getMinDistanceInGroup(groupName, playerUnit)
        if dist == nil then
            return
        end
        if dist < minDist then
            minDist = dist
            group = Group.getByName(groupName)
        end
    end

    for _, groupName in pairs(groupNames) do
        loopBody(groupName)
    end
    return group
end

-- workaround since apparently Unit.getGroup() is unreliable
local getGroupIdFromUnit = function(unit)
    local unitFromDb = mist.DBs.unitsById[tonumber(unit:getID())]
    local groupIdExists = unitFromDb and unitFromDb.groupId
    if not groupIdExists then
        return nil
    end
    return unitFromDb.groupId
end

local getActiveUnitByName = function(name)
    local unit = Unit.getByName(name)
    if not unit then
        return nil
    end

    local isActive = unit:isActive() and unit:getLife() > 0
    if not isActive then
        return nil
    end

    return unit
end

local isAlive = function(unit)
    return unit and unit:isActive() and unit:getLife() > 0
end

local isUnitTransported = function(playerUnitName)
    local playerUnit = Unit.getByName(playerUnitName)
    local groupDetails = simpleTransport.transportedUnits:get(playerUnit)
    return groupDetails and groupDetails['groupName']
end

local loadGroup = function(playerUnitName)
    local playerUnit = Unit.getByName(playerUnitName)
    if isUnitTransported(playerUnitName) then
        local name = simpleTransport.transportedUnits:get(playerUnit).groupName
        local s = _sf("Cannot load another unit, you are already transporting %s", name)
        sendMsgToUnit(playerUnit, s, 10)
        return
    end

    -- find a nearby loadable group
    if not (playerUnit and isAlive(playerUnit)) then
        return
    end

    local nearestGroup = findNearestGroupMatching(playerUnit, simpleTransport.pickupGroupNames)

    local isReallyFar = false
    local dist
    if nearestGroup then
        dist = getMinDistanceInGroup(nearestGroup:getName(), playerUnit)
        isReallyFar = nearestGroup and dist >= MAX_PICKUP_DSTANCE * 5
    end

    if (not nearestGroup) or isReallyFar then
        local s = "Sorry, cannot find any groups to pick up. Make sure you " ..
                      "are within %.0f meters of the group you are trying to pick up."
        local msg = _sf(s, MAX_PICKUP_DSTANCE)
        sendMsgToUnit(playerUnit, msg)
        return
    end

    -- we are relatively close to nearestGroup, so tell the user how far they are in
    -- order to avoid aggravation
    if dist > MAX_PICKUP_DSTANCE then
        local s = "Sorry, cannot find any groups to pick up. Make sure you are " ..
                      "within %.0f meters of the group you are trying to pick up. " ..
                      "Nearest group is %s, and you need to get %.0f meters closer."
        local msg = _sf(s, MAX_PICKUP_DSTANCE, nearestGroup:getName(), dist - MAX_PICKUP_DSTANCE)
        sendMsgToUnit(playerUnit, msg)
        return
    end

    simpleTransport.transportedUnits:add(playerUnit, nearestGroup)

    local s = "Picked up %s."
    local msg = _sf(s, nearestGroup:getName())
    sendMsgToUnit(playerUnit, msg)

end

local getHeading = function(unit)
    if not unit then
        return 0
    end
    local pos = unit:getPosition()
    return math.atan2(pos.x.z, pos.x.x)
end

local spawnGroup = function(playerUnit, position, groupInfo)

    local updateUnitPos = function(unit, point, heading)
        unit["x"] = point.x
        unit["y"] = point.z
        unit["heading"] = math.atan2(position.x.z, position.x.x)
    end

    local n = #(groupInfo["groupData"]["units"]) - 1
    local point = position.p
    local right = position.z
    local forward = position.x

    -- place units out front, centered on the player
    local tenMetersFront = mist.vec.add(point, mist.vec.scalarMult(forward, 20))
    local spawnPos = mist.vec.add(tenMetersFront,
        mist.vec.scalarMult(right, -SPAWN_UNIT_SPACING * n / 2))
    local delta = mist.vec.scalarMult(right, SPAWN_UNIT_SPACING)

    local route = groupInfo.groupData.route
    if route and route["points"] and #(route["points"]) > 0 then
        local routePoints = route["points"]
        routePoints = {routePoints[1]}
        routePoints[1]["alt"] = 0
        routePoints[1]["alt_type"] = "RADIO"
        routePoints[1]["y"] = spawnPos.z
        routePoints[1]["x"] = spawnPos.x
    end

    for index, unit in ipairs(groupInfo["groupData"]["units"]) do
        updateUnitPos(unit, spawnPos)
        spawnPos = mist.vec.add(spawnPos, delta)
    end

    if not groupInfo["country"] then
        groupInfo["country"] = playerUnit:getCountry()
    end

    coalition.addGroup(groupInfo["country"], Group.Category.GROUND, groupInfo["groupData"])

end

local unloadGroup = function(playerUnitName)
    local playerUnit = Unit.getByName(playerUnitName)
    local groupDetails = simpleTransport.transportedUnits:remove(playerUnit)
    if not (groupDetails and groupDetails['groupName']) then
        local s = "Not transporting any units at this time."
        sendMsgToUnit(playerUnit, s)
        return
    end

    if isInAir(playerUnit) then
        sendMsgToUnit(playerUnit, "You must land before unloading troops.")
    end

    local playerPos = playerUnit:getPosition()
    spawnGroup(playerUnit, playerPos, groupDetails)

end

local checkLoadStatus = function(playerUnitName)
    local playerUnit = Unit.getByName(playerUnitName)
    local groupDetails = simpleTransport.transportedUnits:get(playerUnit)
    if not (groupDetails and groupDetails['groupName']) then
        local s = "Not transporting any units at this time."
        sendMsgToUnit(playerUnit, s)
        return
    end

    local groupName = groupDetails['groupName']
    local s = _sf("Group %s is onboard.", groupName)
    sendMsgToUnit(playerUnit, s)
end

local setupMenuForPlayer = function(unitName)
    local unit = getActiveUnitByName(unitName)
    if not unit then
        return
    end
    local groupId = getGroupIdFromUnit(unit)
    if not groupId then
        return
    end

    local alreadyAdded = simpleTransport.trackedGroups:isTracked(groupId)
    if alreadyAdded then
        return
    end

    simpleTransport.trackedGroups:add(groupId)

    local rootMenu = missionCommands.addSubMenuForGroup(groupId, "Transport")
    -- important to pass the unit name and not the unit object itself below,
    -- since any respawn seems to be a new unit object (with the same name)
    missionCommands.addCommandForGroup(groupId, "Load group", rootMenu, loadGroup, unitName)
    missionCommands.addCommandForGroup(groupId, "Unload group", rootMenu, unloadGroup, unitName)
    missionCommands.addCommandForGroup(groupId, "Check load status", rootMenu, checkLoadStatus,
        unitName)

end

local menuTimerHandler
menuTimerHandler = function()
    for _, unitName in pairs(simpleTransport.transportPilotNames) do
        setupMenuForPlayer(unitName)
    end
    timer.scheduleFunction(menuTimerHandler, nil, timer.getTime() + MENU_POLL_INTERVAL)

end

initPickupGroups()
timer.scheduleFunction(menuTimerHandler, nil, timer.getTime() + MENU_POLL_INTERVAL)
