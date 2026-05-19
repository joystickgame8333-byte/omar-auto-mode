#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const OAIRoot = @"/var/jb/Library/OmarAutoIcons";
static BOOL OAIEnabled = YES;
static NSInteger OAIDayStartHour = 6;
static NSInteger OAINightStartHour = 18;
static NSInteger OAIRefreshInterval = 60;
static BOOL OAIIsNightMode = NO;

static BOOL OAIResponds(id obj, SEL sel) {
    return obj && [obj respondsToSelector:sel];
}

static id OAICall0(id obj, SEL sel) {
    if (!OAIResponds(obj, sel)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSString *OAIBundleIdentifierFromIcon(id icon) {
    if (!icon) return nil;

    SEL appSel = NSSelectorFromString(@"application");
    id app = OAICall0(icon, appSel);

    SEL bundleSel = NSSelectorFromString(@"bundleIdentifier");
    id bid = OAICall0(icon, bundleSel);
    if ([bid isKindOfClass:[NSString class]]) return bid;

    bid = OAICall0(app, bundleSel);
    if ([bid isKindOfClass:[NSString class]]) return bid;

    SEL leafSel = NSSelectorFromString(@"leafIdentifier");
    bid = OAICall0(icon, leafSel);
    if ([bid isKindOfClass:[NSString class]]) return bid;

    return nil;
}

static void OAILoadConfig(void) {
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:[OAIRoot stringByAppendingPathComponent:@"config.plist"]];
    if (![cfg isKindOfClass:[NSDictionary class]]) return;

    id enabled = cfg[@"Enabled"];
    if ([enabled respondsToSelector:@selector(boolValue)]) OAIEnabled = [enabled boolValue];

    id day = cfg[@"DayStartHour"];
    if ([day respondsToSelector:@selector(integerValue)]) OAIDayStartHour = [day integerValue];

    id night = cfg[@"NightStartHour"];
    if ([night respondsToSelector:@selector(integerValue)]) OAINightStartHour = [night integerValue];

    id interval = cfg[@"RefreshIntervalSeconds"];
    if ([interval respondsToSelector:@selector(integerValue)]) OAIRefreshInterval = MAX(15, [interval integerValue]);
}

static BOOL OAICalcNightMode(void) {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSCalendarUnitHour fromDate:[NSDate date]];
    NSInteger h = c.hour;

    if (OAIDayStartHour < OAINightStartHour) {
        return (h >= OAINightStartHour || h < OAIDayStartHour);
    } else {
        return !(h >= OAIDayStartHour || h < OAINightStartHour);
    }
}

static NSString *OAIIconPathForBundle(NSString *bundleID) {
    if (!OAIEnabled || bundleID.length == 0) return nil;

    NSString *mode = OAIIsNightMode ? @"Night" : @"Day";
    NSString *path = [NSString stringWithFormat:@"%@/%@/%@.png", OAIRoot, mode, bundleID];

    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    return nil;
}

static UIImage *OAICustomIconImage(NSString *bundleID) {
    NSString *path = OAIIconPathForBundle(bundleID);
    if (!path) return nil;

    UIImage *img = [UIImage imageWithContentsOfFile:path];
    return img;
}

static NSArray<UIWindow *> *OAIApplicationWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            [windows addObjectsFromArray:windowScene.windows ?: @[]];
        }
    }

    if (!windows.count) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:application.windows ?: @[]];
#pragma clang diagnostic pop
    }
    return windows;
}

static void OAIRefreshSpringBoardIcons(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *windows = OAIApplicationWindows();
        for (UIWindow *w in windows) {
            [w setNeedsLayout];
            [w layoutIfNeeded];
        }

        // Try common SpringBoard refresh paths without crashing on unknown iOS versions.
        Class SBIconController = objc_getClass("SBIconController");
        id controller = nil;
        if (SBIconController && [SBIconController respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            controller = ((id (*)(Class, SEL))objc_msgSend)(SBIconController, NSSelectorFromString(@"sharedInstance"));
        }

        NSArray *sels = @[
            @"_rebuildIconViewMap",
            @"relayout",
            @"_reloadIconViews",
            @"_updateVisibleIconViews"
        ];

        for (NSString *s in sels) {
            SEL sel = NSSelectorFromString(s);
            if (controller && [controller respondsToSelector:sel]) {
                ((void (*)(id, SEL))objc_msgSend)(controller, sel);
            }
        }
    });
}

static void OAICheckModeAndRefreshIfNeeded(void) {
    OAILoadConfig();
    BOOL newNight = OAICalcNightMode();
    if (newNight != OAIIsNightMode) {
        OAIIsNightMode = newNight;
        OAIRefreshSpringBoardIcons();
    }
}

static UIImage *OAIResizeImage(UIImage *image, CGSize size) {
    if (!image) return nil;
    if (size.width <= 0 || size.height <= 0) return image;
    UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resized ?: image;
}

%hook SBIconImageView

- (void)setIcon:(id)icon {
    %orig;
    objc_setAssociatedObject(self, @selector(setIcon:), icon, OBJC_ASSOCIATION_ASSIGN);
    [(UIView *)self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;

    id icon = objc_getAssociatedObject(self, @selector(setIcon:));
    if (!icon && [(id)self respondsToSelector:NSSelectorFromString(@"icon")]) {
        icon = OAICall0((id)self, NSSelectorFromString(@"icon"));
    }

    NSString *bundleID = OAIBundleIdentifierFromIcon(icon);
    UIImage *custom = OAICustomIconImage(bundleID);
    if (!custom) return;

    UIImageView *target = nil;

    // Search for the first UIImageView inside SBIconImageView.
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:(UIView *)self];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if ([v isKindOfClass:[UIImageView class]] && v != (UIView *)self) {
            target = (UIImageView *)v;
            break;
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }

    if (target) {
        target.image = OAIResizeImage(custom, target.bounds.size);
        target.contentMode = UIViewContentModeScaleAspectFit;
    }
}

%end

// Fallback: some iOS builds use SBIconView to build icon images.
%hook SBIconView

- (void)layoutSubviews {
    %orig;

    if (![(id)self respondsToSelector:NSSelectorFromString(@"icon")]) return;
    id icon = OAICall0((id)self, NSSelectorFromString(@"icon"));
    NSString *bundleID = OAIBundleIdentifierFromIcon(icon);
    UIImage *custom = OAICustomIconImage(bundleID);
    if (!custom) return;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:(UIView *)self];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if ([v isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)v;
            if (iv.bounds.size.width >= 40 && iv.bounds.size.height >= 40) {
                iv.image = OAIResizeImage(custom, iv.bounds.size);
                iv.contentMode = UIViewContentModeScaleAspectFit;
                break;
            }
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }
}

%end

%ctor {
    @autoreleasepool {
        OAILoadConfig();
        OAIIsNightMode = OAICalcNightMode();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OAIRefreshSpringBoardIcons();

            [NSTimer scheduledTimerWithTimeInterval:OAIRefreshInterval repeats:YES block:^(NSTimer *timer) {
                OAICheckModeAndRefreshIfNeeded();
            }];
        });
    }
}
