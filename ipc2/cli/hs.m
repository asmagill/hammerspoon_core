// TODO:
// * set console mode from cmd line and include in registration
// * allow arbitrary binary from stdin (i.e. don't choke on null in string
// * allow read from file via -f: instead, if arg starts with ./, /, or ~ treat as file and stop parsing args
// * support #! /path/to/hs (if last arg is a file, assume -f?) is there another way to tell?
//   Document (man page, printUsage, HS docs)
//   Decide on legacy mode support... and legacy auto-detection?

@import Foundation ;
@import CoreFoundation ;
@import Darwin.sysexits ;
#include <editline/readline.h>

static NSString       *defaultPortName = @"hsCommandLine" ;
static CFTimeInterval defaultTimeout   = 4.0 ;

// #define DEBUG

#define MSGID_REGISTER   100
#define MSGID_UNREGISTER 200

#define MSGID_ERROR   -1
#define MSGID_OUTPUT   0
#define MSGID_RETURN   1
#define MSGID_CONSOLE  2

@interface HSClient : NSThread
@property CFMessagePortRef localPort ;
@property CFMessagePortRef remotePort ;
@property NSString         *remoteName ;
@property NSString         *localName ;
@property NSString         *console ;

@property CFTimeInterval   sendTimeout ;
@property CFTimeInterval   recvTimeout ;

@property NSString         *colorBanner ;
@property NSString         *colorInput ;
@property NSString         *colorOutput ;
@property NSString         *colorError ;
@property NSString         *colorReset ;
@property NSArray          *arguments ;

@property BOOL             useColors ;

@property int              exitCode ;
@end

