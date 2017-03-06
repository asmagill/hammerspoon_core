#import "eventtap_event.h"
@import IOKit.hidsystem ;

static CGEventSourceRef eventSource = NULL;

static int eventtap_event_gc(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CFRelease(event);
    // Remove the Metatable so future use of the variable in Lua won't think its valid
    lua_pushnil(L) ;
    lua_setmetatable(L, 1) ;
    return 0;
}

/// hs.eventtap.event:copy() -> event
/// Constructor
/// Duplicates an `hs.eventtap.event` event for further modification or injection
///
/// Parameters:
///  * None
///
/// Returns:
///  * A new `hs.eventtap.event` object
static int eventtap_event_copy(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);

    CGEventRef copy = CGEventCreateCopy(event);
    new_eventtap_event(L, copy);
    CFRelease(copy);

    return 1;
}

// static int eventtap_event_create(lua_State* L) {
//     CGEventRef copy = CGEventCreate(eventSource);
//     new_eventtap_event(L, copy);
//     CFRelease(copy);
//
//     return 1;
// }

/// hs.eventtap.event:getFlags() -> table
/// Method
/// Gets the keyboard modifiers of an event
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table containing the keyboard modifiers that present in the event - i.e. zero or more of the following keys, each with a value of `true`:
///   * cmd
///   * alt
///   * shift
///   * ctrl
///   * fn
static int eventtap_event_getFlags(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);

    lua_newtable(L);
    CGEventFlags curAltkey = CGEventGetFlags(event);
    if (curAltkey & kCGEventFlagMaskAlternate) { lua_pushboolean(L, YES); lua_setfield(L, -2, "alt"); }
    if (curAltkey & kCGEventFlagMaskShift) { lua_pushboolean(L, YES); lua_setfield(L, -2, "shift"); }
    if (curAltkey & kCGEventFlagMaskControl) { lua_pushboolean(L, YES); lua_setfield(L, -2, "ctrl"); }
    if (curAltkey & kCGEventFlagMaskCommand) { lua_pushboolean(L, YES); lua_setfield(L, -2, "cmd"); }
    if (curAltkey & kCGEventFlagMaskSecondaryFn) { lua_pushboolean(L, YES); lua_setfield(L, -2, "fn"); }
    return 1;
}

/// hs.eventtap.event:setFlags(table)
/// Method
/// Sets the keyboard modifiers of an event
///
/// Parameters:
///  * A table containing the keyboard modifiers to be sent with the event - i.e. zero or more of the following keys, each with a value of `true`:
///   * cmd
///   * alt
///   * shift
///   * ctrl
///   * fn
///
/// Returns:
///  * The `hs.eventap.event` object.
static int eventtap_event_setFlags(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    luaL_checktype(L, 2, LUA_TTABLE);

    CGEventFlags flags = (CGEventFlags)0;

    if (lua_getfield(L, 2, "cmd"), lua_toboolean(L, -1)) flags |= kCGEventFlagMaskCommand;
    if (lua_getfield(L, 2, "alt"), lua_toboolean(L, -1)) flags |= kCGEventFlagMaskAlternate;
    if (lua_getfield(L, 2, "ctrl"), lua_toboolean(L, -1)) flags |= kCGEventFlagMaskControl;
    if (lua_getfield(L, 2, "shift"), lua_toboolean(L, -1)) flags |= kCGEventFlagMaskShift;
    if (lua_getfield(L, 2, "fn"), lua_toboolean(L, -1)) flags |= kCGEventFlagMaskSecondaryFn;

    CGEventSetFlags(event, flags);

    lua_settop(L,1) ;
    return 1;
}

/// hs.eventtap.event:getRawEventData() -> table
/// Method
/// Returns raw data about the event
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table with two keys:
///    * CGEventData -- a table with keys containing CGEvent data about the event.
///    * NSEventData -- a table with keys containing NSEvent data about the event.
///
/// Notes:
///  * Most of the data in `CGEventData` is already available through other methods, but is presented here without any cleanup or parsing.
///  * This method is expected to be used mostly for testing and expanding the range of possibilities available with the hs.eventtap module.  If you find that you are regularly using specific data from this method for common or re-usable purposes, consider submitting a request for adding a more targeted method to hs.eventtap or hs.eventtap.event -- it will likely be more efficient and faster for common tasks, something eventtaps need to be to minimize affecting system responsiveness.
static int eventtap_event_getRawEventData(lua_State* L) {
    CGEventRef  event    = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CGEventType cgType   = CGEventGetType(event) ;

    lua_newtable(L) ;
        lua_newtable(L) ;
            lua_pushinteger(L, CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode));  lua_setfield(L, -2, "keycode") ;
            lua_pushinteger(L, CGEventGetFlags(event));                                       lua_setfield(L, -2, "flags") ;
            lua_pushinteger(L, cgType);                                                       lua_setfield(L, -2, "type") ;
        lua_setfield(L, -2, "CGEventData") ;

        lua_newtable(L) ;
        if ((cgType != kCGEventTapDisabledByTimeout) && (cgType != kCGEventTapDisabledByUserInput)) {
            NSEvent*    sysEvent = [NSEvent eventWithCGEvent:event];
            NSEventType type     = [sysEvent type] ;
            lua_pushinteger(L, [sysEvent modifierFlags]);                                     lua_setfield(L, -2, "modifierFlags") ;
            lua_pushinteger(L, type);                                                         lua_setfield(L, -2, "type") ;
            lua_pushinteger(L, [sysEvent windowNumber]);                                      lua_setfield(L, -2, "windowNumber") ;
            if ((type == NSKeyDown) || (type == NSKeyUp)) {
                lua_pushstring(L, [[sysEvent characters] UTF8String]) ;                       lua_setfield(L, -2, "characters") ;
                lua_pushstring(L, [[sysEvent charactersIgnoringModifiers] UTF8String]) ;      lua_setfield(L, -2, "charactersIgnoringModifiers") ;
                lua_pushinteger(L, [sysEvent keyCode]) ;                                      lua_setfield(L, -2, "keyCode") ;
            }
            if ((type == NSLeftMouseDown) || (type == NSLeftMouseUp) || (type == NSRightMouseDown) || (type == NSRightMouseUp) || (type == NSOtherMouseDown) || (type == NSOtherMouseUp)) {
                lua_pushinteger(L, [sysEvent buttonNumber]) ;                                 lua_setfield(L, -2, "buttonNumber") ;
                lua_pushinteger(L, [sysEvent clickCount]) ;                                   lua_setfield(L, -2, "clickCount") ;
                lua_pushnumber(L, (lua_Number)[sysEvent pressure]) ;                          lua_setfield(L, -2, "pressure") ;
            }
            if ((type == NSAppKitDefined) || (type == NSSystemDefined) || (type == NSApplicationDefined) || (type == NSPeriodic)) {
                lua_pushinteger(L, [sysEvent data1]) ;                                        lua_setfield(L, -2, "data1") ;
                lua_pushinteger(L, [sysEvent data2]) ;                                        lua_setfield(L, -2, "data2") ;
                lua_pushinteger(L, [sysEvent subtype]) ;                                      lua_setfield(L, -2, "subtype") ;
            }
        }
        lua_setfield(L, -2, "NSEventData") ;
    return 1;
}

/// hs.eventtap.event:getCharacters([clean]) -> string or nil
/// Method
/// Returns the Unicode character, if any, represented by a keyDown or keyUp event.
///
/// Parameters:
///  * clean -- an optional parameter, default `false`, which indicates if key modifiers, other than Shift, should be stripped from the keypress before converting to Unicode.
///
/// Returns:
///  * A string containing the Unicode character represented by the keyDown or keyUp event, or nil if the event is not a keyUp or keyDown.
///
/// Notes:
///  * This method should only be used on keyboard events
///  * If `clean` is true, all modifiers except for Shift are stripped from the character before converting to the Unicode character represented by the keypress.
///  * If the keypress does not correspond to a valid Unicode character, an empty string is returned (e.g. if `clean` is false, then Opt-E will return an empty string, while Opt-Shift-E will return an accent mark).
static int eventtap_event_getCharacters(lua_State* L) {
    CGEventRef  event    = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    BOOL        clean    = lua_isnone(L, 2) ? NO : (BOOL)lua_toboolean(L, 2) ;
    CGEventType cgType   = CGEventGetType(event) ;

    if ((cgType == kCGEventKeyDown) || (cgType == kCGEventKeyUp)) {
        if (clean)
            lua_pushstring(L, [[[NSEvent eventWithCGEvent:event] charactersIgnoringModifiers] UTF8String]) ;
        else
            lua_pushstring(L, [[[NSEvent eventWithCGEvent:event] characters] UTF8String]) ;
    } else {
        lua_pushnil(L) ;
    }
    return 1;
}

