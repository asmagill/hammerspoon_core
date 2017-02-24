hs.eventtap
===========

This is a modified version of the Hammerspoon core module `hs.eventtap`.  This version adds support for creating `flagsChanged` events independant of other key events.  It is uncertain if this will eventually be merged into the core application because I am also working on a complete re-write of event handling and generation in an effort to reduce latency when many eventtaps are running concurrently and to more closely integrate eventaps with the `hs.hotkey` module in an attempt to address some of the idiosyncrasies and limitations of that module as well.

Note that in addition to the changes outlined below, minor adjustments were made to the source code to remove warnings during compilation. These changes should not affect the behavior of this module since they just make explicit some defaults that the compiler was assuming anyways. If you suspect that these changes have in fact altered the module behavior, please submit an issue so that I can examine it more closely and see what might need further adjustment.

### Installation

A precompiled version of this module can be found in this directory with a name along the lines of `eventtap-v0.x.tar.gz`. This can be installed by downloading the file and then expanding it as follows:

~~~sh
cd ~/.hammerspoon # or wherever your Hammerspoon init.lua file is located
tar -xzf ~/Downloads/eventtap-v0.x.tar.gz # or wherever your downloads are located
~~~

If you wish to build this module yourself, and have XCode installed on your Mac, the best way (you are welcome to clone the entire repository if you like, but no promises on the current state of anything) is to download `Makefile`, `init.lua`, `internal.m`, `event.m`, and `eventtap_event.h` (at present, nothing else is required) into a directory of your choice and then do the following:

~~~sh
$ cd wherever-you-downloaded-the-files
$ [HS_APPLICATION=/Applications] [PREFIX=~/.hammerspoon] make install
~~~

If your Hammerspoon application is located in `/Applications`, you can leave out the `HS_APPLICATION` environment variable, and if your Hammerspoon files are located in their default location, you can leave out the `PREFIX` environment variable.  For most people it will be sufficient to just type `make install`.

As always, whichever method you chose, if you are updating from an earlier version you must fully quit and restart Hammerspoon after installing this module to ensure that the latest version of the module is loaded into memory.

### Removal

If/When this module is finally updated in the Hammerspoon application itself and a new release occurs, you should remove this module from your configuration directory to ensure that the official module and not this temporary one is used.  You can do this by doing the following:

~~~sh
cd ~/.hammerspoon # or wherever your Hammerspoon init.lua file is located
rm -fr hs/eventtap
rmdir hs
~~~

If you have any other code or modules stored in the `hs` subdirectory, you can skip the `rmdir hs` line.  If you don't, it will issue an error but you can safely ignore the error since it indicates that the directory is not empty and so nothing additional was removed.

As an alternative, if you downloaded the source and built the module yourself, you can just do the following:

~~~sh
$ cd wherever-you-downloaded-the-files
$ [HS_APPLICATION=/Applications] [PREFIX=~/.hammerspoon] make uninstall
~~~

The same caveats about the `HS_APPLICATION` and `PREFIX` environment variables described in the Installation section apply here.

### Usage

`hs.eventtap.event.newKeyEvent` has been modified so that it can generate `flagsChanged` events or `keyUp`/`keyDown` events.  According to Apple's current documentation for the `CGEventCreateKeyboardEvent` function, this is the preferred approach and the Hammerspoon constructor as originally defined uses a shortcut which may not work in all instances.  For backwards compatibility (and because in most cases it *does* work as expected), this shortcut which allows combining multiple modifiers and a single key up or down event into one event is still supported by Hammerspoon, but see the Notes section of the constructors documentation for a description of how Apple recommends arranging things.

- - -

~~~lua
hs.eventtap.event.newKeyEvent([mods], key, isdown) -> event
~~~
Creates a keyboard event

Parameters:
 * mods - An optional table containing zero or more of the following:
  * cmd
  * alt
  * shift
  * ctrl
  * fn
 * key - A string containing the name of a key (see `hs.hotkey` for more information) or an integer specifying the virtual keycode for the key (see `hs.keycodes.map` and [hs.eventtap.event.modifierKeys](#modifierKeys))
 * isdown - A boolean, true if the event should be a key-down, false if it should be a key-up

Returns:
 * An `hs.eventtap.event` object

Notes:
 * The original version of this constructor utilized a shortcut which merged `flagsChanged` and `keyUp`/`keyDown` events into one.  This approach is still supported for backwards compatibility and because it *does* work in most cases.

 * According to Apple Documentation, the proper way to perform a keypress with modifiers is through multiple key events; for example to generate 'Å', you *should* do the following:
~~~lua
   hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.shift, true):post()
   hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.alt, true):post()
   hs.eventtap.event.newKeyEvent("a", true):post()
   hs.eventtap.event.newKeyEvent("a", false):post()
   hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.alt, false):post()
   hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.shift, false):post()
~~~
 * The shortcut method is still supported, though if you run into odd behavior or need to generate `flagsChanged` events without a corresponding `keyUp` or `keyDown`, please check out the syntax demonstrated above.
~~~lua
   hs.eventtap.event.newKeyEvent({"shift", "alt"}, "a", true):post()
   hs.eventtap.event.newKeyEvent({"shift", "alt"}, "a", false):post()
~~~

* The additional virtual keycodes for the modifier keys have been added to the [hs.eventtap.event.modifierKeys](#modifierKeys) table.  Note that these will probably move to `hs.keycodes` once the refectoring of `hs.eventtap` has been completed.

* The shortcut approach is still limited to generating only the left version of modifiers.

- - -

The following table contains the virtual keycodes required by [hs.eventtap.event.newKeyEvent](#newKeyEvent) to generate the appropriate `flagsChanged` events for modifier keys.

- - -

~~~lua
hs.eventtap.event.modifierKeys[]
~~~
Keycodes for modifiers not currently defined in `hs.keycodes`. Use with [hs.eventtap.event.newKeyEvent](#newKeyEvent).

Currently the following are defined in this table:
 * `cmd`        - the left Command modifier key (or only, if the keyboard only has one)
 * `shift`      - the left Shift modifier key (or only, if the keyboard only has one)
 * `alt`        - the left Option or Alt modifier key (or only, if the keyboard only has one)
 * `ctrl`       - the left Control modifier key (or only, if the keyboard only has one)
 * `rightCmd`   - the right Command modifier key, if present on the keyboard
 * `rightShift` - the right Shift modifier key, if present on the keyboard
 * `rightAlt`   - the right Option or Alt modifier key, if present on the keyboard
 * `rightCtrl`  - the right Control modifier key, if present on the keyboard
 * `capsLock`   - the Caps Lock toggle
 * `fn`         - the Function modifier key found on many laptops

Notes:
 * These will probably move to `hs.keycodes` once the refectoring of `hs.eventtap` has been completed.
 * These keycodes should only be used with [hs.eventtap.event.newKeyEvent](#newKeyEvent) when no `mods` table is included in the constructor arguments. Doing so will result in unexpected or broken behavior.

- - -

### License

> The MIT License (MIT)
>
> Copyright (c) 2014 Various contributors (see Hammerspoon git history)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.
