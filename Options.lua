-- The options page (Esc > Options > AddOns > YippRoute): one checkbox per feature.
local _, YR = ...

local OPTIONS = {
    { key = "showSplits", name = "Show level splits",
      tooltip = "A timer of this character's playing time since level 1, and how far ahead of or behind your best run you are at each level.",
      apply = function(on) YR:ShowSplits(on) end },
    { key = "pickRewards", name = "Pick quest rewards (up to level 10)",
      tooltip = "When a quest offers a choice, take a two-handed weapon, else mail armour, else water. Hold Shift to choose yourself." },
    { key = "logging", name = "Log runs",
      tooltip = "Record quests, levels, deaths, fights and your position every 2 seconds, for the route analysis.",
      apply = function(on) YR:SetLogging(on) end },
}

function YR:BuildOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category = Settings.RegisterVerticalLayoutCategory("YippRoute")
    for _, o in ipairs(OPTIONS) do
        if YippRouteDB[o.key] == nil then YippRouteDB[o.key] = true end
        local setting = Settings.RegisterAddOnSetting(category, "YippRoute_" .. o.key, o.key, YippRouteDB,
            type(true), o.name, true)
        if o.apply then setting:SetValueChangedCallback(function(_, value) o.apply(value) end) end
        Settings.CreateCheckbox(category, setting, o.tooltip)
    end
    Settings.RegisterAddOnCategory(category)
end
