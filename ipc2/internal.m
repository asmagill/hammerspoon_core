@import Cocoa ;
@import LuaSkin ;

static const char * const USERDATA_TAG = "hs.ipc2" ;
static int refTable = LUA_NOREF;

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))
// #define get_structFromUserdata(objType, L, idx, tag) ((objType *)luaL_checkudata(L, idx, tag))
// #define get_cfobjectFromUserdata(objType, L, idx, tag) *((objType *)luaL_checkudata(L, idx, tag))

#pragma mark - Support Functions and Classes

@interface HSIPCMessagePort : NSObject
@property NSString           *name ;
@property CFMessagePortRef   messagePort ;
@property int                callbackRef ;
@end

static CFDataRef ipc2_callback(__unused CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {
    LuaSkin          *skin   = [LuaSkin shared];
    HSIPCMessagePort *port   = (__bridge HSIPCMessagePort *)info ;
    CFDataRef        outdata = NULL ;
    if (port.callbackRef != LUA_NOREF) {
        lua_State *L = skin.L ;
        [skin pushLuaRef:refTable ref:port.callbackRef] ;
        [skin pushNSObject:port] ;
        lua_pushinteger(L, msgid) ;
        [skin pushNSObject:(__bridge NSData *)data] ;
        [skin protectedCallAndTraceback:3 nresults:1] ; // we want one result anyways, be it correct or an error
        luaL_tolstring(L, -1, NULL) ;                   // make sure it's a string
        NSData *result = [skin toNSObjectAtIndex:-1 withOptions:LS_NSLuaStringAsDataOnly] ;
        lua_pop(L, 2) ;                                 // remove the result and the tostring version
        if (result) outdata = (__bridge_retained CFDataRef)result ;
    } else {
        [skin logWarn:[NSString stringWithFormat:@"%s:callback - no callback function defined for %@", USERDATA_TAG, port.name]] ;
    }
    return outdata ;
}

@implementation HSIPCMessagePort

- (instancetype)initWithName:(NSString *)portName {
    self = [super init] ;
    if (self) {
        _name        = portName ;
        _messagePort = NULL ;
        _callbackRef = LUA_NOREF ;
    }
    return self ;
}

@end

#pragma mark - Module Functions

/// hs.ipc2.new(name) -> ipcObject
/// Constructor
/// Create a new ipcObject representing a message port.
///
/// Parameters:
///  * name - a string acting as the message port name.
///
/// Returns:
///  * the ipc object
static int ipc2_new(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING, LS_TBREAK] ;

    HSIPCMessagePort *newPort = [[HSIPCMessagePort alloc] initWithName:[skin toNSObjectAtIndex:1]] ;
    if (newPort) {
        [skin pushNSObject:newPort] ;
    } else {
        lua_pushnil(L) ;
    }
    return 1 ;
}

#pragma mark - Module Methods

/// hs.ipc2:start() -> ipcObject
/// Method
/// Start the message port and enable communication with outside processes
///
/// Parameters:
///  * None
///
/// Returns:
///  * the ipc object
///
/// Notes:
///  * if an error occurs or if a message port with this object's name is already listening, generates an error.
static int ipc2_start(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSIPCMessagePort *port = [skin toNSObjectAtIndex:1] ;

    if (!port.messagePort) {
        CFMessagePortContext ctx = { 0, (__bridge void *)port, NULL, NULL, NULL } ;
        Boolean error = false ;
        port.messagePort = CFMessagePortCreateLocal(kCFAllocatorDefault, (__bridge CFStringRef)port.name, ipc2_callback, &ctx, &error) ;

        if (error) {
            NSString *errorMsg = port.messagePort ? @"port name already in use" : @"failed to create new port" ;
            port.messagePort = nil ;
            return luaL_error(L, errorMsg.UTF8String) ;
        }

        CFRunLoopSourceRef runLoop = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, port.messagePort, 0) ;
        if (runLoop) {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoop, kCFRunLoopCommonModes);
            CFRelease(runLoop) ;
        } else {
            return luaL_error(L, "unable to create runloop source") ;
        }
    } else {
        [LuaSkin logDebug:[NSString stringWithFormat:@"%s:start - message port already already started", USERDATA_TAG]] ;
    }

    lua_pushvalue(L, 1) ;
    return 1 ;
}

/// hs.ipc2:stop() -> ipcObject
/// Method
/// Stop the message port.
///
/// Parameters:
///  * None
///
/// Returns:
///  * the ipc object
static int ipc2_stop(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSIPCMessagePort *port = [skin toNSObjectAtIndex:1] ;

    if (port.messagePort) {
        CFMessagePortInvalidate(port.messagePort) ;
        CFRelease(port.messagePort) ;
        port.messagePort = NULL ;
    } else {
        [LuaSkin logDebug:[NSString stringWithFormat:@"%s:start - message port not active", USERDATA_TAG]] ;
    }

    lua_pushvalue(L, 1) ;
    return 1 ;
}

/// hs.ipc2:active() -> boolean
/// Method
/// Indicates whether or not the ipcObject is currently active and listening for communications or not.
///
/// Parameters:
///  * None
///
/// Returns:
///  * a boolean indicating whether or not the ipcObject is currently listening
static int ipc2_active(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSIPCMessagePort *port = [skin toNSObjectAtIndex:1] ;

    lua_pushboolean(L, port.messagePort != nil) ;
    return 1 ;
}

/// hs.ipc2:name() -> string
/// Method
/// Returns the name the ipcObject uses for its port when active
///
/// Parameters:
///  * None
///
/// Returns:
///  * the name as a string
static int ipc2_name(__unused lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK] ;
    HSIPCMessagePort *port = [skin toNSObjectAtIndex:1] ;

    [skin pushNSObject:port.name] ;
    return 1 ;
}