static CFDataRef localPortCallback(__unused CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {
    HSClient  *self   = (__bridge HSClient *)info ;

    CFIndex maxSize = CFDataGetLength(data) ;
    char  *responseCString = malloc((size_t)maxSize) ;

    CFDataGetBytes(data, CFRangeMake(0, maxSize), (UInt8 *)responseCString );

    BOOL isStdOut = (msgid < 0) ? NO : YES ;
    NSString *outputColor ;
    switch(msgid) {
        case MSGID_OUTPUT:
        case MSGID_RETURN:  outputColor = self.colorOutput ; break ;
        case MSGID_CONSOLE: outputColor = self.colorBanner ; break ;
        case MSGID_ERROR:
        default:            outputColor = self.colorError ;
    }
    fprintf((isStdOut ? stdout : stderr), "%s", outputColor.UTF8String) ;
    fwrite(responseCString, 1, (size_t)maxSize, (isStdOut ? stdout : stderr));
    fprintf((isStdOut ? stdout : stderr), "%s", self.colorReset.UTF8String) ;
    fprintf((isStdOut ? stdout : stderr), "\n") ;

    // if the main thread is stuck waiting for readline to complete, the active display color
    // should be the input color; any other output will set it's color before showing text, so
    // this would end up being a noop
    if (msgid == MSGID_CONSOLE) printf("%s", self.colorInput.UTF8String) ;

    free(responseCString) ;

    return CFStringCreateExternalRepresentation(NULL, CFSTR("check"), kCFStringEncodingUTF8, 0); ;
}

static const char *portError(SInt32 code) {
    const char* errstr = "unknown error";
    switch (code) {
        case kCFMessagePortSendTimeout:        errstr = "send timeout" ; break ;
        case kCFMessagePortReceiveTimeout:     errstr = "receive timeout" ; break ;
        case kCFMessagePortIsInvalid:          errstr = "message port invalid" ; break ;
        case kCFMessagePortTransportError:     errstr = "error during transport" ; break ;
        case kCFMessagePortBecameInvalidError: errstr = "message port was invalidated" ; break ;
    }
    return errstr ;
}

@implementation HSClient

- (instancetype)initWithRemote:(NSString *)remoteName inLegacyMode:(BOOL)legacyMode inColor:(BOOL)inColor {
    self = [super init] ;
    if (self) {
        _remotePort  = NULL ;
        _localPort   = NULL ;
        _remoteName  = remoteName ;
        _localName   = legacyMode ? nil : [[NSUUID UUID] UUIDString] ;

        _useColors   = inColor ;
        [self updateColorStrings] ;

        _arguments   = nil ;
        _sendTimeout = 4.0 ;
        _recvTimeout = 4.0 ;
        _exitCode    = EX_TEMPFAIL ; // until the thread is actually ready
        _console     = @"none" ;
    }
    return self ;
}

- (void)dealloc {
    if (_localPort)  CFRelease(_localPort) ;
    if (_remotePort) CFRelease(_remotePort) ;
}

- (void)main {
    @autoreleasepool {
        _remotePort = CFMessagePortCreateRemote(NULL, (__bridge CFStringRef)_remoteName) ;
        if (!_remotePort) {
            fprintf(stderr, "error: can't access Hammerspoon message port %s; is it running with the ipc2 module loaded?\n", _remoteName.UTF8String);
            _exitCode = EX_UNAVAILABLE ;
            [self cancel] ;
            return ;
        }

        if (_localName) {
            CFMessagePortContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL } ;
            Boolean error = false ;
            _localPort = CFMessagePortCreateLocal(NULL, (__bridge CFStringRef)_localName, localPortCallback, &ctx, &error) ;

            if (error) {
                NSString *errorMsg = _localPort ? [NSString stringWithFormat:@"%@ port name already in use", _localName] : @"failed to create new local port" ;
                fprintf(stderr, "error: %s\n", errorMsg.UTF8String);
                _exitCode = EX_UNAVAILABLE ;
                [self cancel] ;
                return ;
            }

            CFRunLoopSourceRef runLoop = CFMessagePortCreateRunLoopSource(NULL, _localPort, 0) ;
            if (runLoop) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoop, kCFRunLoopCommonModes);
                CFRelease(runLoop) ;
            } else {
                fprintf(stderr, "unable to create runloop source for local port\n");
                _exitCode = EX_UNAVAILABLE ;
                [self cancel] ;
                return ;
            }
        }

        if ([self registerWithRemote]) {
            BOOL keepRunning = YES ;
            _exitCode = EX_OK ;
            while(keepRunning && ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])) {
                if (_exitCode != EX_OK)  {
                    keepRunning = NO ;
                } else {
                    keepRunning = ![self isCancelled] ;
                }
            }
        } else {
            _exitCode = EX_UNAVAILABLE ;
            [self cancel] ;
            return ;
        }
        [self unregisterWithRemote] ;
    };
}

- (void)poke:(__unused id)obj {
    // do nothing but allows an external performSelector:onThread: to break the runloop
}

- (void)updateColorStrings {
    if (_useColors) {
        CFStringRef initial = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_initial"), CFSTR("org.hammerspoon.Hammerspoon")) ;
        CFStringRef input   = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_input"),   CFSTR("org.hammerspoon.Hammerspoon")) ;
        CFStringRef output  = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_output"),  CFSTR("org.hammerspoon.Hammerspoon")) ;
        CFStringRef error   = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_error"),   CFSTR("org.hammerspoon.Hammerspoon")) ;
        _colorBanner = initial ? (__bridge_transfer NSString *)initial : @"\033[35m" ;
        _colorInput  = input   ? (__bridge_transfer NSString *)input   : @"\033[33m" ;
        _colorOutput = output  ? (__bridge_transfer NSString *)output  : @"\033[36m" ;
        _colorError  = error   ? (__bridge_transfer NSString *)error   : @"\033[31m" ;
        _colorReset = @"\033[0m" ;
    } else {
        _colorReset  = @"" ;
        _colorBanner = @"" ;
        _colorInput  = @"" ;
        _colorOutput = @"" ;
        _colorError  = @"" ;
    }
}

