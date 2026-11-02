--!nonstrict

local MAX_VISIBLE_RESULTS = 12
local MAX_RESULT_PATH_LENGTH = 4096
local MAX_RESULT_SNIPPET_LENGTH = 1200
local MAX_PREVIEW_BYTES = 256 * 1024
local IMAGE_EXTENSIONS = {
    png = true, jpg = true, jpeg = true, webp = true, gif = true,
    bmp = true, avif = true, tif = true, tiff = true, svg = true,
}
local VIDEO_EXTENSIONS = {
    mp4 = true, mkv = true, webm = true, avi = true, mov = true,
    m4v = true, mpg = true, mpeg = true, ogv = true, ["3gp"] = true,
}
local BINARY_EXTENSIONS = {
    zip = true, gz = true, bz2 = true, xz = true, zst = true, tar = true,
    rar = true, ["7z"] = true, exe = true, dll = true, so = true, bin = true,
    doc = true, docx = true, xls = true, xlsx = true, ppt = true, pptx = true,
}
local AUDIO_EXTENSIONS = {
    mp3 = true, wav = true, flac = true, ogg = true, opus = true,
    m4a = true, aac = true, wma = true, aiff = true, alac = true,
}
local FILTER_OPTIONS = {
    { id = "all", titleKey = "filters.all" },
    { id = "image", titleKey = "filters.images" },
    { id = "text", titleKey = "filters.text" },
    { id = "video", titleKey = "filters.videos" },
}

local isOpen = false
local queryText = ""
local inputRevision = 0
local focusSearch = true
local results = {}
local statusText = ""
local filter = "all"
local selectedIndex = 1
local previewVisible = false
local preview = nil
local currentQuery = 0
local searchPending = false
local digupCommand = nil
local resolvingDigup = false
local digupWaiters = {}
local videoThumbnails = {}
local pendingVideoThumbnails = {}

local function trim(value)
    return noctalia.string.trim(value or "")
end

local function tr(key, substitutions)
    if substitutions then return noctalia.tr(key, substitutions) end
    return noctalia.tr(key)
end

local function settings()
    local cli = trim(noctalia.getConfig("digup_cli"))
    local keepPreview = noctalia.getConfig("keep_preview_open")
    return {
        cli = cli,
        maxResults = tonumber(noctalia.getConfig("max_results")) or 8,
        keepPreviewOpen = keepPreview == nil or keepPreview == true or keepPreview == "true",
    }
end

local function extension(path)
    return (path:match("%.([^./]+)$") or ""):lower()
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function fileKind(path, resultKind)
    local ext = extension(path)
    if resultKind == "screenshot" or resultKind == "image" then return "image" end
    if resultKind == "video" then return "video" end
    if resultKind == "audio" or AUDIO_EXTENSIONS[ext] then return "audio" end
    if IMAGE_EXTENSIONS[ext] then return "image" end
    if VIDEO_EXTENSIONS[ext] then return "video" end
    if ext == "pdf" or resultKind == "pdf" or resultKind == "doc" or resultKind == "code" then return "text" end
    if BINARY_EXTENSIONS[ext] then return "other" end
    return "text"
end

local function visibleResults()
    local found = {}
    for _, item in ipairs(results) do
        if filter == "all" or fileKind(item.path, item.kind) == filter then
            table.insert(found, item)
        end
    end
    local limit = math.max(1, math.min(settings().maxResults, MAX_VISIBLE_RESULTS))
    while #found > limit do table.remove(found) end
    if selectedIndex > #found then selectedIndex = math.max(1, #found) end
    if selectedIndex < 1 then selectedIndex = 1 end
    return found
end

local function decode(body)
    if not body or body == "" then return nil end
    local ok, value = pcall(noctalia.json.decode, body)
    return ok and type(value) == "table" and value or nil
end

