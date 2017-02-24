This module was tested against two files in my own Hammerspoon configuration which utilize lone modifiers for toggling.

This document briefly describes these tests.

Note that when cutting and pasting these into the Hammerspoon console, each block of lua code is expected to be pasted in as one whole block, not as individual lines entered separately into the console.

- - -

First, some predefined functions:

~~~lua
-- a more accurate timestamp than os.date
timestamp = function(date)
    date = date or hs.timer.secondsSinceEpoch()
    return os.date("%F %T" .. string.format("%-5s", ((tostring(date):match("(%.%d+)$")) or "")), math.floor(date))
end

-- a flattened inspect that dereferences the event info into something more human friendly
flatinspect = function(what)
    return (hs.inspect(what, {
        process = function(i,p)
            if p[#p] == "flags" then
                 -- supresses the nonCoalesced modifier and what seems to be a synthesized event flag, though
                 -- I haven't found supporting documentation to confirm this.  These two modifiers are not
                 -- something we can control/set and they just confuse things when comparing against the values
                 -- defined in IOLLEvent.h
                return string.format("0x%08x", i & 0xdffffeff)
            elseif p[#p] == "type" then
                -- displays the event type rather than its number
                return hs.eventtap.event.types[i] or i
            elseif p[#p] == "keycode" then
                -- displays the actual key instead of the keycode number
                return hs.keycodes.map[i] or hs.eventtap.event.modifierKeys[i] or i
            else
                return i
            end
        end
    }):gsub("%s+", " ")) -- the extra () wrapping the return value suppresses string.gsub's second return value
end
~~~

Now, the first test was against a file which displays a summary of defined command key shortcuts for the current application.  In my setup, this display appears when you hold down the command key for more than 3.5 seconds.  The test was performed with the following code:

~~~lua
-- setup an event watcher so we can see what happens
a = hs.eventtap.new({
    hs.eventtap.event.types.flagsChanged,
    hs.eventtap.event.types.keyUp,
    hs.eventtap.event.types.keyDown
}, function(e)
    print(timestamp(), flatinspect(e:getRawEventData().CGEventData))
end):start()

-- trigger the command down
hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.cmd, true):post()

-- after a delay of 7 seconds, send the command key up
-- (it can take a few seconds to generate the display and I want it up long enough to confirm it works)
b = hs.timer.doAfter(7, function()
    hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.cmd, false):post()
    -- and then wait a second so we can see the eventtap messages and then kill it as well
    b = hs.timer.doAfter(1, function() a:stop() end)
end)
~~~

In the Hammerspoon console, I get the following:

~~~lua
2017-02-24 01:06:43.4874	{ flags = "0x00100008", keycode = "cmd", type = "flagsChanged" }
2017-02-24 01:06:43.5518	{ flags = "0x00000000", keycode = "return", type = "keyUp" }
2017-02-24 01:06:50.4835	{ flags = "0x00000000", keycode = "cmd", type = "flagsChanged" }
~~~

And the "Cheatsheet" for Hammerspoon does indeed appear.

Note that the `keyUp` event in the middle of the two `flagsChanged` events is due to the fact that the eventtap watcher we create goes into effect before Hammerspoon has a chance to receive the `return` key event that enters the code into the console input field.  We could have suppressed it by setting up the watcher to look only for `flagsChanged`, but I wanted to confirm that the `newKeyEvent` constructor was properly generating *only* `flagsChanged` events when we specify a modifier key rather than a regular keyboard character.

If you wish to perform this test yourself, you can find the code for the "Cheatsheet" like display at https://github.com/asmagill/hammerspoon-config/blob/master/utils/_keys/cheatsheet.lua (make sure to comment out line 231 and uncomment line 230 -- I use a local assets server so that it looks good even when I'm not connected to the internet)

You'll need to enable it by typing something like `cheatsheet = require("cheatsheet")` into the Hammerspoon console or adding it to your `init.lua` file (adjust as appropriate for your configuration and where you save the `cheatsheet.lua` file, just make sure that the returned table is stored in a global variable to prevent garbage collection from removing it).

- - -

For the second test, I used a touchbar display toggle that I have defined to be toggled when I press and hold the right alt (option) key on my keyboard.  If you wish to replicate this yourself, you will first need to install `hs._asm.touchbar` which can be found at https://github.com/asmagill/hammerspoon_asm/tree/master/touchbar and then use the code found at https://github.com/asmagill/hammerspoon-config/blob/master/utils/_keys/touchbar.lua -- again, you'll need to enable it by typing something like `touchbar = require("touchbar")` into the Hammerspoon console or adding it to your `init.lua` file (adjust as appropriate for your configuration and where you save the `touchbar.lua` file, just make sure that the returned table is stored in a global variable to prevent garbage collection from removing it).

~~~lua
-- setup an event watcher so we can see what happens
a = hs.eventtap.new({
    hs.eventtap.event.types.flagsChanged,
    hs.eventtap.event.types.keyUp,
    hs.eventtap.event.types.keyDown
}, function(e)
    print(timestamp(), flatinspect(e:getRawEventData().CGEventData))
end):start()

-- you can change the `rightAlt` keys to `alt` to confirm that it does *not* bring up the touchbar for the
-- left option key

-- trigger the rightAlt down
hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.rightAlt, true):post()

-- after a delay of 5 seconds, send the rightAlt key up
b = hs.timer.doAfter(5, function()
    hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.rightAlt, false):post()
    -- and then wait a second so we can see the eventtap messages and then kill it as well
    b = hs.timer.doAfter(1, function() a:stop() end)
end)
~~~

Resulting in:

~~~lua
2017-02-24 01:20:20.6874	{ flags = "0x00080040", keycode = "rightAlt", type = "flagsChanged" }
2017-02-24 01:20:20.7932	{ flags = "0x00000000", keycode = "return", type = "keyUp" }
2017-02-24 01:20:25.6817	{ flags = "0x00000000", keycode = "rightAlt", type = "flagsChanged" }
~~~

Repeat the above code (or hold the key yourself) to hide the touchbar again.

- - -

These are just initial tests... it should be tested further against applications other than Hammerspoon as well, but as there is interest in this addition to `hs.eventtap` and I don't know how long the refactoring will take and my availability is sporadic at the moment, I am putting this out there for people to use and play with.  Feel free to submit fixes, additions, or bug reports and I will get to them as and when I can.
