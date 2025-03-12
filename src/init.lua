--!optimize 2
--!nonstrict
--!native

-- Allows easy command bar paste.
if (not script and Instance) then
    script = game:GetService("ReplicatedFirst").Cleaner
end

local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))

local GC = require(script:WaitForChild("GC")).new()
    local GCUpdate = GC.update
    local GCForget = GC.forget
    local GCTrack = GC.track

local InstanceHookCount = 0
local GCHookCount = 0

local SUPPORTED_OBJECT_METHODS = table.freeze({"Disconnect", "Destroy", "Clean"})
local CLEANED_TABLE = table.freeze({})
local EMPTY_TABLE = table.freeze({})

--- New object & utility functions for handling the lifecycles of Lua objects, aims to help prevent memory leaks.
local Cleaner = {}
Cleaner.__index = Cleaner

local CleanerType = TypeGuard.Object():OfClass(Cleaner)

local DestroyableType = TypeGuard.Object({
    Destroy = TypeGuard.Function();
})

type DestroyableType = {
    Destroy: (() -> ());
}

local CustomSignalConnectionType = TypeGuard.Object({
    Disconnect = TypeGuard.Function();
})

type CustomSignalConnectionType = {
    Disconnect: (() -> ());
}

CleanableType = TypeGuard.Or(
    TypeGuard.RBXScriptConnection(),
    CustomSignalConnectionType,
    TypeGuard.Instance(),
    DestroyableType,
    TypeGuard.Function(),
    TypeGuard.Thread(),
    CleanerType:Equals(function(self)
        -- Cleaners should not be able to Add() themselves because that would cause non-stop recursion.
        -- Work out a way to avoid cycles in future.
        return self
    end):Negate():FailMessage("Cannot add a Cleaner to itself"),
    TypeGuard.Object():Equals(EMPTY_TABLE)
)

export type Cleaner = {
    Contains: ((Item: CleanableType) -> (boolean));
    Remove: ((...CleanableType) -> (Cleaner));
    Clean: (() -> (Cleaner));
    Add: ((...CleanableType) -> (Cleaner));
}

type CleanableType = (Instance | (() -> ()) | RBXScriptConnection | DestroyableType | CustomSignalConnectionType | Cleaner | thread)

-- Any extra implementations go in SupportedCleanables.
local SupportedCleanables = {} do
    local _FastDestroy = game.Destroy
    local _Connection = game.Close:Connect(function() end)
    local _FastDisconnect = _Connection.Disconnect
    _Connection:Disconnect()

    SupportedCleanables["table"] = function(Item)
        if (table.isfrozen(Item)) then
            return
        end

        for _, Name in SUPPORTED_OBJECT_METHODS do
            local Method = Item[Name]

            if (Method) then
                task.spawn(Method, Item)
            end
        end
    end

    SupportedCleanables["RBXScriptConnection"] = _FastDisconnect
    SupportedCleanables["Instance"] = _FastDestroy
    SupportedCleanables["function"] = task.spawn
    SupportedCleanables["thread"] = task.cancel
end

function Cleaner.new(): Cleaner
    local self = setmetatable({}, Cleaner)
    return self
end

local AddParams = TypeGuard.VariadicWithContext(CleanableType)
--- Adds an object to this Cleaner. Object must be one of the following:
--- - Cleaner
--- - Function
--- - Coroutine / Thread
--- - Roblox Instance
--- - Roblox Event Connection
--- - Table containing one of the following methods:
---   - Object:Clean()
---   - Object:Destroy()
---   - Object:Disconnect()
function Cleaner:Add(...)
    AddParams(self, ...)

    local Size = select("#", ...)

    -- If the Cleaner was already cleaned, then clean the new items immediately.
    -- This helps with race conditions in the code using the Cleaner, usually.
    if (self[1] == CLEANED_TABLE) then
        for Arg = 1, Size do
            local Item = select(Arg, ...)
            SupportedCleanables[typeof(Item)](Item)
        end

        return self
    end

    for Arg = 1, Size do
        table.insert(self, (select(Arg, ...)))
    end

    return self
end

local RemoveParams = TypeGuard.VariadicWithContext(CleanableType)
--- Removes an object from this Cleaner.
function Cleaner:Remove(...)
    RemoveParams(self, ...)

    for Arg = 1, select("#", ...) do
        local Index = table.find(self, (select(Arg, ...)))

        if (Index) then
            self[Index] = EMPTY_TABLE
        end
    end

    return self
