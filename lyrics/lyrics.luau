--!nonstrict

local PLAYERCTL = "/run/current-system/sw/bin/playerctl"

------------------------------------------------------------
-- CAMINHO DOS ARQUIVOS
--
-- Não usamos /home/dinho.
--
-- $HOME é expandido pelo shell diretamente nos comandos.
-- Não passar esses caminhos por shellQuote(), pois isso
-- impediria a expansão de $HOME.
------------------------------------------------------------

local LYRICS_DIR =
    "$HOME/.cache/noctalia/lyrics"

local LYRICS_FILE_1 =
    "$HOME/.cache/noctalia/lyrics/lyrics_1.lrc"

local LYRICS_FILE_2 =
    "$HOME/.cache/noctalia/lyrics/lyrics_2.lrc"


------------------------------------------------------------
-- SLOTS
--
-- Cada player/aplicativo recebe um slot.
--
-- slot 1 -> lyrics_1.lrc
-- slot 2 -> lyrics_2.lrc
------------------------------------------------------------

local slots = {
    {
        id = 1,
        file = LYRICS_FILE_1,

        player = "",
        title = "",
        artist = "",

        position = 0,

        lyrics = {},

        loaded = false,
        loading = false,

        state = "no_player",

        lastLookupKey = "",
    },

    {
        id = 2,
        file = LYRICS_FILE_2,

        player = "",
        title = "",
        artist = "",

        position = 0,

        lyrics = {},

        loaded = false,
        loading = false,

        state = "no_player",

        lastLookupKey = "",
    },
}


------------------------------------------------------------
-- SLOT ATUAL EXIBIDO
------------------------------------------------------------

local activeSlot = 1


------------------------------------------------------------
-- CONFIGURAÇÕES
------------------------------------------------------------

local LYRICS_OFFSET = 0

local MAX_POSITION_CACHE = 3

local positionCache = {}
local positionCacheOrder = {}


------------------------------------------------------------
-- PARSER LRC
------------------------------------------------------------

local function parseLrc(text)

    local result = {}

    for line in text:gmatch("[^\r\n]+") do

        for minutes,
            seconds,
            hundredths,
            lyric
            in line:gmatch(
                "%[(%d+):(%d+)%.(%d+)%]%s*(.*)"
            ) do

            local time =
                tonumber(minutes) * 60
                + tonumber(seconds)
                + tonumber(hundredths) / 100

            table.insert(
                result,
                {
                    time = time,
                    text = lyric,
                }
            )
        end
    end


    table.sort(
        result,

        function(a, b)
            return a.time < b.time
        end
    )


    return result
end


------------------------------------------------------------
-- PARSER DE LETRA SIMPLES
------------------------------------------------------------

local function parsePlain(text)

    local result = {}

    for line in text:gmatch("[^\r\n]+") do

        if line ~= "" then

            table.insert(
                result,
                {
                    time = nil,
                    text = line,
                }
            )
        end
    end


    return result
end


------------------------------------------------------------
-- SHELL QUOTE
--
-- Usado para conteúdo da letra.
--
-- NÃO usar em caminhos que contenham $HOME.
------------------------------------------------------------

local function shellQuote(value)

    value =
        tostring(value or "")

    return "'" ..
        value:gsub(
            "'",
            "'\\''"
        )
        .. "'"
end


------------------------------------------------------------
-- CRIA DIRETÓRIO E ARQUIVOS
------------------------------------------------------------

local function ensureLyricsFiles(callback)

    local command =
        "mkdir -p \"$HOME/.cache/noctalia/lyrics\""
        .. " && touch "
        .. "\"$HOME/.cache/noctalia/lyrics/lyrics_1.lrc\" "
        .. "\"$HOME/.cache/noctalia/lyrics/lyrics_2.lrc\""


    print(
        "LYRICS: criando arquivos",
        LYRICS_FILE_1,
        LYRICS_FILE_2
    )


    noctalia.runAsync(
        command,

        function(result)

            if result
                and result.exitCode == 0 then

                print(
                    "LYRICS: arquivos prontos",
                    LYRICS_FILE_1,
                    LYRICS_FILE_2
                )

                callback(true)

                return
            end


            print(
                "LYRICS: erro criando arquivos",
                LYRICS_DIR,
                result
                    and result.stderr
                    or "sem resultado"
            )

            callback(false)
        end
    )
