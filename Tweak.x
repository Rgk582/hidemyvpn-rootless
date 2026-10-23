#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSMutableDictionary<NSString *, NSValue *> *gOrig;

// Returns a copy of a status bar entry with enabled = NO, so its item isn't drawn.
static id disabledEntry(id entry) {
    if (!entry) return nil;
    @try {
        id copy = [entry copy];
        [copy setValue:@NO forKey:@"enabled"];
        return copy;
    } @catch (NSException *e) {
        return entry;
    }
}

static IMP origFor(SEL sel) {
    return (IMP)[gOrig[NSStringFromSelector(sel)] pointerValue];
}

static id hookedGetter(id self, SEL _cmd) {
    id entry = ((id (*)(id, SEL))origFor(_cmd))(self, _cmd);
    return disabledEntry(entry);
}

static void hookedSetter(id self, SEL _cmd, id entry) {
    ((void (*)(id, SEL, id))origFor(_cmd))(self, _cmd, disabledEntry(entry));
}

static void hookMethod(Class cls, SEL sel, IMP replacement) {
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, replacement, &orig);
    gOrig[NSStringFromSelector(sel)] = [NSValue valueWithPointer:(void *)orig];
}

static BOOL shouldHide(NSString *getter) {
    NSString *g = getter.lowercaseString;
    if (![g hasSuffix:@"entry"]) return NO;
    return [g containsString:@"vpn"] || [g containsString:@"cellular"] || [g containsString:@"service"];
}

// Hooks every *Entry getter/setter on the status bar data class that relates to
// VPN, cellular or service, which covers the "No Service" carrier label.
static void hookStatusBarData(void) {
    Class cls = objc_getClass("_UIStatusBarData");
    if (!cls) return;
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

// Original HideMyVPN hook: SpringBoard's source of truth for the VPN status bar item.
%group Telephony
%hook SBTelephonyManager
- (BOOL)isUsingVPNConnection {
    return NO;
}
%end
%end

%ctor {
    gOrig = [NSMutableDictionary dictionary];
    Class telephony = objc_getClass("SBTelephonyManager");
    if (telephony && class_getInstanceMethod(telephony, @selector(isUsingVPNConnection))) {
        %init(Telephony);
    }
    hookStatusBarData();
}