local render
local executeSearch
local selectResult
local function resolveDigup(callback)
    local configured = settings().cli
    if configured ~= "" then
        configured = noctalia.expandPath(configured)
        local appDirHelper = configured:gsub("/usr/bin/digup%-shell$", "/usr/lib/DigUp/helper/digup")
        if appDirHelper == configured and configured:match("/AppRun$") then
            appDirHelper = configured:gsub("/AppRun$", "/usr/lib/DigUp/helper/digup")
        end
        if appDirHelper ~= configured and noctalia.fileExists(appDirHelper) then
            configured = appDirHelper
        end
        if noctalia.fileExists(configured) or noctalia.commandExists(configured) then
            digupCommand = configured
            callback(digupCommand)
        else
            callback(nil, tr("errors.digup_path"))
        end
        return
    end
    if digupCommand then
        if noctalia.fileExists(digupCommand) or noctalia.commandExists(digupCommand) then
            callback(digupCommand)
            return
        end
        digupCommand = nil
    end
    if noctalia.commandExists("digup") then
        digupCommand = "digup"
        callback(digupCommand)
        return
    end
    local packaged = "/usr/lib/DigUp/helper/digup"
    if noctalia.fileExists(packaged) then
        digupCommand = packaged
        callback(digupCommand)
        return
    end
    if resolvingDigup then
        table.insert(digupWaiters, callback)
        return
    end
    resolvingDigup = true
    digupWaiters = { callback }
    local function finish(path, err)
        resolvingDigup = false
        if path then digupCommand = path end
        local waiters = digupWaiters
        digupWaiters = {}
        for _, waiter in ipairs(waiters) do waiter(path, err) end
    end
    local function searchAppImageMount()
        if not noctalia.commandExists("find") then
            finish(nil, tr("errors.digup_missing"))
            return
        end
        local accepted = noctalia.runAsync({ "find", "/tmp", "-maxdepth", "7", "-type", "f", "-path",
            "*/usr/lib/DigUp/helper/digup", "-executable", "-print", "-quit" }, function(result)
            local path = trim(result.stdout or "")
            if path ~= "" and noctalia.fileExists(path) then
                finish(path)
            else
                finish(nil, tr("errors.digup_missing"))
            end
        end)
        if not accepted then finish(nil, tr("errors.digup_locate")) end
    end
    local function searchAppManagerInstall(fallback)
        if not noctalia.commandExists("find") then
            fallback()
            return
        end
        local managedRoot = noctalia.expandPath("~/Applications/.installed")
        local portableRoot = noctalia.expandPath("~/Applications/DigUp Portable")
        local accepted = noctalia.runAsync({ "find", managedRoot, portableRoot, "-maxdepth", "8", "-type", "f", "-path",
            "*/usr/lib/DigUp/helper/digup", "-executable", "-print", "-quit" }, function(result)
            local path = trim(result.stdout or "")
            if path ~= "" and noctalia.fileExists(path) then
                finish(path)
            else
                fallback()
            end
        end)
        if not accepted then fallback() end
    end
    if not noctalia.commandExists("find") then
        finish(nil, tr("errors.digup_missing"))
        return
    end
    local accepted = noctalia.runAsync({ "sh", "-c",
        "pid=$(pgrep -n -x digup-shell 2>/dev/null) || exit 1; exe=$(readlink -f \"/proc/$pid/exe\") || exit 1; helper=\"$(dirname \"$exe\")/../lib/DigUp/helper/digup\"; [ -x \"$helper\" ] && printf '%s\\n' \"$helper\"" },
        function(result)
            local path = trim(result.stdout or "")
            if path ~= "" and noctalia.fileExists(path) then
                finish(path)
            else
                searchAppManagerInstall(searchAppImageMount)
            end
        end)
    if not accepted then searchAppManagerInstall(searchAppImageMount) end
end

local function normalizeResults(value)
    if type(value) ~= "table" then return nil end
    local rows = value.results or value.hits or value
    if type(rows) ~= "table" then return nil end
    local normalized = {}
    for _, item in ipairs(rows) do
        if type(item) == "table" and type(item.path) == "string" and #item.path <= MAX_RESULT_PATH_LENGTH then
            local snippet = item.excerpt or item.snippet or item.text or ""
            if type(snippet) ~= "string" then snippet = "" end
            item.snippet = snippet:sub(1, MAX_RESULT_SNIPPET_LENGTH)
            table.insert(normalized, item)
        end
    end
    return normalized
end