end

local ContainsParams = TypeGuard.Params(CleanableType)
--- Checks if this Cleaner contains an object.
function Cleaner:Contains(Item)
    ContainsParams(Item)

    return (table.find(self, Item) ~= nil)
end

--- Cleans and locks this Cleaner preventing it from being used again. If an object is added
--- to the Cleaner after it has been locked, it will be cleaned immediately.
function Cleaner:Clean()
    if (self[1] == CLEANED_TABLE) then
        return self
    end

    for _, Item in self do
        SupportedCleanables[typeof(Item)](Item)
    end

    table.clear(self)
    self[1] = CLEANED_TABLE
    return self
end

local FromObjectLifecyclesParams = TypeGuard.Params(
    TypeGuard.Array(TypeGuard.Any),
    TypeGuard.Optional(TypeGuard.Boolean())
)
--- Binds this Cleaner to the existence of a reference. If the target is garbage collected, the Cleaner will be cleaned.
--- Default assumption is conjunctive (and): all objects must be GC'ed before the Cleaner cleans. Optional argument for
--- disjunctive / or: any object can be GC'ed to trigger the Cleaner.
function Cleaner.fromObjectLifecycles(References, Disjunctive)
    if (typeof(References) == "table") then
        References = {References}
    end

    FromObjectLifecyclesParams(References, Disjunctive)

    local Result = Cleaner.new()
    local Count = #References
    GCHookCount += Count

    for _, Reference in References do
        local Tracker; Tracker = GCTrack(Reference, function()
            GCForget(Tracker)

            if (Disjunctive) then
                if (Result[1] ~= CLEANED_TABLE) then
                    Result:Clean()
                end

                return
            end

            GCHookCount -= 1
            Count -= 1

            if (Count == 0) then
                Result:Clean()
            end
        end)
    end

    return Result
end

local FromInstanceLifecyclesParams = TypeGuard.Params(
    TypeGuard.Array(TypeGuard.Instance()),
    TypeGuard.Optional(TypeGuard.Boolean()),
    TypeGuard.Optional(TypeGuard.Boolean())
)
--- Binds a new Cleaner to the lifecycles of a list of Instances. When the Instances are deparented (default assumption) or
--- destroyed (optional), the Cleaner will be cleaned. By default, clean condition is conjunctive (and): all Instances must end
--- their lifecycle before the Cleaner cleans. Optional argument for disjunctive (or): first Instance to end its lifecycle.
function Cleaner.fromInstanceLifecycles(Instances: Instance | {Instance}, UseDestroyedEvent: boolean?, Disjunctive: boolean?): Cleaner
    if (typeof(Instances) == "Instance") then
        Instances = {Instances}
    end

    FromInstanceLifecyclesParams(Instances, UseDestroyedEvent, Disjunctive)

    local Result = Cleaner.new()
    local Count = #(Instances :: {Instance})
    InstanceHookCount += Count

    if (UseDestroyedEvent) then
        for _, Reference in (Instances :: {Instance}) do
            -- Clean only when Instance is destroyed.
            Reference.Destroying:Once(function()
                if (Disjunctive) then
                    if (Result[1] ~= CLEANED_TABLE) then
                        Result:Clean()
                    end

                    return
                end

                InstanceHookCount -= 1
                Count -= 1

                if (Count == 0) then
                    Result:Clean()
                end
            end)
        end

        return Result
    end

    for _, Reference in (Instances :: {Instance}) do
        local Temp; Temp = Reference.AncestryChanged:Connect(function(_, Parent)
            if (Reference:IsDescendantOf(game)) then
                return
            end

            Temp:Disconnect()

            if (Disjunctive) then
                if (Result[1] ~= CLEANED_TABLE) then
                    Result:Clean()
                end

                return
            end

            InstanceHookCount -= 1
            Count -= 1

            if (Count == 0) then
                Result:Clean()
            end
        end)
    end

    return Result
end

Cleaner.__add = Cleaner.Add
Cleaner.__sub = Cleaner.Remove

task.spawn(function()
    while (task.wait(5)) do
        debug.profilebegin("CleanerGC")
        GCUpdate(math.min(math.ceil(GCHookCount / 10), 1000))
        debug.profileend()
    end
end)

return table.freeze(Cleaner)