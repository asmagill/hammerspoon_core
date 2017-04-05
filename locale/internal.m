@import Cocoa ;
@import LuaSkin ;

static const char * const USERDATA_TAG = "hs.host.locale" ;
static int refTable = LUA_NOREF;
static int callbackRef = LUA_NOREF ;

#pragma mark - Support Functions and Classes

@interface HSLocaleChangeObserver : NSObject
@end
static HSLocaleChangeObserver *observerOfChanges = nil ;

@implementation HSLocaleChangeObserver

- (void) localeChanged:(__unused NSNotification*)notification {
    if (callbackRef != LUA_NOREF) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LuaSkin *skin = [LuaSkin shared];
            [skin pushLuaRef:refTable ref:callbackRef];
            if (![skin protectedCallAndTraceback:0 nresults:0]) {
                [skin logError:[NSString stringWithFormat:@"%s: callback error: %s", USERDATA_TAG, lua_tostring(skin.L, -1)]];
                lua_pop(skin.L, 1) ; // remove error message
            }
        }) ;
    }
}

- (void) start {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localeChanged:)
                                                 name:NSCurrentLocaleDidChangeNotification
                                               object:nil];
}

- (void) stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSCurrentLocaleDidChangeNotification
                                                  object:nil];
}

@end

// NOTE: These may one day become valid types that we want to create module support for or subclass, so...
//       create support tables for what we care about right now and don't register them as helpers

static int pushNSCalendar(lua_State *L, id obj) {
    LuaSkin *skin = [LuaSkin shared] ;
    NSCalendar *calendar = obj ;
    lua_newtable(L) ;
    // obj-c uses zero based indexing; lua uses 1 based indexing
    lua_pushinteger(L, (lua_Integer)(calendar.firstWeekday + 1)) ;     lua_setfield(L, -2, "firstWeekday") ;
    lua_pushinteger(L, (lua_Integer)calendar.minimumDaysInFirstWeek) ; lua_setfield(L, -2, "minimumDaysInFirstWeek") ;
// we're already getting info about the locale, so...
//     if (calendar.locale) {
//         [skin pushNSObject:calendar.locale.localeIdentifier] ;         lua_setfield(L, -2, "locale") ;
//     }
// Returns the users timezone, so not pertinent to calendar info for the specified locale
//     if (calendar.timeZone) {
//         [skin pushNSObject:calendar.timeZone.name] ;                   lua_setfield(L, -2, "timeZone") ;
//     }
    [skin pushNSObject:calendar.eraSymbols] ;                          lua_setfield(L, -2, "eraSymbols") ;
    [skin pushNSObject:calendar.longEraSymbols] ;                      lua_setfield(L, -2, "longEraSymbols") ;
    [skin pushNSObject:calendar.monthSymbols] ;                        lua_setfield(L, -2, "monthSymbols") ;
    [skin pushNSObject:calendar.quarterSymbols] ;                      lua_setfield(L, -2, "quarterSymbols") ;
    [skin pushNSObject:calendar.shortMonthSymbols] ;                   lua_setfield(L, -2, "shortMonthSymbols") ;
    [skin pushNSObject:calendar.shortQuarterSymbols] ;                 lua_setfield(L, -2, "shortQuarterSymbols") ;
    [skin pushNSObject:calendar.shortStandaloneMonthSymbols] ;         lua_setfield(L, -2, "shortStandaloneMonthSymbols") ;
    [skin pushNSObject:calendar.shortStandaloneQuarterSymbols] ;       lua_setfield(L, -2, "shortStandaloneQuarterSymbols") ;
    [skin pushNSObject:calendar.shortStandaloneWeekdaySymbols] ;       lua_setfield(L, -2, "shortStandaloneWeekdaySymbols") ;
    [skin pushNSObject:calendar.shortWeekdaySymbols] ;                 lua_setfield(L, -2, "shortWeekdaySymbols") ;
    [skin pushNSObject:calendar.standaloneMonthSymbols] ;              lua_setfield(L, -2, "standaloneMonthSymbols") ;
    [skin pushNSObject:calendar.standaloneQuarterSymbols] ;            lua_setfield(L, -2, "standaloneQuarterSymbols") ;
    [skin pushNSObject:calendar.standaloneWeekdaySymbols] ;            lua_setfield(L, -2, "standaloneWeekdaySymbols") ;
    [skin pushNSObject:calendar.veryShortMonthSymbols] ;               lua_setfield(L, -2, "veryShortMonthSymbols") ;
    [skin pushNSObject:calendar.veryShortStandaloneMonthSymbols] ;     lua_setfield(L, -2, "veryShortStandaloneMonthSymbols") ;
    [skin pushNSObject:calendar.veryShortStandaloneWeekdaySymbols] ;   lua_setfield(L, -2, "veryShortStandaloneWeekdaySymbols") ;
    [skin pushNSObject:calendar.veryShortWeekdaySymbols] ;             lua_setfield(L, -2, "veryShortWeekdaySymbols") ;
    [skin pushNSObject:calendar.weekdaySymbols] ;                      lua_setfield(L, -2, "weekdaySymbols") ;
    [skin pushNSObject:calendar.AMSymbol] ;                            lua_setfield(L, -2, "AMSymbol") ;
    [skin pushNSObject:calendar.calendarIdentifier] ;                  lua_setfield(L, -2, "calendarIdentifier") ;
    [skin pushNSObject:calendar.PMSymbol] ;                            lua_setfield(L, -2, "PMSymbol") ;
    return 1 ;
}

