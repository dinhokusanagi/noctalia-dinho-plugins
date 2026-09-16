--!nonstrict

local PLAYERCTL = "/run/current-system/sw/bin/playerctl"

local lyrics = {}
local currentPlayer = ""
local currentTitle = ""
local currentArtist = ""

local currentPosition = 0
local LYRICS_OFFSET = 0

local playerIsPlaying = false

local lastLookupKey = ""

local positionCache = {}
local positionCacheOrder = {}
local MAX_POSITION_CACHE = 3

local state = "no_player"

local function normalizePosition(value)
    local n = tonumber(value)

    if not n then
        return nil
    end

    -- playerctl/MPRIS normalmente usa microssegundos.
    if n > 100000 then
        return n / 1000000
    end

    return n
end


local function cachePosition(key, position)
    positionCache[key] = position

    for i, cachedKey in ipairs(positionCacheOrder) do
        if cachedKey == key then
            table.remove(positionCacheOrder, i)
            break
        end
    end

    table.insert(positionCacheOrder, key)

    while #positionCacheOrder > MAX_POSITION_CACHE do
        local oldestKey = table.remove(positionCacheOrder, 1)
        positionCache[oldestKey] = nil
    end
end


local function clearCachedPosition(key)
    positionCache[key] = nil

    for i, cachedKey in ipairs(positionCacheOrder) do
        if cachedKey == key then
            table.remove(positionCacheOrder, i)
            break
        end
    end
end


function parseLrc(text)
    local result = {}

    for line in text:gmatch("[^\r\n]+") do
        for minutes, seconds, hundredths, lyric in line:gmatch(
            "%[(%d+):(%d+)%.(%d+)%]%s*(.*)"
        ) do
            local time =
                tonumber(minutes) * 60
                + tonumber(seconds)
                + tonumber(hundredths) / 100

            table.insert(result, {
                time = time,
                text = lyric,
            })
        end
    end

    table.sort(result, function(a, b)
        return a.time < b.time
    end)

    return result
end


function parsePlain(text)
    local result = {}

    for line in text:gmatch("[^\r\n]+") do
        if line ~= "" then
            table.insert(result, {
                time = nil,
                text = line,
            })
        end
    end

    return result
end


function searchLyricsFallback(title, artist)
    local query = noctalia.string.urlEncode(title .. " " .. artist)

    noctalia.http(
        {
            url = "https://lrclib.net/api/search?q=" .. query,
            method = "GET",
            headers = {
                "User-Agent: Noctalia-Lyrics/1.0",
                "Accept: application/json",
            },
        },
        function(response)
            if not response or not response.ok or not response.body then
                lyrics = {}
                state = "not_found"
                render()
                return
            end

            local ok, results = pcall(
                noctalia.json.decode,
                response.body
            )

            if not ok or type(results) ~= "table" then
                lyrics = {}
                state = "not_found"
                render()
                return
            end

            -- Primeiro tenta letras sincronizadas
            for _, item in ipairs(results) do
                if item.syncedLyrics and item.syncedLyrics ~= "" then
                    lyrics = parseLrc(item.syncedLyrics)

                    if #lyrics > 0 then
                        state = "lyrics"
                        render()
                        return
                    end
                end
            end

            -- Depois aceita letras simples
            for _, item in ipairs(results) do
                if item.plainLyrics and item.plainLyrics ~= "" then
                    lyrics = parsePlain(item.plainLyrics)

                    if #lyrics > 0 then
                        state = "lyrics"
                        render()
                        return
                    end
                end
            end

            lyrics = {}
            state = "not_found"
            render()
        end
    )
end


function searchLyrics(title, artist)
    local encodedTitle = noctalia.string.urlEncode(title)
    local encodedArtist = noctalia.string.urlEncode(artist)

    local url =
        "https://lrclib.net/api/get?track_name="
        .. encodedTitle
        .. "&artist_name="
        .. encodedArtist

    noctalia.http(
        {
            url = url,
            method = "GET",
            headers = {
                "User-Agent: Noctalia-Lyrics/1.0",
                "Accept: application/json",
            },
        },
        function(response)
            if response and response.ok and response.body then
                local ok, data =
                    pcall(noctalia.json.decode, response.body)

                if ok and data then
                    -- Primeiro tenta sincronizada
                    if data.syncedLyrics
                        and data.syncedLyrics ~= "" then

                        lyrics = parseLrc(data.syncedLyrics)

                        if #lyrics > 0 then
                            state = "lyrics"
                            render()
                            return
                        end
                    end

                    -- Depois aceita plain lyrics
                    if data.plainLyrics
                        and data.plainLyrics ~= "" then

                        lyrics = parsePlain(data.plainLyrics)

                        if #lyrics > 0 then
                            state = "lyrics"
                            render()
                            return
                        end
                    end
                end
            end

            searchLyricsFallback(title, artist)
        end
    )
end


