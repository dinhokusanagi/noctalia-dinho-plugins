--!nonstrict

local M = {}

function M.render(ctx)
    local BAR_COUNT = ctx.BAR_COUNT
    local VISUAL_BAR_COUNT = ctx.VISUAL_BAR_COUNT
    local smoothedBars = ctx.smoothedBars
    local highlightIndex = ctx.highlightIndex
    local barWidth = ctx.barWidth
    local barSpacing = ctx.barSpacing
    local minHeight = ctx.minHeight
    local maxHeight = ctx.maxHeight
    local opacity = ctx.opacity
    local highlightOpacity = ctx.highlightOpacity
    local normalColor = ctx.normalColor
    local highlightColor = ctx.highlightColor
    local waveJumpActive = ctx.waveJumpActive
    local waveJump = ctx.waveJump
    local numberSetting = ctx.numberSetting

    local children = {}

        local blockSize =
            math.max(
                4,
                barWidth
            )

        local waveHeightScale =
            numberSetting(
                "wave_height",
                100
            ) / 100

        local barHeightScale =
            numberSetting(
                "bar_height",
                100
            ) / 100

        local maxJump =
            maxHeight * 0.30

        local totalHeight =
            maxHeight
            + blockSize
            + maxJump

        ----------------------------------------------------------------
        -- Converte o índice do CAVA para UMA posição visual.
        -- O segundo bloco destacado fica imediatamente ao lado.
        ----------------------------------------------------------------

        local highlightVisualIndex =
            math.floor(
                (
                    (highlightIndex - 1)
                    * (VISUAL_BAR_COUNT - 1)
                    / (BAR_COUNT - 1)
                )
                + 1.5
            )

        local secondHighlightVisualIndex =
            math.min(
                VISUAL_BAR_COUNT,
                highlightVisualIndex + 1
            )

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

            local normalized =
                math.max(
                    0,
                    math.min(
                        1,
                        value / 1000
                    )
                )

            local barHeight =
                (
                    minHeight
                    + (maxHeight - minHeight)
                    * normalized
                )
                * waveHeightScale

            barHeight =
                math.min(
                    barHeight,
                    maxHeight * barHeightScale
                )

            local isHighlighted =
                i == highlightVisualIndex
                or i == secondHighlightVisualIndex

            ----------------------------------------------------------------
            -- O SALTO PERTENCE SOMENTE AO BLOQUINHO.
            ----------------------------------------------------------------

            local jump =
                waveJumpActive
                and (
                    maxJump
                    * normalized
                    * math.min(
                        waveJump,
                        1
                    )
                )
                or 0

            table.insert(
                children,
                ui.column(
                    {
                        align = "center",
                        justify = "end",
                        gap = 0,

                        width =
                            barWidth,

                        height =
                            totalHeight,
                    },
                    {
                        ----------------------------------------------------------------
                        -- PARTE MAIOR
                        -- Sempre permanece na cor normal.
                        ----------------------------------------------------------------

                        ui.box({
                            key =
                                "cavamix-wave-bar-"
                                .. tostring(i),

                            width =
                                barWidth,

                            height =
                                barHeight,

                            radius = 0,

                            softness = 0,

                            opacity =
                                opacity / 100,

                            fill =
                                normalColor,
                        }),

                        ----------------------------------------------------------------
                        -- ESPAÇO DO SALTO
                        ----------------------------------------------------------------

                        ui.box({
                            key =
                                "cavamix-wave-jump-"
                                .. tostring(i),

                            width = 1,

                            height =
                                jump,

                            radius = 0,

                            softness = 0,

                            opacity = 0,

                            fill =
                                normalColor,
                        }),

                        ----------------------------------------------------------------
                        -- BLOQUINHO / BASE
                        --
                        -- O bloco principal e o bloco imediatamente
                        -- ao lado recebem a mesma highlightColor.
                        ----------------------------------------------------------------

                        ui.box({
                            key =
                                "cavamix-wave-block-"
                                .. tostring(i),

                            width =
                                blockSize,

                            height =
                                blockSize,

                            radius = 0,

                            softness = 0,

                            opacity =
                                isHighlighted
                                and highlightOpacity / 100
                                or opacity / 100,

                            fill =
                                isHighlighted
                                and highlightColor
                                or normalColor,
                        }),
                    }
                )
            )
    end


    return ui.row(
        {
            gap = barSpacing,
            align = "end",
            justify = "center",
            height = totalHeight,
        },
        children
    )
end

return M
