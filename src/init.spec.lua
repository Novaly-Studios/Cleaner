local Workspace = game:GetService("Workspace")

local function anyfn(...) return ({} :: any) end
it = it or anyfn
expect = expect or anyfn
describe = describe or anyfn

return function()
    local Cleaner = require(script.Parent)

    describe("Cleaner.new", function()
        it("should create a new Cleaner", function()
            expect(Cleaner.new()).never.to.equal(nil)
            expect(Cleaner.new()).to.be.a("table")
        end)
    end)

    describe("Cleaner.Add", function()
        it("should reject invalid objects", function()
            expect(function() -- Number
                Cleaner.new():Add(1)
            end).to.throw()

            expect(function() -- String
                Cleaner.new():Add("test")
            end).to.throw()

            expect(function() -- Empty/unsupported object
                Cleaner.new():Add({})
            end).to.throw()
        end)

        it("should accept only valid CleanableObjects", function()
            expect(function() -- Instance
                Cleaner.new():Add(Instance.new("Part"))
            end).never.to.throw()

            expect(function() -- Inbuilt Signal connection
                local Connection = game.ChildAdded:Connect(function() end)
                Cleaner.new():Add(Connection)
                Connection:Disconnect()
            end).never.to.throw()

            expect(function() -- Cleaner
                Cleaner.new():Add(Cleaner.new())
            end).never.to.throw()

            expect(function() -- Coroutine
                Cleaner.new():Add(coroutine.running())
            end).never.to.throw()

            expect(function() -- Function
                Cleaner.new():Add(function() end)
            end).never.to.throw()

            expect(function() -- Custom object
                Cleaner.new():Add({
                    Destroy = function() end;
                })
            end).never.to.throw()

            expect(function() -- Custom Signal implementation
                Cleaner.new():Add({
                    Disconnect = function() end;
                })
            end).never.to.throw()
        end)

        it("should accept multiple CleanableObjects as args", function()
            expect(function()
                Cleaner.new():Add({
                    Destroy = function() end;
                }, {
                    Disconnect = function() end;
                })
            end).never.to.throw()
        end)

        it("should reject when Cleaner is passed itself", function()
            local Test = Cleaner.new()

            expect(function()
                Test:Add(Test)
            end).to.throw()

            expect(function()
                Test:Add({Test})
            end).to.throw()

            expect(function()
                Test:Add({game, Test})
            end).to.throw()
        end)
    end)

    describe("Cleaner.Clean", function()
        it("should destroy Instances", function()
            local Part = Instance.new("Part")
            Part.Parent = Workspace

            local Test = Cleaner.new()
            Test:Add(Part)
            Test:Clean()

            expect(Part.Parent).to.equal(nil)
        end)

        it("should clean up script signal connections", function()
            local Part = Instance.new("Part")
            local Activated = 0

            local Test = Cleaner.new()
            Test:Add(Part.ChildAdded:Connect(function()
                Activated += 1
            end))
            Instance.new("Part", Part)
            task.wait() -- Deferred signals are evil.
            Test:Clean()
            Instance.new("Part", Part)
            task.wait()

            expect(Activated).to.equal(1)
        end)

        it("should clean up other cleaners", function()
            local Cleaned = false

            local Test1 = Cleaner.new()
                local Test2 = Cleaner.new()
                Test2:Add(function()
                    Cleaned = true
                end)
            Test1:Add(Test2)
            Test1:Clean()

            expect(Cleaned).to.equal(true)
        end)

        it("should close coroutines", function()
            local Closed = true
            local Running

            task.spawn(function()
                Running = coroutine.running()
                task.wait()
                Closed = false
            end)

            local Test = Cleaner.new()
            Test:Add(Running)
            Test:Clean()

            task.wait()
            expect(Closed).to.equal(true)
        end)

        --[[ it("should run functions async", function()
            local Count = 0

            local Test = Cleaner.new()

            for _ = 1, 5 do
                Test:Add(function()
                    Count += 1
                end)
            end

            for _ = 1, 5 do
                Test:Add(function()
                    task.wait(1)
                    Count += 1
                end)
            end

            local Time = os.clock()
            Test:Clean()
            expect(os.clock() - Time).to.be.near(0, 1/1000)
            expect(Count).to.equal(5)
        end) ]]

        it("should call Destroy on custom objects", function()
            local Test = Cleaner.new()
            local Destroyed = false

            Test:Add({
                Destroy = function()
                    Destroyed = true
                end;
            })

            expect(Destroyed).to.equal(false)
            Test:Clean()
            expect(Destroyed).to.equal(true)
        end)

        it("should call Disconnect on custom signals", function()
            local Test = Cleaner.new()
            local Disconnected = false

            Test:Add({
                Disconnect = function()
                    Disconnected = true
                end;
            })

            expect(Disconnected).to.equal(false)
            Test:Clean()
            expect(Disconnected).to.equal(true)
        end)
    end)

    describe("Cleaner.Add, Cleaner.Clean", function()
        it("should automatically clean for items added after Clean is called", function()
            local Test = Cleaner.new()
            local Count = 0

            Test:Add({
                Disconnect = function()
                    Count += 1
                end;
            })

            Test:Clean()

            Test:Add({
                Disconnect = function()
                    Count += 1
                end;
            })

            expect(Count).to.equal(2)
        end)
    end)

    describe("Cleaner.Remove", function()
        it("should accept valid CleanableObjects", function()
            expect(function()
                Cleaner.new():Remove(function() end)
            end).never.to.throw()

            expect(function()
                Cleaner.new():Remove(1)
            end).to.throw()
        end)

        it("should remove a CleanableObject", function()
            local Test = Cleaner.new()
            local Called = false

            local function TestFunc()
                Called = true
            end

            Test:Add(TestFunc)
            Test:Remove(TestFunc)
            Test:Clean()
            expect(Called).to.equal(false)
        end)

        it("should remove with variadic arguments", function()
            local Test = Cleaner.new()
            local Called = 0

            local function TestFunc1()
                Called += 1
            end

            local function TestFunc2()
                Called += 1
            end

            Test:Add(TestFunc1, TestFunc2)
            Test:Remove(TestFunc1, TestFunc2)
            Test:Clean()
            expect(Called).to.equal(0)
        end)
    end)

    describe("Cleaner.Contains", function()
        it("should accept valid CleanableObjects", function()
            expect(function()
                Cleaner.new():Contains(function() end)
            end).never.to.throw()

            expect(function()
                Cleaner.new():Contains(1)
            end).to.throw()
        end)

        it("should return true if the object is in the Cleaner", function()
            local Test = Cleaner.new()
            local TestFunc = function() end

            Test:Add(TestFunc)
            expect(Test:Contains(TestFunc)).to.equal(true)
        end)

        it("should return false if the object is not in the Cleaner", function()
            local Test = Cleaner.new()
            local TestFunc = function() end

            expect(Test:Contains(TestFunc)).to.equal(false)
        end)
    end)

    describe("Cleaner.fromInstanceLifecycles", function()
        it("should accept an Instance or array of Instances as the first arg and reject other arg types", function()
            expect(function()
                Cleaner.fromInstanceLifecycles(Instance.new("Part"))
            end).never.to.throw()

            expect(function()
                Cleaner.fromInstanceLifecycles({Instance.new("Part"), Instance.new("Part")})
            end).never.to.throw()

            expect(function()
                Cleaner.fromInstanceLifecycles(1, function() end)
            end).to.throw()
        end)

        it("accept an optional boolean as the second arg and reject non-booleans", function()
            expect(function()
                Cleaner.fromInstanceLifecycles(Instance.new("Part"), true)
            end).never.to.throw()

            expect(function()
                Cleaner.fromInstanceLifecycles(Instance.new("Part"), 1)
            end).to.throw()
        end)

        it("should accept an optional boolean as the third arg and reject non-booleans", function()
            expect(function()
                Cleaner.fromInstanceLifecycles(Instance.new("Part"), true, true)
            end).never.to.throw()

            expect(function()
                Cleaner.fromInstanceLifecycles(Instance.new("Part"), true, 1)
            end).to.throw()
        end)

        it("should clean up when one bound Instance is deparented, by default", function()
            local Part = Instance.new("Part")
            Part.Parent = Workspace

            local Test = Cleaner.fromInstanceLifecycles(Part)
            local Count = 0

            Test:Add(function()
                Count += 1
            end)

            expect(Count).to.equal(0)
            Part.Parent = nil
            task.wait()
            expect(Count).to.equal(1)
            Part:Destroy()
            task.wait()
            expect(Count).to.equal(1)
        end)

        it("should clean up when multiple bound Instances are destroyed, by default", function()
            local Part1 = Instance.new("Part")
            Part1.Parent = Workspace

            local Part2 = Instance.new("Part")
            Part2.Parent = Workspace

            local Count = 0
            local Test = Cleaner.fromInstanceLifecycles({Part1, Part2})

            Test:Add(function()
                Count += 1
            end)

            expect(Count).to.equal(0)
            Part1.Parent = nil
            task.wait()
            expect(Count).to.equal(0)
            Part2.Parent = nil
            task.wait()
            expect(Count).to.equal(1)
            Part1:Destroy()
            task.wait()
            expect(Count).to.equal(1)
            Part2:Destroy()
            task.wait()
            expect(Count).to.equal(1)
        end)

        it("should detect destroyed Instances if specified, instead of using deparent events", function()
            local Part = Instance.new("Part")
            Part.Parent = Workspace
            local Count = 0
            
            local Test = Cleaner.fromInstanceLifecycles(Part, true)
            Test:Add(function()
                Count += 1
            end)

            expect(Count).to.equal(0)
            Part.Parent = nil
            task.wait()
            expect(Count).to.equal(0)
            Part:Destroy()
            task.wait()
            expect(Count).to.equal(1)
        end)

        it("should clean when any of the given Instances are destroyed, if disjunctive is specified", function()
            local Part1 = Instance.new("Part")
            Part1.Parent = Workspace

            local Part2 = Instance.new("Part")
            Part2.Parent = Workspace

            local Test = Cleaner.fromInstanceLifecycles({Part1, Part2}, nil, true)
            local Count = 0

            Test:Add(function()
                Count += 1
            end)

            expect(Count).to.equal(0)
            Part1:Destroy()
            task.wait()
            expect(Count).to.equal(1)
            Part2:Destroy()
            task.wait()
            expect(Count).to.equal(1)
        end)
    end)
end