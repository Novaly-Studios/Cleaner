local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))

local ValidClass = TypeGuard.Object():OfStructure({
    __index = TypeGuard.Object();
    Destroy = TypeGuard.Function();
    new = TypeGuard.Function();
})

local CleanerType = TypeGuard.Object():OfStructure({
    IsCleaner = TypeGuard.Boolean();
})

local DestroyableType = TypeGuard.Object():OfStructure({
    Destroy = TypeGuard.Function();
})

local CustomSignalType = TypeGuard.Object():OfStructure({
    Disconnect = TypeGuard.Function();
})

local CustomMethodType = TypeGuard.Object():OfStructure({
    IsCustomMethod = TypeGuard.Boolean();
})

local CleanableType = TypeGuard.Instance()
                        :Or(TypeGuard.Function())
                        :Or(TypeGuard.Thread())
                        :Or(TypeGuard.RBXScriptConnection())
                        :Or(CleanerType:Equals(function(self)
                            return self -- Cleaners should not be able to Add() themselves because that would just cause recursion overflow
                        end):Negate())
                        :Or(DestroyableType)
                        :Or(CustomSignalType)
                        :Or(CustomMethodType)

local VALIDATE_METHOD_PARAMS = true
local VALIDATE_CLEANABLES = true

local ERR_CLASS_ALREADY_WRAPPED = "Class already wrapped"
local ERR_OBJECT_FINISHED = "Object lifecycle ended, but key %s was indexed"

local TYPE_SCRIPT_CONNECTION = "RBXScriptConnection"
local TYPE_INSTANCE = "Instance"
local TYPE_FUNCTION = "function"
local TYPE_THREAD = "thread"
local TYPE_TABLE = "table"

local OBJECT_FINALIZED_MT = {
    __index = function(_, Key)
        error(ERR_OBJECT_FINISHED:format(tostring(Key)))
    end;
}

local SUPPORTED_OBJECT_METHODS = {"Disconnect", "Destroy", "Clean"}

--- New object & utility functions for handling the lifecycles of Lua objects, aims to help prevent memory leaks
local Cleaner = {}
Cleaner.__index = Cleaner

-- Any extra implementations go here
local SupportedCleanables = {}

SupportedCleanables[TYPE_TABLE] = function(Item)
    local IsLocked = Cleaner.IsLocked

    for _, MethodName in SUPPORTED_OBJECT_METHODS do
        if (IsLocked(Item)) then
            break
        end

        local Method = Item[MethodName]

        if (not Method) then
            continue
        end

        Method(Item)
    end

    -- There should be no last resort case because the type validator should filter in all supported object types
end

SupportedCleanables[TYPE_THREAD] = function(Item)
    coroutine.close(Item)
end

SupportedCleanables[TYPE_FUNCTION] = function(Item)
    Item()
end

SupportedCleanables[TYPE_SCRIPT_CONNECTION] = function(Item)
    Item:Disconnect()
end

SupportedCleanables[TYPE_INSTANCE] = function(Item)
    Item:Destroy()
end

function Cleaner.new()
    return setmetatable({
        IsCleaner = true;
        _DidClean = false;
        _CleanList = {};
        _Index = 1;
    }, Cleaner)
end

local AddParams = TypeGuard.VariadicParamsWithContext(CleanableType)
--- Adds an object to this Cleaner. Object must be one of the following:
--- - Cleaner
--- - Function
--- - Coroutine / Thread
--- - Roblox Instance
--- - Roblox Event Connection
--- - Custom Method (via Cleaner.CustomMethod)
--- - Table containing one of the following methods:
---   - Object:Clean()
---   - Object:Destroy()
---   - Object:Disconnect()
function Cleaner:Add(...): typeof(Cleaner)
    if (VALIDATE_CLEANABLES) then
        AddParams(self, ...)
    end

    local CleanList = self._CleanList

    -- Verify types & push onto array
    local Size = select("#", ...)
    local Index = self._Index

    for Arg = 1, Size do
        local Item = select(Arg, ...)
        CleanList[Index] = Item
        Index += 1
    end

    self._Index = Index

    -- Add after Clean called? Likely result of bad yielding, so clean up whatever is doing this.
    if (self._DidClean) then
        self:Clean()
    end

    return self
