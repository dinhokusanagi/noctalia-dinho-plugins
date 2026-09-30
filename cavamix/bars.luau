--!nonstrict

local BAR_COUNT = 32
local VISUAL_BAR_COUNT = BAR_COUNT * 2

local DEFAULT_BAR_WIDTH = 8
local DEFAULT_BAR_SPACING = 6
local DEFAULT_MIN_HEIGHT = 8
local DEFAULT_MAX_HEIGHT = 180
local DEFAULT_SMOOTHING = 70
local DEFAULT_SENSITIVITY = 100
local DEFAULT_SPEED = 100

local bars = {}
local smoothedBars = {}
local barVelocity = {}
local highlightIndex = 1
local streamStarted = false
local mediaMonitorStarted = false
local hasActiveMedia = true

local waveJump = 0
local waveJumpVelocity = 0
local waveJumpActive = false

local WAVE_JUMP_IMPULSE = 4.2
local WAVE_JUMP_GRAVITY = 12.5

local previousPeak = 0

for i = 1, BAR_COUNT do
    bars[i] = 0
    smoothedBars[i] = 0
    barVelocity[i] = 0
end

local jumpLayout = require("./jump.luau")

local render

local function numberSetting(key, default)
    return tonumber(noctalia.getConfig(key)) or default
end

local function colorSetting(key, default)
    return noctalia.getConfig(key) or default
end

local function hideWhenNoMedia()
    return noctalia.getConfig("hide_when_no_media") == true
end

local function smoothingAlpha(value)
    value = math.max(0, math.min(100, value))

    return 0.35
        - (value / 100) * 0.27
end

local FRAME_DT = 1 / 60

local function speedAlpha(value)
    value = math.max(0, math.min(100, value))

    if value >= 100 then
        return 1
    end

    local normalized =
        value / 100

    local response =
        0.35
        + (normalized ^ 2.2) * 119.65

    return 1
        - math.exp(
            -response
            * FRAME_DT
        )
end

local function smoothingDamping(value)
    value = math.max(0, math.min(100, value))

    return 0.45
        + (value / 100) * 0.55
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

    local speed = math.max(
        0,
        math.min(
            100,
            numberSetting(
                "speed",
                DEFAULT_SPEED
            )
        )
    )

    local strongestIndex = highlightIndex
    local strongestValue = -1
    local totalValue = 0

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

        local target =
            raw

        local alpha =
            speedAlpha(speed)

        smoothedBars[i] =
            smoothedBars[i]
            + (target - smoothedBars[i])
            * alpha

        bars[i] =
            bars[i]
            + (raw - bars[i])
            * smoothingAlpha(smoothing)

        totalValue =
            totalValue
            + smoothedBars[i]

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

    local averageValue =
        totalValue / BAR_COUNT

    local peakRatio =
        strongestValue
        / math.max(
            averageValue,
            1
        )

    local peakDelta =
        strongestValue
        - previousPeak

    local jumpTrigger =
        peakRatio >= 1.65
        and peakDelta >= 18

    if jumpTrigger
        and not waveJumpActive then

        waveJump = 0

        waveJumpVelocity =
            WAVE_JUMP_IMPULSE

        waveJumpActive = true
    end

    previousPeak = strongestValue

    render()
end