/// hs.eventtap.event:getKeyCode() -> keycode
/// Method
/// Gets the raw keycode for the event
///
/// Parameters:
///  * None
///
/// Returns:
///  * A number containing the raw keycode, taken from `hs.keycodes.map`
///
/// Notes:
///  * This method should only be used on keyboard events
static int eventtap_event_getKeyCode(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    lua_pushinteger(L, CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode));
    return 1;
}

/// hs.eventtap.event:setKeyCode(keycode)
/// Method
/// Sets the raw keycode for the event
///
/// Parameters:
///  * keycode - A number containing a raw keycode, taken from `hs.keycodes.map`
///
/// Returns:
///  * The `hs.eventtap.event` object
///
/// Notes:
///  * This method should only be used on keyboard events
static int eventtap_event_setKeyCode(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CGKeyCode keycode = (CGKeyCode)luaL_checkinteger(L, 2);
    CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, (int64_t)keycode);

    lua_settop(L,1) ;
    return 1;
}

/// hs.eventtap.event:post([app])
/// Method
/// Posts the event to the OS - i.e. emits the keyboard/mouse input defined by the event
///
/// Parameters:
///  * app - An optional `hs.application` object. If specified, the event will only be sent to that application
///
/// Returns:
///  * The `hs.eventtap.event` object
//  * None
static int eventtap_event_post(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);

    if (luaL_testudata(L, 2, "hs.application")) {
//         AXUIElementRef app = lua_touserdata(L, 2);
        AXUIElementRef app = *((AXUIElementRef*)luaL_checkudata(L, 2, "hs.application")) ;

        pid_t pid;
        AXUIElementGetPid(app, &pid);

        ProcessSerialNumber psn;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        GetProcessForPID(pid, &psn);
#pragma clang diagnostic pop
        CGEventPostToPSN(&psn, event);
    }
    else {
        CGEventPost(kCGSessionEventTap, event);
    }

    usleep(1000);

    lua_settop(L, 1) ;
//     return 0;
    return 1 ;
}

/// hs.eventtap.event:getType() -> number
/// Method
/// Gets the type of the event
///
/// Parameters:
///  * None
///
/// Returns:
///  * A number containing the type of the event, taken from `hs.eventtap.event.types`
static int eventtap_event_getType(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    lua_pushinteger(L, CGEventGetType(event));
    return 1;
}

/// hs.eventtap.event:getProperty(prop) -> number
/// Method
/// Gets a property of the event
///
/// Parameters:
///  * prop - A value taken from `hs.eventtap.event.properties`
///
/// Returns:
///  * A number containing the value of the requested property
///
/// Notes:
///  * The properties are `CGEventField` values, as documented at https://developer.apple.com/library/mac/documentation/Carbon/Reference/QuartzEventServicesRef/index.html#//apple_ref/c/tdef/CGEventField
static int eventtap_event_getProperty(lua_State* L) {
    CGEventRef   event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CGEventField field = (CGEventField)(luaL_checkinteger(L, 2));

    if ((field == kCGMouseEventPressure)                ||   // These fields use a double (floating point number)
        (field == kCGScrollWheelEventFixedPtDeltaAxis1) ||
        (field == kCGScrollWheelEventFixedPtDeltaAxis2) ||
        (field == kCGScrollWheelEventFixedPtDeltaAxis3) ||
        (field == kCGTabletEventPointPressure)          ||
        (field == kCGTabletEventTiltX)                  ||
        (field == kCGTabletEventTiltY)                  ||
        (field == kCGTabletEventRotation)               ||
        (field == kCGTabletEventTangentialPressure)) {
        lua_pushnumber(L, CGEventGetDoubleValueField(event, field));
    } else {
        lua_pushinteger(L, CGEventGetIntegerValueField(event, field));
    }
    return 1;
}

/// hs.eventtap.event:getButtonState(button) -> bool
/// Method
/// Gets the state of a mouse button in the event
///
/// Parameters:
///  * button - A number between 0 and 31. The left mouse button is 0, the right mouse button is 1 and the middle mouse button is 2. The meaning of the remaining buttons varies by hardware, and their functionality varies by application (typically they are not present on a mouse and have no effect in an application)
///
/// Returns:
///  * A boolean, true if the specified mouse button is to be clicked by the event
///
/// Notes:
///  * This method should only be called on mouse events
static int eventtap_event_getButtonState(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CGMouseButton whichButton = (CGMouseButton)(luaL_checkinteger(L, 2));

    if (CGEventSourceButtonState((CGEventSourceStateID)(CGEventGetIntegerValueField(event, kCGEventSourceStateID)), whichButton))
        lua_pushboolean(L, YES) ;
    else
        lua_pushboolean(L, NO) ;
    return 1;
}

/// hs.eventtap.event:setProperty(prop, value)
/// Method
/// Sets a property of the event
///
/// Parameters:
///  * prop - A value from `hs.eventtap.event.properties`
///  * value - A number containing the value of the specified property
///
/// Returns:
///  * The `hs.eventtap.event` object.
///
/// Notes:
///  * The properties are `CGEventField` values, as documented at https://developer.apple.com/library/mac/documentation/Carbon/Reference/QuartzEventServicesRef/index.html#//apple_ref/c/tdef/CGEventField
static int eventtap_event_setProperty(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CGEventField field = (CGEventField)(luaL_checkinteger(L, 2));
    if ((field == kCGMouseEventPressure)                ||   // These fields use a double (floating point number)
        (field == kCGScrollWheelEventFixedPtDeltaAxis1) ||
        (field == kCGScrollWheelEventFixedPtDeltaAxis2) ||
        (field == kCGScrollWheelEventFixedPtDeltaAxis3) ||
        (field == kCGTabletEventPointPressure)          ||
        (field == kCGTabletEventTiltX)                  ||
        (field == kCGTabletEventTiltY)                  ||
        (field == kCGTabletEventRotation)               ||
        (field == kCGTabletEventTangentialPressure)) {
        double value = luaL_checknumber(L, 3) ;
        CGEventSetDoubleValueField(event, field, value);
    } else {
        int64_t value = (int64_t)luaL_checkinteger(L, 3);
        CGEventSetIntegerValueField(event, field, value);
    }

    lua_settop(L,1) ;
    return 1;
}

