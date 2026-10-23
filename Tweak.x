#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// Original HideMyVPN hook: SpringBoard's source of truth for the VPN status bar item.
%group Telephony
%hook SBTelephonyManager
- (BOOL)isUsingVPNConnection {
    return NO;
}
%end
%end

static BOOL isServiceText(NSString *text) {
    return [text isEqualToString:@"No Service"] || [text isEqualToString:@"No SIM"];
}

// iOS 26 draws the lock screen and Control Center carrier label with STUIStatusBarStringView
// (older versions use _UIStatusBarStringView). Blank it when it says "No Service" or "No SIM".
static void (*origSetText)(id, SEL, NSString *);
static void hookedSetText(id self, SEL _cmd, NSString *text) {
    origSetText(self, _cmd, isServiceText(text) ? @"" : text);
}

static void (*origSetOriginalText)(id, SEL, NSString *);
static void hookedSetOriginalText(id self, SEL _cmd, NSString *text) {
    origSetOriginalText(self, _cmd, isServiceText(text) ? @"" : text);
}

static void (*origSetAlternateText)(id, SEL, NSString *);
static void hookedSetAlternateText(id self, SEL _cmd, NSString *text) {
    origSetAlternateText(self, _cmd, isServiceText(text) ? @"" : text);
}

%ctor {
    Class telephony = objc_getClass("SBTelephonyManager");
    if (telephony && class_getInstanceMethod(telephony, @selector(isUsingVPNConnection))) {
        %init(Telephony);
    }

    Class label = objc_getClass("STUIStatusBarStringView") ?: objc_getClass("_UIStatusBarStringView");
    if (!label) return;
    MSHookMessageEx(label, @selector(setText:), (IMP)hookedSetText, (IMP *)&origSetText);
    if (class_getInstanceMethod(label, @selector(setOriginalText:))) {
        MSHookMessageEx(label, @selector(setOriginalText:), (IMP)hookedSetOriginalText, (IMP *)&origSetOriginalText);
    }
    if (class_getInstanceMethod(label, @selector(setAlternateText:))) {
        MSHookMessageEx(label, @selector(setAlternateText:), (IMP)hookedSetAlternateText, (IMP *)&origSetAlternateText);
    }
}