end


------------------------------------------------------------
-- POSIÇÃO MPRIS
------------------------------------------------------------

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


------------------------------------------------------------
-- CACHE DE POSIÇÃO
------------------------------------------------------------

local function cachePosition(key, position)

    positionCache[key] = position

    for i, cachedKey in ipairs(positionCacheOrder) do

        if cachedKey == key then

            table.remove(
                positionCacheOrder,
                i
            )

            break
        end
    end

    table.insert(
        positionCacheOrder,
        key
    )

    while #positionCacheOrder > MAX_POSITION_CACHE do

        local oldestKey =
            table.remove(
                positionCacheOrder,
                1
            )

        positionCache[oldestKey] = nil
    end
end


local function clearCachedPosition(key)

    positionCache[key] = nil

    for i, cachedKey in ipairs(positionCacheOrder) do

        if cachedKey == key then

            table.remove(
                positionCacheOrder,
                i
            )

            break
        end
    end
end


------------------------------------------------------------
-- SALVA A LETRA INTEIRA NO SLOT
------------------------------------------------------------

local function saveLyricsFile(
    slot,
    text,
    callback
)

    local filename

    if slot.id == 1 then
        filename = "lyrics_1.lrc"
    else
        filename = "lyrics_2.lrc"
    end


    local command =
        "mkdir -p \"$HOME/.cache/noctalia/lyrics\""
        .. " && printf '%s' "
        .. shellQuote(text)
        .. " > "
        .. "\"$HOME/.cache/noctalia/lyrics/"
        .. filename
        .. "\""


    noctalia.runAsync(
        command,

        function(result)

            if result
                and result.exitCode == 0 then

                print(
                    "LYRICS: letra salva no slot",
                    slot.id,
                    filename
                )

                callback(true)

                return
            end


            print(
                "LYRICS: erro salvando slot",
                slot.id,
                filename,
                result
                    and result.stderr
                    or "sem resultado"
            )


            callback(false)
        end
    )
end


------------------------------------------------------------
-- LÊ A LETRA INTEIRA DO SLOT
------------------------------------------------------------

local function loadLyricsFile(
    slot,
    callback
)

    local filename

    if slot.id == 1 then
        filename = "lyrics_1.lrc"
    else
        filename = "lyrics_2.lrc"
    end


    local command =
        "cat "
        .. "\"$HOME/.cache/noctalia/lyrics/"
        .. filename
        .. "\""


    noctalia.runAsync(
        command,

        function(result)

            if not result
                or result.exitCode ~= 0
                or not result.stdout then

                print(
                    "LYRICS: erro lendo arquivo",
                    slot.id,
                    filename,
                    result
                        and result.stderr
                        or "sem resultado"
                )

                callback(false)

                return
            end


            local text =
                result.stdout


            if text == "" then

                print(
                    "LYRICS: arquivo vazio",
                    slot.id,
                    filename
                )

                callback(false)

                return
            end


            print(
                "LYRICS: arquivo lido",
                slot.id,
                filename,
                "chars=",
                #text
            )


            ------------------------------------------------
            -- LRC
            ------------------------------------------------

            local parsed =
                parseLrc(text)


            print(
                "LYRICS: LRC parse",
                slot.id,
                "lines=",
                #parsed
            )


            if #parsed > 0 then

                slot.lyrics =
                    parsed

                slot.loaded =
                    true

                slot.loading =
                    false

                slot.state =
                    "lyrics"


                print(
                    "LYRICS: carregado",
                    slot.id,
                    "first=",
                    slot.lyrics[1]
                        and slot.lyrics[1].text
                        or "NIL"
                )


                callback(true)

                return
            end


            ------------------------------------------------
            -- PLAIN
            ------------------------------------------------

            parsed =
                parsePlain(text)


            print(
                "LYRICS: PLAIN parse",
                slot.id,
                "lines=",
                #parsed
            )


            if #parsed > 0 then

                slot.lyrics =
                    parsed

                slot.loaded =
                    true

                slot.loading =
                    false

                slot.state =
                    "lyrics"


                print(
                    "LYRICS: plain carregado",
                    slot.id,
                    "first=",
                    slot.lyrics[1]
                        and slot.lyrics[1].text
                        or "NIL"
                )


                callback(true)

                return
            end


            slot.loaded =
                false

            slot.loading =
                false


            print(
                "LYRICS: arquivo não pôde ser interpretado",
                slot.id,
                filename
            )


            callback(false)
        end
    )
