hs.host.locale
==============

Retrieve information about the user's Language and Region settings.

Locales encapsulate information about linguistic, cultural, and technological conventions and standards. Examples of information encapsulated by a locale include the symbol used for the decimal separator in numbers and the way dates are formatted. Locales are typically used to provide, format, and interpret information about and according to the user’s customs and preferences.

### Usage
~~~lua
locale = require("hs.host.locale")
~~~

### Contents


##### Module Functions
* <a href="#availableLocales">locale.availableLocales() -> table</a>
* <a href="#localeInformation">locale.localeInformation([identifier]) -> table</a>
* <a href="#registerCallback">locale.registerCallback(function) -> uuidString</a>
* <a href="#unregisterCallback">locale.unregisterCallback(uuidString) -> boolean</a>

- - -

### Module Functions

<a name="availableLocales"></a>
~~~lua
locale.availableLocales() -> table
~~~
Returns an array table containing the identifiers for the locales available on the system.

Parameters:
 * None

Returns:
 * an array table of strings specifying the locale identifiers recognized by this system.

- - -

<a name="localeInformation"></a>
~~~lua
locale.localeInformation([identifier]) -> table
~~~
Returns a table containing information about the current or specified locale.

Parameters:
 * `identifier` - an optional string, specifying the locale to display information about.  If you do not specify an identifier, information about eh user's currently selected locale is returned.

Returns:
 * a table containing one or more of the following key-value pairs:
   * `alternateQuotationBeginDelimiterKey` - A string containing the alternating begin quotation symbol associated with the locale. In some locales, when quotations are nested, the quotation characters alternate.
   * `alternateQuotationEndDelimiterKey`   - A string containing the alternate end quotation symbol associated with the locale. In some locales, when quotations are nested, the quotation characters alternate.
   * `calendar`                            - A table containing key-value pairs describing for calendar associated with the locale. The table will contain one or more of the following pairs:
     * `AMSymbol`                          - The AM symbol for time in the locale's calendar.
     * `calendarIdentifier`                - A string representing the calendar identity.
     * `eraSymbols`                        - An array table of strings specifying the names of the eras as recognized in the locale's calendar.
     * `firstWeekday`                      - The index in `weekdaySymbols` of the first weekday in the locale's calendar.
     * `longEraSymbols`                    - An array table of strings specifying long names of the eras as recognized in the locale's calendar.
     * `minimumDaysInFirstWeek`            - The minimum number of days, an integer value, in the first week in the locale's calendar.
     * `monthSymbols`                      - An array table of strings for the months of the year in the locale's calendar.
     * `PMSymbol`                          - The PM symbol for time in the locale's calendar.
     * `quarterSymbols`                    - An array table of strings for the quarters of the year in the locale's calendar.
     * `shortMonthSymbols`                 - An array table of short strings for the months of the year in the locale's calendar.
     * `shortQuarterSymbols`               - An array table of short strings for the quarters of the year in the locale's calendar.
     * `shortStandaloneMonthSymbols`       - An array table of short standalone strings for the months of the year in the locale's calendar.
     * `shortStandaloneQuarterSymbols`     - An array table of short standalone strings for the quarters of the year in the locale's calendar.
     * `shortStandaloneWeekdaySymbols`     - An array table of short standalone strings for the days of the week in the locale's calendar.
     * `shortWeekdaySymbols`               - An array table of short strings for the days of the week in the locale's calendar.
     * `standaloneMonthSymbols`            - An array table of standalone strings for the months of the year in the locale's calendar.
     * `standaloneQuarterSymbols`          - An array table of standalone strings for the quarters of the year in the locale's calendar.
     * `standaloneWeekdaySymbols`          - An array table of standalone strings for the days of the week in the locale's calendar.
     * `veryShortMonthSymbols`             - An array table of very short strings for the months of the year in the locale's calendar.
     * `veryShortStandaloneMonthSymbols`   - An array table of very short standalone strings for the months of the year in the locale's calendar.
     * `veryShortStandaloneWeekdaySymbols` - An array table of very short standalone strings for the days of the week in the locale's calendar.
     * `veryShortWeekdaySymbols`           - An array table of very short strings for the days of the week in the locale's calendar.
     * `weekdaySymbols`                    - An array table of strings for the days of the week in the locale's calendar.
   * `collationIdentifier`                 - A string containing the collation associated with the locale.
   * `collatorIdentifier`                  - A string containing the collation identifier for the locale.
   * `countryCode`                         - A string containing the locale country code.
   * `currencyCode`                        - A string containing the currency code associated with the locale.
   * `currencySymbol`                      - A string containing the currency symbol associated with the locale.
   * `decimalSeparator`                    - A string containing the decimal separator associated with the locale.
   * `exemplarCharacterSet`                - An array table of strings which make up the exemplar character set for the locale.
   * `groupingSeparator`                   - A string containing the numeric grouping separator associated with the locale.
   * `identifier`                          - A string containing the locale identifier.
   * `languageCode`                        - A string containing the locale language code.
   * `measurementSystem`                   - A string containing the measurement system associated with the locale.
   * `quotationBeginDelimiterKey`          - A string containing the begin quotation symbol associated with the locale.
   * `quotationEndDelimiterKey`            - A string containing the end quotation symbol associated with the locale.
   * `scriptCode`                          - A string containing the locale script code.
   * `temperatureUnit`                     - A string containing the preferred measurement system for temperature.
   * `usesMetricSystem`                    - A boolean specifying whether or not the locale uses the metric system.
   * `variantCode`                         - A string containing the locale variant code.

- - -

<a name="registerCallback"></a>
~~~lua
locale.registerCallback(function) -> uuidString
~~~
Registers a function to be invoked when anything in the user's locale settings change

Parameters:
 * `fn` - the function to be invoked when a setting changes

Returns:
 * a uuid string which can be used to unregister a callback function when you no longer require notification of changes

Notes:
 * The callback function will not receive any arguments and should return none.  You can retrieve the new locale settings with [hs.host.locale.localeInformation](#localeInformation) and check its keys to determine if the change is of interest.

 * Any change made within the Language and Region settings panel will trigger this callback, even changes which are not reflected in the locale information provided by [hs.host.locale.localeInformation](#localeInformation).

- - -

<a name="unregisterCallback"></a>
~~~lua
locale.unregisterCallback(uuidString) -> boolean
~~~
Unregister a callback function when you no longer care about changes to the user's locale

Parameters:
 * `uuidString` - the uuidString returned by [hs.host.locale.registerCallback](#registerCallback) when you registered the callback function

Returns:
 * true if the callback was successfully unregistered or false if it was not, usually because the uuidString does not correspond to a current callback function.

- - -

### License

>     The MIT License (MIT)
>
> Copyright (c) 2017 Aaron Magill
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
>