static int pushNSCharacterSet(__unused lua_State *L, id obj) {
    LuaSkin *skin = [LuaSkin shared] ;
    NSCharacterSet *charSet = obj ;

// tweaked from http://stackoverflow.com/questions/26610931/list-of-characters-in-an-nscharacterset

    NSMutableArray *array = [NSMutableArray array];
    for (unsigned int plane = 0; plane <= 16; plane++) {
        if ([charSet hasMemberInPlane:(uint8_t)plane]) {
            UTF32Char c;
            for (c = plane << 16; c < (plane+1) << 16; c++) {
                if ([charSet longCharacterIsMember:c]) {
                    UTF32Char c1 = OSSwapHostToLittleInt32(c); // To make it byte-order safe
                    NSString *s = [[NSString alloc] initWithBytes:&c1 length:4 encoding:NSUTF32LittleEndianStringEncoding];
                    if (s) {
                        [array addObject:s];
                    } else {
                        [skin logDebug:[NSString stringWithFormat:@"%s:setCharacters skipping 0x%08x : nil string representation",
                                                                   USERDATA_TAG, c1]] ;
                    }
                }
            }
        }
    }
    [[LuaSkin shared] pushNSObject:array] ;
    return 1 ;
}

FOUNDATION_EXPORT NSLocaleKey const NSLocaleTemperatureUnit  __attribute__((weak_import));