end


------------------------------------------------------------
-- SALVA E DEPOIS LÊ
------------------------------------------------------------

local function saveAndLoadLyrics(
    slot,
    text
)

    slot.loading =
        true

    slot.state =
        "searching"


    render()


    saveLyricsFile(
        slot,
        text,

        function(saved)

            if not saved then

                slot.lyrics =
                    {}

                slot.loaded =
                    false

                slot.loading =
                    false

                slot.state =
                    "not_found"

                render()

                return
            end


            ------------------------------------------------
            -- Depois de salvar, a fonte da exibição
            -- passa a ser o arquivo.
            ------------------------------------------------

            loadLyricsFile(
                slot,

                function(loaded)

                    if loaded then

                        render()

                        return
                    end


                    slot.lyrics =
                        {}

                    slot.loaded =
                        false

                    slot.loading =
                        false

                    slot.state =
                        "not_found"


                    render()
                end
            )
        end
    )
end


------------------------------------------------------------
-- BUSCA FALLBACK
------------------------------------------------------------

local function searchLyricsFallback(
    slot,
    title,
    artist
)

    local query =
        noctalia.string.urlEncode(
            title .. " " .. artist
        )


    noctalia.http(
        {
            url =
                "https://lrclib.net/api/search?q="
                .. query,

            method = "GET",

            headers = {
                "User-Agent: Noctalia-Lyrics/1.0",
                "Accept: application/json",
            },
        },

        function(response)

            if not response
                or not response.ok
                or not response.body then

                slot.lyrics =
                    {}

                slot.loading =
                    false

                slot.state =
                    "not_found"

                render()

                return
            end


            local ok, results =
                pcall(
                    noctalia.json.decode,
                    response.body
                )


            if not ok
                or type(results) ~= "table" then

                slot.lyrics =
                    {}

                slot.loading =
                    false

                slot.state =
                    "not_found"

                render()

                return
            end


            ------------------------------------------------
            -- SINCRONIZADA
            ------------------------------------------------

            for _, item in ipairs(results) do

                if item.syncedLyrics
                    and item.syncedLyrics ~= "" then

                    saveAndLoadLyrics(
                        slot,
                        item.syncedLyrics
                    )

                    return
                end
            end


            ------------------------------------------------
            -- PLAIN
            ------------------------------------------------

            for _, item in ipairs(results) do

                if item.plainLyrics
                    and item.plainLyrics ~= "" then

                    saveAndLoadLyrics(
                        slot,
                        item.plainLyrics
                    )

                    return
                end
            end


            slot.lyrics =
                {}

            slot.loading =
                false

            slot.state =
                "not_found"

            render()
        end
    )
end


------------------------------------------------------------
-- BUSCA LRCLIB
------------------------------------------------------------

local function searchLyrics(
    slot,
    title,
    artist
)

    local encodedTitle =
        noctalia.string.urlEncode(
            title
        )


    local encodedArtist =
        noctalia.string.urlEncode(
            artist
        )


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

            if response
                and response.ok
                and response.body then

                local ok, data =
                    pcall(
                        noctalia.json.decode,
                        response.body
                    )


                if ok and data then

                    ------------------------------------------------
                    -- SINCRONIZADA
                    ------------------------------------------------

                    if data.syncedLyrics
                        and data.syncedLyrics ~= "" then

                        saveAndLoadLyrics(
                            slot,
                            data.syncedLyrics
                        )

                        return
                    end


                    ------------------------------------------------
                    -- PLAIN
                    ------------------------------------------------

                    if data.plainLyrics
                        and data.plainLyrics ~= "" then

                        saveAndLoadLyrics(
                            slot,
                            data.plainLyrics
                        )

                        return
                    end
                end
            end


            ------------------------------------------------
            -- FALLBACK
            ------------------------------------------------

            searchLyricsFallback(
                slot,
                title,
                artist
            )
        end
    )
end


------------------------------------------------------------
-- ENCONTRA SLOT PARA UM PLAYER
------------------------------------------------------------