/// hs.eventtap.event.newKeyEvent([mods], key, isdown) -> event
/// Constructor
/// Creates a keyboard event
///
/// Parameters:
///  * mods - An optional table containing zero or more of the following:
///   * cmd
///   * alt
///   * shift
///   * ctrl
///   * fn
///  * key - A string containing the name of a key (see `hs.hotkey` for more information) or an integer specifying the virtual keycode for the key.
///  * isdown - A boolean, true if the event should be a key-down, false if it should be a key-up
///
/// Returns:
///  * An `hs.eventtap.event` object
///
/// Notes:
///  * The original version of this constructor utilized a shortcut which merged `flagsChanged` and `keyUp`/`keyDown` events into one.  This approach is still supported for backwards compatibility and because it *does* work in most cases.
///  * According to Apple Documentation, the proper way to perform a keypress with modifiers is through multiple key events; for example to generate 'Å', you should do the following:
/// ~~~lua
///     hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.shift, true):post()
///     hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.alt, true):post()
///     hs.eventtap.event.newKeyEvent("a", true):post()
///     hs.eventtap.event.newKeyEvent("a", false):post()
///     hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.alt, false):post()
///     hs.eventtap.event.newKeyEvent(hs.eventtap.event.modifierKeys.shift, false):post()
/// ~~~
///  * The shortcut method is still supported, though if you run into odd behavior or need to generate `flagsChanged` events without a corresponding `keyUp` or `keyDown`, please check out the syntax demonstrated above.
/// ~~~lua
///     hs.eventtap.event.newKeyEvent({"shift", "alt"}, "a", true):post()
///     hs.eventtap.event.newKeyEvent({"shift", "alt"}, "a", false):post()
/// ~~~
///
/// * The additional virtual keycodes for the modifier keys have been added to the [hs.eventtap.event.modifierKeys](#modifierKeys) table.  Note that these will probably move to `hs.keycodes` once the refectoring of `hs.eventtap` has been completed.
///
/// * The shortcut approach is still limited to generating only the left version of modifiers.
static int eventtap_event_newKeyEvent(lua_State* L) {
    LuaSkin      *skin = [LuaSkin shared];
    BOOL         hasModTable = NO ;
    int          keyCodePos = 2 ;
    CGEventFlags flags = (CGEventFlags)0;

    if (lua_type(L, 1) == LUA_TTABLE) {
        [skin checkArgs:LS_TTABLE, LS_TNUMBER | LS_TINTEGER, LS_TBOOLEAN | LS_TOPTIONAL, LS_TBREAK] ;
        const char *modifier;

        lua_pushnil(L);
        while (lua_next(L, 1) != 0) {
            modifier = lua_tostring(L, -1);
            if (!modifier) {
                [skin logBreadcrumb:[NSString stringWithFormat:@"hs.eventtap.event.newKeyEvent() unexpected entry in modifiers table: %d", lua_type(L, -1)]];
                lua_pop(L, 1);
                continue;
            }

            if (strcmp(modifier, "cmd") == 0 || strcmp(modifier, "⌘") == 0) flags |= kCGEventFlagMaskCommand;
            else if (strcmp(modifier, "ctrl") == 0 || strcmp(modifier, "⌃") == 0) flags |= kCGEventFlagMaskControl;
            else if (strcmp(modifier, "alt") == 0 || strcmp(modifier, "⌥") == 0) flags |= kCGEventFlagMaskAlternate;
            else if (strcmp(modifier, "shift") == 0 || strcmp(modifier, "⇧") == 0) flags |= kCGEventFlagMaskShift;
            else if (strcmp(modifier, "fn") == 0) flags |= kCGEventFlagMaskSecondaryFn;
            lua_pop(L, 1);
        }
        hasModTable = YES ;
    } else if (lua_type(L, 1) == LUA_TNIL) {
        [skin checkArgs:LS_TNIL, LS_TNUMBER | LS_TINTEGER, LS_TBOOLEAN | LS_TOPTIONAL, LS_TBREAK] ;
    } else {
        [skin checkArgs:LS_TNUMBER | LS_TINTEGER, LS_TBOOLEAN | LS_TOPTIONAL, LS_TBREAK] ;
        keyCodePos  = 1 ;
    }
    BOOL         isDown  = (BOOL)lua_toboolean(L, keyCodePos + 1) ;
    CGKeyCode    keyCode = (CGKeyCode)lua_tointeger(L, keyCodePos) ;

    CGEventRef keyevent = CGEventCreateKeyboardEvent(eventSource, keyCode, isDown);
    if (hasModTable) CGEventSetFlags(keyevent, flags);
    new_eventtap_event(L, keyevent);
    CFRelease(keyevent);

    return 1;
}

/// hs.eventtap.event.newSystemKeyEvent(key, isdown) -> event
/// Constructor
/// Creates a keyboard event for special keys (e.g. media playback)
///
/// Parameters:
///  * key - A string containing the name of a special key. The possible names are:
///   * SOUND_UP
///   * SOUND_DOWN
///   * MUTE
///   * BRIGHTNESS_UP
///   * BRIGHTNESS_DOWN
///   * CONTRAST_UP
///   * CONTRAST_DOWN
///   * POWER
///   * LAUNCH_PANEL
///   * VIDMIRROR
///   * PLAY
///   * EJECT
///   * NEXT
///   * PREVIOUS
///   * FAST
///   * REWIND
///   * ILLUMINATION_UP
///   * ILLUMINATION_DOWN
///   * ILLUMINATION_TOGGLE
///   * CAPS_LOCK
///   * HELP
///   * NUM_LOCK
///  * isdown - A boolean, true if the event should be a key-down, false if it should be a key-up
///
/// Returns:
///  * An `hs.eventtap.event` object
///
/// Notes:
///  * To set modifiers on a system key event (e.g. cmd/ctrl/etc), see the `hs.eventtap.event:setFlags()` method
///  * The event names are case sensitive
static int eventtap_event_newSystemKeyEvent(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin checkArgs:LS_TSTRING, LS_TBOOLEAN, LS_TBREAK];

    NSString *keyName = [skin toNSObjectAtIndex:1];
    BOOL isDown = (BOOL)lua_toboolean(L, 2);
    int keyVal = -1;

    if ([keyName isEqualToString:@"SOUND_UP"]) {
        keyVal = NX_KEYTYPE_SOUND_UP;
    } else if ([keyName isEqualToString:@"SOUND_DOWN"]) {
        keyVal = NX_KEYTYPE_SOUND_DOWN;
    } else if ([keyName isEqualToString:@"POWER"]) {
        keyVal = NX_POWER_KEY;
    } else if ([keyName isEqualToString:@"MUTE"]) {
        keyVal = NX_KEYTYPE_MUTE;
    } else if ([keyName isEqualToString:@"BRIGHTNESS_UP"]) {
        keyVal = NX_KEYTYPE_BRIGHTNESS_UP;
    } else if ([keyName isEqualToString:@"BRIGHTNESS_DOWN"]) {
        keyVal = NX_KEYTYPE_BRIGHTNESS_DOWN;
    } else if ([keyName isEqualToString:@"CONTRAST_UP"]) {
        keyVal = NX_KEYTYPE_CONTRAST_UP;
    } else if ([keyName isEqualToString:@"CONTRAST_DOWN"]) {
        keyVal = NX_KEYTYPE_CONTRAST_DOWN;
    } else if ([keyName isEqualToString:@"LAUNCH_PANEL"]) {
        keyVal = NX_KEYTYPE_LAUNCH_PANEL;
    } else if ([keyName isEqualToString:@"EJECT"]) {
        keyVal = NX_KEYTYPE_EJECT;
    } else if ([keyName isEqualToString:@"VIDMIRROR"]) {
        keyVal = NX_KEYTYPE_VIDMIRROR;
    } else if ([keyName isEqualToString:@"PLAY"]) {
        keyVal = NX_KEYTYPE_PLAY;
    } else if ([keyName isEqualToString:@"NEXT"]) {
        keyVal = NX_KEYTYPE_NEXT;
    } else if ([keyName isEqualToString:@"PREVIOUS"]) {
        keyVal = NX_KEYTYPE_PREVIOUS;
    } else if ([keyName isEqualToString:@"FAST"]) {
        keyVal = NX_KEYTYPE_FAST;
    } else if ([keyName isEqualToString:@"REWIND"]) {
        keyVal = NX_KEYTYPE_REWIND;
    } else if ([keyName isEqualToString:@"ILLUMINATION_UP"]) {
        keyVal = NX_KEYTYPE_ILLUMINATION_UP;
    } else if ([keyName isEqualToString:@"ILLUMINATION_DOWN"]) {
        keyVal = NX_KEYTYPE_ILLUMINATION_DOWN;
    } else if ([keyName isEqualToString:@"ILLUMINATION_TOGGLE"]) {
        keyVal = NX_KEYTYPE_ILLUMINATION_TOGGLE;
    } else if ([keyName isEqualToString:@"CAPS_LOCK"]) {
        keyVal = NX_KEYTYPE_CAPS_LOCK;
    } else if ([keyName isEqualToString:@"HELP"]) {
        keyVal = NX_KEYTYPE_HELP;
    } else if ([keyName isEqualToString:@"NUM_LOCK"]) {
        keyVal = NX_KEYTYPE_NUM_LOCK;
    } else {
        [skin logError:[NSString stringWithFormat:@"Unknown system key for hs.eventtap.event.newSystemKeyEvent(): %@", keyName]];
        lua_pushnil(L);
        return 1;
    }

    NSEvent *keyEvent = [NSEvent otherEventWithType:NSSystemDefined location:NSMakePoint(0, 0) modifierFlags:(isDown ? NX_KEYDOWN : NX_KEYUP) timestamp:0 windowNumber:0 context:0 subtype:NX_SUBTYPE_AUX_CONTROL_BUTTONS data1:(keyVal << 16 | (isDown ? NX_KEYDOWN : NX_KEYUP) << 8) data2:-1];
    new_eventtap_event(L, keyEvent.CGEvent);

    return 1;
}

