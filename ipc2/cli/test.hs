#! ./hs -N -C -i

local inspect = require("hs.inspect")
print([[

Hello from scriptland!

Console mode is ]] .. tostring(_cli.console) .. [[

_cli._args is ]] .. inspect(_cli._args) .. [[

_cli.args  is ]] .. inspect(_cli.args) .. [[


Enjoy your stay!
]])