local function findSlotForPlayer(
    player
)

    ------------------------------------------------
    -- Primeiro: player já conhecido.
    ------------------------------------------------

    for _, slot in ipairs(slots) do

        if slot.player == player
            and player ~= "" then

            return slot
        end
    end


    ------------------------------------------------
    -- Segundo: slot vazio.
    ------------------------------------------------

    for _, slot in ipairs(slots) do

        if slot.player == "" then

            return slot
        end
    end


    ------------------------------------------------
    -- Terceiro:
    -- reutiliza o slot 1.
    ------------------------------------------------

    return slots[1]
end


------------------------------------------------------------
-- PROCESSA UM PLAYER MPRIS
------------------------------------------------------------

local function processPlayer(
    status,
    title,
    artist,
    position,
    player
)

    if not title
        or title == "" then

        return
    end


    local slot =
        findSlotForPlayer(
            player or ""
        )


    local previousPlayer =
        slot.player


    local lookupKey =
        (artist or "")
        .. "|"
        .. (title or "")


    local previousLookupKey =
        slot.lastLookupKey


    local mprisPosition =
        normalizePosition(
            position
        )


    ------------------------------------------------
    -- Atualiza identidade do slot.
    ------------------------------------------------

    slot.player =
        player or ""

    slot.title =
        title or ""

    slot.artist =
        artist or ""


    ------------------------------------------------
    -- NOVA MÚSICA
    ------------------------------------------------

    if lookupKey ~= previousLookupKey
        or previousPlayer ~= slot.player then

        slot.lastLookupKey =
            lookupKey


        slot.lyrics =
            {}

        slot.loaded =
            false

        slot.loading =
            true

        slot.state =
            "searching"


        slot.position =
            positionCache[lookupKey]
            or 0


        ------------------------------------------------
        -- Se a música é realmente nova,
        -- procura a letra inteira.
        ------------------------------------------------

        searchLyrics(
            slot,
            slot.title,
            slot.artist
        )


    else

        ------------------------------------------------
        -- MESMA MÚSICA
        ------------------------------------------------

        if mprisPosition
            and mprisPosition <= 3
            and slot.position > 5 then

            clearCachedPosition(
                lookupKey
            )


            slot.position =
                0


            slot.lyrics =
                {}

            slot.loaded =
                false

            slot.loading =
                true

            slot.state =
                "searching"


            searchLyrics(
                slot,
                slot.title,
                slot.artist
            )
        end
    end


    ------------------------------------------------
    -- STATUS
    ------------------------------------------------

    if status == "Playing" then

        slot.state =
            "lyrics"

    elseif status == "Paused" then

        slot.state =
            "paused"

    end


    ------------------------------------------------
    -- Escolhe o slot ativo.
    --
    -- Um player tocando tem prioridade.
    ------------------------------------------------

    if status == "Playing" then

        activeSlot =
            slot.id

    elseif activeSlot == slot.id then

        activeSlot =
            slot.id
    end


    print(
        "LYRICS DEBUG SLOT:",
        slot.id,
        status,
        slot.title,
        slot.artist,
        slot.player,
        slot.position
    )
end


------------------------------------------------------------
-- PLAYERCTL
------------------------------------------------------------

local function runPlayerctl()

    noctalia.runAsync(

        PLAYERCTL
            .. " -a metadata --format '{{status}}|{{title}}|{{artist}}|{{position}}|{{playerName}}'",

        function(result)

            if not result
                or result.exitCode ~= 0
                or not result.stdout then

                for _, slot in ipairs(slots) do

                    slot.state =
                        "no_player"

                    slot.lyrics =
                        {}

                    slot.loaded =
                        false

                    slot.loading =
                        false

                    slot.player =
                        ""
                end


                render()

                return
            end


            local output =
                result.stdout:gsub(
                    "%s+$",
                    ""
                )


            if output == "" then

                for _, slot in ipairs(slots) do

                    slot.state =
                        "no_player"

                    slot.lyrics =
                        {}

                    slot.loaded =
                        false

                    slot.loading =
                        false

                    slot.player =
                        ""
                end


                render()

                return
            end


            ------------------------------------------------
            -- Players encontrados nesta execução.
            ------------------------------------------------

            local seenPlayers = {}


            ------------------------------------------------
            -- PROCESSA TODAS AS LINHAS.
            ------------------------------------------------

            for line in output:gmatch(
                "[^\r\n]+"
            ) do

                local status,
                    title,
                    artist,
                    position,
                    player =
                    line:match(
                        "([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)"
                    )


                if title
                    and title ~= "" then

                    player =
                        player or ""


                    seenPlayers[player] =
                        true


                    processPlayer(
                        status,
                        title,
                        artist,
                        position,
                        player
                    )
                end
            end


            ------------------------------------------------
            -- Limpa slots de players que desapareceram.
            ------------------------------------------------

            for _, slot in ipairs(slots) do

                if slot.player ~= ""
                    and not seenPlayers[
                        slot.player
                    ] then

                    slot.player =
                        ""

                    slot.title =
                        ""

                    slot.artist =
                        ""

                    slot.position =
                        0

                    slot.lyrics =
                        {}

                    slot.loaded =
                        false

                    slot.loading =
                        false

                    slot.state =
                        "no_player"

                    slot.lastLookupKey =
                        ""
                end
            end


            render()
        end,

        2000
    )