local function runDigupSearch(command, query, requestId)
    local limit = MAX_VISIBLE_RESULTS
    local argv = { command, "search", query, "-n", tostring(limit), "--json" }
    statusText = tr("status.searching")
    searchPending = true
    render()
    local accepted = noctalia.runAsync(argv, function(result)
        if requestId ~= currentQuery or not isOpen then return end
        searchPending = false
        if result.exitCode ~= 0 then
            local message = trim(result.stderr or "")
            if message == "" then message = tr("errors.digup_failed") end
            statusText = message:sub(1, 220)
            results = {}
            render()
            return
        end
        if result.stdoutTruncated then
            statusText = tr("errors.too_many_results")
            results = {}
            render()
            return
        end
        local decoded = decode(result.stdout)
        local normalized = normalizeResults(decoded)
        if not normalized then
            statusText = tr("errors.invalid_json")
            results = {}
        else
            results = normalized
            statusText = #results > 0 and tr("status.results", { count = #visibleResults() }) or tr("status.no_results")
        end
        selectedIndex = 1
        if previewVisible and settings().keepPreviewOpen then
            local visible = visibleResults()
            if visible[1] then selectResult(visible[1]) else render() end
        else
            render()
        end
    end)
    if not accepted then
        searchPending = false
        statusText = tr("errors.digup_execute")
        render()
    end
end

executeSearch = function(rawQuery)
    local query = trim(rawQuery)
    queryText = query
    currentQuery = currentQuery + 1
    local requestId = currentQuery
    local keepPreview = settings().keepPreviewOpen
    preview = nil
    previewVisible = keepPreview
    results = {}
    selectedIndex = 1
    filter = "all"
    if query == "" then
        statusText = ""
        searchPending = false
        render()
        return
    end
    focusSearch = false
    inputRevision = inputRevision + 1
    statusText = tr("status.locating_digup")
    render()
    resolveDigup(function(command, err)
        if requestId ~= currentQuery or not isOpen then return end
        if not command then
            statusText = err or tr("errors.digup_missing_short")
            searchPending = false
            render()
            return
        end
        runDigupSearch(command, query, requestId)
    end)
end

local function thumbnailPath(path, prefix, suffix)
    local dir = noctalia.pluginDataDir()
    if not dir then return nil end
    local hash = 0
    for i = 1, #path do hash = (hash * 31 + path:byte(i)) % 2147483647 end
    return dir .. "/" .. prefix .. tostring(hash) .. suffix
end

local function videoThumbnail(path, callback)
    if videoThumbnails[path] ~= nil then callback(videoThumbnails[path] or nil); return end
    if pendingVideoThumbnails[path] then return end
    if not noctalia.commandExists("ffmpeg") then
        videoThumbnails[path] = false
        callback(nil)
        return
    end
    local target = thumbnailPath(path, "video-preview-", ".jpg")
    if not target then callback(nil); return end
    if noctalia.fileExists(target) then
        videoThumbnails[path] = target
        callback(target)
        return
    end
    pendingVideoThumbnails[path] = true
    local accepted = noctalia.runAsync({ "ffmpeg", "-loglevel", "error", "-ss", "00:00:01", "-i", path,
        "-frames:v", "1", "-vf", "scale=480:360:force_original_aspect_ratio=decrease", "-y", target }, function(result)
        pendingVideoThumbnails[path] = nil
        videoThumbnails[path] = result.exitCode == 0 and noctalia.fileExists(target) and target or false
        callback(videoThumbnails[path] or nil)
    end)
    if not accepted then
        pendingVideoThumbnails[path] = nil
        videoThumbnails[path] = false
        callback(nil)
    end
end

