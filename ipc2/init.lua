--- === hs.ipc2 ===
---
---
--- Provides the server portion of the Hammerspoon command line interface
--- Note that in order to use the command line tool, you will need to explicitly load `hs.ipc2` in your init.lua. The simplest way to do that is `require("hs.ipc2")`
---
--- This module is based primarily on code from Mjolnir by [Steven Degutis](https://github.com/sdegutis/).

local USERDATA_TAG = "hs.ipc2"
local module       = require(USERDATA_TAG..".internal")

local basePath = package.searchpath(USERDATA_TAG, package.path)
if basePath then
    basePath = basePath:match("^(.+)/init.lua$")
    if require"hs.fs".attributes(basePath .. "/docs.json") then
        require"hs.doc".registerJSONFile(basePath .. "/docs.json")
    end
end

-- private variables and methods -----------------------------------------

local function rawhandler(str)
    local fn, err = load("return " .. str)
    if not fn then fn, err = load(str) end
    if fn then return fn() else return err end
end

-- Public interface ------------------------------------------------------

--- hs.ipc2.handler(str) -> value
--- Function
--- Processes received IPC messages and returns the results
---
--- Parameters:
---  * str - A string containing some a message to process (typically, some Lua code)
---
--- Returns:
---  * A string containing the results of the IPC message
---
--- Notes:
---  * This is not a function you should typically call directly, rather, it is documented because you can override it with your own function if you have particular IPC needs.
---  * The return value of this function is always turned into a string via `lua_tostring()` and returned to the IPC client (typically the `hs` command line tool)
---  * The default handler is:
--- ~~~
---     function hs.ipc2.handler(str)
---         local fn, err = load("return " .. str)
---         if not fn then fn, err = load(str) end
---         if fn then return fn() else return err end
---     end
--- ~~~
module.handler = rawhandler

--- hs.ipc2.cliGetColors() -> table
--- Function
--- Gets the terminal escape codes used to produce colors in the `hs` command line tool
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing the terminal escape codes used to produce colors. The available keys are:
---   * initial
---   * input
---   * output
---   * error
module.cliGetColors = function()
    local settings = require("hs.settings")
    local colors = {}
    colors.initial = settings.get("ipc2.cli.color_initial") or "\27[35m" ;
    colors.input   = settings.get("ipc2.cli.color_input")   or "\27[33m" ;
    colors.output  = settings.get("ipc2.cli.color_output")  or "\27[36m" ;
    colors.error   = settings.get("ipc2.cli.color_error")   or "\27[31m" ;
    return colors
end

--- hs.ipc2.cliSetColors(table) -> table
--- Function
--- Sets the terminal escape codes used to produce colors in the `hs` command line tool
---
--- Parameters:
---  * table - A table of terminal escape sequences (or empty strings if you wish to suppress the usage of colors) containing the following keys:
---   * initial
---   * input
---   * output
---   * error
---
--- Returns:
---  * A table containing the terminal escape codes that have been set. The available keys match the table parameter.
---
--- Notes:
---  * For a brief intro into terminal colors, you can visit a web site like this one [http://jafrog.com/2013/11/23/colors-in-terminal.html](http://jafrog.com/2013/11/23/colors-in-terminal.html)
---  * Lua doesn't support octal escapes in it's strings, so use `\x1b` or `\27` to indicate the `escape` character e.g. `ipc2.cliSetColors{ initial = "", input = "\27[33m", output = "\27[38;5;11m" }`
---  * The values are stored by the `hs.settings` extension, so will persist across restarts of Hammerspoon
module.cliSetColors = function(colors)
    local settings = require("hs.settings")
    if colors.initial then settings.set("ipc2.cli.color_initial", colors.initial) end
    if colors.input   then settings.set("ipc2.cli.color_input",   colors.input)   end
    if colors.output  then settings.set("ipc2.cli.color_output",  colors.output)  end
    if colors.error   then settings.set("ipc2.cli.color_error",   colors.error)   end
    return module.cliGetColors()
end

--- hs.ipc2.cliResetColors()
--- Function
--- Restores default terminal escape codes used to produce colors in the `hs` command line tool
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
module.cliResetColors = function()
    local settings = require("hs.settings")
    settings.clear("ipc2.cli.color_initial")
    settings.clear("ipc2.cli.color_input")
    settings.clear("ipc2.cli.color_output")
    settings.clear("ipc2.cli.color_error")
end

--- hs.ipc2.cliStatus([path][,silent]) -> bool
--- Function
--- Gets the status of the `hs` command line tool
---
--- Parameters:
---  * path - An optional string containing a path to look for the `hs` tool. Defaults to `/usr/local`
---  * silent - An optional boolean indicating whether or not to print errors to the Hammerspoon Console
---
--- Returns:
---  * A boolean, true if the `hs` command line tool is correctly installed, otherwise false
module.cliStatus = function(path, silent)
    local path = path or "/usr/local"
    local mod_path = string.match(package.searchpath("hs.ipc2",package.path), "^(.*)/init%.lua$")

    local silent = silent or false

    local bin_file = os.execute("[ -f \""..path.."/bin/hs\" ]")
    local man_file = os.execute("[ -f \""..path.."/share/man/man1/hs.1\" ]")
    local bin_link = os.execute("[ -L \""..path.."/bin/hs\" ]")
    local man_link = os.execute("[ -L \""..path.."/share/man/man1/hs.1\" ]")
    local bin_ours = os.execute("[ \""..path.."/bin/hs\" -ef \""..mod_path.."/bin/hs\" ]")
    local man_ours = os.execute("[ \""..path.."/share/man/man1/hs.1\" -ef \""..mod_path.."/share/man/man1/hs.1\" ]")

    local result = bin_file and man_file and bin_link and man_link and bin_ours and man_ours or false
    local broken = false

    if not bin_ours and bin_file then
        if not silent then
            print([[cli installation problem: 'hs' is not ours.]])
        end
        broken = true
    end
    if not man_ours and man_file then
        if not silent then
            print([[cli installation problem: 'hs.1' is not ours.]])
        end
        broken = true
    end
    if bin_file and not bin_link then
        if not silent then
            print([[cli installation problem: 'hs' is an independant file won't be updated when Hammerspoon is.]])
        end
        broken = true
    end
    if not bin_file and bin_link then
        if not silent then
            print([[cli installation problem: 'hs' is a dangling link.]])
        end
        broken = true
    end
    if man_file and not man_link then
        if not silent then
            print([[cli installation problem: man page for 'hs.1' is an independant file and won't be updated when Hammerspoon is.]])
        end
        broken = true
    end
    if not man_file and man_link then
        if not silent then
            print([[cli installation problem: man page for 'hs.1' is a dangling link.]])
        end
        broken = true
    end
    if ((bin_file and bin_link) and not (man_file and man_link)) or ((man_file and man_link) and not (bin_file and bin_link)) then
        if not silent then
            print([[cli installation problem: incomplete installation of 'hs' and 'hs.1'.]])
        end
        broken = true
    end

    return broken and "broken" or result
end

--- hs.ipc2.cliInstall([path][,silent]) -> bool
--- Function
--- Installs the `hs` command line tool
---
--- Parameters:
---  * path - An optional string containing a path to install the tool in. Defaults to `/usr/local`
---  * silent - An optional boolean indicating whether or not to print errors to the Hammerspoon Console
---
--- Returns:
---  * A boolean, true if the tool was successfully installed, otherwise false
---
--- Notes:
---  * If this function fails, it is likely that you have some old/broken symlinks. You can use `hs.ipc2.cliUninstall()` to forcibly tidy them up
module.cliInstall = function(path, silent)
    local path = path or "/usr/local"
    local silent = silent or false
    if module.cliStatus(path, true) == false then
        local mod_path = string.match(package.searchpath("hs.ipc2",package.path), "^(.*)/init%.lua$")
        os.execute("ln -s \""..mod_path.."/bin/hs\" \""..path.."/bin/\"")
        os.execute("ln -s \""..mod_path.."/share/man/man1/hs.1\" \""..path.."/share/man/man1/\"")
    end
    return module.cliStatus(path, silent)
end

--- hs.ipc2.cliUninstall([path][,silent]) -> bool
--- Function
--- Uninstalls the `hs` command line tool
---
--- Parameters:
---  * path - An optional string containing a path to remove the tool from. Defaults to `/usr/local`
---  * silent - An optional boolean indicating whether or not to print errors to the Hammerspoon Console
---
--- Returns:
---  * A boolean, true if the tool was successfully removed, otherwise false
---
--- Notes:
---  * This function used to be very conservative and refuse to remove symlinks it wasn't sure about, but now it will unconditionally remove whatever it finds at `path/bin/hs` and `path/share/man/man1/hs.1`. This is more likely to be useful in situations where this command is actually needed (please open an Issue on GitHub if you disagree!)
module.cliUninstall = function(path, silent)
    local path = path or "/usr/local"
    local silent = silent or false
    os.execute("rm \""..path.."/bin/hs\"")
    os.execute("rm \""..path.."/share/man/man1/hs.1\"")
    return not module.cliStatus(path, silent)
end

module.__default = module.localPort("hsCommandLine", function(self, msgID, msg)
    local raw = (msgID == -1)
    local originalprint = print
    local fakestdout = ""
    print = function(...)
        originalprint(...)
        local things = table.pack(...)
        fakestdout = fakestdout .. tostring(things[1])
        for i = 2, things.n do
            fakestdout = fakestdout .. "\t" .. tostring(things[i])
        end
        fakestdout = fakestdout .. "\n"
    end

    local fn = raw and rawhandler or module.handler
    local results = table.pack(pcall(function() return fn(msg) end))

    local str = ""
    for i = 2, results.n do
        if i > 2 then str = str .. "\t" end
        str = str .. tostring(results[i])
    end

    print = originalprint
    return "ipc2 --> " .. fakestdout .. str
end)

-- Return Module Object --------------------------------------------------

return module