/// hs.eventtap.event.newScrollEvent(offsets, mods, unit) -> event
/// Constructor
/// Creates a scroll wheel event
///
/// Parameters:
///  * offsets - A table containing the {horizontal, vertical} amount to scroll. Positive values scroll up or left, negative values scroll down or right.
///  * mods - A table containing zero or more of the following:
///   * cmd
///   * alt
///   * shift
///   * ctrl
///   * fn
///  * unit - An optional string containing the name of the unit for scrolling. Either "line" (the default) or "pixel"
///
/// Returns:
///  * An `hs.eventtap.event` object
static int eventtap_event_newScrollWheelEvent(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared];
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_pushnumber(L, 1); lua_gettable(L, 1); int32_t offset_y = (int32_t)lua_tointeger(L, -1) ; lua_pop(L, 1);
    lua_pushnumber(L, 2); lua_gettable(L, 1); int32_t offset_x = (int32_t)lua_tointeger(L, -1) ; lua_pop(L, 1);

    const char *modifier;
    const char *unit;
    CGEventFlags flags = (CGEventFlags)0;
    CGScrollEventUnit type;

    luaL_checktype(L, 2, LUA_TTABLE);
    lua_pushnil(L);
    while (lua_next(L, 2) != 0) {
        modifier = lua_tostring(L, -1);
        if (!modifier) {
            [skin logBreadcrumb:[NSString stringWithFormat:@"hs.eventtap.event.newScrollEvent() unexpected entry in modifiers table: %d", lua_type(L, -1)]];
            lua_pop(L, 1);
            continue;
        }

        if (strcmp(modifier, "cmd") == 0 || strcmp(modifier, "⌘") == 0) flags |= kCGEventFlagMaskCommand;
        else if (strcmp(modifier, "ctrl") == 0 || strcmp(modifier, "⌃") == 0) flags |= kCGEventFlagMaskControl;
        else if (strcmp(modifier, "alt") == 0 || strcmp(modifier, "⌥") == 0) flags |= kCGEventFlagMaskAlternate;
        else if (strcmp(modifier, "shift") == 0 || strcmp(modifier, "⇧") == 0) flags |= kCGEventFlagMaskShift;
        else if (strcmp(modifier, "fn") == 0) flags |= kCGEventFlagMaskSecondaryFn;
        lua_pop(L, 1);
    }
    unit = lua_tostring(L, 3);
    if (unit && strcmp(unit, "pixel") == 0) type = kCGScrollEventUnitPixel; else type = kCGScrollEventUnitLine;

    CGEventRef scrollEvent = CGEventCreateScrollWheelEvent(eventSource, type, 2, offset_x, offset_y);
    CGEventSetFlags(scrollEvent, flags);
    new_eventtap_event(L, scrollEvent);
    CFRelease(scrollEvent);

    return 1;
}

static int eventtap_event_newMouseEvent(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared];
    CGEventType type = (CGEventType)(luaL_checkinteger(L, 1));
    CGPoint point = hs_topoint(L, 2);
    const char* buttonString = luaL_checkstring(L, 3);

    CGEventFlags flags = (CGEventFlags)0;
    const char *modifier;

    CGMouseButton button = kCGMouseButtonLeft;

    if (strcmp(buttonString, "right") == 0)
        button = kCGMouseButtonRight;
    else if (strcmp(buttonString, "middle") == 0)
        button = kCGMouseButtonCenter;

    if (!lua_isnoneornil(L, 4) && (lua_type(L, 4) == LUA_TTABLE)) {
        lua_pushnil(L);
        while (lua_next(L, 4) != 0) {
            modifier = lua_tostring(L, -2);
            if (!modifier) {
                [skin logBreadcrumb:[NSString stringWithFormat:@"hs.eventtap.event.newMouseEvent() unexpected entry in modifiers table: %d", lua_type(L, -1)]];
                lua_pop(L, 1);
                continue;
            }
            if (strcmp(modifier, "cmd") == 0 || strcmp(modifier, "⌘") == 0) flags |= kCGEventFlagMaskCommand;
            else if (strcmp(modifier, "ctrl") == 0 || strcmp(modifier, "⌃") == 0) flags |= kCGEventFlagMaskControl;
            else if (strcmp(modifier, "alt") == 0 || strcmp(modifier, "⌥") == 0) flags |= kCGEventFlagMaskAlternate;
            else if (strcmp(modifier, "shift") == 0 || strcmp(modifier, "⇧") == 0) flags |= kCGEventFlagMaskShift;
            else if (strcmp(modifier, "fn") == 0) flags |= kCGEventFlagMaskSecondaryFn;
            lua_pop(L, 1);
        }
    }

    CGEventRef event = CGEventCreateMouseEvent(eventSource, type, point, button);
    CGEventSetFlags(event, flags);
    new_eventtap_event(L, event);
    CFRelease(event);

    return 1;
}

