local parse = require("../src/parser").parse
local count = 0

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function commands(text)
    local result = {}
    for _, block in parse(text) do
        if block.kind == "command" then
            table.insert(result, block)
        end
    end
    return result
end

local function test(name, run)
    run()
    count += 1
    print("PASS " .. name)
end

test("labels belong only to the next executable fence", function()
    local result = commands("# Group\n  First  \n\n```sh\none\n```\n```sh\ntwo\n```\nSecond\n```sh\nthree\n```")
    equal(result[1].title, "First", "trimmed prose label")
    assert(result[2].title ~= "First" and result[2].title ~= "Group", "label leaked across a fence")
    equal(result[3].title, "Second", "next prose label")
    for id, command in result do
        equal(command.id, id, "command identity")
    end
    for _, boundary in { "---", "***", "# Group", "<!-- hidden -->", "```text\nhidden\n```", "```sh\n\n```" } do
        assert(commands("Old\n" .. boundary .. "\n```sh\nx\n```")[1].title ~= "Old", "boundary retained old label")
    end
    equal(commands("Old\n<!-- hidden -->\nNew\n```sh\nx\n```")[1].title, "New", "label after comment")
end)

test("all supported shells accept case-insensitive fence info", function()
    for _, language in { "sh", "bash", "zsh", "powershell", "pwsh", "cmd" } do
        local result = commands("```" .. language:upper() .. " extra\nx\n```\n")
        equal(#result, 1, language)
        equal(result[1].lang, language, "normalized language")
    end
end)

test("unsupported, incomplete, blank and nested fences never execute", function()
    for _, text in {
        "Before\r\n```python\r\n# hidden\r\n```sh\r\nx\r\n```\r\nAfter",
        "# Title\n```bash\necho missing\n", "```\nplain\n```", "```sh\n \t\n```", "```sh\n```",
        "    ```sh\n    x\n    ```", "~~~sh\nx\n```",
        "<!-- ```sh\nx\n```", "<!--\n```sh\nx\n```\n-->",
        "- item\n\n  ```sh\n  danger\n```", "1. item\n   ```sh\n   danger\n   ```",
        "- ```sh\n  danger\n  ```", "> ```sh\n> danger\n> ```",
        "- item\n    ```sh\n    danger\n    ```", "- item\nlazy continuation\n  ```sh\n  danger\n  ```",
    } do
        equal(#commands(text), 0, "non-executable input")
    end
    local result = commands("- ```sh\n  danger\n  ```\n\nTop level\n```sh\nsafe\n```")
    equal(#result, 1, "top-level command after list")
    equal(result[1].text, "safe", "safe source")
end)

test("source preserves blank lines, indentation and literal delimiters", function()
    equal(commands("Title\r\n```pwsh\r\none\r\n\r\ntwo\r\n```\r\n")[1].text, "one\n\ntwo", "CRLF normalization")
    equal(commands("```sh\nx\n\n```\n")[1].text, "x\n", "trailing blank line")
    equal(commands("  ```bash\n  one\n two\nthree\n    four\n\tfive\n  ```")[1].text, "one\ntwo\nthree\n  four\n  five", "fence indentation")
    local result = commands("```sh\n# Comment\necho '<!--'\n---\n***\n```\nNew\n```sh\nx\n```")
    equal(result[1].text, "# Comment\necho '<!--'\n---\n***", "literal shell source")
    equal(result[2].title, "New", "comment did not escape fence")
end)

test("only matching fence markers close source", function()
    equal(commands("````sh\nx\n```\n~~~~\ny\n`````")[1].text, "x\n```\n~~~~\ny", "shorter and mismatched markers")
    equal(commands("~~~ZSH\nx\n~~~~~")[1].text, "x", "longer tilde closer at EOF")
    equal(commands("```sh\nx\n``` nope\ny\n```")[1].text, "x\n``` nope\ny", "closer with info")
end)

test("headings retain levels and do not become button labels", function()
    for level = 1, 6 do
        local blocks = parse(string.rep("#", level) .. " Title ###\n```sh\nx\n```")
        equal(blocks[1].title, "Title", "heading text")
        equal(blocks[1].level, level, "heading level")
        assert(blocks[2].title ~= "Title", "heading became button label")
    end
    equal(parse("# Title#\n")[1].title, "Title#", "attached hash")
    for _, prose in { "#NoSpace", "####### Seven" } do
        equal(commands(prose .. "\n```sh\nx\n```")[1].title, prose, "ordinary prose")
    end
    local bom = "\239\187\191"
    equal(parse(bom .. "# Title\n")[1].title, "Title", "BOM before heading")
    equal(commands(bom .. "```sh\nx\n```")[1].text, "x", "BOM before fence")
end)

test("nested and repeated headings retain document order", function()
    local blocks = parse("Before\n```sh\nfirst\n```\n# Same\nOne\n```sh\nsecond\n```\n### Child\nTwo\n```sh\nthird\n```\n# Same\nFour\n```sh\nfourth\n```")
    local sequence = {}
    for _, block in blocks do
        table.insert(sequence, if block.kind == "heading" then tostring(block.level) .. ":" .. block.title else block.text .. ":" .. block.title)
    end
    equal(table.concat(sequence, "|"), "first:Before|1:Same|second:One|3:Child|third:Two|1:Same|fourth:Four", "group order")
end)

test("separators split rows without consuming command identities", function()
    local blocks = parse("A\n```sh\na\n```\n\nB\n```sh\nb\n```\n---\n```sh\nc\n```\n***\n# Next\nD\n```sh\nd\n```")
    local sequence = {}
    for _, block in blocks do
        table.insert(sequence, block.kind)
    end
    equal(table.concat(sequence, "|"), "command|command|separator|command|separator|heading|command", "row boundaries")
    equal(blocks[4].id, 3, "ID after separator")
    for _, rule in { "---", "***", "-----", " * * * ", "  - - -\t" } do
        equal(parse(rule .. "\r\n")[1].kind, "separator", "Markdown rule")
    end
    equal(parse("- item\n---\n")[1].kind, "separator", "rule ends lazy list continuation")
end)

test("fences, comments, lists and quotes cannot create layout boundaries", function()
    local blocks = parse("# Visible\n```text\n## Hidden\n---\n```\n<!--\n## Hidden\n***\n-->\n> ## Quote\n> ***\n- item\n  ## Nested\n  ---\n\n    ***\n--\n**\n-*-")
    equal(#blocks, 1, "only visible group")
    equal(blocks[1].title, "Visible", "visible heading")
end)

print("Passed " .. count .. " parser tests")
