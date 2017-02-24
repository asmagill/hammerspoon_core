@import Cocoa ;
@import LuaSkin ;
@import MapKit ;

#define USERDATA_TAG "hs.location.mapkit"
static int refTable = LUA_NOREF;

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))
// #define get_structFromUserdata(objType, L, idx, tag) ((objType *)luaL_checkudata(L, idx, tag))
// #define get_cfobjectFromUserdata(objType, L, idx, tag) *((objType *)luaL_checkudata(L, idx, tag))

#pragma mark - Support Functions and Classes

#pragma mark - Module Functions

#pragma mark - Module Methods

#pragma mark - Module Constants

#pragma mark - Lua<->NSObject Conversion Functions
// These must not throw a lua error to ensure LuaSkin can safely be used from Objective-C
// delegates and blocks.

static int pushMKLocalSearch(lua_State *L, id obj) {
    MKLocalSearch *value = obj;
    void** valuePtr = lua_newuserdata(L, sizeof(MKLocalSearch *));
    *valuePtr = (__bridge_retained void *)value;
    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

id toMKLocalSearchFromLua(lua_State *L, int idx) {
    LuaSkin *skin = [LuaSkin shared] ;
    MKLocalSearch *value ;
    if (luaL_testudata(L, idx, USERDATA_TAG)) {
        value = get_objectFromUserdata(__bridge MKLocalSearch, L, idx, USERDATA_TAG) ;
    } else {
        [skin logError:[NSString stringWithFormat:@"expected %s object, found %s", USERDATA_TAG,
                                                   lua_typename(L, lua_type(L, idx))]] ;
    }
    return value ;
}

static int pushMKMapItem(lua_State *L, id obj) {
    LuaSkin *skin = [LuaSkin shared] ;
    MKMapItem *value = obj;
    lua_newtable(L) ;
    [skin pushNSObject:value.name] ; lua_setfield(L, -2, "name") ;
    [skin pushNSObject:value.url] ; lua_setfield(L, -2, "url") ;
    [skin pushNSObject:value.phoneNumber] ; lua_setfield(L, -2, "phoneNumber") ;
    lua_pushboolean(L, value.isCurrentLocation) ; lua_setfield(L, -2, "isCurrentLocation") ;
    // timezone added in OS X 10.11
    if ([value respondsToSelector:@selector(timeZone)]) {
        [skin pushNSObject:[[value performSelector:@selector(timeZone)] abbreviation]] ;
        lua_setfield(L, -2, "timeZone") ;
    }
    [skin pushNSObject:value.placemark] ; lua_setfield(L, -2, "placemark") ;
    return 1;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int userdata_tostring(lua_State* L) {
    LuaSkin *skin = [LuaSkin shared] ;
    MKLocalSearch *obj = [skin luaObjectAtIndex:1 toClass:"MKLocalSearch"] ;
    NSString *title = obj.searching ? @"active" : @"idle" ;
    [skin pushNSObject:[NSString stringWithFormat:@"%s: %@ (%p)", USERDATA_TAG, title, lua_topointer(L, 1)]] ;
    return 1 ;
}

static int userdata_eq(lua_State* L) {
// can't get here if at least one of us isn't a userdata type, and we only care if both types are ours,
// so use luaL_testudata before the macro causes a lua error
    if (luaL_testudata(L, 1, USERDATA_TAG) && luaL_testudata(L, 2, USERDATA_TAG)) {
        LuaSkin *skin = [LuaSkin shared] ;
        MKLocalSearch *obj1 = [skin luaObjectAtIndex:1 toClass:"MKLocalSearch"] ;
        MKLocalSearch *obj2 = [skin luaObjectAtIndex:2 toClass:"MKLocalSearch"] ;
        lua_pushboolean(L, [obj1 isEqualTo:obj2]) ;
    } else {
        lua_pushboolean(L, NO) ;
    }
    return 1 ;
}

static int userdata_gc(lua_State* L) {
    MKLocalSearch *obj = get_objectFromUserdata(__bridge_transfer MKLocalSearch, L, 1, USERDATA_TAG) ;
    if (obj) obj = nil ;
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
    {"__tostring", userdata_tostring},
    {"__eq",       userdata_eq},
    {"__gc",       userdata_gc},
    {NULL,         NULL}
};

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {NULL, NULL}
};

// // Metatable for module, if needed
// static const luaL_Reg module_metaLib[] = {
//     {"__gc", meta_gc},
//     {NULL,   NULL}
// };

// NOTE: ** Make sure to change luaopen_..._internal **
int luaopen_hs_module_internal(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin shared] ;
    refTable = [skin registerLibraryWithObject:USERDATA_TAG
                                     functions:moduleLib
                                 metaFunctions:nil    // or module_metaLib
                               objectFunctions:userdata_metaLib];

    [skin registerPushNSHelper:pushMKLocalSearch         forClass:"MKLocalSearch"];
    [skin registerLuaObjectHelper:toMKLocalSearchFromLua forClass:"MKLocalSearch"
                                              withUserdataMapping:USERDATA_TAG];

    return 1;
}