/// hs.eventtap.event:systemKey() -> table
/// Method
/// Returns the special key and its state if the event is a NSSystemDefined event of subtype AUX_CONTROL_BUTTONS (special-key pressed)
///
/// Parameters:
///  * None
///
/// Returns:
///  * If the event is a NSSystemDefined event of subtype AUX_CONTROL_BUTTONS, a table with the following keys defined:
///    * key    -- a string containing one of the following labels indicating the key involved:
///      * SOUND_UP
///      * SOUND_DOWN
///      * MUTE
///      * BRIGHTNESS_UP
///      * BRIGHTNESS_DOWN
///      * CONTRAST_UP
///      * CONTRAST_DOWN
///      * POWER
///      * LAUNCH_PANEL
///      * VIDMIRROR
///      * PLAY
///      * EJECT
///      * NEXT
///      * PREVIOUS
///      * FAST
///      * REWIND
///      * ILLUMINATION_UP
///      * ILLUMINATION_DOWN
///      * ILLUMINATION_TOGGLE
///      * CAPS_LOCK
///      * HELP
///      * NUM_LOCK
///      or "undefined" if the key detected is unrecognized.
///    * keyCode -- the numeric keyCode corresponding to the key specified in `key`.
///    * down   -- a boolean value indicating if the key is pressed down (true) or just released (false)
///    * repeat -- a boolean indicating if this event is because the keydown is repeating.  This will always be false for a key release.
///  * If the event does not correspond to a NSSystemDefined event of subtype AUX_CONTROL_BUTTONS, then an empty table is returned.
///
/// Notes:
/// * CAPS_LOCK seems to sometimes generate 0 or 2 key release events (down == false), especially on builtin laptop keyboards, so it is probably safest (more reliable) to look for cases where down == true only.
/// * If the key field contains "undefined", you can use the number in keyCode to look it up in `/System/Library/Frameworks/IOKit.framework/Headers/hidsystem/ev_keymap.h`.  If you believe the numeric value is part of a new system update or was otherwise mistakenly left out, please submit the label (it will defined in the header file as `NX_KEYTYPE_something`) and number to the Hammerspoon maintainers at https://github.com/Hammerspoon/hammerspoon with a request for inclusion in the next Hammerspoon update.
static int eventtap_event_systemKey(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    NSEvent*    sysEvent = [NSEvent eventWithCGEvent:event];
    NSEventType type     = [sysEvent type] ;

    lua_newtable(L) ;
    if ((type == NSAppKitDefined) || (type == NSSystemDefined) || (type == NSApplicationDefined) || (type == NSPeriodic)) {
        NSInteger data1      = [sysEvent data1] ;
        if ([sysEvent subtype] == NX_SUBTYPE_AUX_CONTROL_BUTTONS) {
            int keyCode      = (data1 & 0xFFFF0000) >> 16;
            int keyFlags     = (data1 &     0xFFFF);
            switch(keyCode) {
//
// This list is based on the definition of NX_SPECIALKEY_POST_MASK found in
// /System/Library/Frameworks/IOKit.framework/Headers/hidsystem/ev_keymap.h
//
                case NX_KEYTYPE_SOUND_UP:            lua_pushstring(L, "SOUND_UP");            break ;
                case NX_KEYTYPE_SOUND_DOWN:          lua_pushstring(L, "SOUND_DOWN");          break ;
                case NX_POWER_KEY:                   lua_pushstring(L, "POWER");               break ;
                case NX_KEYTYPE_MUTE:                lua_pushstring(L, "MUTE");                break ;
                case NX_KEYTYPE_BRIGHTNESS_UP:       lua_pushstring(L, "BRIGHTNESS_UP");       break ;
                case NX_KEYTYPE_BRIGHTNESS_DOWN:     lua_pushstring(L, "BRIGHTNESS_DOWN");     break ;
                case NX_KEYTYPE_CONTRAST_UP:         lua_pushstring(L, "CONTRAST_UP");         break ;
                case NX_KEYTYPE_CONTRAST_DOWN:       lua_pushstring(L, "CONTRAST_DOWN");       break ;
                case NX_KEYTYPE_LAUNCH_PANEL:        lua_pushstring(L, "LAUNCH_PANEL");        break ;
                case NX_KEYTYPE_EJECT:               lua_pushstring(L, "EJECT");               break ;
                case NX_KEYTYPE_VIDMIRROR:           lua_pushstring(L, "VIDMIRROR");           break ;
                case NX_KEYTYPE_PLAY:                lua_pushstring(L, "PLAY");                break ;
                case NX_KEYTYPE_NEXT:                lua_pushstring(L, "NEXT");                break ;
                case NX_KEYTYPE_PREVIOUS:            lua_pushstring(L, "PREVIOUS");            break ;
                case NX_KEYTYPE_FAST:                lua_pushstring(L, "FAST");                break ;
                case NX_KEYTYPE_REWIND:              lua_pushstring(L, "REWIND");              break ;
                case NX_KEYTYPE_ILLUMINATION_UP:     lua_pushstring(L, "ILLUMINATION_UP");     break ;
                case NX_KEYTYPE_ILLUMINATION_DOWN:   lua_pushstring(L, "ILLUMINATION_DOWN");   break ;
                case NX_KEYTYPE_ILLUMINATION_TOGGLE: lua_pushstring(L, "ILLUMINATION_TOGGLE"); break ;
//
// The following also seem to trigger NSSystemDefined events, but are not listed in NX_SPECIALKEY_POST_MASK
//
                case NX_KEYTYPE_CAPS_LOCK:           lua_pushstring(L, "CAPS_LOCK");           break ;
                case NX_KEYTYPE_HELP:                lua_pushstring(L, "HELP");                break ;
                case NX_KEYTYPE_NUM_LOCK:            lua_pushstring(L, "NUM_LOCK");            break ;

                default:                             lua_pushstring(L, "undefined") ;          break ;
            }
            lua_setfield(L, -2, "key") ;
            lua_pushinteger(L, keyCode) ; lua_setfield(L, -2, "keyCode") ;
            lua_pushboolean(L, ((keyFlags & 0xFF00) >> 8) == 0x0a ) ; lua_setfield(L, -2, "down") ;
            lua_pushboolean(L, (keyFlags & 0x1) > 0) ; lua_setfield(L, -2, "repeat") ;
        }
    }
    return 1;
}

/// hs.eventtap.event.types -> table
/// Constant
/// A table containing event types to be used with `hs.eventtap.new(...)` and returned by `hs.eventtap.event:type()`.  The table supports forward (label to number) and reverse (number to label) lookups to increase its flexibility.
///
/// The constants defined in this table are as follows:
///
///   * nullEvent               --  Specifies a null event.
///   * leftMouseDown           --  Specifies a mouse down event with the left button.
///   * leftMouseUp             --  Specifies a mouse up event with the left button.
///   * rightMouseDown          --  Specifies a mouse down event with the right button.
///   * rightMouseUp            --  Specifies a mouse up event with the right button.
///   * mouseMoved              --  Specifies a mouse moved event.
///   * leftMouseDragged        --  Specifies a mouse drag event with the left button down.
///   * rightMouseDragged       --  Specifies a mouse drag event with the right button down.
///   * keyDown                 --  Specifies a key down event.
///   * keyUp                   --  Specifies a key up event.
///   * flagsChanged            --  Specifies a key changed event for a modifier or status key.
///   * scrollWheel             --  Specifies a scroll wheel moved event.
///   * tabletPointer           --  Specifies a tablet pointer event.
///   * tabletProximity         --  Specifies a tablet proximity event.
///   * otherMouseDown          --  Specifies a mouse down event with one of buttons 2-31.
///   * otherMouseUp            --  Specifies a mouse up event with one of buttons 2-31.
///   * otherMouseDragged       --  Specifies a mouse drag event with one of buttons 2-31 down.
///
///  The following events, also included in the lookup table, are provided through NSEvent and currently may require the use of `hs.eventtap.event:getRawEventData()` to retrieve supporting information.  Target specific methods may be added as the usability of these events is explored.
///
///   * NSMouseEntered          --  See Mouse-Tracking and Cursor-Update Events in Cocoa Event Handling Guide.
///   * NSMouseExited           --  See Mouse-Tracking and Cursor-Update Events in Cocoa Event Handling Guide.
///   * NSCursorUpdate          --  See Mouse-Tracking and Cursor-Update Events in Cocoa Event Handling Guide.
///   * NSAppKitDefined         --  See Event Objects and Types in Cocoa Event Handling Guide.
///   * NSSystemDefined         --  See Event Objects and Types in Cocoa Event Handling Guide.
///   * NSApplicationDefined    --  See Event Objects and Types in Cocoa Event Handling Guide.
///   * NSPeriodic              --  See Event Objects and Types in Cocoa Event Handling Guide.
///   * NSEventTypeGesture      --  An event that represents some type of gesture such as NSEventTypeMagnify, NSEventTypeSwipe, NSEventTypeRotate, NSEventTypeBeginGesture, or NSEventTypeEndGesture.
///   * NSEventTypeMagnify      --  An event representing a pinch open or pinch close gesture.
///   * NSEventTypeSwipe        --  An event representing a swipe gesture.
///   * NSEventTypeRotate       --  An event representing a rotation gesture.
///   * NSEventTypeBeginGesture --  An event that represents a gesture beginning.
///   * NSEventTypeEndGesture   --  An event that represents a gesture ending.
///   * NSEventTypeSmartMagnify --  NSEvent type for the smart zoom gesture (2-finger double tap on trackpads) along with a corresponding NSResponder method. In response to this event, you should intelligently magnify the content.
///   * NSEventTypeQuickLook    --  Supports the new event responder method that initiates a Quicklook.
///   * NSEventTypePressure     --  An NSEvent type representing a change in pressure on a pressure-sensitive device. Requires a 64-bit processor.
///
/// Notes:
///  * This table has a __tostring() metamethod which allows listing it's contents in the Hammerspoon console by typing `hs.eventtap.event.types`.
///  * In previous versions of Hammerspoon, type labels were defined with the labels in all lowercase.  This practice is deprecated, but an __index metamethod allows the lowercase labels to still be used; however a warning will be printed to the Hammerspoon console.  At some point, this may go away, so please update your code to follow the new format.

