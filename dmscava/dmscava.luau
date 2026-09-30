--!nonstrict

-- DMSCava
-- Single-file CAVA desktop visualizer.
--
-- Styles:
--   bars
--   box
--   wall
--   enderpulse
--
-- CAVA stream handling is kept inside this file intentionally.

local BAR_COUNT = 32

local DEFAULT_BAR_WIDTH = 8
local DEFAULT_BAR_SPACING = 6
local DEFAULT_MIN_HEIGHT = 8
local DEFAULT_MAX_HEIGHT = 180
local DEFAULT_SMOOTHING = 70
local DEFAULT_SENSITIVITY = 100
local DEFAULT_OPACITY = 75

local bars = {}
local smoothedBars = {}

local streamStarted = false

for i = 1, BAR_COUNT do
    bars[i] = 0
    smoothedBars[i] = 0
end

local function numberSetting(key, default)
    return tonumber(noctalia.getConfig(key)) or default
end

local function colorSetting(key, default)
    return noctalia.getConfig(key) or default
end

local function styleSetting()
    return tostring(noctalia.getConfig("style") or "bars"):lower()
end

local function smoothingAlpha(value)
    value = math.max(0, math.min(100, value))

    return 0.35
        - (value / 100) * 0.27
end

local function parseCavaLine(line)
    local values = {}

    for value in tostring(line or ""):gmatch("%d+") do
        if #values < BAR_COUNT then
            table.insert(
                values,
                tonumber(value) or 0
            )
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

    local sensitivity = math.max(
        0,
        math.min(
            100,
            numberSetting(
                "sensitivity",
                DEFAULT_SENSITIVITY
            )
        )
    )

    local alpha = smoothingAlpha(smoothing)

    for i = 1, BAR_COUNT do
        local raw = math.max(
            0,
            math.min(
                1000,
                values[i] or 0
            )
        )

        raw =
            raw
            * (sensitivity / 100)

        bars[i] =
            bars[i]
            + (raw - bars[i])
            * alpha

        smoothedBars[i] =
            smoothedBars[i]
            + (raw - smoothedBars[i])
            * alpha
    end
end

local function normalizedValue(value)
    return math.max(
        0,
        math.min(
            1,
            value / 300
        )
    )
end

local function barHeight(value)
    local minHeight = numberSetting(
        "min_height",
        DEFAULT_MIN_HEIGHT
    )

    local maxHeight = numberSetting(
        "max_height",
        DEFAULT_MAX_HEIGHT
    )

    return minHeight
        + (maxHeight - minHeight)
        * normalizedValue(value)
end

local function commonValues()
    return {
        width = numberSetting(
            "bar_width",
            DEFAULT_BAR_WIDTH
        ),

        spacing = numberSetting(
            "bar_spacing",
            DEFAULT_BAR_SPACING
        ),

        maxHeight = numberSetting(
            "max_height",
            DEFAULT_MAX_HEIGHT
        ),

        opacity =
            math.max(
                0,
                math.min(
                    100,
                    numberSetting(
                        "opacity",
                        DEFAULT_OPACITY
                    )
                )
            ) / 100,

        color = colorSetting(
            "normal_color",
            "primary"
        ),
    }
end

local function renderBars()
    local cfg = commonValues()
    local children = {}

    for i = 1, BAR_COUNT do
        local height =
            barHeight(
                smoothedBars[i] or 0
            )

        table.insert(
            children,
            ui.box({
                key =
                    "dmscava-bars-"
                    .. tostring(i),

                width = cfg.width,
                height = height,

                radius =
                    cfg.width / 2,

                opacity = cfg.opacity,
                fill = cfg.color,
            })
        )
    end

    desktopWidget.render(
        ui.row(
            {
                gap = cfg.spacing,
                align = "end",
                justify = "center",
                minHeight = cfg.maxHeight,
            },
            children
        )
    )
end

