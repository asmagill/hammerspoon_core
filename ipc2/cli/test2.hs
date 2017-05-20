#! ./hs -A

-- The timeout for a respons is 2 seconds by default, so this example sets up a timer to
-- do the animation, plus its a little less stressfull on Hammerspoon to not block until
-- things are complete.  A shell script must complete within the timeout window so, use
-- timers to "background" things or add `-t ###` in the shebang line above (but realize
-- that while your script is running, Hammerspoon isn't doing anything else)

local text = _cli.args[2] or "You didn't specify a message!"

local screenFrame = require"hs.screen".mainScreen():frame()

local thing = require"hs.canvas".new{
    x = screenFrame.x + (screenFrame.w - 400) / 2,
    y = screenFrame.y + (screenFrame.h - 200) / 2,
    h = 200,
    w = 400,
}:show()

thing[#thing + 1] = {
    type = "rectangle",
    roundedRectRadii = { xRadius = 10, yRadius = 10 },
    fillColor = { white = .5, alpha = .5 },
    strokeColor = { white = .75, alpha = .75 },
    action = "strokeAndFill",
}

thing[#thing + 1] = {
    type = "text",
    text = text,
    frame = { x = 0, y = 80, h = 100, w = 400 },
    textAlignment = "center",
    textColor = { red = 1 },
}

local angle = 0
local timer
timer = require"hs.timer".doEvery(.1, function()
    if angle <= 360 then
        thing[2].transformation = require"hs.canvas.matrix".translate(200, 100):rotate(angle):translate(-200, -100)
        angle = angle + 5
    else
        timer:stop()
        timer = nil
        require"hs.timer".doAfter(2, function()
            thing:delete()
        end)
    end
end)
