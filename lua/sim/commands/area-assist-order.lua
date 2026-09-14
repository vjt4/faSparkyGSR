--******************************************************************************************************
--** Copyright (c) 2026 FAForever
--**
--** Permission is hereby granted, free of charge, to any person obtaining a copy
--** of this software and associated documentation files (the "Software"), to deal
--** in the Software without restriction, including without limitation the rights
--** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--** copies of the Software, and to permit persons to whom the Software is
--** furnished to do so, subject to the following conditions:
--**
--** The above copyright notice and this permission notice shall be included in all
--** copies or substantial portions of the Software.
--**
--** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--** SOFTWARE.
--******************************************************************************************************

local TableGetn = table.getn
local TableSort = table.sort
local StringFormat = string.format

local IssueGuard = IssueGuard
local GetCurrentCommandSourceArmy = import("/lua/SimUtils.lua").GetCurrentCommandSourceArmy

local distances = {}

local function SortByDistance(a, b)
    return distances[a.EntityId] < distances[b.EntityId]
end

---@param units Unit[]
---@param ps Vector
---@param pe Vector
---@param width number
---@param doPrint boolean
---@param initialTargetId EntityId
function AreaAssistUnits(units, ps, pe, width, doPrint, initialTargetId)
    if TableGetn(units) == 0 then
        return
    end

    local commandQueueCount = TableGetn(units[1]:GetCommandQueue())
    local maximumCommandsToProcess = 450 - commandQueueCount
    if maximumCommandsToProcess <= 0 then
        if doPrint and GetFocusArmy() == GetCurrentCommandSourceArmy() then
            print("Command queue is saturated")
        end
        return
    end

    local dx = pe[1] - ps[1]
    local dz = pe[3] - ps[3]
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance == 0 then
        return
    end

    local maximumDistance = import("/lua/shared/commands/area-reclaim-order.lua").MaximumDistance
    if distance > maximumDistance then
        pe[1] = ps[1] + dx * maximumDistance / distance
        pe[3] = ps[3] + dz * maximumDistance / distance
        dx = pe[1] - ps[1]
        dz = pe[3] - ps[3]
        distance = maximumDistance
    end

    local ox = dz / distance
    local oz = -dx / distance
    local minX = math.min(ps[1] + width * ox, ps[1] - width * ox, pe[1] + width * ox, pe[1] - width * ox)
    local minZ = math.min(ps[3] + width * oz, ps[3] - width * oz, pe[3] + width * oz, pe[3] - width * oz)
    local maxX = math.max(ps[1] + width * ox, ps[1] - width * ox, pe[1] + width * ox, pe[1] - width * ox)
    local maxZ = math.max(ps[3] + width * oz, ps[3] - width * oz, pe[3] + width * oz, pe[3] - width * oz)

    local candidates = GetUnitsInRect(minX, minZ, maxX, maxZ) or {}
    for entityId, _ in distances do
        distances[entityId] = nil
    end

    for _, candidate in candidates do
        local cx, _, cz = candidate:GetPositionXYZ()
        local ex = cx - ps[1]
        local ez = cz - ps[3]
        distances[candidate.EntityId] = ex * ex + ez * ez
    end
    TableSort(candidates, SortByDistance)

    local selected = {}
    for _, unit in units do
        selected[unit.EntityId] = true
    end

    local commandArmy = GetCurrentCommandSourceArmy()
    local processed = 0
    local distanceSquared = distance * distance
    for _, candidate in candidates do
        local cx, _, cz = candidate:GetPositionXYZ()
        local pvx = cx - ps[1]
        local pvz = cz - ps[3]
        local t = math.max(0, math.min(1, (pvx * dx + pvz * dz) / distanceSquared))
        local nearestX = ps[1] + t * dx
        local nearestZ = ps[3] + t * dz
        local offsetX = cx - nearestX
        local offsetZ = cz - nearestZ

        if not IsDestroyed(candidate)
            and not selected[candidate.EntityId]
            and candidate.EntityId ~= initialTargetId
            and IsAlly(commandArmy, candidate.Army)
            and offsetX * offsetX + offsetZ * offsetZ <= width * width
        then
            IssueGuard(units, candidate)
            processed = processed + 1
            if processed >= maximumCommandsToProcess then
                break
            end
        end
    end

    if doPrint and GetFocusArmy() == commandArmy then
        if processed > 0 then
            print(StringFormat("Assisting %d units", processed))
        end
        if processed >= maximumCommandsToProcess then
            print("Command queue is saturated")
        end
    end
end