- (NSData *)sendToRemote:(id)data msgID:(SInt32)msgid wantResponse:(BOOL)wantResponse error:(NSError * __autoreleasing *)error {
    NSMutableData *dataToSend = [NSMutableData data] ;
    if (msgid < MSGID_REGISTER) {
        // prepend our UUID so the receiving callback knows which instance to communicate with
        UInt8 j= 0x00;
        NSData *prefix = [_localName dataUsingEncoding:NSUTF8StringEncoding] ;
        [dataToSend appendData:prefix] ;
        [dataToSend appendData:[NSData dataWithBytes:&j length:1]] ;
    }
    if (data) {
        NSData *actualMessage = [data isKindOfClass:[NSData class]] ? data : [[data description] dataUsingEncoding:NSUTF8StringEncoding] ;
        if (actualMessage) [dataToSend appendData:actualMessage] ;
    }

    CFDataRef returnedData;
    SInt32 code = CFMessagePortSendRequest(
                                              _remotePort,
                                              msgid,
                                              (__bridge CFDataRef)dataToSend,
                                              _sendTimeout,
                                              (wantResponse ? _recvTimeout : 0.0),
                                              (wantResponse ? kCFRunLoopDefaultMode : NULL),
                                              &returnedData
                                          ) ;

    if (code != kCFMessagePortSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:code userInfo:nil] ;
        } else {
            fprintf(stderr, "error sending to remote: %s\n", portError(code));
        }
        return nil ;
    }

    NSData *resultData = nil ;
    if (wantResponse) {
        resultData = returnedData ? (__bridge_transfer NSData *)returnedData : nil ;
    }
    return resultData ;
}

- (BOOL)registerWithRemote {
    if (_localPort) { // not needed for legacy mode
        NSString *registration = _localName ;
        if (_arguments) {
            NSError* error;
            NSData* data = [NSJSONSerialization dataWithJSONObject:_arguments options:(NSJSONWritingOptions)0 error:&error];
            if (!error && data) {
                NSString* str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                registration = [NSString stringWithFormat:@"%@:%@:%@", _localName, _console, str] ;
            } else {
                fprintf(stderr, "unable to serialize arguments for registration: %s\n", error.localizedDescription.UTF8String);
            }
        }

        NSError *error = nil ;
        [self sendToRemote:registration msgID:MSGID_REGISTER wantResponse:NO error:&error] ;
        if (error) {
            fprintf(stderr, "error registering CLI instance with Hammerspoon: %s\n", portError((SInt32)error.code));
            return NO ;
        }
    }
    return YES ;
}

- (BOOL)unregisterWithRemote {
    if (_localPort) { // not needed for legacy mode
        NSError *error = nil ;
        [self sendToRemote:_localName msgID:MSGID_UNREGISTER wantResponse:NO error:&error] ;
        if (error) {
            fprintf(stderr, "error unregistering CLI instance with Hammerspoon: %s\n", portError((SInt32)error.code));
            return NO ;
        }
    }
    return YES ;
}

- (BOOL)executeCommand:(id)command {
    NSError *error ;
    NSData *response = [self sendToRemote:command msgID:0 wantResponse:YES error:&error];
    if (error) {
        fprintf(stderr, "error communicating with Hammerspoon: %s\n", portError((SInt32)error.code));
        _exitCode = EX_UNAVAILABLE ;
        return NO ;
    } else {
        NSString *answer = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding] ;
        return [answer isEqualToString:@"+ok"] ;
    }
}

@end