static int pushNSLocale(lua_State *L, id obj) {
    LuaSkin *skin = [LuaSkin shared] ;
    NSLocale *locale = obj ;
    lua_newtable(L) ;
// thought this might be more reliable under 10.12, but it's the same, so stick with one code chunk unless/until
// a difference is found or the later is finally deprecated.
//     NSOperatingSystemVersion targetOS = { 10, 12, 0 } ;
//     if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:targetOS]) {
// #pragma clang diagnostic push
// #pragma clang diagnostic ignored "-Wpartial-availability"
//         [skin pushNSObject:locale.localeIdentifier] ;                                      lua_setfield(L, -2, "identifier") ;
//         [skin pushNSObject:locale.languageCode] ;                                          lua_setfield(L, -2, "languageCode") ;
//         [skin pushNSObject:locale.countryCode] ;                                           lua_setfield(L, -2, "countryCode") ;
//         [skin pushNSObject:locale.scriptCode] ;                                            lua_setfield(L, -2, "scriptCode") ;
//         [skin pushNSObject:locale.variantCode] ;                                           lua_setfield(L, -2, "variantCode") ;
//         pushNSCharacterSet(L, locale.exemplarCharacterSet) ;                               lua_setfield(L, -2, "exemplarCharacterSet") ;
//         pushNSCalendar(L, [NSCalendar calendarWithIdentifier:locale.calendarIdentifier]) ; lua_setfield(L, -2, "calendar") ;
//         [skin pushNSObject:locale.collationIdentifier] ;                                   lua_setfield(L, -2, "collationIdentifier") ;
//         lua_pushboolean(L, locale.usesMetricSystem) ;                                       lua_setfield(L, -2, "usesMetricSystem") ;
//         [skin pushNSObject:[locale objectForKey:NSLocaleMeasurementSystem]] ;              lua_setfield(L, -2, "measurementSystem") ;
//         [skin pushNSObject:locale.decimalSeparator] ;                                      lua_setfield(L, -2, "decimalSeparator") ;
//         [skin pushNSObject:locale.groupingSeparator] ;                                     lua_setfield(L, -2, "groupingSeparator") ;
//         [skin pushNSObject:locale.currencySymbol] ;                                        lua_setfield(L, -2, "currencySymbol") ;
//         [skin pushNSObject:locale.currencyCode] ;                                          lua_setfield(L, -2, "currencyCode") ;
//         [skin pushNSObject:locale.collatorIdentifier] ;                                    lua_setfield(L, -2, "collatorIdentifier") ;
//         [skin pushNSObject:locale.quotationBeginDelimiter] ;                               lua_setfield(L, -2, "quotationBeginDelimiterKey") ;
//         [skin pushNSObject:locale.quotationEndDelimiter] ;                                 lua_setfield(L, -2, "quotationEndDelimiterKey") ;
//         [skin pushNSObject:locale.alternateQuotationBeginDelimiter] ;                      lua_setfield(L, -2, "alternateQuotationBeginDelimiterKey") ;
//         [skin pushNSObject:locale.alternateQuotationEndDelimiter] ;                        lua_setfield(L, -2, "alternateQuotationEndDelimiterKey") ;
// #pragma clang diagnostic pop
//     } else {
        [skin pushNSObject:[locale objectForKey:NSLocaleIdentifier]] ;                          lua_setfield(L, -2, "identifier") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleLanguageCode]] ;                        lua_setfield(L, -2, "languageCode") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleCountryCode]] ;                         lua_setfield(L, -2, "countryCode") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleScriptCode]] ;                          lua_setfield(L, -2, "scriptCode") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleVariantCode]] ;                         lua_setfield(L, -2, "variantCode") ;
        pushNSCharacterSet(L, [locale objectForKey:NSLocaleExemplarCharacterSet]) ;             lua_setfield(L, -2, "exemplarCharacterSet") ;
        pushNSCalendar(L, [locale objectForKey:NSLocaleCalendar]) ;                             lua_setfield(L, -2, "calendar") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleCollationIdentifier]] ;                 lua_setfield(L, -2, "collationIdentifier") ;
        NSNumber *usesMetricSystem = [locale objectForKey:NSLocaleUsesMetricSystem] ;
        if (usesMetricSystem) {
            [skin pushNSObject:usesMetricSystem] ;
        } else {
            lua_pushboolean(L, NO) ;
        }
        lua_setfield(L, -2, "usesMetricSystem") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleMeasurementSystem]] ;                   lua_setfield(L, -2, "measurementSystem") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleDecimalSeparator]] ;                    lua_setfield(L, -2, "decimalSeparator") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleGroupingSeparator]] ;                   lua_setfield(L, -2, "groupingSeparator") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleCurrencySymbol]] ;                      lua_setfield(L, -2, "currencySymbol") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleCurrencyCode]] ;                        lua_setfield(L, -2, "currencyCode") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleCollatorIdentifier]] ;                  lua_setfield(L, -2, "collatorIdentifier") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleQuotationBeginDelimiterKey]] ;          lua_setfield(L, -2, "quotationBeginDelimiterKey") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleQuotationEndDelimiterKey]] ;            lua_setfield(L, -2, "quotationEndDelimiterKey") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleAlternateQuotationBeginDelimiterKey]] ; lua_setfield(L, -2, "alternateQuotationBeginDelimiterKey") ;
        [skin pushNSObject:[locale objectForKey:NSLocaleAlternateQuotationEndDelimiterKey]] ;   lua_setfield(L, -2, "alternateQuotationEndDelimiterKey") ;

        if (&NSLocaleTemperatureUnit != NULL) {
            [skin pushNSObject:[locale objectForKey:NSLocaleTemperatureUnit]] ;   lua_setfield(L, -2, "temperatureUnit") ;
        }
