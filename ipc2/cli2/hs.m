@import Foundation ;
@import CoreFoundation ;
@import Darwin.sysexits ;
#include <editline/readline.h>

#define DEBUG

#define MSGID_REGISTER   100
#define MSGID_UNREGISTER 200

@interface HSClient : NSThread
@property CFMessagePortRef localPort ;
@property CFMessagePortRef remotePort ;
@property NSString         *remoteName ;
@property NSString         *localName ;

@property CFTimeInterval   sendTimeout ;
@property CFTimeInterval   recvTimeout ;

@property NSString         *colorBanner ;
@property NSString         *colorInput ;
@property NSString         *colorOutput ;
@property NSString         *colorError ;
@property NSString         *colorReset ;


@property BOOL             useColors ;

@property int              exitCode ;
@end

static CFDataRef localPortCallback(__unused CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {
    HSClient  *self   = (__bridge HSClient *)info ;

    CFIndex maxSize = CFDataGetLength(data) ;
    char  *responseCString = malloc((size_t)maxSize) ;

    CFDataGetBytes(data, CFRangeMake(0, maxSize), (UInt8 *)responseCString );

    BOOL isStdOut = (msgid < 0) ? NO : YES ;

    fprintf((isStdOut ? stdout : stderr), "%s", (isStdOut ? self.colorOutput.UTF8String : self.colorError.UTF8String)) ;
    fwrite(responseCString, 1, (size_t)maxSize, (isStdOut ? stdout : stderr));
    fprintf((isStdOut ? stdout : stderr), "%s", self.colorReset.UTF8String) ;
    fprintf((isStdOut ? stdout : stderr), "\n") ;

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
        _sendTimeout = 2.0 ;
        _recvTimeout = 2.0 ;
        _exitCode   = EX_TEMPFAIL ; // until the thread is actually ready
    }
    return self ;
}

- (void)main {
    @autoreleasepool {
        _remotePort = CFMessagePortCreateRemote(NULL, (__bridge CFStringRef)_remoteName) ;
        if (!_remotePort) {
            fprintf(stderr, "error: can't access Hammerspoon message port %s; is it running with the ipc2 module loaded?\n", _remoteName.UTF8String);
            _exitCode = EX_UNAVAILABLE ;
            return ;
        }

        if (_localName) {
            CFMessagePortContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL } ;
            Boolean error = false ;
            _localPort = CFMessagePortCreateLocal(NULL, (__bridge CFStringRef)_localName, localPortCallback, &ctx, &error) ;

            if (error) {
                NSString *errorMsg = _localPort ? [NSString stringWithFormat:@"%@ port name already in use", _localName] : @"failed to create new local port" ;
                // pedantic, I know, but proper cleanup... maybe it will become a habit eventually
                if (_localPort)  CFRelease(_localPort) ;
                if (_remotePort) CFRelease(_remotePort) ;
                _localPort  = NULL ;
                _remotePort = NULL ;
                fprintf(stderr, "error: %s\n", errorMsg.UTF8String);
                _exitCode = EX_UNAVAILABLE ;
                return ;
            }

            CFRunLoopSourceRef runLoop = CFMessagePortCreateRunLoopSource(NULL, _localPort, 0) ;
            if (runLoop) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoop, kCFRunLoopCommonModes);
                CFRelease(runLoop) ;
            } else {
                if (_localPort)  CFRelease(_localPort) ;
                if (_remotePort) CFRelease(_remotePort) ;
                _localPort  = NULL ;
                _remotePort = NULL ;
                fprintf(stderr, "unable to create runloop source for local port\n");
                _exitCode = EX_UNAVAILABLE ;
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
    // prepend our UUID so the receiving callback knows which instance to communicate with
    NSMutableData *dataToSend = (msgid < MSGID_REGISTER) ?
                                [[[NSString stringWithFormat:@"%@:",_localName] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] :
                                [NSMutableData data] ;

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
        NSError *error = nil ;
        [self sendToRemote:_localName msgID:MSGID_REGISTER wantResponse:NO error:&error] ;
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

@end

static void printUsage(const char *cmd) {
    printf("usage: %s ... I'm working on it...\n", cmd) ;
}

int main()
{
    int exitCode = 0 ;

    @autoreleasepool {

        BOOL           readStdIn   = (BOOL)!isatty(fileno(stdin)) ;
        BOOL           interactive = !readStdIn ;
        BOOL           useColors   = (BOOL)isatty(fileno(stdout)) ;
        BOOL           legacyMode  = NO ;
        NSString       *portName   = @"hsCommandLine" ;
        CFTimeInterval timeout     = 2.0 ;

        NSMutableArray<NSString *> *preRun     = nil ;

        BOOL           hasSeenI = NO, hasSeenS = NO ;

        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments] ;
        NSUInteger idx   = 1 ; // skip command name

        while(idx < args.count) {
            NSString *errorMsg = nil ;

            if ([args[idx] isEqualToString:@"-i"]) {
                if (!hasSeenS) readStdIn = NO ; // ignore default switch if it's already been explicitly seen
                interactive = YES ;
                hasSeenI = YES ;
            } else if ([args[idx] isEqualToString:@"-s"]) {
                if (!hasSeenI) interactive = NO ; // ignore default switch if it's already been explicitly seen
                readStdIn = YES ;
                hasSeenS = YES ;
            } else if ([args[idx] isEqualToString:@"-n"]) {
                useColors = NO ;
            } else if ([args[idx] isEqualToString:@"-N"]) {
                useColors = YES ;
            } else if ([args[idx] isEqualToString:@"-L"]) {
                legacyMode = YES ;
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
                } else {
                    errorMsg = @"option requires an argument" ;
                }
                if (!hasSeenI) interactive = NO ; // ignore default switch if it's already been explicitly seen
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
            } else {
                errorMsg = @"illegal option" ;
            }

            if (errorMsg) {
                fprintf(stderr, "%s: %s -- %s\n", args[0].UTF8String, errorMsg.UTF8String, [args[idx] substringFromIndex:1].UTF8String) ;
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

#ifdef DEBUG
        fprintf(stderr, "DEBUG\tCLI local port %s\n", core.localName.UTF8String) ;
#endif

        [core start] ;

#ifdef DEBUG
        printf("Waiting for background thread to start\n") ;
#endif
        while (core.exitCode == EX_TEMPFAIL) ;

        while (core.exitCode == EX_OK) {
            printf("\n%s", core.colorInput.UTF8String);
            char* input = readline("> ");
            printf("%s", core.colorReset.UTF8String);
            if (!input) { // ctrl-d or other issue with readline
                printf("\n") ;
                [core cancel] ;
                [core performSelector:@selector(poke:) onThread:core withObject:nil waitUntilDone:YES] ;
                break ;
            }

            add_history(input);

            if (!CFMessagePortIsValid(core.remotePort)) {
                fprintf(stderr, "Message port has become invalid.  Attempting to re-establish.\n");
                core.remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)portName) ;
                if (!core.remotePort) {
                    fprintf(stderr, "error: can't access Hammerspoon; is it running?\n");
                    core.exitCode = EX_UNAVAILABLE ;
                }
            }
            if (core.exitCode == EX_OK) {
                NSError *error ;
                [core sendToRemote:[NSString stringWithFormat:@"%s", input] msgID:0 wantResponse:YES error:&error];
                if (error) {
                    fprintf(stderr, "error communicating with Hammerspoon: %s\n", portError((SInt32)error.code));
                    core.exitCode = EX_UNAVAILABLE ;
                }
            }

            if (input) free(input) ;
        }
        exitCode = core.exitCode ;
    } ;
    return(exitCode);
}
