#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSMutableArray<NSString *> *gLog;
static NSMutableDictionary<NSString *, NSValue *> *gOrig;
static int gGetterCalls, gSetterCalls;
static NSString *gLastError;

// Returns a copy of a status bar entry with enabled = NO, so its item isn't drawn.
static id disabledEntry(id entry) {
    if (!entry) return nil;
    @try {
        id copy = [entry copy];
        [copy setValue:@NO forKey:@"enabled"];
        return copy;
    } @catch (NSException *e) {
        gLastError = [NSString stringWithFormat:@"%@: %@", NSStringFromClass([entry class]), e.reason];
        return entry;
    }
}

static IMP origFor(SEL sel) {
    return (IMP)[gOrig[NSStringFromSelector(sel)] pointerValue];
}

static id hookedGetter(id self, SEL _cmd) {
    gGetterCalls++;
    id entry = ((id (*)(id, SEL))origFor(_cmd))(self, _cmd);
    return disabledEntry(entry);
}

static void hookedSetter(id self, SEL _cmd, id entry) {
    gSetterCalls++;
    ((void (*)(id, SEL, id))origFor(_cmd))(self, _cmd, disabledEntry(entry));
}

static void hookMethod(Class cls, SEL sel, IMP replacement) {
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, replacement, &orig);
    gOrig[NSStringFromSelector(sel)] = [NSValue valueWithPointer:(void *)orig];
    [gLog addObject:[NSString stringWithFormat:@"hooked %@", NSStringFromSelector(sel)]];
}

static BOOL shouldHide(NSString *getter) {
    NSString *g = getter.lowercaseString;
    if (![g hasSuffix:@"entry"]) return NO;
    return [g containsString:@"vpn"] || [g containsString:@"cellular"] || [g containsString:@"service"];
}

// Hooks every *Entry getter/setter on the status bar data class that relates to VPN, cellular or service.
static void hookStatusBarData(void) {
    Class cls = objc_getClass("_UIStatusBarData");
    if (!cls) { [gLog addObject:@"_UIStatusBarData MISSING"]; return; }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *getters = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if (![name containsString:@":"] && shouldHide(name)) [getters addObject:name];
    }
    free(methods);
    for (NSString *getter in getters) {
        hookMethod(cls, NSSelectorFromString(getter), (IMP)hookedGetter);
        NSString *setter = [NSString stringWithFormat:@"set%@%@:",
            [[getter substringToIndex:1] uppercaseString], [getter substringFromIndex:1]];
        if (class_getInstanceMethod(cls, NSSelectorFromString(setter))) {
            hookMethod(cls, NSSelectorFromString(setter), (IMP)hookedSetter);
        }
    }
}

%group Telephony
%hook SBTelephonyManager
- (BOOL)isUsingVPNConnection {
    return NO;
}
%end
%end

// Lists a class's methods whose names contain any of the given words.
static NSString *methodsMatching(const char *className, NSArray<NSString *> *words) {
    Class cls = objc_getClass(className);
    if (!cls) return [NSString stringWithFormat:@"%s: MISSING", className];
    NSMutableArray *found = [NSMutableArray array];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        for (NSString *w in words) {
            if ([name.lowercaseString containsString:w]) { [found addObject:name]; break; }
        }
    }
    free(methods);
    return [NSString stringWithFormat:@"%s (super %@): %@", className,
        NSStringFromClass(class_getSuperclass(cls)), [found componentsJoinedByString:@", "]];
}

static NSString *classesMatching(NSArray<NSString *> *words) {
    NSMutableArray *found = [NSMutableArray array];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        NSString *lower = name.lowercaseString;
        if (![lower containsString:@"statusbar"]) continue;
        for (NSString *w in words) {
            if ([lower containsString:w]) { [found addObject:name]; break; }
        }
    }
    free(classes);
    return [found componentsJoinedByString:@", "];
}

static void copyReport(void) {
    NSArray *words = @[@"service", @"cellular", @"carrier", @"vpn", @"sim"];
    NSMutableArray *r = [NSMutableArray array];
    [r addObject:[NSString stringWithFormat:@"HideMyVPN report, iOS %@", UIDevice.currentDevice.systemVersion]];
    [r addObjectsFromArray:gLog];
    [r addObject:[NSString stringWithFormat:@"getter calls %d, setter calls %d, last error %@", gGetterCalls, gSetterCalls, gLastError]];
    [r addObject:methodsMatching("_UIStatusBarData", words)];
    [r addObject:methodsMatching("STStatusBarData", words)];
    [r addObject:methodsMatching("SBStatusBarStateAggregator", words)];
    [r addObject:methodsMatching("SBTelephonyManager", words)];
    [r addObject:methodsMatching("_UIStatusBarDataCellularEntry", @[@"enabl", @"string", @"service", @"type"])];
    [r addObject:[@"classes: " stringByAppendingString:classesMatching(words)]];
    UIPasteboard.generalPasteboard.string = [r componentsJoinedByString:@"\n\n"];
}

%ctor {
    gLog = [NSMutableArray array];
    gOrig = [NSMutableDictionary dictionary];

    Class telephony = objc_getClass("SBTelephonyManager");
    if (telephony && class_getInstanceMethod(telephony, @selector(isUsingVPNConnection))) {
        %init(Telephony);
        [gLog addObject:@"hooked isUsingVPNConnection"];
    }
    hookStatusBarData();

    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            copyReport();
        });
    }
}
