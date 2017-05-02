@import Foundation ;
@import CoreFoundation ;
@import Darwin.sysexits ;

#define DEBUG

static const NSString *_colorReset = @"\033[0m" ;

@interface HSClient : NSObject
@property CFMessagePortRef localPort ;
@property CFMessagePortRef remotePort ;
@property NSString         *colorBanner ;
@property NSString         *colorInput ;
@property NSString         *colorOutput ;
@property NSString         *colorError ;
@property NSString         *localName ;

@property BOOL             useColors ;

@property BOOL             shouldExit ;
@property int              exitCode ;
@end

static CFDataRef localPortCallback(__unused CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {
    HSClient  *self   = (__bridge HSClient *)info ;

    CFIndex maxSize = CFDataGetLength(data) ;
    char  *responseCString = malloc((size_t)maxSize) ;

    CFDataGetBytes(data, CFRangeMake(0, maxSize), (UInt8 *)responseCString );

    BOOL isStdOut = (msgid < 0) ? NO : YES ;

    if (self.useColors) {
        fprintf((isStdOut ? stdout : stderr), "%s", (isStdOut ? self.colorOutput.UTF8String : self.colorError.UTF8String)) ;
    }
    fwrite(responseCString, 1, (size_t)maxSize, (isStdOut ? stdout : stderr));
    if (self.useColors) {
        fprintf((isStdOut ? stdout : stderr), "%s", _colorReset.UTF8String) ;
    }
    fprintf((isStdOut ? stdout : stderr), "\n") ;

    free(responseCString) ;

    return CFStringCreateExternalRepresentation(NULL, CFSTR("check"), kCFStringEncodingUTF8, 0); ;
}

@implementation HSClient

- (instancetype)initWithRemote:(NSString *)remoteName inLegacyMode:(BOOL)legacyMode inColor:(BOOL)inColor {
    self = [super init] ;
    if (self) {
        _remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, (__bridge CFStringRef)remoteName) ;
        if (!_remotePort) {
            fprintf(stderr, "error: can't access Hammerspoon message port %s; is it running with the ipc2 module loaded?\n", remoteName.UTF8String);
            exit(EX_UNAVAILABLE) ;
        }

        if (legacyMode) {
            _localName = @"legacyMode" ;
            _localPort = NULL ;
        } else {
            _localName = [[NSUUID UUID] UUIDString] ;

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
                exit(EX_UNAVAILABLE) ;
            }

            CFRunLoopSourceRef runLoop = CFMessagePortCreateRunLoopSource(NULL, _localPort, 0) ;
            if (runLoop) {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoop, kCFRunLoopCommonModes);
                CFRelease(runLoop) ;
            } else {
                if (_localPort)  CFRelease(_localPort) ;
                if (_remotePort) CFRelease(_remotePort) ;
                _localPort  = NULL ;
                _remotePort = NULL ;
                fprintf(stderr, "unable to create runloop source for local port\n");
                exit(EX_UNAVAILABLE) ;
            }

            // register _localName with Hammerspoon so it can print to us

        }
        [self updateColorStrings] ;
        _useColors   = inColor ;

        _shouldExit = NO ;
        _exitCode   = EX_OK ;
    }
    return self ;
}

- (void)updateColorStrings {
    CFStringRef initial = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_initial"), CFSTR("org.hammerspoon.Hammerspoon")) ;
    CFStringRef input   = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_input"),   CFSTR("org.hammerspoon.Hammerspoon")) ;
    CFStringRef output  = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_output"),  CFSTR("org.hammerspoon.Hammerspoon")) ;
    CFStringRef error   = CFPreferencesCopyAppValue(CFSTR("ipc2.cli.color_error"),   CFSTR("org.hammerspoon.Hammerspoon")) ;
    _colorBanner = initial ? (__bridge_transfer NSString *)initial : @"\033[35m" ;
    _colorInput  = input   ? (__bridge_transfer NSString *)input   : @"\033[33m" ;
    _colorOutput = output  ? (__bridge_transfer NSString *)output  : @"\033[36m" ;
    _colorError  = error   ? (__bridge_transfer NSString *)error   : @"\033[31m" ;
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
        BOOL           isRaw       = NO ;
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
            } else if ([args[idx] isEqualToString:@"-r"]) {
                isRaw = YES ;
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
        fprintf(stderr, "DEBUG\tisRaw:       %s\n", (isRaw       ? "Yes" : "No")) ;
        fprintf(stderr, "DEBUG\tlegacyMode:  %s\n", (legacyMode  ? "Yes" : "No")) ;
        fprintf(stderr, "DEBUG\tportName:    %s\n", portName.UTF8String) ;
        fprintf(stderr, "DEBUG\ttimeout:     %f\n", timeout) ;
        fprintf(stderr, "DEBUG\texplicit commands:\n") ;
        for (NSUInteger i = 0; i < preRun.count ; i++) {
            fprintf(stderr, "DEBUG\t%2lu. %s\n", i + 1, preRun[i].UTF8String) ;
        }
#endif

        NSRunLoop   *runLoop = [NSRunLoop currentRunLoop] ;
        HSClient    *core    = [[HSClient alloc] initWithRemote:portName
                                                   inLegacyMode:legacyMode
                                                        inColor:useColors] ;

#ifdef DEBUG
        fprintf(stderr, "DEBUG\tCLI local port %s\n", core.localName.UTF8String) ;
#endif

        while((!core.shouldExit) && ([runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])) ;

        exitCode = core.exitCode ;
    } ;
    return(exitCode);
}