end
Cleaner.add = Cleaner.Add

--- Cleans and locks this Cleaner preventing it from being used again. If an object is added to the Cleaner after it has been locked, it will be cleaned immediately.
function Cleaner:Clean()
    local CleanList = self._CleanList

    for Index, Item in CleanList do
        SupportedCleanables[typeof(Item)](Item)
        CleanList[Index] = nil
    end

    self._Index = 1
    self._DidClean = true
end
Cleaner.clean = Cleaner.Clean

--- Adds whatever coroutine called this method to the Cleaner
function Cleaner:AddContext(): typeof(Cleaner)
    return self:Add(coroutine.running())
end
Cleaner.addContext = Cleaner.AddContext

local function CleanerSpawn(self, Call, ...)
    self:AddContext()
    Call(...)
end

local SpawnParams = TypeGuard.Params(TypeGuard.Function())
--- Spawns a coroutine & adds to the Cleaner
function Cleaner:Spawn(Callback, ...): typeof(Cleaner)
    if (VALIDATE_METHOD_PARAMS) then
        SpawnParams(Callback)
    end

    task.spawn(CleanerSpawn, self, Callback, ...)
    return self
end
Cleaner.spawn = Cleaner.Spawn

local function CleanerDelay(Duration, Call, ...)
    task.wait(Duration)
    Call()
end

local DelayParams = TypeGuard.Params(TypeGuard.Number(), TypeGuard.Function())
--- Delays a spawned coroutine & adds to cleaner
function Cleaner:Delay(Time, Callback, ...): typeof(Cleaner)
    if (VALIDATE_METHOD_PARAMS) then
        DelayParams(Time, Callback)
    end

    self:Spawn(CleanerDelay, Time, Callback, ...)
    return self
end
Cleaner.delay = Cleaner.Delay

-------------------- Standalone functions --------------------

local LockParams = TypeGuard.Params(TypeGuard.Object())
--- Permanently locks down an object once finished
function Cleaner.Lock(Object)
    if (VALIDATE_METHOD_PARAMS) then
        LockParams(Object)
    end

    -- Have to "nil" everything to ensure the __index error works
    for Key in Object do
        Object[Key] = nil
    end

    setmetatable(Object, OBJECT_FINALIZED_MT)
    table.freeze(Object)
end

local WrapParams = TypeGuard.Params(ValidClass)
--- Wraps the class to ensure more lifecycle safety, including auto-lock on Destroy
function Cleaner.Wrap(Class)
    if (VALIDATE_METHOD_PARAMS) then
        WrapParams(Class)
        assert(not Cleaner.IsWrapped(Class), ERR_CLASS_ALREADY_WRAPPED)
    end

    local OriginalDestroy = Class.Destroy

    Class.Destroy = function(self, ...)
        OriginalDestroy(self, ...)
        Cleaner.Lock(self)
    end

    Class._CLEANER_WRAPPED = true

    return Class
end
Cleaner.wrap = Cleaner.Wrap

local IsWrappedParams = TypeGuard.Params(ValidClass)
--- Determines if a class is already wrapped
function Cleaner.IsWrapped(Class)
    if (VALIDATE_METHOD_PARAMS) then
        IsWrappedParams(Class)
    end

    return Class._CLEANER_WRAPPED ~= nil
end
Cleaner.isWrapped = Cleaner.IsWrapped

local IsLockedParams = TypeGuard.Params(TypeGuard.Object())
-- Determines if an object is locked via the mechanism in Cleaner
function Cleaner.IsLocked(Object)
    if (VALIDATE_METHOD_PARAMS) then
        IsLockedParams(Object)
    end

    return getmetatable(Object) == OBJECT_FINALIZED_MT
end
Cleaner.isLocked = Cleaner.IsLocked

local CustomMethodParams = TypeGuard.Params(TypeGuard.Object(), TypeGuard.String())
-- Creates an object which signals for a Cleaner to call an arbitrary method name with a set of params
function Cleaner.CustomMethod(Object, Name, ...)
    if (VALIDATE_METHOD_PARAMS) then
        CustomMethodParams(Object, Name)
    end

    return {
        _Args = {...};
        IsCustomMethod = true;

        Destroy = function(self)
            Object[Name](Object, unpack(self._Args))
        end;
    };
end

return Cleaner