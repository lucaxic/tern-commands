-- Extract command buttons, headings and row separators from top-level Markdown.
local supported = {
    sh = true,
    bash = true,
    zsh = true,
    powershell = true,
    pwsh = true,
    cmd = true,
}

local function fenceStart(line)
    local indent, marks, rest = line:match("^( *)(`+)(.*)$")
    local marker = "`"
    if not marks then
        indent, marks, rest = line:match("^( *)(~+)(.*)$")
        marker = "~"
    end
    if not marks or #indent > 3 or #marks < 3 then
        return nil
    end
    if marker == "`" and rest:find("`", 1, true) then
        return nil
    end
    return {
        indent = #indent,
        marker = marker,
        length = #marks,
        lang = (rest:match("^%s*(%S+)") or ""):lower(),
    }
end

local function fenceEnd(line, fence)
    local indent, marks, rest
    if fence.marker == "`" then
        indent, marks, rest = line:match("^( *)(`+)(.*)$")
    else
        indent, marks, rest = line:match("^( *)(~+)(.*)$")
    end
    return marks ~= nil and #indent <= 3 and #marks >= fence.length
        and rest:match("^[ \t]*$") ~= nil
end

local function stripIndent(line, amount)
    local index = 1
    local column = 0
    while column < amount and index <= #line do
        local char = line:sub(index, index)
        if char == " " then
            column += 1
        elseif char == "\t" then
            column += 4 - column % 4
        else
            break
        end
        index += 1
    end
    return string.rep(" ", math.max(0, column - amount)) .. line:sub(index)
end

local function headingTitle(line)
    local indent, hashes, rest = line:match("^( *)(#+)(.*)$")
    if not hashes or #indent > 3 or #hashes > 6 then
        return nil
    end
    if rest ~= "" and not rest:match("^[ \t]") then
        return nil
    end
    -- Closing hashes count only when separated from the heading by whitespace.
    rest = rest:gsub("[ \t]+#+[ \t]*$", "")
    return (rest:gsub("^[ \t]+", ""):gsub("[ \t]+$", ""))
end

local function scanComments(line, inside)
    local position = 1
    local touched = inside
    while true do
        local first, last = line:find(inside and "-->" or "<!--", position, true)
        if not first then
            return inside, touched
        end
        touched = true
        inside = not inside
        position = last + 1
    end
end

local function indentation(line)
    local column = 0
    for index = 1, #line do
        local char = line:sub(index, index)
        if char == " " then
            column += 1
        elseif char == "\t" then
            column += 4 - column % 4
        else
            break
        end
    end
    return column
end

local function listContentIndent(line)
    local spaces, marker, gap = line:match("^( *)([-+*])([ \t]+)")
    if not marker then
        spaces, marker, gap = line:match("^( *)(%d+[.)])([ \t]+)")
        if marker and #marker > 10 then
            return nil
        end
    end
    if not marker or #spaces > 3 then
        return nil
    end
    local base = #spaces + #marker
    local width = indentation(string.rep(" ", base) .. gap) - base
    return base + (width <= 4 and width or 1), line:sub(#spaces + #marker + #gap + 1)
end

local function isSeparator(line)
    if indentation(line) > 3 then
        return false
    end
    local marks = line:gsub("[ \t]", "")
    return #marks >= 3 and (marks:match("^%-+$") ~= nil or marks:match("^%*+$") ~= nil)
end

local function parse(text)
    local blocks = {}
    local position = 1
    local active = nil
    local title = nil
    local commandCount = 0
    local inComment = false
    local listIndent = nil
    local listBlank = false

    while position <= #text do
        local newline = text:find("\n", position, true)
        local last = newline and newline - 1 or #text
        local line = text:sub(position, last)
        if newline and line:sub(-1) == "\r" then
            line = line:sub(1, -2)
        end
        if position == 1 and line:sub(1, 3) == "\239\187\191" then
            line = line:sub(4)
        end
        local nextPosition = newline and newline + 1 or #text + 1

        if active then
            local closingLine = active.containerIndent and stripIndent(line, active.containerIndent) or line
            if fenceEnd(closingLine, active) then
                if active.executable then
                    local code = table.concat(active.lines)
                    if code:sub(-1) == "\n" then
                        code = code:sub(1, -2)
                    end
                    if code:find("%S") then
                        commandCount += 1
                        table.insert(blocks, {
                            kind = "command",
                            text = code,
                            lang = active.lang,
                            title = title or ("Run command " .. commandCount),
                            id = commandCount,
                        })
                    end
                end
                active = nil
                title = nil
            elseif active.executable then
                table.insert(active.lines, stripIndent(line, active.indent) .. (newline and "\n" or ""))
            end
        else
            local commentTouched
            inComment, commentTouched = scanComments(line, inComment)
            if commentTouched then
                title = nil
            else
                local blank = line:match("^[ \t]*$") ~= nil
                local nested = listIndent ~= nil and (blank or indentation(line) >= listIndent)
                local separator = isSeparator(line)
                local itemContent
                if not blank and not nested then
                    local nextIndent
                    if not separator then
                        nextIndent, itemContent = listContentIndent(line)
                    end
                    if nextIndent then
                        listIndent = nextIndent
                    elseif listIndent and not listBlank and not separator and headingTitle(line) == nil and not fenceStart(line) then
                        -- A paragraph can lazily continue a list item without indentation.
                        nested = true
                    else
                        listIndent = nil
                    end
                end
                listBlank = blank
                local candidate = itemContent or (nested and stripIndent(line, listIndent) or line)
                local fence = fenceStart(candidate)
                if fence then
                    fence.executable = not nested and not itemContent and supported[fence.lang] == true
                    fence.containerIndent = (nested or itemContent) and listIndent or nil
                    fence.lines = if fence.executable then {} else nil
                    active = fence
                elseif not blank then
                    if nested or itemContent or line:match("^ *>") or indentation(line) > 3 then
                        title = nil
                    else
                        local heading = headingTitle(line)
                        if separator then
                            table.insert(blocks, { kind = "separator" })
                            title = nil
                        elseif heading ~= nil then
                            table.insert(blocks, {
                                kind = "heading",
                                title = heading,
                                level = #(line:match("^ *(#+)") :: string),
                            })
                            title = nil
                        else
                            title = line:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
                        end
                    end
                end
            end
        end
        position = nextPosition
    end

    return blocks
end

return { parse = parse }