static void printUsage(const char *cmd) {
    printf("\n") ;
    printf("usage: %s [arguments] [file]\n", cmd) ;
    printf("\n") ;
    printf("    -c cmd     Specifies a Hammerspoon command to execute. May be specified more than once and commands will be executed in the order they appear. Disables colorized output unless -N is present. Disables interactive mode unless -i is present. If -i is present or if stdin is a pipe, these commands will be executed first.\n") ;
    printf("    -C         Enable print mirroring from the Hammerspoon Console to this instance. Disables -P. Unlike modifying `_cli.console` within an instance, this setting will persist if the instance has to reconnect.\n") ;
    printf("    -h         Displays this help and exits.\n") ;
    printf("    -i         Enable interactive mode. Default unless -c argument is present. In interactive mode, if the connection to Hammerspoon becomes invalid, usually because Hammerspoon has been reloaded, this tool will attempt to reconnect when submitting the user input before exiting with an error.\n") ;
    printf("    -L         Force legacy mode.  Shouldn't be required unless you are using a custom remote port setup.\n") ;
    printf("    -m name    Specify the remote port to connect to. Defaults to %s.\n", defaultPortName.UTF8String) ;
    printf("    -n         Disable colorized output. Automatic if stdin is a pipe, output is redirected, or as specified below.\n") ;
    printf("    -N         Force colorized output even when it would normally not be enabled.\n") ;
    printf("    -P         Enable print mirroring from this instance to the Hammerspoon Console. Disables -C. Unlike modifying `_cli.console` within an instance, this setting will persist if the instance has to reconnect.\n") ;
    printf("    -s         Read stdin for the contents to execute and exit.  Included for backwards compatibility as this tool now detects when stdin is a pipe automatically. Disables colorized output unless -N is present. Disables interactive mode.\n") ;
    printf("    -t sec     Specifies the send and receive timeouts in seconds.  Defaults to %f seconds.\n", defaultTimeout) ;
    printf("    --         Ignore all arguments following, allowing custom arguments to be passed into the cli instance.\n") ;
    printf("    /path/file Specifies a file containing Hammerspoon code to load and execute. Must start with  ~, ./, or / and be a file readable by the user.  Disables colorized output unless -N is present.  Disables interactive mode unless -i is present. Like --, all arguments following are passed in unparsed.\n") ;
    printf("\n") ;
    printf("Within the instance, console behavior can also be modified by modifying the `_cli.console` variable.  Set this variable to true to enable print mirroring from the Hammerspoon Console to this instance. Set this variable to nil to enable print mirroring from this instance to the Hammerspoon Console (legacy behavior).  Set this variable to false (the default) to disable print mirroring in either direction. This change does not carry over if the instance has to reconnect to Hammerspoon because of a reload or lost connection.\n") ;
    printf("\n") ;
    printf("Within the instance, all arguments passed to the %s executable are available as strings in the `_cli._args` array.  If the -- argument or a file path is present, that argument and all arguments that follow will be available as strings in the `_cli.args` array; otherwise the `_cli.args` array will be a mirror of `_cli._args`.\n", cmd) ;
    printf("\n") ;
}

