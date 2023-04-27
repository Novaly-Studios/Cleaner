--!strict
--https://gist.github.com/zeux/99c0ede2680d1aad565cb37e0d0f076d

--[[
BSD Zero Clause License

Copyright (c) 2022 Arseny Kapoulkine

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
]]--

export type GCTracker = {
    -- track the lifetime of object obj; update will call dtor when obj is dead
    -- note: dtor should not reference obj directly or transitively since tracker keeps a strong reference to it
    track: (obj: any, dtor: () -> ()) -> any,
    -- forget previously tracked object; note, this needs to be passed the token that was returned by track
    forget: (token: any) -> (),
    -- update tracker, calling destructors for dead objects; if n is specified, do at most n iterations to amortize cost
    update: (n: number?) -> ()
}

local function GCTracker(): GCTracker
    -- key: token
    -- value: tracked object (weak)
    local tobj = {}
    setmetatable(tobj, { __mode = "vs" })

    -- key: token
    -- value: destructor
    local tdtor = {}

    local self = { lasttoken = nil }

    function self.track(obj, dtor)
        assert(type(dtor) == "function")

        local token = newproxy()

        tobj[token] = obj
        tdtor[token] = dtor

        return token
    end

    function self.forget(token)
        assert(type(token) == "userdata")
        assert(tdtor[token] ~= nil)

        tobj[token] = nil
        tdtor[token] = nil
    end

    function self.update(n: number?)
        assert(n == nil or type(n) == "number")

        if n then
            local lt = self.lasttoken
            if lt ~= nil and tdtor[lt] == nil then
                lt = nil
            end

            for i=1,n do
                local k, v = next(tdtor, lt)

                if k == nil then
                    lt = nil
                    break
                end

                if tobj[k] == nil then
                    pcall(v)
                    tdtor[k] = nil
                end

                lt = k
            end

            self.lasttoken = lt
        else
            for k,v in tdtor do
                if tobj[k] == nil then
                    pcall(v)
                    tdtor[k] = nil
                end
            end
        end
    end

    return self
end

return { new = GCTracker }