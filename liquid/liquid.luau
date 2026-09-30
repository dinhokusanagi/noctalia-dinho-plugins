--!nonstrict

local BAR_COUNT = 32
local DEFAULT_BAR_WIDTH = 8
local DEFAULT_BAR_SPACING = 6
local DEFAULT_MIN_HEIGHT = 8
local DEFAULT_MAX_HEIGHT = 180
local DEFAULT_SMOOTHING = 70

local bars = {}
local smoothedBars = {}
local highlightIndex = 1
local streamStarted = false

for i = 1, BAR_COUNT do
    bars[i] = 0
    smoothedBars[i] = 0
end

local render

local function numberSetting(key, default)
    return tonumber(noctalia.getConfig(key)) or default
end

local function colorSetting(key, default)
    return noctalia.getConfig(key) or default
end

local function smoothingAlpha(value)
    value = math.max(0, math.min(100, value))
    return 0.35 - (value / 100) * 0.27
end

local function parseCavaLine(line)
    local values = {}

    for value in tostring(line or ""):gmatch("%d+") do
        if #values < BAR_COUNT then
            table.insert(values, tonumber(value) or 0)
        end
    end

    if #values ~= BAR_COUNT then
        return nil
    end

    return values
end

local function updateSpectrum(values)
    local smoothing = numberSetting(
        "smoothing",
        DEFAULT_SMOOTHING
    )

    local alpha = smoothingAlpha(smoothing)

    local strongestIndex = highlightIndex
    local strongestValue = -1

    for i = 1, BAR_COUNT do
        local raw = math.max(
            0,
            math.min(
                1000,
                values[i] or 0
            )
        )

        bars[i] = raw

        smoothedBars[i] =
            smoothedBars[i]
            + (raw - smoothedBars[i]) * alpha

        if smoothedBars[i] > strongestValue then
            strongestValue = smoothedBars[i]
            strongestIndex = i
        end
    end

    local currentValue =
        smoothedBars[highlightIndex] or 0

    local switchThreshold =
        math.max(
            currentValue * 1.08,
            currentValue + 12
        )

    if strongestIndex ~= highlightIndex
        and strongestValue >= switchThreshold then

        highlightIndex =
            strongestIndex
    end

    render()
end

render = function()
    local barWidth = numberSetting(
        "bar_width",
        DEFAULT_BAR_WIDTH
    )

    local barSpacing = numberSetting(
        "bar_spacing",
        DEFAULT_BAR_SPACING
    )

    local minHeight = numberSetting(
        "min_height",
        DEFAULT_MIN_HEIGHT
    )

    local maxHeight = numberSetting(
        "max_height",
        DEFAULT_MAX_HEIGHT
    )

    local normalColor = colorSetting(
        "normal_color",
        "primary"
    )

    local highlightColor = colorSetting(
        "highlight_color",
        "secondary"
    )

    if maxHeight < minHeight then
        maxHeight = minHeight
    end

    local children = {}

    for i = 1, BAR_COUNT do
        local value =
            smoothedBars[i] or 0

        local normalized =
            math.max(
                0,
                math.min(
                    1,
                    value / 1000
                )
            )

        local height =
            minHeight
            + (maxHeight - minHeight)
            * normalized

        table.insert(
            children,
            ui.box({
                key =
                    "liquid-bar-"
                    .. tostring(i),

                width =
                    barWidth,

                height =
                    height,
                radius =
                   barWidth / 2,
                fill =
                    i == highlightIndex
                    and highlightColor
                    or normalColor,
            })
        )
    end

    desktopWidget.render(
        ui.row(
            {
                gap = barSpacing,
                align = "end",
                justify = "center",
                minHeight = maxHeight,
            },
            children
        )
    )
end

local function shellQuote(value)
    value = tostring(value or "")

    return "'"
        .. value:gsub(
            "'",
            "'\\''"
        )
        .. "'"
end

local function startCava()
    if streamStarted then
        return
    end

    if not noctalia.commandExists("cava") then
        noctalia.log(
            "Liquid: cava was not found in PATH"
        )
        return
    end

    local config = [[
[general]
framerate = 60
bars = 32
autosens = 1

[input]
method = pulse
source = auto

[output]
method = raw
channels = mono
mono_option = average
reverse = 0
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
frame_delimiter = 10

[smoothing]
integral = 0
monstercat = 0
waves = 0
]]

    local command =
        "printf '%s\\n' "
        .. shellQuote(config)
        .. " | cava -p /dev/stdin"

    local started =
        noctalia.runStream(
            command,

            function(line)
                local values =
                    parseCavaLine(line)

                if values then
                    updateSpectrum(values)
                end
            end
        )

    if started then
        streamStarted = true
        noctalia.log(
            "Liquid: CAVA stream started"
        )
    else
        noctalia.log(
            "Liquid: failed to start CAVA stream"
        )
    end
end

function update()
    if not streamStarted then
        startCava()
    end
end

render()
startCava()
