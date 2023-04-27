--!nonstrict
-- Allows easy command bar paste.
if (not script) then
    script = game:GetService("ReplicatedFirst").Cleaner
end

local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))
local GC = require(script:WaitForChild("GC")).new()

local SUPPORTED_OBJECT_METHODS = {"Disconnect", "Destroy", "Clean"}

--- New object & utility functions for handling the lifecycles of Lua objects, aims to help prevent memory leaks.
--- @todo garbage collector support, hooking onto table lifecycles.
--- @todo Instance support, hooking onto Instance lifecycles.
local Cleaner = {}
Cleaner.__index = Cleaner

local CleanerType = TypeGuard.Object():OfClass(Cleaner)

type CleanerType = {
    _IsCleaner: true;
}

local DestroyableType = TypeGuard.Object():OfStructure({
    Destroy = TypeGuard.Function();
})

type DestroyableType = {
    Destroy: () -> ();
}

local CustomSignalType = TypeGuard.Object():OfStructure({
    Disconnect = TypeGuard.Function();
})

type CustomSignalType = {
    Disconnect: () -> ();
}

local CleanableType = TypeGuard.Instance()
                        :Or(TypeGuard.Function())
                        :Or(TypeGuard.Thread())
                        :Or(TypeGuard.RBXScriptConnection())
                        :Or(CleanerType:Equals(function(self)
                            return self -- Cleaners should not be able to Add() themselves because that would just cause recursion overflow.
                        end):Negate():FailMessage("Cannot add a Cleaner to itself"))
                        :Or(DestroyableType)
                        :Or(CustomSignalType)

type AnyObject = {[any]: any}

export type Cleaner = {
    BindToInstanceLifecycles: ((References: Instance | {Instance}, OnDeparented: boolean?, Disjunctive: boolean?) -> ());
    BindToObjectLifecycles: ((References: AnyObject | {AnyObject}, Disjunctive: boolean?) -> ());
    Contains: ((Item: CleanableType) -> (boolean));

    Remove: ((...CleanableType) -> ());
    Clean: (() -> ());
    Add: ((...CleanableType) -> ());
}

type CleanableType = Instance | (() -> ()) | RBXScriptConnection | DestroyableType | CustomSignalType | Cleaner | thread

-- Any extra implementations go in SupportedCleanables.
local SupportedCleanables = {}

SupportedCleanables["table"] = function(Item)
    for _, Name in SUPPORTED_OBJECT_METHODS do
        if (table.isfrozen(Item)) then
            break
        end

        local Method = Item[Name]

        if (not Method) then
            continue
        end

        Method(Item)
    end

    -- There should be no last resort case here because the type validator should filter in all supported object types.
end

SupportedCleanables["thread"] = task.cancel

SupportedCleanables["function"] = task.spawn

SupportedCleanables["RBXScriptConnection"] = function(Item)
    Item:Disconnect()
end

SupportedCleanables["Instance"] = function(Item)
    Item:Destroy()
end

function Cleaner.new(): Cleaner
    local self = setmetatable({
        _DidClean = false;
        _CleanList = {};
    }, Cleaner)

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

    local CleanList = self._CleanList
    local Size = select("#", ...)

    -- If the Cleaner was already cleaned, then clean the new items immediately.
    -- This helps with race conditions in the code using the Cleaner, usually.
    if (self._DidClean) then
        for Arg = 1, Size do
            local Item = select(Arg, ...)
            SupportedCleanables[typeof(Item)](Item)
        end

        return
    end

    for Arg = 1, Size do
        local Item = select(Arg, ...)
        CleanList[Item] = true
    end

    return self
end

local RemoveParams = TypeGuard.VariadicWithContext(CleanableType)
--- Removes an object from this Cleaner.
function Cleaner:Remove(...)
    RemoveParams(self, ...)

    local CleanList = self._CleanList

    for Arg = 1, select("#", ...) do
        local Item = select(Arg, ...)
        CleanList[Item] = nil
    end