int main()
{
    int exitCode = 0 ;

    @autoreleasepool {

        BOOL           readStdIn   = (BOOL)!isatty(STDIN_FILENO) ;
        BOOL           readFile    = NO ;
        BOOL           interactive = !readStdIn ;
        BOOL           useColors   = interactive && (BOOL)isatty(STDOUT_FILENO) ;
        BOOL           legacyMode  = NO ;
        NSString       *portName   = defaultPortName ;
        NSString       *console    = @"none" ;
        NSString       *fileName   = nil ;

        CFTimeInterval timeout     = defaultTimeout ;

        NSMutableArray<NSString *> *preRun     = nil ;

        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments] ;
        NSUInteger idx   = 1 ; // skip command name

        BOOL seenColors      = NO ;
        BOOL seenInteractive = NO ;

        while(idx < args.count) {
            NSString *errorMsg = nil ;

            if ([args[idx] isEqualToString:@"-i"]) {
                readStdIn       = NO ;
                interactive     = YES ;
                seenInteractive = YES ;
// Not really necessary, except maybe for backwards compatibility?
            } else if ([args[idx] isEqualToString:@"-s"]) {
                interactive = NO ;
                readStdIn   = YES ;
                if (!seenColors) useColors = NO ;
            } else if ([args[idx] isEqualToString:@"-n"]) {
                useColors = NO ;
            } else if ([args[idx] isEqualToString:@"-N"]) {
                useColors  = YES ;
                seenColors = YES ;
            } else if ([args[idx] isEqualToString:@"-L"]) {
                legacyMode = YES ;
            } else if ([args[idx] isEqualToString:@"-C"]) {
                console = @"mirror" ;
            } else if ([args[idx] isEqualToString:@"-P"]) {
                console = @"legacy" ;
            } else if ([args[idx] isEqualToString:@"-m"]) {
                if ((idx + 1) < args.count) {
                    idx++ ;
                    portName = args[idx] ;
                } else {
                    errorMsg = @"option requires an argument" ;
                }
            } else if ([args[idx] isEqualToString:@"-c"]) {
                if (!preRun) preRun = [[NSMutableArray alloc] init] ;
                if ((idx + 1) < args.count) {
                    idx++ ;
                    preRun[preRun.count] = args[idx] ;
                    if (!seenColors)      useColors   = NO ;
                    if (!seenInteractive) interactive = NO ;
                } else {
                    errorMsg = @"option requires an argument" ;
                }
            } else if ([args[idx] isEqualToString:@"-t"]) {
                if ((idx + 1) < args.count) {
                    idx++ ;
                    timeout = [args[idx] doubleValue] ;
                } else {
                    errorMsg = @"option requires an argument" ;
                }
            } else if ([args[idx] isEqualToString:@"-h"] || [args[idx] isEqualToString:@"-?"]) {
                printUsage(args[0].UTF8String) ;
                exit(EX_OK) ;
            } else if ([args[idx] isEqualToString:@"--"]) {
                break ; // remaining arguments are to be passed in as is
            } else if ([args[idx] hasPrefix:@"~"] || [args[idx] hasPrefix:@"./"] || [args[idx] hasPrefix:@"/"]) {
                fileName = [args[idx] stringByExpandingTildeInPath] ;
                if (access(fileName.UTF8String, R_OK) == 0) {
                    readFile  = YES ;
                    readStdIn = NO ; // maybe capture and save as _cli.stdin?
                    if (!seenColors)      useColors   = NO ;
                    if (!seenInteractive) interactive = NO ;
                    break ; // remaining arguments are to be passed in as is
                } else {
                    errorMsg = [NSString stringWithFormat:@"%s", strerror(errno)] ;
                }
            } else {
                errorMsg = @"illegal option" ;
            }

            if (errorMsg) {
                fprintf(stderr, "%s: %s: %s\n", args[0].UTF8String, errorMsg.UTF8String, args[idx].UTF8String) ;
                exit(EX_USAGE) ;
            }
            idx++ ;
        }

#ifdef DEBUG
        fprintf(stderr, "DEBUG\treadStdIn:   %s\n", (readStdIn   ? "Yes" : "No")) ;
        fprintf(stderr, "DEBUG\tinteractive: %s\n", (interactive ? "Yes" : "No")) ;
        fprintf(stderr, "DEBUG\tuseColors:   %s\n", (useColors   ? "Yes" : "No")) ;
        fprintf(stderr, "DEBUG\tlegacyMode:  %s\n", (legacyMode  ? "Yes" : "No")) ;
        fprintf(stderr, "DEBUG\tportName:    %s\n", portName.UTF8String) ;
        fprintf(stderr, "DEBUG\ttimeout:     %f\n", timeout) ;
        fprintf(stderr, "DEBUG\texplicit commands:\n") ;
        for (NSUInteger i = 0; i < preRun.count ; i++) {
            fprintf(stderr, "DEBUG\t%2lu. %s\n", i + 1, preRun[i].UTF8String) ;
        }
#endif

        HSClient    *core    = [[HSClient alloc] initWithRemote:portName
                                                   inLegacyMode:legacyMode
                                                        inColor:useColors] ;
        // may split them up later...
        core.sendTimeout = timeout ;
        core.recvTimeout = timeout ;
        core.arguments   = args ;
        core.console     = console ;

#ifdef DEBUG
        fprintf(stderr, "DEBUG\tCLI local port %s\n", core.localName.UTF8String) ;
#endif

        [core start] ;

#ifdef DEBUG
        printf("DEBUG\tWaiting for background thread to start\n") ;
#endif
        while (core.exitCode == EX_TEMPFAIL) ;

        if (core.exitCode == EX_OK && preRun) {
            for (NSString *command in preRun) {
                BOOL status = [core executeCommand:command] ;
                if (!status) {
                    if (core.exitCode == EX_OK) core.exitCode = EX_DATAERR ;
                    break ;
                }
            }
        }

        if (core.exitCode == EX_OK && readStdIn) {
            NSMutableData *command = [[NSMutableData alloc] init] ;
            char buffer[BUFSIZ];
            size_t readLength ;
            while((readLength = fread(buffer, 1, BUFSIZ, stdin)) > 0) {
                [command appendBytes:buffer length:readLength] ;
            }

            if (ferror(stdin)) {
                perror("error reading from stdin:");
                core.exitCode = EX_NOINPUT ;
            } else {
                BOOL status = [core executeCommand:command] ;
                if (!status) {
                    if (core.exitCode == EX_OK) core.exitCode = EX_DATAERR ;
                }
            }
        }

        if (core.exitCode == EX_OK && readFile) {
            FILE *fp = fopen(fileName.UTF8String, "r") ;
            if (fp) {
                NSMutableData *file = [[NSMutableData alloc] init] ;
                char buffer[BUFSIZ];
                size_t readLength ;
                while((readLength = fread(buffer, 1, BUFSIZ, fp)) > 0) {
                    [file appendBytes:buffer length:readLength] ;
                }

                if (ferror(fp)) {
                    perror("error reading from file:");
                    core.exitCode = EX_NOINPUT ;
                } else {
                    char shebang[2] ;
                    [file getBytes:&shebang length:2] ;
                    if (shebang[0] == '#' && shebang[1] == '!') {
                        NSUInteger position = 1 ;
                        while ((position < file.length) && (shebang[0] != '\n') && (shebang[0] != '\r')) {
                            position++ ;
                            [file getBytes:&shebang range:NSMakeRange(position, 1)] ;
                        }
                        if (position < file.length) {
                            file = [[file subdataWithRange:NSMakeRange(position, file.length - position)] mutableCopy] ;
                        } // else give up and let it cause an error
                    }
                    BOOL status = [core executeCommand:file] ;
                    if (!status) {
                        if (core.exitCode == EX_OK) core.exitCode = EX_DATAERR ;
                    }
                }
                fclose(fp) ;
            } else {
                perror("error openning file:");
                core.exitCode = EX_NOINPUT ;
            }
        }

        if (core.exitCode == EX_OK && interactive) {
            printf("%sHammerspoon interactive prompt.%s\n", core.colorBanner.UTF8String, core.colorReset.UTF8String);
            while (core.exitCode == EX_OK) {
                printf("\n%s", core.colorInput.UTF8String);
                char* input = readline("> ");
                printf("%s", core.colorReset.UTF8String);
                if (!input) { // ctrl-d or other issue with readline
                    printf("\n") ;
                    break ;
                }

                add_history(input);

                if (!CFMessagePortIsValid(core.remotePort)) {
                    fprintf(stderr, "Message port has become invalid.  Attempting to re-establish.\n");
                    CFMessagePortRef newPort = CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)portName) ;
                    if (newPort) {
                        CFRelease(core.remotePort) ;
                        core.remotePort = newPort ;
                        [core registerWithRemote] ;
                    } else {
                        fprintf(stderr, "error: can't access Hammerspoon; is it running?\n");
                        core.exitCode = EX_UNAVAILABLE ;
                    }
                }

                if (core.exitCode == EX_OK) [core executeCommand:[NSString stringWithCString:input encoding:NSUTF8StringEncoding]] ;

                if (input) free(input) ;
            }
        }

        if (core.remotePort && !core.cancelled) {
            [core cancel] ;
            // cancel does not break the runloop, so poke it to wake it up
            [core performSelector:@selector(poke:) onThread:core withObject:nil waitUntilDone:YES] ;
        }
        exitCode = core.exitCode ;
        core = nil ;
    } ;
    return(exitCode);
}