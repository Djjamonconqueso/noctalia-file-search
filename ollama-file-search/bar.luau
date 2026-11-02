--!nonstrict

function update()
    barWidget.setGlyph("search")
    barWidget.setTooltip(noctalia.tr("bar.tooltip"))
end

function onClick()
    noctalia.togglePanel("yo/ollama-file-search:search")
end
