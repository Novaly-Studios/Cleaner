return function()
    local Cleaner = require(script.Parent)

    local function GetTestClass()
        local TestClass = {}
        TestClass.__index = TestClass

        function TestClass.new()
            return setmetatable({}, TestClass)
        end

        return TestClass
    end

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

            local function GetValidTypeArray()
                return {
                    Instance.new("Part");
                    game.ChildAdded:Connect(function() end);
                    Cleaner.new();
                    coroutine.running();
                    function() end;
                    { Destroy = function() end };
                    { Disconnect = function() end };
                }
            end

            expect(function() -- Array of all valid types above
                Cleaner.new():Add(GetValidTypeArray())
            end).never.to.throw()

            expect(function() -- Valid types + number
                local Valid = GetValidTypeArray()
                table.insert(Valid, 1)
                Cleaner.new():Add(Valid)
            end).to.throw()

            expect(function() -- Valid types + string
                local Valid = GetValidTypeArray()
                table.insert(Valid, "test")
                Cleaner.new():Add(Valid)
            end).to.throw()

            expect(function() -- Valid types + unsupported object
                local Valid = GetValidTypeArray()
                table.insert(Valid, {})
                Cleaner.new():Add(Valid)
            end).to.throw()
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
            Part.Parent = game:GetService("Workspace")

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
            Test:Clean()
            Instance.new("Part", Part)

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

        it("should run functions async", function()
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
        end)

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

        it("should clean objects given in an array", function()
            local Test = Cleaner.new()
            local Count = 0

            Test:Add({
                function()
                    Count += 1
                end;
                {
                    Disconnect = function()
                        Count += 1
                    end;
                };
                {
                    Destroy = function()
                        Count += 1
                    end;
                };
            })

            expect(Count).to.equal(0)
            Test:Clean()
            expect(Count).to.equal(3)
        end)
    end)

    describe("Cleaner.Add, Cleaner.Clean", function()
        it("should automatically clean for items added after", function()
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

    describe("Cleaner.Spawn", function()
        it("should spawn a function async", function()
            local Complete = false

            Cleaner.new():Spawn(function()
                Complete = true
            end)

            expect(Complete).to.equal(true)
        end)

        it("should terminate the spawned coroutine when Clean is called", function()
            local Test = Cleaner.new()
            local Complete = false

            Test:Spawn(function()
                task.wait()
                Complete = true
            end)
            Test:Clean()

            task.wait()
            expect(Complete).to.equal(false)
        end)
    end)

    describe("Cleaner.Lock", function()
        it("should throw with no object given", function()
            expect(function()
                Cleaner.Lock()
            end).to.throw()
        end)

        it("should accept an object", function()
            expect(function()
                Cleaner.Lock({})
            end).never.to.throw()
        end)

        it("should disallow reads on an object", function()
            local Object = {
                X = 1;
            }

            Cleaner.Lock(Object)

            expect(function()
                local Temp1 = Object.X
            end).to.throw()

            expect(function()
                local Temp2 = Object.Y
            end).to.throw()
        end)

        it("should disallow writes on an object", function()
            local Object = {
                X = 1;
            }

            Cleaner.Lock(Object)

            expect(function()
                Object.X = 2
            end).to.throw()

            expect(function()
                Object.Y = 3
            end).to.throw()
        end)
    end)

    describe("Cleaner.Wrap", function()
        it("should throw with no class given", function()
            expect(function()
                Cleaner.Wrap()
            end).to.throw()
        end)

        it("should throw with an invalid class given", function()
            expect(function()
                Cleaner.Wrap({
                    new = function() end;
                })
            end).to.throw()

            expect(function()
                Cleaner.Wrap({
                    __index = {}
                })
            end).to.throw()
        end)

        it("should accept a valid class", function()
            local Test = GetTestClass()

            expect(function()
                Cleaner.Wrap(Test)
            end).never.to.throw()
        end)

        it("should lock a destroyed object down", function()
            local Test = GetTestClass()
            Cleaner.Wrap(Test)

            expect(function()
                local Temp = Test.X
            end).never.to.throw()

            expect(function()
                Test.Y = 1
            end).never.to.throw()

            Test:Destroy()

            expect(function()
                local Temp = Test.X
            end).to.throw()

            expect(function()
                Test.Y = 2
            end).to.throw()
        end)

        it("should prevent multiple wraps", function()
            local Test = GetTestClass()
            Cleaner.Wrap(Test)

            expect(function()
                Cleaner.Wrap(Test)
            end).to.throw()
        end)

        it("should work without Destroy being initially present", function()
            local Test1 = GetTestClass()
            Cleaner.Wrap(Test1)
            expect(Test1.Destroy).to.be.ok()

            local Test2 = GetTestClass()
            local Destroyed = false

            function Test2:Destroy()
                Destroyed = true
            end

            Cleaner.Wrap(Test2)
            Test2.new():Destroy()
            expect(Destroyed).to.equal(true)
        end)
    end)

    describe("Cleaner.Wrap, Cleaner.IsWrapped", function()
        it("should detect when a class is wrapped", function()
            local Test = GetTestClass()
            expect(Cleaner.IsWrapped(Test)).to.equal(false)
            Cleaner.Wrap(Test)
            expect(Cleaner.IsWrapped(Test)).to.equal(true)
        end)
    end)
end