//     }
    return 1;
}

#pragma mark - Module Functions

/// hs.host.locale.availableLocales() -> table
/// Function
/// Returns an array table containing the identifiers for the locales available on the system.
///
/// Parameters:
///  * None
///
/// Returns:
///  * an array table of strings specifying the locale identifiers recognized by this system.
static int locale_availableLocaleIdentifiers(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TBREAK] ;
    NSArray *locales = [NSLocale availableLocaleIdentifiers] ;
    if (locales) {
        [skin pushNSObject:locales] ;
    } else {
        [skin logWarn:[NSString stringWithFormat:@"%s.availableLocales - returned nil; this should not happen -- notify developers", USERDATA_TAG]] ;
        lua_newtable(L) ;
    }
    return 1 ;
}

/// hs.host.locale.localeInformation([identifier]) -> table
/// Function
/// Returns a table containing information about the current or specified locale.
///
/// Parameters:
///  * `identifier` - an optional string, specifying the locale to display information about.  If you do not specify an identifier, information about eh user's currently selected locale is returned.
///
/// Returns:
///  * a table containing one or more of the following key-value pairs:
///    * `alternateQuotationBeginDelimiterKey` - A string containing the alternating begin quotation symbol associated with the locale. In some locales, when quotations are nested, the quotation characters alternate.
///    * `alternateQuotationEndDelimiterKey`   - A string containing the alternate end quotation symbol associated with the locale. In some locales, when quotations are nested, the quotation characters alternate.
///    * `calendar`                            - A table containing key-value pairs describing for calendar associated with the locale. The table will contain one or more of the following pairs:
///      * `AMSymbol`                          - The AM symbol for time in the locale's calendar.
///      * `calendarIdentifier`                - A string representing the calendar identity.
///      * `eraSymbols`                        - An array table of strings specifying the names of the eras as recognized in the locale's calendar.
///      * `firstWeekday`                      - The index in `weekdaySymbols` of the first weekday in the locale's calendar.
///      * `longEraSymbols`                    - An array table of strings specifying long names of the eras as recognized in the locale's calendar.
///      * `minimumDaysInFirstWeek`            - The minimum number of days, an integer value, in the first week in the locale's calendar.
///      * `monthSymbols`                      - An array table of strings for the months of the year in the locale's calendar.
///      * `PMSymbol`                          - The PM symbol for time in the locale's calendar.
///      * `quarterSymbols`                    - An array table of strings for the quarters of the year in the locale's calendar.
///      * `shortMonthSymbols`                 - An array table of short strings for the months of the year in the locale's calendar.
///      * `shortQuarterSymbols`               - An array table of short strings for the quarters of the year in the locale's calendar.
///      * `shortStandaloneMonthSymbols`       - An array table of short standalone strings for the months of the year in the locale's calendar.
///      * `shortStandaloneQuarterSymbols`     - An array table of short standalone strings for the quarters of the year in the locale's calendar.
///      * `shortStandaloneWeekdaySymbols`     - An array table of short standalone strings for the days of the week in the locale's calendar.
///      * `shortWeekdaySymbols`               - An array table of short strings for the days of the week in the locale's calendar.
///      * `standaloneMonthSymbols`            - An array table of standalone strings for the months of the year in the locale's calendar.
///      * `standaloneQuarterSymbols`          - An array table of standalone strings for the quarters of the year in the locale's calendar.
///      * `standaloneWeekdaySymbols`          - An array table of standalone strings for the days of the week in the locale's calendar.
///      * `veryShortMonthSymbols`             - An array table of very short strings for the months of the year in the locale's calendar.
///      * `veryShortStandaloneMonthSymbols`   - An array table of very short standalone strings for the months of the year in the locale's calendar.
///      * `veryShortStandaloneWeekdaySymbols` - An array table of very short standalone strings for the days of the week in the locale's calendar.
///      * `veryShortWeekdaySymbols`           - An array table of very short strings for the days of the week in the locale's calendar.
///      * `weekdaySymbols`                    - An array table of strings for the days of the week in the locale's calendar.
///    * `collationIdentifier`                 - A string containing the collation associated with the locale.
///    * `collatorIdentifier`                  - A string containing the collation identifier for the locale.
///    * `countryCode`                         - A string containing the locale country code.
///    * `currencyCode`                        - A string containing the currency code associated with the locale.
///    * `currencySymbol`                      - A string containing the currency symbol associated with the locale.
///    * `decimalSeparator`                    - A string containing the decimal separator associated with the locale.
///    * `exemplarCharacterSet`                - An array table of strings which make up the exemplar character set for the locale.
///    * `groupingSeparator`                   - A string containing the numeric grouping separator associated with the locale.
///    * `identifier`                          - A string containing the locale identifier.
///    * `languageCode`                        - A string containing the locale language code.
///    * `measurementSystem`                   - A string containing the measurement system associated with the locale.
///    * `quotationBeginDelimiterKey`          - A string containing the begin quotation symbol associated with the locale.
///    * `quotationEndDelimiterKey`            - A string containing the end quotation symbol associated with the locale.
///    * `scriptCode`                          - A string containing the locale script code.
///    * `temperatureUnit`                     - A string containing the preferred measurement system for temperature.
///    * `usesMetricSystem`                    - A boolean specifying whether or not the locale uses the metric system.
///    * `variantCode`                         - A string containing the locale variant code.
static int locale_localeInformation(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TSTRING | LS_TOPTIONAL, LS_TBREAK] ;
    NSLocale *theLocale ;
    if (lua_gettop(L) == 0) {
        theLocale = [NSLocale currentLocale] ;
    } else {
        NSString *localeName = [skin toNSObjectAtIndex:1] ;
        theLocale = [NSLocale localeWithLocaleIdentifier:localeName] ;
    }
    if (theLocale) {
        pushNSLocale(L, theLocale) ;
    } else {
        return luaL_error(L, "unrecognized locale") ;
    }
    return 1 ;
}