end


------------------------------------------------------------
-- LINHA ATUAL
------------------------------------------------------------

local function getCurrentLine(
    slot
)

    if #slot.lyrics == 0 then
        return 1
    end


    local current =
        1


    ------------------------------------------------
    -- Calibração confirmada.
    ------------------------------------------------

    local LYRICS_SPEED =
        1.01


    local syncPosition =
        (slot.position * LYRICS_SPEED)
        + LYRICS_OFFSET


    for i = 1, #slot.lyrics do

        local line =
            slot.lyrics[i]


        if line.time
            and line.text
            and line.text ~= ""
            and syncPosition >= line.time then

            current =
                i

        elseif line.time
            and syncPosition < line.time then

            break
        end
    end


    return current
end


------------------------------------------------------------
-- RENDER
------------------------------------------------------------

function render()

    local rows = {}


    ------------------------------------------------
    -- SLOT ATIVO
    ------------------------------------------------

    local slot =
        slots[activeSlot]


    ------------------------------------------------
    -- CONFIGURAÇÕES
    ------------------------------------------------

    local widthSetting =
        tonumber(
            noctalia.getConfig(
                "width"
            )
        )
        or 700


    local currentFontSetting =
        tonumber(
            noctalia.getConfig(
                "current_font_size"
            )
        )
        or 36


    local secondaryFontSetting =
        tonumber(
            noctalia.getConfig(
                "secondary_font_size"
            )
        )
        or 27


    local currentOpacitySetting =
        tonumber(
            noctalia.getConfig(
                "current_opacity"
            )
        )
        or 100


    local secondaryOpacitySetting =
        tonumber(
            noctalia.getConfig(
                "secondary_opacity"
            )
        )
        or 73


    local linesAboveSetting =
        tonumber(
            noctalia.getConfig(
                "lines_above"
            )
        )
        or 2


    local linesBelowSetting =
        tonumber(
            noctalia.getConfig(
                "lines_below"
            )
        )
        or 2


    ------------------------------------------------
    -- LARGURA
    ------------------------------------------------

    local widgetWidth =
        300
        + (widthSetting / 1000) * 900


    ------------------------------------------------
    -- FONTES
    ------------------------------------------------

    local currentFontSize =
        currentFontSetting


    local secondaryFontSize =
        secondaryFontSetting


    ------------------------------------------------
    -- OPACIDADE
    ------------------------------------------------

    local currentOpacity =
        currentOpacitySetting / 100


    local secondaryOpacity =
        secondaryOpacitySetting / 100


    ------------------------------------------------
    -- SEM PLAYER
    ------------------------------------------------

    if slot.state == "no_player" then

        table.insert(
            rows,

            ui.label({
                text =
                    "♪ Nenhum player",

                fontSize =
                    secondaryFontSize,

                color =
                    "secondary",

                maxLines = 1,

                textAlign =
                    "center",

                opacity =
                    secondaryOpacity,
            })
        )


    ------------------------------------------------
    -- BUSCANDO
    ------------------------------------------------

    elseif slot.state == "searching"
        or slot.loading then

        table.insert(
            rows,

            ui.label({
                text =
                    "♪ Buscando letra...",

                fontSize =
                    secondaryFontSize,

                color =
                    "secondary",

                maxLines = 1,

                textAlign =
                    "center",

                opacity =
                    secondaryOpacity,
            })
        )


    ------------------------------------------------
    -- NÃO ENCONTRADA
    ------------------------------------------------

    elseif slot.state == "not_found" then

        table.insert(
            rows,

            ui.label({
                text =
                    "♪ Sem letra disponível",

                fontSize =
                    secondaryFontSize,

                color =
                    "secondary",

                maxLines = 1,

                textAlign =
                    "center",

                opacity =
                    secondaryOpacity,
            })
        )


    ------------------------------------------------
    -- PAUSADO
    ------------------------------------------------

    elseif slot.state == "paused" then

        local current =
            getCurrentLine(
                slot
            )


        local line =
            slot.lyrics[current]


        table.insert(
            rows,

            ui.label({
                text =
                    line
                    and line.text
                    or "♪ Pausado",

                fontSize =
                    currentFontSize,

                fontWeight =
                    "bold",

                color =
                    noctalia.getConfig(
                        "current_color"
                    )
                    or "primary",

                maxLines = 1,

                textAlign =
                    "center",

                opacity =
                    currentOpacity,
            })
        )


    ------------------------------------------------
    -- LETRA
    ------------------------------------------------

    else

        local current =
            getCurrentLine(
                slot
            )


        for offset =
            -linesAboveSetting,
            linesBelowSetting do

            local index =
                current + offset


            local line =
                slot.lyrics[index]


            local isCurrent =
                offset == 0


            local text =
                " "


            if line
                and line.text
                and line.text ~= "" then

                text =
                    line.text
            end


            local fontSize =
                isCurrent
                and currentFontSize
                or secondaryFontSize


            table.insert(
                rows,

                ui.label({
                    key =
                        "lyric-"
                        .. tostring(offset),

                    text =
                        text,

                    fontSize =
                        fontSize,

                    fontWeight =
                        isCurrent
                        and "bold"
                        or "normal",

                    baseline =
                        "textFixedHeight",

                    color =
                        isCurrent
                        and (
                            noctalia.getConfig(
                                "current_color"
                            )
                            or "primary"
                        )
                        or (
                            noctalia.getConfig(
                                "secondary_color"
                            )
                            or "secondary"
                        ),

                    opacity =
                        isCurrent
                        and currentOpacity
                        or secondaryOpacity,

                    maxLines = 1,

                    textAlign =
                        "center",
                })
            )
        end
    end


    ------------------------------------------------
    -- WIDGET
    ------------------------------------------------

    desktopWidget.render(

        ui.column(
            {
                width =
                    widgetWidth,

                gap =
                    10,

                align =
                    "center",

                minHeight =
                    100,
            },

            rows
        )
    )