render = function()
    if hideWhenNoMedia() and not hasActiveMedia then
        local barWidth = numberSetting(
            "bar_width",
            DEFAULT_BAR_WIDTH
        )

        local barSpacing = numberSetting(
            "bar_spacing",
            DEFAULT_BAR_SPACING
        )

        local maxHeight = numberSetting(
            "max_height",
            DEFAULT_MAX_HEIGHT
        )

        local totalWidth =
            VISUAL_BAR_COUNT * barWidth
            + (VISUAL_BAR_COUNT - 1) * barSpacing

        desktopWidget.render(
            ui.box({
                width = totalWidth,
                height = maxHeight,
                opacity = 0,
            })
        )

        return
    end

    local layout =
        noctalia.getConfig("layout")
        or "bars"

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

    local opacity = numberSetting(
        "opacity",
        75
    )

    local highlightOpacity = numberSetting(
        "highlight_opacity",
        100
    )

    opacity = math.max(
        0,
        math.min(
            100,
            opacity
        )
    )

    highlightOpacity = math.max(
        0,
        math.min(
            100,
            highlightOpacity
        )
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

    ----------------------------------------------------------------
    -- WAVE
    -- Barra grande fixa + bloquinho na base.
    -- Dois bloquinhos adjacentes recebem highlightColor.
    ----------------------------------------------------------------

    if layout == "jump" then
        desktopWidget.render(
            jumpLayout.render({
                BAR_COUNT = BAR_COUNT,
                VISUAL_BAR_COUNT = VISUAL_BAR_COUNT,
                smoothedBars = smoothedBars,
                highlightIndex = highlightIndex,
                barWidth = barWidth,
                barSpacing = barSpacing,
                minHeight = minHeight,
                maxHeight = maxHeight,
                opacity = opacity,
                highlightOpacity = highlightOpacity,
                normalColor = normalColor,
                highlightColor = highlightColor,
                waveJumpActive = waveJumpActive,
                waveJump = waveJump,
                numberSetting = numberSetting,
            })
        )

        return
    end

    ----------------------------------------------------------------
    -- BARS
    -- Mantém o comportamento original.
    ----------------------------------------------------------------

    local children = {}

    for i = 1, VISUAL_BAR_COUNT do
        local sourcePosition =
            ((i - 1) * (BAR_COUNT - 1))
            / (VISUAL_BAR_COUNT - 1)
            + 1

        local leftIndex =
            math.floor(sourcePosition)

        local rightIndex =
            math.min(
                BAR_COUNT,
                leftIndex + 1
            )

        local fraction =
            sourcePosition - leftIndex

        local leftValue =
            smoothedBars[leftIndex] or 0

        local rightValue =
            smoothedBars[rightIndex] or 0

        local value =
            leftValue
            + (rightValue - leftValue)
            * fraction

        local isHighlighted =
            math.abs(
                sourcePosition - highlightIndex
            ) < 0.5

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

        local sourceIndex =
            math.floor(
                sourcePosition + 0.5
            )

        table.insert(
            children,
            ui.box({
                key =
                    "cavamix-bar-"
                    .. tostring(i),

                width =
                    barWidth,

                height =
                    height,

                radius =
                    barWidth / 2,

                softness =
                    6,

                opacity =
                    sourceIndex == highlightIndex
                    and highlightOpacity / 100
                    or opacity / 100,

                fill =
                    sourceIndex == highlightIndex
                    and highlightColor
                    or normalColor,
            })
        )
    end

    desktopWidget.render(
        ui.row(
            {
                gap =
                    barSpacing,

                align =
                    "end",

                justify =
                    "center",

                minHeight =
                    maxHeight,
            },
            children
        )
    )
end

function onFrameTick(deltaMs)
    if waveJumpActive then
        local deltaSeconds =
            math.max(
                0,
                deltaMs / 1000
            )

        waveJumpVelocity =
            waveJumpVelocity
            - WAVE_JUMP_GRAVITY
            * deltaSeconds

        waveJump =
            waveJump
            + waveJumpVelocity
            * deltaSeconds

        waveJump =
            math.max(
                0,
                math.min(
                    1,
                    waveJump
                )
            )

        if waveJump <= 0
            and waveJumpVelocity <= 0 then

            waveJump = 0

            waveJumpVelocity = 0

            waveJumpActive = false
        end
    end

    render()
end

local function startMediaMonitor()
    if mediaMonitorStarted then
        return
    end

    if not noctalia.commandExists("playerctl") then
        noctalia.log(
            "CavaMix: playerctl was not found in PATH"
        )
        return
    end

    local command = [[
while true; do
    status=$(playerctl -a status --format "{{status}}" 2>/dev/null | head -n 1)
    if [ -n "$status" ]; then
        printf "%s\n" "$status"
    else
        printf "__NO_MEDIA__\n"
    fi
    sleep 1
done
]]

    local started =
        noctalia.runStream(
            command,

            function(line)
                local nextHasMedia =
                    tostring(line or "") ~= "__NO_MEDIA__"

                if hasActiveMedia ~= nextHasMedia then
                    hasActiveMedia = nextHasMedia
                    render()
                end
            end
        )

    if started then
        mediaMonitorStarted = true

        noctalia.log(
            "CavaMix: MPRIS media monitor started"
        )
    else
        noctalia.log(
            "CavaMix: failed to start MPRIS media monitor"
        )
    end
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
            "CavaMix: cava was not found in PATH"
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
            "CavaMix: CAVA stream started"
        )
    else
        noctalia.log(
            "CavaMix: failed to start CAVA stream"
        )
    end
end

function update()
    startMediaMonitor()

    if not streamStarted then
        startCava()
    end
end

desktopWidget.setNeedsFrameTick(true)

render()
startMediaMonitor()
startCava()