local function openPdfPreview(path, requestId)
    if not noctalia.commandExists("pdftoppm") then
        preview.kind = "generic"
        preview.message = tr("preview.install_poppler")
        render()
        return
    end
    local base = thumbnailPath(path, "pdf-preview-", "")
    if not base then preview.kind = "generic"; render(); return end
    local thumbnail = base .. ".png"
    local function show(pathToImage)
        if not isOpen or requestId ~= currentQuery or not preview or preview.path ~= path then return end
        preview.kind = "image"
        preview.imagePath = pathToImage
        render()
    end
    if noctalia.fileExists(thumbnail) then show(thumbnail); return end
    preview.kind = "loading"
    preview.message = tr("preview.generating")
    render()
    local accepted = noctalia.runAsync({ "pdftoppm", "-f", "1", "-singlefile", "-scale-to", "900", "-png", path, base }, function(result)
        if result.exitCode == 0 and noctalia.fileExists(thumbnail) then
            show(thumbnail)
        elseif isOpen and preview and preview.path == path then
            preview.kind = "generic"
            preview.message = tr("preview.generate_failed")
            render()
        end
    end)
    if not accepted then
        preview.kind = "generic"
        preview.message = tr("preview.start_failed")
        render()
    end
end

selectResult = function(item)
    previewVisible = true
    local requestId = currentQuery
    preview = { path = item.path, kind = "loading", item = item, info = noctalia.fileInfo(item.path) or {} }
    render()
    local ext = extension(item.path)
    if IMAGE_EXTENSIONS[ext] then
        preview.kind, preview.imagePath = "image", item.path
        render()
    elseif VIDEO_EXTENSIONS[ext] then
        preview.kind = "video"
        preview.message = tr("preview.generating_thumbnail")
        render()
        videoThumbnail(item.path, function(path)
            if not isOpen or requestId ~= currentQuery or not preview or preview.path ~= item.path then return end
            preview.kind = "video"
            preview.imagePath = path
            preview.message = path and tr("preview.video_ready") or tr("preview.video_no_thumbnail")
            render()
        end)
    elseif ext == "pdf" then
        openPdfPreview(item.path, requestId)
    elseif BINARY_EXTENSIONS[ext] or AUDIO_EXTENSIONS[ext] then
        preview.kind = "generic"
        preview.message = tr("preview.unsupported_text")
        render()
    else
        if (tonumber(preview.info.size) or 0) > MAX_PREVIEW_BYTES then
            preview.kind = "generic"
            preview.message = tr("preview.file_too_large")
            render()
            return
        end
        local accepted = noctalia.readFileAsync(item.path, function(contents, err)
            if not isOpen or requestId ~= currentQuery or not preview or preview.path ~= item.path then return end
            if contents and not contents:find("\0", 1, true) then
                preview.kind = "text"
                preview.contents = contents:sub(1, 24000)
                preview.ext = ext
            else
                preview.kind = "generic"
                preview.message = err and tr("preview.read_failed") or tr("preview.unsupported_text")
            end
            render()
        end)
        if not accepted then
            preview.kind = "generic"
            preview.message = tr("preview.load_failed")
            render()
        end
    end
end

local function previewCode(text, ext)
    local fence = "```"
    while text:find(fence, 1, true) do fence = fence .. "`" end
    return fence .. (ext ~= "" and ext or "text") .. "\n" .. text .. "\n" .. fence
end

local function humanSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.1f MB", bytes / (1024 * 1024))
end

local function renderPreview()
    if not previewVisible or not preview then return nil end
    local info = preview.info or {}
    local children = {
        ui.row({ align = "center", gap = 8 }, {
            ui.column({ flexGrow = 1, gap = 3 }, {
                ui.label({ text = basename(preview.path), fontSize = 16, fontWeight = "bold", maxLines = 1 }),
                ui.label({ text = preview.path .. " · " .. humanSize(info.size), fontSize = 10, color = "on_surface_variant", maxLines = 2 }),
            }),
            ui.button({ text = tr("actions.open"), glyph = "external-link", controlSize = "sm", onClick = function() noctalia.runAsync({ "xdg-open", preview.path }) end }),
        }),
        ui.separator({ spacing = 3 }),
    }
    if (preview.kind == "image" or preview.kind == "video") and preview.imagePath then
        table.insert(children, ui.image({ path = preview.imagePath, width = 420, height = 360, fit = "contain", radius = 9 }))
        if preview.message then table.insert(children, ui.label({ text = preview.message, fontSize = 10, color = "on_surface_variant" })) end
    elseif preview.kind == "text" then
        local markdown = preview.contents
        if preview.ext ~= "md" and preview.ext ~= "markdown" and preview.ext ~= "rst" then
            markdown = previewCode(markdown, preview.ext)
        end
        table.insert(children, ui.scroll({ flexGrow = 1, fill = "surface_container_low", radius = 9, padding = 10 }, {
            ui.markdown({ text = markdown, width = 400, height = 360 }),
        }))
    else
        table.insert(children, ui.column({ gap = 10, padding = 16, flexGrow = 1, align = "center", justify = "center" }, {
            ui.glyph({ name = preview.kind == "video" and "video" or "file", size = 36, color = "on_surface_variant" }),
            ui.label({ text = preview.message or tr("preview.loading"), color = "on_surface_variant", textAlign = "center", maxWidth = 360 }),
        }))
    end
    return ui.column({ gap = 8, flexGrow = 1, fill = "surface_container_low", radius = 10, padding = 12 }, children)
