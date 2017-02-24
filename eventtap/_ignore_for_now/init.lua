--- === hs.eventtap ===
---
--- Tap into input events (mouse, keyboard, trackpad) for observation and possibly overriding them
--- It also provides convenience wrappers for sending mouse and keyboard events. If you need to construct finely controlled mouse/keyboard events, see hs.eventtap.event
---
--- This module is based primarily on code from the previous incarnation of Mjolnir by [Steven Degutis](https://github.com/sdegutis/).

--- === hs.eventtap.event ===
---
--- Create, modify and inspect events for `hs.eventtap`
---
--- This module is based primarily on code from the previous incarnation of Mjolnir by [Steven Degutis](https://github.com/sdegutis/).

local module   = require("hs.eventtap.internal")
module.event   = require("hs.eventtap.event")
local fnutils  = require("hs.fnutils")
local keycodes = require("hs.keycodes")
local timer    = require("hs.timer")

-- private variables and methods -----------------------------------------

local _kMetaTable = {}
_kMetaTable._k = setmetatable({}, {__mode = "k"})
_kMetaTable._t = setmetatable({}, {__mode = "k"})
_kMetaTable.__index = function(obj, key)
        if _kMetaTable._k[obj] then
            if _kMetaTable._k[obj][key] then
                return _kMetaTable._k[obj][key]
            else
                for k,v in pairs(_kMetaTable._k[obj]) do
                    if v == key then return k end
                end
            end
        end
        return nil
    end
_kMetaTable.__newindex = function(obj, key, value)
        error("attempt to modify a table of constants",2)
        return nil
    end
_kMetaTable.__pairs = function(obj) return pairs(_kMetaTable._k[obj]) end
_kMetaTable.__len = function(obj) return #_kMetaTable._k[obj] end
_kMetaTable.__tostring = function(obj)
        local result = ""
        if _kMetaTable._k[obj] then
            local width = 0
            for k,v in pairs(_kMetaTable._k[obj]) do width = width < #tostring(k) and #tostring(k) or width end
            for k,v in require("hs.fnutils").sortByKeys(_kMetaTable._k[obj]) do
                if _kMetaTable._t[obj] == "table" then
                    result = result..string.format("%-"..tostring(width).."s %s\n", tostring(k),
                        ((type(v) == "table") and "{ table }" or tostring(v)))
                else
                    result = result..((type(v) == "table") and "{ table }" or tostring(v)).."\n"
                end
            end
        else
            result = "constants table missing"
        end
        return result
    end
_kMetaTable.__metatable = _kMetaTable -- go ahead and look, but don't unset this

local _makeConstantsTable
_makeConstantsTable = function(theTable)
    if type(theTable) ~= "table" then
        local dbg = debug.getinfo(2)
        local msg = dbg.short_src..":"..dbg.currentline..": attempting to make a '"..type(theTable).."' into a constant table"
        if module.log then module.log.ef(msg) else print(msg) end
        return theTable
    end
    for k,v in pairs(theTable) do
        if type(v) == "table" then
            local count = 0
            for a,b in pairs(v) do count = count + 1 end
            local results = _makeConstantsTable(v)
            if #v > 0 and #v == count then
                _kMetaTable._t[results] = "array"
            else
                _kMetaTable._t[results] = "table"
            end
            theTable[k] = results
        end
    end
    local results = setmetatable({}, _kMetaTable)
    _kMetaTable._k[results] = theTable
    local count = 0
    for a,b in pairs(theTable) do count = count + 1 end
    if #theTable > 0 and #theTable == count then
        _kMetaTable._t[results] = "array"
    else
        _kMetaTable._t[results] = "table"
    end
    return results
end

local function getKeycode(s)
  local n
  if type(s)=='number' then n=s
  elseif type(s)~='string' then error('key must be a string or a number',3)
  elseif (s:sub(1, 1) == '#') then n=tonumber(s:sub(2))
  else n=keycodes.map[string.lower(s)] end
  if not n then error('Invalid key: '..s..' - this may mean that the key requested does not exist in your keymap (particularly if you switch keyboard layouts frequently)',3) end
  return n
end

local function getMods(mods)
  local r={}
  if not mods then return r end
  if type(mods)=='table' then mods=table.concat(mods,'-') end
  if type(mods)~='string' then error('mods must be a string or a table of strings',3) end
  -- super simple substring search for mod names in a string
  mods=string.lower(mods)
  local function find(ps)
    for _,s in ipairs(ps) do
      if string.find(mods,s,1,true) then r[#r+1]=ps[#ps] return end
    end
  end
  find{'cmd','command','⌘'} find{'ctrl','control','⌃'}
  find{'alt','option','⌥'} find{'shift','⇧'}
  find{'fn'}
  return r
end

module.event.types        = _makeConstantsTable(module.event.types)
module.event.properties   = _makeConstantsTable(module.event.properties)
module.event.modifierKeys = _makeConstantsTable(module.event.modifierKeys)

-- Public interface ------------------------------------------------------

local originalNewKeyEvent = module.event.newKeyEvent
module.event.newKeyEvent = function(mods, key, isDown)
    if (type(mods) == "number" or type(mods) == "string") and type(key) == "boolean" then
        mods, key, isDown = {}, mods, key
    end
    local keycode = getKeycode(key)
    local modifiers = getMods(mods)
    print(finspect(table.pack(modifiers, keycode, isDown)))
    return originalNewKeyEvent(modifiers, keycode, isDown)
end

--- hs.eventtap.event.newMouseEvent(eventtype, point[, modifiers) -> event
--- Constructor
--- Creates a new mouse event
---
--- Parameters:
---  * eventtype - One of the values from `hs.eventtap.event.types`
---  * point - A table with keys `{x, y}` indicating the location where the mouse event should occur
---  * modifiers - An optional table containing zero or more of the following keys:
---   * cmd
---   * alt
---   * shift
---   * ctrl
---   * fn
---
--- Returns:
---  * An `hs.eventtap` object
function module.event.newMouseEvent(eventtype, point, modifiers)
    local types = module.event.types
    local button = nil
    if eventtype == types["leftMouseDown"] or eventtype == types["leftMouseUp"] or eventtype == types["leftMouseDragged"] then
        button = "left"
    elseif eventtype == types["rightMouseDown"] or eventtype == types["rightMouseUp"] or eventtype == types["rightMouseDragged"] then
        button = "right"
    elseif eventtype == types["middleMouseDown"] or eventtype == types["middleMouseUp"] or eventtype == types["middleMouseDragged"] then
        button = "middle"
    else
        print("Error: unrecognised mouse button eventtype: " .. tostring(eventtype))
        return nil
    end
    return module.event._newMouseEvent(eventtype, point, button, modifiers)
end

--- hs.eventtap.event.postFlagChangeEvents(mods, isdown, [app], [delay]) -> none
--- Function
--- Create and post a series of flag change events (keyboard modifiers)
---
--- Parameters:
---  * mods   - A key-value table containing zero or more of the keyboard modifiers to include in the flag change events. The recognized modifiers are:
---   * `cmd`      - if present and `true`, specifies the left command key; if present and `false`, specifies the right
---   * `alt`      - if present and `true`, specifies the left alt or option key; if present and `false`, specifies the right
---   * `shift`    - if present and `true`, specifies the left shift key; if present and `false`, specifies the right
---   * `ctrl`     - if present and `true`, specifies the left control key; if present and `false`, specifies the right
---   * `fn`       - if present (i.e. not nil), specifies the function key found on many laptop keyboards
---   * `capsLock` - if present (i.e. not nil), specifies the caps lock key
---  * isdown - A boolean, true if the events should be a key-down, false if it should be a key-up
---  * app    - An optional `hs.application` object. If specified, the events will only be sent to that application
---  * delay  - An optional delay (in microseconds) between subsequent flag change events. Defaults to 0.
---
--- Returns:
---  * None
---
--- Notes:
---  * This function attempts to simulate as closely as possible the behavior observed when a user presses and releases modifier keys.  To that end, this function wraps up one or more events as described below and posts them:
---    * When modifier keys are pressed (isDown is true), a series of multiple `flagsChanged` events are posted, each event containing an additional modifier until all of the modifiers specified are included in the final event.
---    * When modifier keys are released (isDown is false), a series of multiple `flagsChanged` events are posted, each event containing one fewer of the specified modifiers until the final event which contains no modifiers.
---  * Because this function generates multiple events based upon the modifiers specified, you will not receive an event object which can be further modified or require an explicit `post`.
---
---  * See also [hs.eventtap.event.newFlagChangeEvent](#newFlagChangeEvent), but pay close attention to its notes or unexpected behaviors may be observed.
---
---  * The example given in [hs.eventtap.event.newKeyEvent](#newKeyEvent) utilizing this function:
---  ~~~lua
---      hs.eventtap.event.postFlagChangeEvents( { shift = true, alt = true }, true)
---      hs.eventtap.event.newKeyEvent("a", true):post()
---      hs.eventtap.event.newKeyEvent("a", false):post()
---      hs.eventtap.event.postFlagChangeEvents( { shift = true, alt = true }, false)
---  ~~~

-- does not replicate/copy metatables
local tableCopy
tableCopy = function(t, seen)
    seen = seen or {}
    if type(t) == "table" then
        if seen[t] then
            return seen[t]
        else
            local t2 = {}
            seen[t] = t2
            for k, v in pairs(t) do
                local newKey = tableCopy(k, seen)
                t2[newKey] = tableCopy(v, seen)
            end
            return t2
        end
    else
        return t
    end
end

local validKeys = {
    cmd      = true,
    alt      = true,
    shift    = true,
    ctrl     = true,
    fn       = true,
    capsLock = true,
}

module.event.postFlagChangeEvents = function(modsTable, state, target, delay)
    if delay == nil and type(target) == "number" then target, delay = nil, target end
    delay = delay or 0
    local eventsToPost = {}
    for k, v in pairs(modsTable) do
        if validKeys[k] then
            local prev = (#eventsToPost > 1) and tableCopy(eventsToPost[#eventsToPost].mods) or {}
            prev[k] = v and true or false
            table.insert(eventsToPost, { key = k, mods = prev, isLeft = v and true or false })
        else
            hs.luaSkinLog.wf("hs.eventtap.event.postFlagChangeEvents -- invalid modifier %s specified, ignoring", k)
        end
    end

    if not state then
        -- for keyup, it's a little more complex... first reverse the order, then remove them one by one, but the
        -- event key corresponds to the removed modifier at each step
        for i=1, math.floor(#eventsToPost / 2) do
            eventsToPost[i], eventsToPost[#eventsToPost - i + 1] = eventsToPost[#eventsToPost - i + 1], eventsToPost[i]
        end
        for i = 1, #eventsToPost, 1 do eventsToPost[i].mods[eventsToPost[i].key] = nil end
    end

--    if finspect then print(finspect(eventsToPost)) end -- debugging

    for i, v in ipairs(eventsToPost) do
        module.event.newFlagChangeEvent(v.mods, v.key, v.isLeft):post(target)
        if delay ~= 0 then timer.usleep(delay) end
    end
end


--- hs.eventtap.leftClick(point[, delay])
--- Function
--- Generates a left mouse click event at the specified point
---
--- Parameters:
---  * point - A table with keys `{x, y}` indicating the location where the mouse event should occur
---  * delay - An optional delay (in microseconds) between mouse down and up event. Defaults to 200000 (i.e. 200ms)
---
--- Returns:
---  * None
---
--- Notes:
---  * This is a wrapper around `hs.eventtap.event.newMouseEvent` that sends `leftmousedown` and `leftmouseup` events)
function module.leftClick(point, delay)
    if delay==nil then
        delay=200000
    end

    module.event.newMouseEvent(module.event.types["leftMouseDown"], point):post()
    timer.usleep(delay)
    module.event.newMouseEvent(module.event.types["leftMouseUp"], point):post()
end

--- hs.eventtap.rightClick(point[, delay])
--- Function
--- Generates a right mouse click event at the specified point
---
--- Parameters:
---  * point - A table with keys `{x, y}` indicating the location where the mouse event should occur
---  * delay - An optional delay (in microseconds) between mouse down and up event. Defaults to 200000 (i.e. 200ms)
---
--- Returns:
---  * None
---
--- Notes:
---  * This is a wrapper around `hs.eventtap.event.newMouseEvent` that sends `rightmousedown` and `rightmouseup` events)
function module.rightClick(point, delay)
    if delay==nil then
        delay=200000
    end

    module.event.newMouseEvent(module.event.types["rightMouseDown"], point):post()
    timer.usleep(delay)
    module.event.newMouseEvent(module.event.types["rightMouseUp"], point):post()
end

--- hs.eventtap.middleClick(point[, delay])
--- Function
--- Generates a middle mouse click event at the specified point
---
--- Parameters:
---  * point - A table with keys `{x, y}` indicating the location where the mouse event should occur
---  * delay - An optional delay (in microseconds) between mouse down and up event. Defaults to 200000 (i.e. 200ms)
---
--- Returns:
---  * None
---
--- Notes:
---  * This is a wrapper around `hs.eventtap.event.newMouseEvent` that sends `middlemousedown` and `middlemouseup` events)
function module.middleClick(point, delay)
    if delay==nil then
        delay=200000
    end

    module.event.newMouseEvent(module.event.types["middleMouseDown"], point):post()
    timer.usleep(delay)
    module.event.newMouseEvent(module.event.types["middleMouseUp"], point):post()
end

--- hs.eventtap.keyStroke(modifiers, character[, delay])
--- Function
--- Generates and emits a single keystroke event pair for the supplied keyboard modifiers and character
---
--- Parameters:
---  * modifiers - A table containing the keyboard modifiers to apply ("fn", "ctrl", "alt", "cmd", "shift", "fn", or their Unicode equivalents)
---  * character - A string containing a character to be emitted
---  * delay - An optional delay (in microseconds) between mouse down and up event. Defaults to 200000 (i.e. 200ms)
---
--- Returns:
---  * None
---
--- Notes:
---  * This function is ideal for sending single keystrokes with a modifier applied (e.g. sending ⌘-v to paste, with `hs.eventtap.keyStroke({"cmd"}, "v")`). If you want to emit multiple keystrokes for typing strings of text, see `hs.eventtap.keyStrokes()`
function module.keyStroke(modifiers, character, delay)
    if delay==nil then
        delay=200000
    end

    module.event.newKeyEvent(modifiers, character, true):post()
    timer.usleep(delay)
    module.event.newKeyEvent(modifiers, character, false):post()
end


--- hs.eventtap.scrollWheel(offsets, modifiers, unit) -> event
--- Function
--- Generates and emits a scroll wheel event
---
--- Parameters:
---  * offsets - A table containing the {horizontal, vertical} amount to scroll. Positive values scroll up or left, negative values scroll down or right.
---  * mods - A table containing zero or more of the following:
---   * cmd
---   * alt
---   * shift
---   * ctrl
---   * fn
---  * unit - An optional string containing the name of the unit for scrolling. Either "line" (the default) or "pixel"
---
--- Returns:
---  * None
function module.scrollWheel(offsets, modifiers, unit)
    module.event.newScrollEvent(offsets, modifiers, unit):post()
end
-- Return Module Object --------------------------------------------------

return module