local function renderBox()
    local cfg = commonValues()
    local children = {}

    for i = 1, BAR_COUNT do
        local height =
            barHeight(
                smoothedBars[i] or 0
            )

        table.insert(
            children,
            ui.box({
                key =
                    "dmscava-box-"
                    .. tostring(i),

                width = cfg.width,
                height = height,

                radius =
                    math.max(
                        2,
                        cfg.width * 0.28
                    ),

                opacity = cfg.opacity,
                fill = cfg.color,
            })
        )
    end

    desktopWidget.render(
        ui.row(
            {
                gap = cfg.spacing,
                align = "center",
                justify = "center",
                minHeight = cfg.maxHeight,
            },
            children
        )
    )
end

local function renderWall()
    local cfg = commonValues()
    local children = {}

    local half = math.floor(BAR_COUNT / 2)

    for i = 1, half do
        local left =
            smoothedBars[i] or 0

        local right =
            smoothedBars[
                BAR_COUNT - i + 1
            ] or 0

        local value =
            math.max(
                left,
                right
            )

        local height =
            barHeight(value)

        table.insert(
            children,
            ui.box({
                key =
                    "dmscava-wall-left-"
                    .. tostring(i),

                width = cfg.width,
                height = height,

                radius =
                    cfg.width / 2,

                opacity = cfg.opacity,
                fill = cfg.color,
            })
        )
    end

    for i = half, 1, -1 do
        local left =
            smoothedBars[i] or 0

        local right =
            smoothedBars[
                BAR_COUNT - i + 1
            ] or 0

        local value =
            math.max(
                left,
                right
            )

        local height =
            barHeight(value)

        table.insert(
            children,
            ui.box({
                key =
                    "dmscava-wall-right-"
                    .. tostring(i),

                width = cfg.width,
                height = height,

                radius =
                    cfg.width / 2,

                opacity = cfg.opacity,
                fill = cfg.color,
            })
        )
    end

    desktopWidget.render(
        ui.row(
            {
                gap = cfg.spacing,
                align = "center",
                justify = "center",
                minHeight = cfg.maxHeight,
            },
            children
        )
    )
end

local function renderEnderPulse()
    local cfg = commonValues()
    local children = {}

    for i = 1, BAR_COUNT do
        local value =
            smoothedBars[i] or 0

        local normalized =
            normalizedValue(value)

        local height =
            cfg.maxHeight * normalized

        height =
            math.max(
                numberSetting(
                    "min_height",
                    DEFAULT_MIN_HEIGHT
                ),
                height
            )

        table.insert(
            children,
            ui.box({
                key =
                    "dmscava-enderpulse-"
                    .. tostring(i),

                width = cfg.width,
                height = height,

                radius =
                    cfg.width / 2,

                softness = 0,

                opacity = cfg.opacity,
                fill = cfg.color,
            })
        )
    end

    desktopWidget.render(
        ui.row(
            {
                gap = cfg.spacing,
                align = "end",
                justify = "center",
                minHeight = cfg.maxHeight,
            },
            children
        )
    )
end

local function render()
    local style = styleSetting()

    if style == "box" then
        renderBox()
        return
    end

    if style == "wall" then
        renderWall()
        return
    end

    if style == "enderpulse" then
        renderEnderPulse()
        return
    end

    renderBars()
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\''") .. "'"
end

local function startCava()
    if streamStarted then
        return
    end

    if not noctalia.commandExists("cava") then
        noctalia.log(
            "DMSCava: cava was not found in PATH"
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
        "printf '%s\n' "
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
                    render()
                end
            end
        )

    if started then
        streamStarted = true

        noctalia.log(
            "DMSCava: CAVA stream started"
        )
    else
        noctalia.log(
            "DMSCava: failed to start CAVA stream"
        )
    end
end

local function update()
    if not streamStarted then
        startCava()
    end
end

desktopWidget.setNeedsFrameTick(true)

render()
startCava()

return {
    update = update,
    render = render,
}