static int locale_registerCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin shared] ;
    [skin checkArgs:LS_TFUNCTION, LS_TBREAK] ;
    callbackRef = [skin luaUnref:refTable ref:callbackRef] ; // should be unnecessary, but just in case
    lua_pushvalue(L, 1) ;
    callbackRef = [skin luaRef:refTable] ;
    return 0 ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int meta_gc(lua_State* __unused L) {
    LuaSkin *skin = [LuaSkin shared] ;
    callbackRef = [skin luaUnref:refTable ref:callbackRef] ;
    [observerOfChanges stop] ;
    observerOfChanges = nil ;
    return 0 ;
}

// Functions for returned object when module loads
static luaL_Reg moduleLib[] = {
    {"availableLocales",  locale_availableLocaleIdentifiers},
    {"localeInformation", locale_localeInformation},
    {"_registerCallback", locale_registerCallback},
    {NULL, NULL}
};

// Metatable for module, if needed
static const luaL_Reg module_metaLib[] = {
    {"__gc", meta_gc},
    {NULL,   NULL}
};

int luaopen_hs_host_locale_internal(__unused lua_State* L) {
    LuaSkin *skin = [LuaSkin shared] ;
    refTable = [skin registerLibrary:moduleLib metaFunctions:module_metaLib] ;

    observerOfChanges = [[HSLocaleChangeObserver alloc] init] ;
    [observerOfChanges start] ;
    return 1;
}
