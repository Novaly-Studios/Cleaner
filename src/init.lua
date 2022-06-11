local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))

local ValidClass = TypeGuard.Object():OfStructure({
    __index = TypeGuard.Object();
    Destroy = TypeGuard.Function():Optional();
    new = TypeGuard.Function();
})

local CleanerType = TypeGuard.Object():OfStructure({
    Clean = TypeGuard.Function();
}):And(ValidClass)

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
local ERR_NO_OBJECT = "No object given"

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

--- New object & utility functions for handling the lifecycles of Lua objects, aims to help prevent memory leaks
local Cleaner = {}
Cleaner.__index = Cleaner
Cleaner._Supported = {}
Cleaner._Validators = {}
Cleaner._ObjectMethods = {"Disconnect", "Destroy", "Clean"}

Cleaner._Supported[TYPE_TABLE] = function(Item)
    for _, MethodName in ipairs(Cleaner._ObjectMethods) do
        if (Cleaner.IsLocked(Item)) then
            break
        end

        local Method = Item[MethodName]

        if (not Method) then
            continue
        end

        Method(Item)
    end

    -- Array of cleanables (can include other Cleaners)
    if (not Cleaner.IsLocked(Item) and Item[1]) then
        local NextCleaner = Cleaner.new()

        for _, Value in ipairs(Item) do
            NextCleaner:Add(Value)
        end

        NextCleaner:Clean()
    end
end

Cleaner._Supported[TYPE_THREAD] = function(Item)
    coroutine.close(Item)
end

Cleaner._Supported[TYPE_FUNCTION] = task.spawn

Cleaner._Supported[TYPE_SCRIPT_CONNECTION] = function(Item)
    Item:Disconnect()
end

Cleaner._Supported[TYPE_INSTANCE] = function(Item)
    Item:Destroy()
end

function Cleaner.new()
    return setmetatable({
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
function Cleaner:Add(...)
    if (VALIDATE_CLEANABLES) then
        AddParams(self, ...)
    end

    local CleanList = self._CleanList

    -- Verify types & push onto array
    local Size = select("#", ...)

    for Index = 1, Size do
        local Item = select(Index, ...)
        CleanList[self._Index] = Item
        self._Index += 1
    end

    -- Add after Clean called? Likely result of bad yielding, so clean up whatever is doing this.
    if (self._DidClean) then
        self:Clean()
    end

    return self
end
Cleaner.add = Cleaner.Add

--- Cleans and locks this Cleaner preventing it from being used again. If an object is added to the Cleaner after it has been locked, it will be cleaned immediately.
function Cleaner:Clean()
    local Supported = Cleaner._Supported
    local CleanList = self._CleanList

    for Index, Item in ipairs(CleanList) do
        Supported[typeof(Item)](Item)
        CleanList[Index] = nil
    end

    self._Index = 1
    self._DidClean = true
end
Cleaner.clean = Cleaner.Clean

--- Adds whatever coroutine called this method to the Cleaner
function Cleaner:AddContext()
    self:Add(coroutine.running())
end
Cleaner.addContext = Cleaner.AddContext

local function CleanerSpawn(self, Call, ...)
    self:AddContext()
    Call(...)
end

--- Spawns a coroutine & adds to the Cleaner
function Cleaner:Spawn(Callback, ...)
    task.spawn(CleanerSpawn, self, Callback, ...)
end
Cleaner.spawn = Cleaner.Spawn

local function CleanerDelay(Duration, Call, ...)
    task.wait(Duration)
    Call()
end

--- Delays a spawned coroutine & adds to cleaner
function Cleaner:Delay(Time, Callback, ...)
    self:Spawn(CleanerDelay, Time, Callback, ...)
end
Cleaner.delay = Cleaner.Delay

-- Standalone functions --

--- Permanently locks down an object once finished
function Cleaner.Lock(Object)
    assert(Object, ERR_NO_OBJECT)

    -- Have to "nil" everything to ensure the __index error works
    for Key in pairs(Object) do
        Object[Key] = nil
    end

    setmetatable(Object, OBJECT_FINALIZED_MT)
    table.freeze(Object)
end
if (VALIDATE_METHOD_PARAMS) then
    Cleaner.Lock = TypeGuard.WrapFunctionParams(Cleaner.Lock, TypeGuard.Object())
end
Cleaner.lock = Cleaner.Lock

--- Wraps the class to ensure more lifecycle safety, including auto-lock on Destroy
function Cleaner.Wrap(Class)
    assert(not Cleaner.IsWrapped(Class), ERR_CLASS_ALREADY_WRAPPED)

    -- Creation --
    local OriginalNew = Class.new

    Class.new = function(...)
        local Object = OriginalNew(...)
        Object.Cleaner = Object.Cleaner or Cleaner.new()
        return Object
    end

    -- Destruction --
    local OriginalDestroy = Class.Destroy

    Class.Destroy = function(self, ...)
        if (OriginalDestroy) then
            OriginalDestroy(self, ...)
        end

        Cleaner.Lock(self)
    end

    Class._CLEANER_WRAPPED = true

    return Class
end
if (VALIDATE_METHOD_PARAMS) then
    Cleaner.Wrap = TypeGuard.WrapFunctionParams(Cleaner.Wrap, ValidClass)
end
Cleaner.wrap = Cleaner.Wrap

--- Determines if a class is already wrapped
function Cleaner.IsWrapped(Class)
    return Class._CLEANER_WRAPPED ~= nil
end
if (VALIDATE_METHOD_PARAMS) then
    Cleaner.IsWrapped = TypeGuard.WrapFunctionParams(Cleaner.IsWrapped, ValidClass)
end
Cleaner.isWrapped = Cleaner.IsWrapped

-- Determines if an object is locked via the mechanism in Cleaner
function Cleaner.IsLocked(Object)
    return getmetatable(Object) == OBJECT_FINALIZED_MT
end
if (VALIDATE_METHOD_PARAMS) then
    Cleaner.IsLocked = TypeGuard.WrapFunctionParams(Cleaner.IsLocked, TypeGuard.Object())
end
Cleaner.isLocked = Cleaner.IsLocked

-- Creates an object which signals for a Cleaner to call an arbitrary method name with a set of params
function Cleaner.CustomMethod(Object, Name, ...)
    local Args = {...}

    return {
        IsCustomMethod = true;

        Destroy = function()
            Object[Name](Object, unpack(Args))
        end;
    };
end

return Cleaner