end

local ContainsParams = TypeGuard.Params(CleanableType)
--- Returns whether or not this Cleaner contains an object.
function Cleaner:Contains(Item)
    ContainsParams(Item)
    return self._CleanList[Item] ~= nil
end

--- Cleans and locks this Cleaner preventing it from being used again. If an object is added
--- to the Cleaner after it has been locked, it will be cleaned immediately.
function Cleaner:Clean()
    local CleanList = self._CleanList
    self._DidClean = true

    for Item in CleanList do
        SupportedCleanables[typeof(Item)](Item)
    end
end

local BindToObjectLifecyclesParams = TypeGuard.Params(
    TypeGuard.Array(TypeGuard.Any()),
    TypeGuard.Boolean():Optional()
)
--- Binds this Cleaner to the lifecycle of a table. If the table is garbage collected, the Cleaner will be cleaned.
--- Default assumption is conjunctive / and: all objects must be GC'ed before the Cleaner cleans. Optional argument
--- for disjunctive / or: any object can be GC'ed, cleaning the Cleaner.
function Cleaner:BindToObjectLifecycles(References, Disjunctive)
    if (self._IsTracking) then
        error("Cleaner is already bound")
    end

    if (self._DidClean) then
        error("Cleaner has already been cleaned")
    end

    if (typeof(References) == "table") then
        References = {References}
    end

    BindToObjectLifecyclesParams(References, Disjunctive)
    self._IsTracking = true
    local Count = #References

    for _, Reference in References do
        local Tracker; Tracker = GC.track(Reference, function()
            GC.forget(Tracker)

            if (Disjunctive) then
                if (not self._DidClean) then
                    self:Clean()
                end

                return
            end

            Count -= 1

            if (Count == 0) then
                self:Clean()
            end
        end)
    end
end

local BindToInstanceLifecyclesParams = TypeGuard.Params(
    TypeGuard.Array(TypeGuard.Instance()),
    TypeGuard.Boolean():Optional(),
    TypeGuard.Boolean():Optional()
)
--- Binds this Cleaner to the lifecycles of a list of Instances. When the Instances are destroyed (default assumption) or
--- deparented (optional), the Cleaner will be cleaned. Default assumption is conjunctive / and: all Instances must end
--- their lifecycle before the Cleaner cleans. Optional argument for disjunctive / or: any object can end their lifecycle,
--- cleaning the Cleaner.
function Cleaner:BindToInstanceLifecycles(References, OnDeparented, Disjunctive)
    if (self._IsTracking) then
        error("Cleaner is already bound")
    end

    if (self._DidClean) then
        error("Cleaner has already been cleaned")
    end

    if (typeof(References) == "Instance") then
        References = {References}
    end

    BindToInstanceLifecyclesParams(References, OnDeparented, Disjunctive)
    self._IsTracking = true
    local Count = #References

    for _, Reference in References do
        if (OnDeparented) then
            local Temp; Temp = Reference.AncestryChanged:Connect(function(_, Parent)
                if (Reference:IsDescendantOf(game)) then
                    return
                end
    
                Temp:Disconnect()

                if (Disjunctive) then
                    if (not self._DidClean) then
                        self:Clean()
                    end

                    return
                end

                Count -= 1

                if (Count == 0) then
                    self:Clean()
                end
            end)

            continue
        end

        -- Clean only when Instance is destroyed.
        local Temp; Temp = Reference.Destroying:Connect(function()
            Temp:Disconnect()

            if (Disjunctive) then
                if (not self._DidClean) then
                    self:Clean()
                end

                return
            end

            Count -= 1

            if (Count == 0) then
                self:Clean()
            end
        end)
    end
end

function Cleaner.__add(self, Item)
    self:Add(Item)
end

function Cleaner.__sub(self, Item)
    self:Remove(Item)
end

task.spawn(function()
    while (task.wait(5)) do
        GC.update(100)
    end
end)

return Cleaner