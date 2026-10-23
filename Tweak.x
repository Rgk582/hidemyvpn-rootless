#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Returns a copy of a status bar entry with enabled = NO, so its item isn't drawn.
static id disabledEntry(id entry) {
    if (!entry) return nil;
    id copy = [entry copy];
    @try {
        [copy setValue:@NO forKey:@"enabled"];
    } @catch (NSException *e) {
        return entry;
    }
    return copy;
}

// Original HideMyVPN hook: SpringBoard's source of truth for the VPN status bar item.
%group Telephony
%hook SBTelephonyManager
- (BOOL)isUsingVPNConnection {
    return NO;
}
%end
%end

// Status bar data level: hides the VPN icon and the cellular item ("No Service")
// wherever the status bar is drawn.
%group StatusBarData
%hook _UIStatusBarData
- (id)vpnEntry {
    id original = %orig;
    return disabledEntry(original);
}
- (void)setVpnEntry:(id)entry {
    id disabled = disabledEntry(entry);
    %orig(disabled);
}
- (id)cellularEntry {
    id original = %orig;
    return disabledEntry(original);
}
- (void)setCellularEntry:(id)entry {
    id disabled = disabledEntry(entry);
    %orig(disabled);
}
- (id)secondaryCellularEntry {
    id original = %orig;
    return disabledEntry(original);
}
- (void)setSecondaryCellularEntry:(id)entry {
    id disabled = disabledEntry(entry);
    %orig(disabled);
}
%end
%end

%ctor {
    Class telephony = objc_getClass("SBTelephonyManager");
    if (telephony && class_getInstanceMethod(telephony, @selector(isUsingVPNConnection))) {
        %init(Telephony);
    }
    Class data = objc_getClass("_UIStatusBarData");
    if (data && class_getInstanceMethod(data, @selector(vpnEntry))
             && class_getInstanceMethod(data, @selector(setVpnEntry:))
             && class_getInstanceMethod(data, @selector(cellularEntry))
             && class_getInstanceMethod(data, @selector(setCellularEntry:))
             && class_getInstanceMethod(data, @selector(secondaryCellularEntry))
             && class_getInstanceMethod(data, @selector(setSecondaryCellularEntry:))) {
        %init(StatusBarData);
    }
}