static void pushtypestable(lua_State* L) {
    lua_newtable(L);
    lua_pushinteger(L, kCGEventLeftMouseDown);      lua_setfield(L, -2, "leftMouseDown");
    lua_pushinteger(L, kCGEventLeftMouseUp);        lua_setfield(L, -2, "leftMouseUp");
    lua_pushinteger(L, kCGEventLeftMouseDragged);   lua_setfield(L, -2, "leftMouseDragged");
    lua_pushinteger(L, kCGEventRightMouseDown);     lua_setfield(L, -2, "rightMouseDown");
    lua_pushinteger(L, kCGEventRightMouseUp);       lua_setfield(L, -2, "rightMouseUp");
    lua_pushinteger(L, kCGEventRightMouseDragged);  lua_setfield(L, -2, "rightMouseDragged");
    lua_pushinteger(L, kCGEventOtherMouseDown);     lua_setfield(L, -2, "middleMouseDown");
    lua_pushinteger(L, kCGEventOtherMouseUp);       lua_setfield(L, -2, "middleMouseUp");
    lua_pushinteger(L, kCGEventOtherMouseDragged);  lua_setfield(L, -2, "middleMouseDragged");
    lua_pushinteger(L, kCGEventMouseMoved);         lua_setfield(L, -2, "mouseMoved");
    lua_pushinteger(L, kCGEventFlagsChanged);       lua_setfield(L, -2, "flagsChanged");
    lua_pushinteger(L, kCGEventScrollWheel);        lua_setfield(L, -2, "scrollWheel");
    lua_pushinteger(L, kCGEventKeyDown);            lua_setfield(L, -2, "keyDown");
    lua_pushinteger(L, kCGEventKeyUp);              lua_setfield(L, -2, "keyUp");
    lua_pushinteger(L, kCGEventTabletPointer);      lua_setfield(L, -2, "tabletPointer");
    lua_pushinteger(L, kCGEventTabletProximity);    lua_setfield(L, -2, "tabletProximity");
    lua_pushinteger(L, kCGEventNull);               lua_setfield(L, -2, "nullEvent");
    lua_pushinteger(L, NSMouseEntered);             lua_setfield(L, -2, "NSMouseEntered");
    lua_pushinteger(L, NSMouseExited);              lua_setfield(L, -2, "NSMouseExited");
    lua_pushinteger(L, NSAppKitDefined);            lua_setfield(L, -2, "NSAppKitDefined");
    lua_pushinteger(L, NSSystemDefined);            lua_setfield(L, -2, "NSSystemDefined");
    lua_pushinteger(L, NSApplicationDefined);       lua_setfield(L, -2, "NSApplicationDefined");
    lua_pushinteger(L, NSPeriodic);                 lua_setfield(L, -2, "NSPeriodic");
    lua_pushinteger(L, NSCursorUpdate);             lua_setfield(L, -2, "NSCursorUpdate");
    lua_pushinteger(L, NSEventTypeGesture);         lua_setfield(L, -2, "NSEventTypeGesture");
    lua_pushinteger(L, NSEventTypeMagnify);         lua_setfield(L, -2, "NSEventTypeMagnify");
    lua_pushinteger(L, NSEventTypeSwipe);           lua_setfield(L, -2, "NSEventTypeSwipe");
    lua_pushinteger(L, NSEventTypeRotate);          lua_setfield(L, -2, "NSEventTypeRotate");
    lua_pushinteger(L, NSEventTypeBeginGesture);    lua_setfield(L, -2, "NSEventTypeBeginGesture");
    lua_pushinteger(L, NSEventTypeEndGesture);      lua_setfield(L, -2, "NSEventTypeEndGesture");
    lua_pushinteger(L, NSEventTypeSmartMagnify);    lua_setfield(L, -2, "NSEventTypeSmartMagnify");
    lua_pushinteger(L, NSEventTypeQuickLook);       lua_setfield(L, -2, "NSEventTypeQuickLook");
    lua_pushinteger(L, NSEventTypePressure);        lua_setfield(L, -2, "NSEventTypePressure");

//     lua_pushinteger(L, kCGEventTapDisabledByTimeout);    lua_setfield(L, -2, "tapDisabledByTimeout");
//     lua_pushinteger(L, kCGEventTapDisabledByUserInput);  lua_setfield(L, -2, "tapDisabledByUserInput");
}