end

render = function()
    if not isOpen then return end
    local visible = visibleResults()
    local top = {
        ui.row({ align = "center", gap = 8 }, {
            ui.input({
                key = "search-input-" .. tostring(inputRevision),
                value = queryText,
                placeholder = tr("search.placeholder"),
                focus = focusSearch,
                controlSize = "sm",
                flexGrow = 1,
                onChange = function(value) queryText = value; focusSearch = true end,
                onSubmit = function(value) queryText = value; executeSearch(value) end,
            }),
            ui.button({ glyph = "search", tooltip = tr("actions.search"), variant = "primary", controlSize = "sm", onClick = function() executeSearch(queryText) end }),
            ui.button({ glyph = "close", tooltip = tr("actions.close"), controlSize = "sm", onClick = function() panel.close() end }),
        }),
    }
    if statusText ~= "" then
        table.insert(top, ui.label({ text = statusText, fontSize = 11, color = "on_surface_variant", maxLines = 1 }))
    end
    local children = { ui.column({ gap = 8 }, top) }
    if #results > 0 then
        local buttons = {}
        for _, option in ipairs(FILTER_OPTIONS) do
            table.insert(buttons, ui.button({
                key = "filter-" .. option.id,
                text = tr(option.titleKey),
                selected = filter == option.id,
                variant = filter == option.id and "secondary" or "ghost",
                controlSize = "sm",
                onClick = function()
                    filter = option.id
                    selectedIndex = 1
                    local nextResults = visibleResults()
                    if previewVisible and settings().keepPreviewOpen and nextResults[1] then
                        selectResult(nextResults[1])
                    elseif previewVisible and settings().keepPreviewOpen then
                        preview = nil
                        render()
                    else
                        previewVisible = false
                        preview = nil
                        render()
                    end
                end,
            }))
        end
        table.insert(children, ui.row({ gap = 5, align = "center" }, buttons))
        local rows = {}
        for index, item in ipairs(visible) do
            local selected = selectedIndex == index
            local kind = fileKind(item.path, item.kind)
            local thumb
            if kind == "image" then
                thumb = ui.image({ path = item.path, width = 56, height = 48, fit = "cover", radius = 6 })
            elseif kind == "text" then
                thumb = ui.column({ width = 56, height = 48, padding = 4, fill = "surface_container_high", radius = 6, justify = "center" }, {
                    ui.label({ text = (item.snippet or ""):gsub("%s+", " "), fontSize = 8, color = "on_surface_variant", maxLines = 3 }),
                })
            else
                thumb = ui.column({ width = 56, height = 48, fill = "surface_container_high", radius = 6, align = "center", justify = "center" }, {
                    ui.glyph({ name = kind == "video" and "video" or "file", size = 20, color = "primary" }),
                })
            end
            table.insert(rows, ui.row({
                key = "result-" .. item.path,
                gap = 9,
                padding = 7,
                radius = 8,
                align = "center",
                fill = selected and "primary/0.16" or "surface_container_low",
                onClick = function()
                    selectedIndex = index
                    if previewVisible and settings().keepPreviewOpen then
                        selectResult(item)
                    else
                        previewVisible = false
                        preview = nil
                        render()
                    end
                end,
            }, {
                thumb,
                ui.column({ gap = 2, flexGrow = 1 }, {
                    ui.label({ text = basename(item.path), fontWeight = "bold", maxLines = 1 }),
                    ui.label({ text = item.path, fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
                    ui.label({ text = item.snippet or "", fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
                }),
            }))
        end
        if #rows == 0 then
            table.insert(rows, ui.label({ text = tr("results.empty_filter"), color = "on_surface_variant", textAlign = "center" }))
        end
        local list = ui.scroll({ height = 420, gap = 5, fill = "surface_container", radius = 10, padding = 7 }, rows)
        if previewVisible and preview then
            table.insert(children, ui.row({ gap = 10, align = "stretch" }, {
                ui.column({ width = 360 }, { list }),
                renderPreview(),
            }))
        else
            table.insert(children, list)
        end
        table.insert(children, ui.label({
            text = tr(settings().keepPreviewOpen and "results.keyboard_hint_pinned" or "results.keyboard_hint_toggle", { count = #visible }),
            fontSize = 10,
            color = "on_surface_variant",
        }))
    elseif queryText == "" then
        table.insert(children, ui.label({ text = tr("search.empty_hint"), fontSize = 11, color = "on_surface_variant" }))
    end
    panel.render(ui.column({ key = previewVisible and "file-search-preview" or "file-search-results", gap = 8, padding = 12, fill = "surface" }, children))
end

function onKey(chord, pressed)
    local isPressed = pressed == true or pressed == "true"
    if not isPressed or not isOpen then return end
    if chord == "ctrl+k" then
        queryText = ""
        inputRevision = inputRevision + 1
        focusSearch = true
        results = {}
        selectedIndex = 1
        local keepPreview = previewVisible and settings().keepPreviewOpen
        previewVisible = keepPreview
        preview = nil
        statusText = ""
        render()
        return
    end
    local visible = visibleResults()
    if chord == "up" and #visible > 0 then
        selectedIndex = selectedIndex <= 1 and #visible or selectedIndex - 1
        if previewVisible then selectResult(visible[selectedIndex]) else render() end
    elseif chord == "down" and #visible > 0 then
        selectedIndex = selectedIndex >= #visible and 1 or selectedIndex + 1
        if previewVisible then selectResult(visible[selectedIndex]) else render() end
    elseif chord == "space" and #visible > 0 then
        if settings().keepPreviewOpen then
            if not preview or preview.path ~= visible[selectedIndex].path then
                selectResult(visible[selectedIndex])
            end
        elseif previewVisible then
            previewVisible = false
            preview = nil
            render()
        else
            selectResult(visible[selectedIndex])
        end
    elseif chord == "Return" and focusSearch then
        executeSearch(queryText)
    elseif chord == "Return" and not focusSearch and #visible > 0 then
        noctalia.runAsync({ "xdg-open", visible[selectedIndex].path })
    elseif (chord == "left" or chord == "right") and not focusSearch and #results > 0 then
        local currentFilter = 1
        for index, option in ipairs(FILTER_OPTIONS) do
            if option.id == filter then currentFilter = index; break end
        end
        local delta = chord == "right" and 1 or -1
        currentFilter = ((currentFilter - 1 + delta) % #FILTER_OPTIONS) + 1
        filter = FILTER_OPTIONS[currentFilter].id
        selectedIndex = 1
        local nextResults = visibleResults()
        if previewVisible and settings().keepPreviewOpen and nextResults[1] then
            selectResult(nextResults[1])
        elseif previewVisible and settings().keepPreviewOpen then
            preview = nil
            statusText = tr("status.results", { count = #nextResults })
            render()
        else
            previewVisible = false
            preview = nil
            statusText = tr("status.results", { count = #nextResults })
            render()
        end
    end
end

function onOpen(_context)
    isOpen = true
    currentQuery = currentQuery + 1
    searchPending = false
    queryText = ""
    inputRevision = inputRevision + 1
    focusSearch = true
    results = {}
    preview = nil
    previewVisible = settings().keepPreviewOpen
    selectedIndex = 1
    filter = "all"
    statusText = ""
    render()
end

function onClose()
    isOpen = false
    currentQuery = currentQuery + 1
    searchPending = false
end
