hs.wifi
=======

This is an alpha test for a semi-regression of the `hs.wifi.watcher` sub-module for Hammerspoon.

In 0.9.51, the `hs.wifi.watcher` was updated to include additional event types to watch for (BSSID change, link quality change, power on/off, etc) and migrated to the `CWWiFiClient` class for monitoring wifi events because the Apple API documentation indicated that this class was fully supported as of OS X 10.10.  While this works fine in macOS 10.12, bug reports have shown that this is not the case with earlier OS versions.

This module has been adjusted to use the macOS notification center framework for observing wifi events, even though this method has been deprecated as of 10.10.  The additional events are still included and there should be no difference in function or code changes in your watchers required.

If you encounter any errors with this module, please submit them to the Hammerspoon issue at https://github.com/Hammerspoon/hammerspoon/issues/1210.

### Installation

A precompiled version of this module can be found in this directory with a name along the lines of `wifi-v0.x.tar.gz`. This can be installed by downloading the file and then expanding it as follows:

~~~sh
cd ~/.hammerspoon # or wherever your Hammerspoon init.lua file is located
tar -xzf ~/Downloads/wifi-v0.x.tar.gz # or wherever your downloads are located
~~~

If you wish to build this module yourself, and have XCode installed on your Mac, the best way (you are welcome to clone the entire repository if you like, but no promises on the current state of anything) is to download `Makefile`, `init.lua`, `internal.m`, and `watcher.m` (at present, nothing else is required) into a directory of your choice and then do the following:

~~~sh
$ cd wherever-you-downloaded-the-files
$ [HS_APPLICATION=/Applications] [PREFIX=~/.hammerspoon] make install
~~~

If your Hammerspoon application is located in `/Applications`, you can leave out the `HS_APPLICATION` environment variable, and if your Hammerspoon files are located in their default location, you can leave out the `PREFIX` environment variable.  For most people it will be sufficient to just type `make install`.

As always, whichever method you chose, if you are updating from an earlier version you must fully quit and restart Hammerspoon after installing this module to ensure that the latest version of the module is loaded into memory.

### Removal

When this module is finally updated in the Hammerspoon application itself and a new release occurs, you should remove this module from your configuration directory to ensure that the official module and not this temporary one is used.  You can do this by doing the following:

~~~sh
cd ~/.hammerspoon # or wherever your Hammerspoon init.lua file is located
rm -fr hs/wifi
rmdir hs
~~~

If you have any other code or modules stored in the `hs` subdirectory, you can skip the `rmdir hs` line.  If you don't, it will issue an error but you can safely ignore the error since it indicates that the directory is not empty and so nothing additional was removed.

As an alternative, if you downloaded the source and built the module yourself, you can just do the following:

~~~sh
$ cd wherever-you-downloaded-the-files
$ [HS_APPLICATION=/Applications] [PREFIX=~/.hammerspoon] make uninstall
~~~

The same caveats about the `HS_APPLICATION` and `PREFIX` environment variables described in the Installation section apply here.
