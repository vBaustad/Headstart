-- /headstart perf: what Headstart costs, measured by the game itself, beside the addons that cost most.
--   The game's own profiler (C_AddOnProfiler) times every addon's code each frame; memory is the game's
--   count per addon. Nothing here measures anything by itself, and none of it is loaded until asked
--   for (this file is part of Headstart_Options, the load-on-demand window addon).
--   Read it as: ms a frame is the time our code takes out of each frame (at 60 frames a second a frame
--   is 16.7 ms); "frames over 1 ms" are hitches of ours since login.
local YR = _G.HeadstartNS

local OURS = { "Headstart", "Headstart_Options", "Headstart_Setup", "Headstart_Routes" }

local function Metric(name, metric)
    local profiler = _G.C_AddOnProfiler
    if type(profiler) ~= "table" or not profiler.GetAddOnMetric or metric == nil then return nil end
    local ok, v = pcall(profiler.GetAddOnMetric, name, metric)
    return ok and type(v) == "number" and v or nil
end

local function Loaded(name)
    local ok, yes = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and yes
end

--- The numbers as lines of text (also for the tests).
function YR.PerfLines()
    local out = {}
    local M = Enum and Enum.AddOnProfilerMetric or {}
    local profiler = _G.C_AddOnProfiler
    local profiling = type(profiler) == "table" and profiler.IsEnabled and profiler.IsEnabled()
    if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
    local kb, recent, session = 0, 0, 0
    for _, name in ipairs(OURS) do
        if Loaded(name) then
            local mem = GetAddOnMemoryUsage and GetAddOnMemoryUsage(name) or 0
            local r, s, peak = Metric(name, M.RecentAverageTime), Metric(name, M.SessionAverageTime), Metric(name, M.PeakTime)
            local over1, over5 = Metric(name, M.CountTimeOver1Ms), Metric(name, M.CountTimeOver5Ms)
            kb, recent, session = kb + mem, recent + (r or 0), session + (s or 0)
            out[#out + 1] = ("%s: %.0f KB%s"):format(name, mem, r and (", %.3f ms a frame now (%.3f since login), peak %.2f ms, frames over 1 ms: %d, over 5 ms: %d")
                :format(r, s or 0, peak or 0, over1 or 0, over5 or 0) or "")
        end
    end
    table.insert(out, 1, ("Headstart in all: %.0f KB%s"):format(kb,
        profiling and (", %.3f ms a frame now, %.3f since login"):format(recent, session) or " (the game's addon profiler is off: no timings)"))
    -- beside the addons that take the most time now
    if profiling and profiler.GetTopKAddOnsForMetric and M.RecentAverageTime then
        local ok, top = pcall(profiler.GetTopKAddOnsForMetric, M.RecentAverageTime, 8)
        if ok and type(top) == "table" then
            local names = {}
            for _, t in ipairs(top) do
                if type(t) == "table" and t.addOnName then
                    -- (each comes with its time: AddOnProfilerResult.metricValue)
                    local v = type(t.metricValue) == "number" and t.metricValue or Metric(t.addOnName, M.RecentAverageTime)
                    names[#names + 1] = ("%s %.3f"):format(t.addOnName, v or 0)
                end
            end
            if #names > 0 then out[#out + 1] = "The most time a frame now (ms): " .. table.concat(names, ", ") end
        end
        local all = profiler.GetOverallMetric and select(2, pcall(profiler.GetOverallMetric, M.RecentAverageTime))
        if type(all) == "number" and all > 0 then
            out[#out + 1] = ("Every addon together: %.3f ms a frame; Headstart is %.1f%% of that"):format(all, recent / all * 100)
        end
    end
    return out
end

function YR.Perf()
    for i, line in ipairs(YR.PerfLines()) do
        if i == 1 then YR.Print(line) else print("  " .. line) end
    end
end