end


------------------------------------------------------------
-- FRAME TICK
--
-- Cada slot possui sua própria posição.
------------------------------------------------------------

function onFrameTick(deltaMs)

    for _, slot in ipairs(slots) do

        if slot.player ~= ""
            and slot.state ~= "no_player"
            and slot.loaded then

            ------------------------------------------------
            -- Só avança se estiver tocando.
            ------------------------------------------------

            if slot.state == "lyrics" then

                slot.position =
                    slot.position
                    + (deltaMs / 1000)


                cachePosition(
                    slot.artist
                    .. "|"
                    .. slot.title,

                    slot.position
                )
            end
        end
    end


    render()
end


------------------------------------------------------------
-- FRAME TICK
------------------------------------------------------------

desktopWidget.setNeedsFrameTick(
    true
)


------------------------------------------------------------
-- ATUALIZAÇÃO MPRIS
------------------------------------------------------------

noctalia.setUpdateInterval(
    500
)


function update()

    runPlayerctl()
end


------------------------------------------------------------
-- INICIALIZAÇÃO
--
-- Primeiro garante que os arquivos existem.
-- Só depois começa a consultar o MPRIS.
------------------------------------------------------------

local function initialize()

    ensureLyricsFiles(
        function(success)

            if not success then

                print(
                    "LYRICS: inicialização dos arquivos falhou"
                )

                render()

                return
            end


            print(
                "LYRICS: inicialização concluída"
            )


            render()

            update()
        end
    )
end


------------------------------------------------------------
-- INÍCIO
------------------------------------------------------------

render()

initialize()