local function runPlayerctl()
    noctalia.runAsync(
        PLAYERCTL
            .. " -a metadata --format '{{status}}|{{title}}|{{artist}}|{{position}}|{{playerName}}'",
        function(result)

            if not result
                or result.exitCode ~= 0
                or not result.stdout then

                playerIsPlaying = false
                state = "no_player"
                lyrics = {}
                lastLookupKey = ""
                positionCache = {}
                positionCacheOrder = {}
                render()
                return
            end

            local line = result.stdout:gsub("%s+$", "")

            if line == "" then
                playerIsPlaying = false
                state = "no_player"
                lyrics = {}
                lastLookupKey = ""
                positionCache = {}
                positionCacheOrder = {}
                render()
                return
            end

            local status, title, artist, position, player =
                line:match(
                    "([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)"
                )

            print(
                "LYRICS DEBUG:",
                status,
                title,
                artist,
                position,
                player
            )

            if not title or title == "" then
                playerIsPlaying = false
                state = "no_player"
                lyrics = {}
                lastLookupKey = ""
                positionCache = {}
                positionCacheOrder = {}
                render()
                return
            end

            currentPlayer = player or ""
            currentTitle = title or ""
            currentArtist = artist or ""

            local lookupKey =
                currentArtist .. "|" .. currentTitle

	    local mprisPosition = normalizePosition(position)

            -- Música nova
            if lookupKey ~= lastLookupKey then
                lastLookupKey = lookupKey

                lyrics = {}
                state = "searching"

                currentPosition = positionCache[lookupKey] or 0
                playerIsPlaying = status == "Playing"

                render()
                searchLyrics(currentTitle, currentArtist)
                return
            end
            
            -- A mesma música foi reiniciada.
            -- Limpa somente a memória dessa música.
            if mprisPosition
                and mprisPosition <= 3
                and currentPosition > 5 then
            
                clearCachedPosition(lookupKey)
            
                currentPosition = 0
                lyrics = {}
                state = "searching"
                playerIsPlaying = status == "Playing"
            
                render()
                searchLyrics(currentTitle, currentArtist)
                return
             end

            -- Player pausado
            if status == "Paused" then
                state = "paused"
                playerIsPlaying = false
                render()
                return
            end

            -- Player tocando
            if status == "Playing" then
                state = "lyrics"
                playerIsPlaying = true
                render()
                return
            end

            playerIsPlaying = false
            state = "no_player"
            render()
        end,
        2000
    )
end


function getCurrentLine()
    if #lyrics == 0 then
        return 1
    end

    local current = 1

    -- A letra é considerada ativa 11 segundos antes
    -- do timestamp original do LRCLIB.
   local LYRICS_SPEED = 1.01

local syncPosition =
    (currentPosition * LYRICS_SPEED) + LYRICS_OFFSET

    for i = 1, #lyrics do
        local line = lyrics[i]

        if line.time
            and line.text
            and line.text ~= ""
            and syncPosition >= line.time then

            current = i

        elseif line.time and syncPosition < line.time then
            break
        end
     end

    return current
end

function render()
    local rows = {}

    if state == "searching" then

        table.insert(
            rows,
            ui.label({
                text = "♪ Buscando letra...",
                fontSize = 20,
                color = "secondary",
            })
        )

    elseif state == "not_found" then

        table.insert(
            rows,
            ui.label({
                text = "♪ Sem letra disponível",
                fontSize = 20,
                color = "secondary",
            })
        )

    elseif state == "paused" then

        local current = getCurrentLine()
        local line = lyrics[current]

        table.insert(
            rows,
            ui.label({
                text = line and line.text or "♪ Pausado",
                fontSize = 24,
                fontWeight = "bold",
                color = "primary",
                maxLines = 1,
                textAlign = "center",
            })
        )

    else

        local current = getCurrentLine()

        for offset = -2, 2 do
            local index = current + offset
            local line = lyrics[index]
            local isCurrent = offset == 0

            local text = " "

            if line and line.text and line.text ~= "" then
                text = line.text
            end

            local fontSize = isCurrent and 30 or 24

        table.insert(
            rows,
            ui.label({
                text = text,
                fontSize = 32,
                fontWeight = isCurrent and "bold" or "normal",
                baseline = "textFixedHeight",
                color = isCurrent
                    and (noctalia.getConfig("current_color") or "primary")
                    or (noctalia.getConfig("secondary_color") or "secondary"),
                opacity = isCurrent and 1.0 or 0.73,
                maxLines = 1,
                textAlign = "center",
            })
        )
        end
    end

    desktopWidget.render(
        ui.column(
            {
                gap = 10,
                align = "center",
            },
            rows
        )
    )
end


-- Atualiza o tempo da música usando o tempo real
-- decorrido entre os frames do desktop widget.
function onFrameTick(deltaMs)
    if not playerIsPlaying then
        return
    end

    currentPosition =
        currentPosition + (deltaMs / 1000)

	cachePosition(
            currentArtist .. "|" .. currentTitle,
            currentPosition
        )

    render()
end


-- Habilita os ticks de frame do desktop widget.
desktopWidget.setNeedsFrameTick(true)


noctalia.setUpdateInterval(500)

function update()
    runPlayerctl()
end


render()
update()