/// hs.eventtap.event.properties -> table
/// Constant
/// A table containing property types for use with `hs.eventtap.event:getProperty()` and `hs.eventtap.event:setProperty()`.  The table supports forward (label to number) and reverse (number to label) lookups to increase its flexibility.
///
/// The constants defined in this table are as follows:
///    (I) in the description indicates that this property is returned or set as an integer
///    (N) in the description indicates that this property is returned or set as a number (floating point)
///
///   * mouseEventNumber                              -- (I) The mouse button event number. Matching mouse-down and mouse-up events will have the same event number.
///   * mouseEventClickState                          -- (I) The mouse button click state. A click state of 1 represents a single click. A click state of 2 represents a double-click. A click state of 3 represents a triple-click.
///   * mouseEventPressure                            -- (N) The mouse button pressure. The pressure value may range from 0 to 1, with 0 representing the mouse being up. This value is commonly set by tablet pens mimicking a mouse.
///   * mouseEventButtonNumber                        -- (I) The mouse button number. For information about the possible values, see Mouse Buttons.
///   * mouseEventDeltaX                              -- (I) The horizontal mouse delta since the last mouse movement event.
///   * mouseEventDeltaY                              -- (I) The vertical mouse delta since the last mouse movement event.
///   * mouseEventInstantMouser                       -- (I) The value is non-zero if the event should be ignored by the Inkwell subsystem.
///   * mouseEventSubtype                             -- (I) Encoding of the mouse event subtype as a kCFNumberIntType.
///   * keyboardEventAutorepeat                       -- (I) Non-zero when this is an autorepeat of a key-down, and zero otherwise.
///   * keyboardEventKeycode                          -- (I) The virtual keycode of the key-down or key-up event.
///   * keyboardEventKeyboardType                     -- (I) The keyboard type identifier.
///   * scrollWheelEventDeltaAxis1                    -- (I) Scrolling data. This field typically contains the change in vertical position since the last scrolling event from a Mighty Mouse scroller or a single-wheel mouse scroller.
///   * scrollWheelEventDeltaAxis2                    -- (I) Scrolling data. This field typically contains the change in horizontal position since the last scrolling event from a Mighty Mouse scroller.
///   * scrollWheelEventDeltaAxis3                    -- (I) This field is not used.
///   * scrollWheelEventFixedPtDeltaAxis1             -- (N) Contains scrolling data which represents a line-based or pixel-based change in vertical position since the last scrolling event from a Mighty Mouse scroller or a single-wheel mouse scroller.
///   * scrollWheelEventFixedPtDeltaAxis2             -- (N) Contains scrolling data which represents a line-based or pixel-based change in horizontal position since the last scrolling event from a Mighty Mouse scroller.
///   * scrollWheelEventFixedPtDeltaAxis3             -- (N) This field is not used.
///   * scrollWheelEventPointDeltaAxis1               -- (I) Pixel-based scrolling data. The scrolling data represents the change in vertical position since the last scrolling event from a Mighty Mouse scroller or a single-wheel mouse scroller.
///   * scrollWheelEventPointDeltaAxis2               -- (I) Pixel-based scrolling data. The scrolling data represents the change in horizontal position since the last scrolling event from a Mighty Mouse scroller.
///   * scrollWheelEventPointDeltaAxis3               -- (I) This field is not used.
///   * scrollWheelEventInstantMouser                 -- (I) Indicates whether the event should be ignored by the Inkwell subsystem. If the value is non-zero, the event should be ignored.
///   * tabletEventPointX                             -- (I) The absolute X coordinate in tablet space at full tablet resolution.
///   * tabletEventPointY                             -- (I) The absolute Y coordinate in tablet space at full tablet resolution.
///   * tabletEventPointZ                             -- (I) The absolute Z coordinate in tablet space at full tablet resolution.
///   * tabletEventPointButtons                       -- (I) The tablet button state. Bit 0 is the first button, and a set bit represents a closed or pressed button. Up to 16 buttons are supported.
///   * tabletEventPointPressure                      -- (N) The tablet pen pressure. A value of 0.0 represents no pressure, and 1.0 represents maximum pressure.
///   * tabletEventTiltX                              -- (N) The horizontal tablet pen tilt. A value of 0.0 represents no tilt, and 1.0 represents maximum tilt.
///   * tabletEventTiltY                              -- (N) The vertical tablet pen tilt. A value of 0.0 represents no tilt, and 1.0 represents maximum tilt.
///   * tabletEventRotation                           -- (N) The tablet pen rotation.
///   * tabletEventTangentialPressure                 -- (N) The tangential pressure on the device. A value of 0.0 represents no pressure, and 1.0 represents maximum pressure.
///   * tabletEventDeviceID                           -- (I) The system-assigned unique device ID.
///   * tabletEventVendor1                            -- (I) A vendor-specified value.
///   * tabletEventVendor2                            -- (I) A vendor-specified value.
///   * tabletEventVendor3                            -- (I) A vendor-specified value.
///   * tabletProximityEventVendorID                  -- (I) The vendor-defined ID, typically the USB vendor ID.
///   * tabletProximityEventTabletID                  -- (I) The vendor-defined tablet ID, typically the USB product ID.
///   * tabletProximityEventPointerID                 -- (I) The vendor-defined ID of the pointing device.
///   * tabletProximityEventDeviceID                  -- (I) The system-assigned device ID.
///   * tabletProximityEventSystemTabletID            -- (I) The system-assigned unique tablet ID.
///   * tabletProximityEventVendorPointerType         -- (I) The vendor-assigned pointer type.
///   * tabletProximityEventVendorPointerSerialNumber -- (I) The vendor-defined pointer serial number.
///   * tabletProximityEventVendorUniqueID            -- (I) The vendor-defined unique ID.
///   * tabletProximityEventCapabilityMask            -- (I) The device capabilities mask.
///   * tabletProximityEventPointerType               -- (I) The pointer type.
///   * tabletProximityEventEnterProximity            -- (I) Indicates whether the pen is in proximity to the tablet. The value is non-zero if the pen is in proximity to the tablet and zero when leaving the tablet.
///   * eventTargetProcessSerialNumber                -- (I) The event target process serial number. The value is a 64-bit long word.
///   * eventTargetUnixProcessID                      -- (I) The event target Unix process ID.
///   * eventSourceUnixProcessID                      -- (I) The event source Unix process ID.
///   * eventSourceUserData                           -- (I) Event source user-supplied data, up to 64 bits.
///   * eventSourceUserID                             -- (I) The event source Unix effective UID.
///   * eventSourceGroupID                            -- (I) The event source Unix effective GID.
///   * eventSourceStateID                            -- (I) The event source state ID used to create this event.
///   * scrollWheelEventIsContinuous                  -- (I) Indicates whether a scrolling event contains continuous, pixel-based scrolling data. The value is non-zero when the scrolling data is pixel-based and zero when the scrolling data is line-based.
///
/// Notes:
///  * This table has a __tostring() metamethod which allows listing it's contents in the Hammerspoon console by typing `hs.eventtap.event.properties`.
///  * In previous versions of Hammerspoon, property labels were defined with the labels in all lowercase.  This practice is deprecated, but an __index metamethod allows the lowercase labels to still be used; however a warning will be printed to the Hammerspoon console.  At some point, this may go away, so please update your code to follow the new format.
static void pushpropertiestable(lua_State* L) {
    lua_newtable(L);
    lua_pushinteger(L, kCGMouseEventNumber);                                 lua_setfield(L, -2, "mouseEventNumber");
    lua_pushinteger(L, kCGMouseEventClickState);                             lua_setfield(L, -2, "mouseEventClickState");
    lua_pushinteger(L, kCGMouseEventPressure);                               lua_setfield(L, -2, "mouseEventPressure");
    lua_pushinteger(L, kCGMouseEventButtonNumber);                           lua_setfield(L, -2, "mouseEventButtonNumber");
    lua_pushinteger(L, kCGMouseEventDeltaX);                                 lua_setfield(L, -2, "mouseEventDeltaX");
    lua_pushinteger(L, kCGMouseEventDeltaY);                                 lua_setfield(L, -2, "mouseEventDeltaY");
    lua_pushinteger(L, kCGMouseEventInstantMouser);                          lua_setfield(L, -2, "mouseEventInstantMouser");
    lua_pushinteger(L, kCGMouseEventSubtype);                                lua_setfield(L, -2, "mouseEventSubtype");
    lua_pushinteger(L, kCGKeyboardEventAutorepeat);                          lua_setfield(L, -2, "keyboardEventAutorepeat");
    lua_pushinteger(L, kCGKeyboardEventKeycode);                             lua_setfield(L, -2, "keyboardEventKeycode");
    lua_pushinteger(L, kCGKeyboardEventKeyboardType);                        lua_setfield(L, -2, "keyboardEventKeyboardType");
    lua_pushinteger(L, kCGScrollWheelEventDeltaAxis1);                       lua_setfield(L, -2, "scrollWheelEventDeltaAxis1");
    lua_pushinteger(L, kCGScrollWheelEventDeltaAxis2);                       lua_setfield(L, -2, "scrollWheelEventDeltaAxis2");
    lua_pushinteger(L, kCGScrollWheelEventDeltaAxis3);                       lua_setfield(L, -2, "scrollWheelEventDeltaAxis3");
    lua_pushinteger(L, kCGScrollWheelEventFixedPtDeltaAxis1);                lua_setfield(L, -2, "scrollWheelEventFixedPtDeltaAxis1");
    lua_pushinteger(L, kCGScrollWheelEventFixedPtDeltaAxis2);                lua_setfield(L, -2, "scrollWheelEventFixedPtDeltaAxis2");
    lua_pushinteger(L, kCGScrollWheelEventFixedPtDeltaAxis3);                lua_setfield(L, -2, "scrollWheelEventFixedPtDeltaAxis3");
    lua_pushinteger(L, kCGScrollWheelEventPointDeltaAxis1);                  lua_setfield(L, -2, "scrollWheelEventPointDeltaAxis1");
    lua_pushinteger(L, kCGScrollWheelEventPointDeltaAxis2);                  lua_setfield(L, -2, "scrollWheelEventPointDeltaAxis2");
    lua_pushinteger(L, kCGScrollWheelEventPointDeltaAxis3);                  lua_setfield(L, -2, "scrollWheelEventPointDeltaAxis3");
    lua_pushinteger(L, kCGScrollWheelEventInstantMouser);                    lua_setfield(L, -2, "scrollWheelEventInstantMouser");
    lua_pushinteger(L, kCGTabletEventPointX);                                lua_setfield(L, -2, "tabletEventPointX");
    lua_pushinteger(L, kCGTabletEventPointY);                                lua_setfield(L, -2, "tabletEventPointY");
    lua_pushinteger(L, kCGTabletEventPointZ);                                lua_setfield(L, -2, "tabletEventPointZ");
    lua_pushinteger(L, kCGTabletEventPointButtons);                          lua_setfield(L, -2, "tabletEventPointButtons");
    lua_pushinteger(L, kCGTabletEventPointPressure);                         lua_setfield(L, -2, "tabletEventPointPressure");
    lua_pushinteger(L, kCGTabletEventTiltX);                                 lua_setfield(L, -2, "tabletEventTiltX");
    lua_pushinteger(L, kCGTabletEventTiltY);                                 lua_setfield(L, -2, "tabletEventTiltY");
    lua_pushinteger(L, kCGTabletEventRotation);                              lua_setfield(L, -2, "tabletEventRotation");
    lua_pushinteger(L, kCGTabletEventTangentialPressure);                    lua_setfield(L, -2, "tabletEventTangentialPressure");
    lua_pushinteger(L, kCGTabletEventDeviceID);                              lua_setfield(L, -2, "tabletEventDeviceID");
    lua_pushinteger(L, kCGTabletEventVendor1);                               lua_setfield(L, -2, "tabletEventVendor1");
    lua_pushinteger(L, kCGTabletEventVendor2);                               lua_setfield(L, -2, "tabletEventVendor2");
    lua_pushinteger(L, kCGTabletEventVendor3);                               lua_setfield(L, -2, "tabletEventVendor3");
    lua_pushinteger(L, kCGTabletProximityEventVendorID);                     lua_setfield(L, -2, "tabletProximityEventVendorID");
    lua_pushinteger(L, kCGTabletProximityEventTabletID);                     lua_setfield(L, -2, "tabletProximityEventTabletID");
    lua_pushinteger(L, kCGTabletProximityEventPointerID);                    lua_setfield(L, -2, "tabletProximityEventPointerID");
    lua_pushinteger(L, kCGTabletProximityEventDeviceID);                     lua_setfield(L, -2, "tabletProximityEventDeviceID");
    lua_pushinteger(L, kCGTabletProximityEventSystemTabletID);               lua_setfield(L, -2, "tabletProximityEventSystemTabletID");
    lua_pushinteger(L, kCGTabletProximityEventVendorPointerType);            lua_setfield(L, -2, "tabletProximityEventVendorPointerType");
    lua_pushinteger(L, kCGTabletProximityEventVendorPointerSerialNumber);    lua_setfield(L, -2, "tabletProximityEventVendorPointerSerialNumber");
    lua_pushinteger(L, kCGTabletProximityEventVendorUniqueID);               lua_setfield(L, -2, "tabletProximityEventVendorUniqueID");
    lua_pushinteger(L, kCGTabletProximityEventCapabilityMask);               lua_setfield(L, -2, "tabletProximityEventCapabilityMask");
    lua_pushinteger(L, kCGTabletProximityEventPointerType);                  lua_setfield(L, -2, "tabletProximityEventPointerType");
    lua_pushinteger(L, kCGTabletProximityEventEnterProximity);               lua_setfield(L, -2, "tabletProximityEventEnterProximity");
    lua_pushinteger(L, kCGEventTargetProcessSerialNumber);                   lua_setfield(L, -2, "eventTargetProcessSerialNumber");
    lua_pushinteger(L, kCGEventTargetUnixProcessID);                         lua_setfield(L, -2, "eventTargetUnixProcessID");
    lua_pushinteger(L, kCGEventSourceUnixProcessID);                         lua_setfield(L, -2, "eventSourceUnixProcessID");
    lua_pushinteger(L, kCGEventSourceUserData);                              lua_setfield(L, -2, "eventSourceUserData");
    lua_pushinteger(L, kCGEventSourceUserID);                                lua_setfield(L, -2, "eventSourceUserID");
    lua_pushinteger(L, kCGEventSourceGroupID);                               lua_setfield(L, -2, "eventSourceGroupID");
    lua_pushinteger(L, kCGEventSourceStateID);                               lua_setfield(L, -2, "eventSourceStateID");
    lua_pushinteger(L, kCGScrollWheelEventIsContinuous);                     lua_setfield(L, -2, "scrollWheelEventIsContinuous");
}

