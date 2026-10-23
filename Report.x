// One-time diagnostic: finds what draws the "No Service" label on iOS 26 and copies a report
// to the clipboard. SpringBoard only. Remove this file once the label is hidden.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

extern int HMVGetterCalls, HMVSetterCalls, HMVStringViewCalls;
extern NSMutableArray<NSString *> *HMVHooked;

static NSMutableArray<NSString *> *gSightings;

static BOOL mentionsService(NSString *text) {
    return [text containsString:@"No Service"] || [text containsString:@"No SIM"];
}

static NSString *viewChain(id view) {
    NSMutableArray *chain = [NSMutableArray array];
    UIView *v = [view isKindOfClass:UIView.class] ? view : nil;
    for (int i = 0; v && i < 8; i++, v = v.superview) [chain addObject:NSStringFromClass(v.class)];
    return [chain componentsJoinedByString:@" < "];
}

static void recordSighting(NSString *how, id obj) {
    if (gSightings.count >= 6) return;
    NSArray *stack = [NSThread callStackSymbols];
    NSArray *top = [stack subarrayWithRange:NSMakeRange(1, MIN((NSUInteger)12, stack.count - 1))];
    [gSightings addObject:[NSString stringWithFormat:@"%@ on %@\nviews: %@\nstack:\n%@",
        how, NSStringFromClass([obj class]), viewChain(obj), [top componentsJoinedByString:@"\n"]]];
}

static NSString *methodsMatching(Class cls, NSArray<NSString *> *words) {
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
    return [found componentsJoinedByString:@", "];
}

static NSString *statusBarClasses(void) {
    NSArray *words = @[@"service", @"cellular", @"carrier", @"string", @"label", @"text"];
    NSMutableArray *lines = [NSMutableArray array];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        NSString *lower = name.lowercaseString;
        if (![lower containsString:@"statusbar"]) continue;
        BOOL match = NO;
        for (NSString *w in words) if ([lower containsString:w]) { match = YES; break; }
        if (!match) continue;
        [lines addObject:[NSString stringWithFormat:@"%@ : %@ [%@]", name,
            NSStringFromClass(class_getSuperclass(classes[i])),
            methodsMatching(classes[i], @[@"service", @"text", @"string", @"enabl"])]];
    }
    free(classes);
    return [lines componentsJoinedByString:@"\n"];
}

static void copyReport(void) {
    NSMutableArray *r = [NSMutableArray array];
    [r addObject:[NSString stringWithFormat:@"HideMyVPN report, iOS %@", UIDevice.currentDevice.systemVersion]];
    [r addObject:[NSString stringWithFormat:@"data hooks: %@", [HMVHooked componentsJoinedByString:@", "]]];
    [r addObject:[NSString stringWithFormat:@"getter calls %d, setter calls %d, string view calls %d",
        HMVGetterCalls, HMVSetterCalls, HMVStringViewCalls]];
    [r addObject:[NSString stringWithFormat:@"sightings (%lu):\n%@", (unsigned long)gSightings.count,
        [gSightings componentsJoinedByString:@"\n\n"]]];
    [r addObject:[@"classes:\n" stringByAppendingString:statusBarClasses()]];
    UIPasteboard.generalPasteboard.string = [r componentsJoinedByString:@"\n\n"];
}

%group Report
%hook UILabel
- (void)setText:(NSString *)text {
    if (mentionsService(text)) recordSighting(@"UILabel setText", self);
    %orig;
}
- (void)setAttributedText:(NSAttributedString *)text {
    if (mentionsService(text.string)) recordSighting(@"UILabel setAttributedText", self);
    %orig;
}
%end

%hook CATextLayer
- (void)setString:(id)string {
    NSString *s = [string isKindOfClass:NSAttributedString.class] ? [string string] : string;
    if ([s isKindOfClass:NSString.class] && mentionsService(s)) recordSighting(@"CATextLayer setString", self);
    %orig;
}
%end
%end

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    gSightings = [NSMutableArray array];
    %init(Report);
    // Copies after 20 s, then again at 60 s and 120 s so sightings from the lock screen
    // or Control Center are included.
    for (NSNumber *delay in @[@20, @60, @120]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay.longLongValue * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ copyReport(); });
    }
}