/// hs.ipc2:setCallback(fn) -> ipcObject
/// Method
/// Set or remove the callback function for the ipcObject
///
/// Parameters:
///  * fn - the callback function.  Specify an explicit nil to remove the callback from this ipcObject.
///
/// Returns:
///  * the ipcObject
///
/// Notes:
///  * the callback function should expect something and maybe even return something.  Not sure.
static int ipc2_setCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK] ;
    HSIPCMessagePort *port = [skin toNSObjectAtIndex:1] ;

    port.callbackRef = [skin luaUnref:refTable ref:port.callbackRef] ;
    if ([skin luaTypeAtIndex:2] == LUA_TFUNCTION) {
        lua_pushvalue(L, 2);
        port.callbackRef = [skin luaRef:refTable] ;
    }

    lua_pushvalue(L, 1);
    return 1;
}

#pragma mark - Module Constants

#pragma mark - Lua<->NSObject Conversion Functions
// These must not throw a lua error to ensure LuaSkin can safely be used from Objective-C
// delegates and blocks.

static int pushHSIPCMessagePort(lua_State *L, id obj) {
    HSIPCMessagePort *value = obj;
    void** valuePtr = lua_newuserdata(L, sizeof(HSIPCMessagePort *));
    *valuePtr = (__bridge_retained void *)value;
    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

id toHSIPCMessagePortFromLua(lua_State *L, int idx) {
    LuaSkin *skin = [LuaSkin shared] ;
    HSIPCMessagePort *value ;
    if (luaL_testudata(L, idx, USERDATA_TAG)) {
        value = get_objectFromUserdata(__bridge HSIPCMessagePort, L, idx, USERDATA_TAG) ;
    } else {
        [skin logError:[NSString stringWithFormat:@"expected %s object, found %s", USERDATA_TAG,
                                                   lua_typename(L, lua_type(L, idx))]] ;
    }
    return value ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int userdata_tostring(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared] ;
    HSIPCMessagePort *obj = [skin luaObjectAtIndex:1 toClass:"HSIPCMessagePort"] ;
    NSString *title = [NSString stringWithFormat:@"%@ - %@", obj.name, (obj.messagePort ? @"running" : @"stopped")] ;
    [skin pushNSObject:[NSString stringWithFormat:@"%s: %@ (%p)", USERDATA_TAG, title, lua_topointer(L, 1)]] ;
    return 1 ;
}

static int userdata_eq(lua_State* L) {
// can't get here if at least one of us isn't a userdata type, and we only care if both types are ours,
// so use luaL_testudata before the macro causes a lua error
    if (luaL_testudata(L, 1, USERDATA_TAG) && luaL_testudata(L, 2, USERDATA_TAG)) {
        LuaSkin *skin = [LuaSkin shared] ;
        HSIPCMessagePort *obj1 = [skin luaObjectAtIndex:1 toClass:"HSIPCMessagePort"] ;
        HSIPCMessagePort *obj2 = [skin luaObjectAtIndex:2 toClass:"HSIPCMessagePort"] ;
        lua_pushboolean(L, [obj1 isEqualTo:obj2]) ;
    } else {
        lua_pushboolean(L, NO) ;
    }
    return 1 ;
}

/// hs.ipc2:delete() -> None
/// Method
/// Deletes the ipcObject, stopping it as well if necessary
///
/// Parameters:
///  * None
///
/// Returns:
///  * None
static int userdata_gc(lua_State* L) {
    HSIPCMessagePort *obj = get_objectFromUserdata(__bridge_transfer HSIPCMessagePort, L, 1, USERDATA_TAG) ;
    if (obj) {
        LuaSkin *skin = [LuaSkin shared] ;
        obj.callbackRef = [skin luaUnref:refTable ref:obj.callbackRef] ;
        if (obj.messagePort) {
            CFMessagePortInvalidate(obj.messagePort) ;
            CFRelease(obj.messagePort) ;
            obj.messagePort = NULL ;
        }
    }
    obj = nil ;

    // Remove the Metatable so future use of the variable in Lua won't think its valid
    lua_pushnil(L) ;
    lua_setmetatable(L, 1) ;
    return 0 ;
}

// static int meta_gc(lua_State* __unused L) {
//     return 0 ;
// }

// Metatable for userdata objects
static const luaL_Reg userdata_metaLib[] = {
    {"start",       ipc2_start},
    {"stop",        ipc2_stop},
    {"active",      ipc2_active},
    {"setCallback", ipc2_setCallback},
    {"name",        ipc2_name},
    {"delete",      userdata_gc},

    {"__tostring",  userdata_tostring},
    {"__eq",        userdata_eq},
    {"__gc",        userdata_gc},
    {NULL,          NULL}
};

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {"new", ipc2_new},
    {NULL,  NULL}
};

// // Metatable for module, if needed
// static const luaL_Reg module_metaLib[] = {
//     {"__gc", meta_gc},
//     {NULL,   NULL}
// };

int luaopen_hs_ipc2_internal(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin shared] ;
    refTable = [skin registerLibraryWithObject:USERDATA_TAG
                                     functions:moduleLib
                                 metaFunctions:nil    // or module_metaLib
                               objectFunctions:userdata_metaLib];

    [skin registerPushNSHelper:pushHSIPCMessagePort         forClass:"HSIPCMessagePort"];
    [skin registerLuaObjectHelper:toHSIPCMessagePortFromLua forClass:"HSIPCMessagePort"
                                             withUserdataMapping:USERDATA_TAG];

    return 1;
}