/// hs.eventtap.event.modifierKeys[]
/// Constant
/// Keycodes for modifiers not currently defined in `hs.keycodes`. Use with [hs.eventtap.event.newKeyEvent](#newKeyEvent).
///
/// Currently the following are defined in this table:
///  * `cmd`        - the left Command modifier key (or only, if the keyboard only has one)
///  * `shift`      - the left Shift modifier key (or only, if the keyboard only has one)
///  * `alt`        - the left Option or Alt modifier key (or only, if the keyboard only has one)
///  * `ctrl`       - the left Control modifier key (or only, if the keyboard only has one)
///  * `rightCmd`   - the right Command modifier key, if present on the keyboard
///  * `rightShift` - the right Shift modifier key, if present on the keyboard
///  * `rightAlt`   - the right Option or Alt modifier key, if present on the keyboard
///  * `rightCtrl`  - the right Control modifier key, if present on the keyboard
///  * `capsLock`   - the Caps Lock toggle
///  * `fn`         - the Function modifier key found on many laptops
///
/// Notes:
///  * These will probably move to `hs.keycodes` once the refectoring of `hs.eventtap` has been completed.
///  * These keycodes should only be used with [hs.eventtap.event.newKeyEvent](#newKeyEvent) when no `mods` table is included in the constructor arguments. Doing so will result in unexpected or broken behavior.
static int push_modifierKeys(lua_State *L) {
    lua_newtable(L) ;
    lua_pushinteger(L, kVK_Command) ;      lua_setfield(L, -2, "cmd") ;
    lua_pushinteger(L, kVK_Shift) ;        lua_setfield(L, -2, "shift") ;
    lua_pushinteger(L, kVK_CapsLock) ;     lua_setfield(L, -2, "capsLock") ;
    lua_pushinteger(L, kVK_Option) ;       lua_setfield(L, -2, "alt") ;
    lua_pushinteger(L, kVK_Control) ;      lua_setfield(L, -2, "ctrl") ;
    lua_pushinteger(L, kVK_RightCommand) ; lua_setfield(L, -2, "rightCmd") ;
    lua_pushinteger(L, kVK_RightShift) ;   lua_setfield(L, -2, "rightShift") ;
    lua_pushinteger(L, kVK_RightOption) ;  lua_setfield(L, -2, "rightAlt") ;
    lua_pushinteger(L, kVK_RightControl) ; lua_setfield(L, -2, "rightCtrl") ;
    lua_pushinteger(L, kVK_Function) ;     lua_setfield(L, -2, "fn") ;

    return 1 ;
}

static int userdata_tostring(lua_State* L) {
    CGEventRef event = *(CGEventRef*)luaL_checkudata(L, 1, EVENT_USERDATA_TAG);
    CGEventType eventType = CGEventGetType(event) ;

    lua_pushstring(L, [[NSString stringWithFormat:@"%s: Event type: %d (%p)", EVENT_USERDATA_TAG, eventType, lua_topointer(L, 1)] UTF8String]) ;
    return 1 ;
}

static int meta_gc(lua_State* __unused L) {
    if (eventSource) {
        CFRelease(eventSource);
        eventSource = NULL;
    }
    return 0;
}

// Metatable for created objects when _new invoked
static const luaL_Reg eventtapevent_metalib[] = {
    {"copy",            eventtap_event_copy},
    {"getFlags",        eventtap_event_getFlags},
    {"setFlags",        eventtap_event_setFlags},
    {"getKeyCode",      eventtap_event_getKeyCode},
    {"setKeyCode",      eventtap_event_setKeyCode},
    {"getType",         eventtap_event_getType},
    {"post",            eventtap_event_post},
    {"getProperty",     eventtap_event_getProperty},
    {"setProperty",     eventtap_event_setProperty},
    {"getButtonState",  eventtap_event_getButtonState},
    {"getRawEventData", eventtap_event_getRawEventData},
    {"getCharacters",   eventtap_event_getCharacters},
    {"systemKey",       eventtap_event_systemKey},
    {"__tostring",      userdata_tostring},
    {"__gc",            eventtap_event_gc},
    {NULL,              NULL}
};

// Functions for returned object when module loads
static luaL_Reg eventtapeventlib[] = {
    {"newKeyEvent",        eventtap_event_newKeyEvent},
    {"newSystemKeyEvent",  eventtap_event_newSystemKeyEvent},
    {"_newMouseEvent",     eventtap_event_newMouseEvent},
    {"newScrollEvent",     eventtap_event_newScrollWheelEvent},

    {NULL,                NULL}
};

// Metatable for returned object when module loads
static const luaL_Reg meta_gcLib[] = {
    {"__gc",    meta_gc},
    {NULL,      NULL}
};

int luaopen_hs_eventtap_event(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared];
    [skin registerLibraryWithObject:EVENT_USERDATA_TAG functions:eventtapeventlib metaFunctions:meta_gcLib objectFunctions:eventtapevent_metalib];

    pushtypestable(L);
    lua_setfield(L, -2, "types");

    pushpropertiestable(L);
    lua_setfield(L, -2, "properties");

    push_modifierKeys(L) ;
    lua_setfield(L, -2, "modifierKeys") ;

    eventSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
//     eventSource = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    return 1;
}
