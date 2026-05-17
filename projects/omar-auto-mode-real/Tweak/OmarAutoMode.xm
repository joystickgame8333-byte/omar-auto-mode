#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

@interface SBApplicationIcon : NSObject
@end

@interface SBIconImageView : UIView
@end

@interface SBIconView : UIView
@end

static void OMAOMRefreshAllIconViews(void);
static NSInteger OMAOMIconHitCount = 0;
static NSInteger OMAOMIconMissCount = 0;

static NSNumber *OMAOMNowNumber(void) {
    return @([[NSDate date] timeIntervalSince1970]);
}

static void OMAOMDebugEvent(NSString *event) {
    OMAOMSetDiagnosticValue(@"LastEvent", event ?: @"");
    OMAOMSetDiagnosticValue(@"LastEventAt", OMAOMNowNumber());
}

static NSUInteger OMAOMPNGFileCountAtPath(NSString *path) {
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return 0;
    }

    NSUInteger count = 0;
    NSDirectoryEnumerator<NSString *> *enumerator = [NSFileManager.defaultManager enumeratorAtPath:path];
    for (NSString *item in enumerator) {
        if ([item.pathExtension.lowercaseString isEqualToString:@"png"]) {
            count++;
        }
    }
    return count;
}

static NSArray<UIWindow *> *OMAOMApplicationWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window) {
                    [windows addObject:window];
                }
            }
        }
    }

    if (!windows.count) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray<UIWindow *> *legacyWindows = UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
        if (legacyWindows.count) {
            [windows addObjectsFromArray:legacyWindows];
        }
    }

    return windows;
}

static NSString *OMAOMLastDetectedMode(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
        for (UIWindow *window in OMAOMApplicationWindows()) {
            UIUserInterfaceStyle windowStyle = window.traitCollection.userInterfaceStyle;
            if (windowStyle == UIUserInterfaceStyleDark || windowStyle == UIUserInterfaceStyleLight) {
                style = windowStyle;
                break;
            }
        }
        if (style == UIUserInterfaceStyleUnspecified) {
            style = UITraitCollection.currentTraitCollection.userInterfaceStyle;
        }
        if (style == UIUserInterfaceStyleUnspecified) {
            style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        }
        return style == UIUserInterfaceStyleDark ? @"dark" : @"light";
    }
    return @"light";
}

static BOOL OMAOMCopyDirectory(NSString *source, NSString *destination) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:source isDirectory:&isDirectory] || !isDirectory) {
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Theme folder missing: %@", source ?: @""]);
        return NO;
    }

    NSString *tmp = [destination stringByAppendingString:@".tmp"];
    [fm removeItemAtPath:tmp error:nil];
    NSError *createError = nil;
    if (![fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:&createError]) {
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Active temp create failed: %@", createError.localizedDescription ?: @"unknown"]);
        return NO;
    }

    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:source error:nil] ?: @[];
    for (NSString *item in items) {
        NSString *from = [source stringByAppendingPathComponent:item];
        NSString *to = [tmp stringByAppendingPathComponent:item];
        NSError *copyError = nil;
        if (![fm copyItemAtPath:from toPath:to error:&copyError]) {
            OMAOMSetDiagnosticError([NSString stringWithFormat:@"Theme copy failed at %@: %@", item, copyError.localizedDescription ?: @"unknown"]);
            [fm removeItemAtPath:tmp error:nil];
            return NO;
        }
    }

    [fm removeItemAtPath:destination error:nil];
    NSError *moveError = nil;
    BOOL moved = [fm moveItemAtPath:tmp toPath:destination error:&moveError];
    if (!moved) {
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Active theme move failed: %@", moveError.localizedDescription ?: @"unknown"]);
    }
    return moved;
}

static BOOL OMAOMInvokeIntegerSelector(id target, SEL selector, NSInteger value) {
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature) {
        return NO;
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:target];
    [invocation setSelector:selector];
    [invocation setArgument:&value atIndex:2];
    [invocation invoke];
    return YES;
}

static BOOL OMAOMApplyWallpaperAtPath(NSString *path, NSInteger wallpaperMode) {
    OMAOMSetDiagnosticValue(@"LastWallpaperPath", path ?: @"");
    OMAOMSetDiagnosticValue(@"LastWallpaperMode", @(wallpaperMode));

    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"missing file");
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Wallpaper missing: %@", path ?: @""]);
        return NO;
    }

    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) {
        OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"image decode failed");
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Wallpaper image decode failed: %@", path ?: @""]);
        return NO;
    }

    @try {
        NSBundle *photoLibrary = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PhotoLibrary.framework"];
        [photoLibrary load];

        Class wallpaperClass = NSClassFromString(@"PLStaticWallpaperImageViewController") ?: NSClassFromString(@"SBSUIWallpaperPreviewViewController");
        if (!wallpaperClass) {
            OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"wallpaper class not found");
            OMAOMSetDiagnosticError(@"Wallpaper API class not found");
            return NO;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id allocated = [wallpaperClass alloc];
        id controller = nil;
        SEL initWithUIImage = NSSelectorFromString(@"initWithUIImage:");
        SEL initWithImage = NSSelectorFromString(@"initWithImage:");
        if ([allocated respondsToSelector:initWithUIImage]) {
            controller = [allocated performSelector:initWithUIImage withObject:image];
        } else if ([allocated respondsToSelector:initWithImage]) {
            controller = [allocated performSelector:initWithImage withObject:image];
        } else {
            controller = [allocated init];
            @try {
                [controller setValue:image forKey:@"image"];
            } @catch (__unused NSException *exception) {
            }
        }
        if (!controller) {
            OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"controller init failed");
            OMAOMSetDiagnosticError(@"Wallpaper controller init failed");
            return NO;
        }

        [controller setValue:@(wallpaperMode) forKey:@"wallpaperMode"];
        [controller setValue:@YES forKey:@"saveWallpaperData"];
        if ([controller respondsToSelector:@selector(setWallpaperForLocations:)]) {
            if (OMAOMInvokeIntegerSelector(controller, @selector(setWallpaperForLocations:), wallpaperMode)) {
                OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"called setWallpaperForLocations");
                return YES;
            }
        } else if ([controller respondsToSelector:@selector(_savePhoto)]) {
            [controller performSelector:@selector(_savePhoto)];
            OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"called _savePhoto");
            return YES;
        }
#pragma clang diagnostic pop
        OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"no supported save selector");
        OMAOMSetDiagnosticError(@"Wallpaper save selector not found");
    } @catch (NSException *exception) {
        OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"exception");
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Wallpaper exception: %@", exception.reason ?: @"unknown"]);
    }
    return NO;
}

static void OMAOMApplyProofLockWallpaperIfNeeded(void) {
    if (OMAOMBoolPreference(@"ProofLockWallpaperApplied", NO)) {
        return;
    }

    NSString *path = OMAOMProofLockWallpaperPath();
    OMAOMSetDiagnosticValue(@"ProofWallpaperPath", path);
    OMAOMDebugEvent(@"proof lock wallpaper requested");
    BOOL applied = OMAOMApplyWallpaperAtPath(path, 2);
    OMAOMSetDiagnosticValue(@"ProofWallpaperResult", applied ? @"called" : @"failed");
    OMAOMSetPreferenceSilently(@"ProofLockWallpaperApplied", @(applied));
}

static void OMAOMApplyMode(NSString *mode) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        OMAOMDebugEvent(@"apply skipped: disabled");
        return;
    }

    OMAOMClearDiagnosticError();
    OMAOMDebugEvent([NSString stringWithFormat:@"apply mode %@", mode ?: @""]);
    OMAOMSetDiagnosticValue(@"LastApplyAt", OMAOMNowNumber());
    OMAOMSetDiagnosticValue(@"LastMode", mode ?: @"");
    OMAOMEnsureDirectories();

    NSString *themeKey = [mode isEqualToString:@"dark"] ? @"DarkIconTheme" : @"LightIconTheme";
    NSString *themePath = OMAOMStringPreference(themeKey, OMAOMDefaultPathForKey(themeKey));
    OMAOMSetDiagnosticValue(@"ThemeKey", themeKey);
    OMAOMSetDiagnosticValue(@"ThemePath", themePath);
    OMAOMSetDiagnosticValue(@"ThemePNGCount", @(OMAOMPNGFileCountAtPath(themePath)));
    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(OMAOMActiveIconsPath())));
    } else if ([NSFileManager.defaultManager fileExistsAtPath:themePath]) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePath", themePath);
    }

    NSString *homeKey = [mode isEqualToString:@"dark"] ? @"DarkHomeWallpaper" : @"LightHomeWallpaper";
    NSString *lockKey = [mode isEqualToString:@"dark"] ? @"DarkLockWallpaper" : @"LightLockWallpaper";
    OMAOMApplyWallpaperAtPath(OMAOMStringPreference(homeKey, OMAOMDefaultPathForKey(homeKey)), 1);
    OMAOMApplyWallpaperAtPath(OMAOMStringPreference(lockKey, OMAOMDefaultPathForKey(lockKey)), 2);
    OMAOMRefreshAllIconViews();
}

static void OMAOMApplyCurrentMode(void) {
    OMAOMApplyMode(OMAOMLastDetectedMode());
}

static NSString *OMAOMBundleIdentifierForIcon(id icon) {
    NSArray<NSString *> *selectors = @[@"applicationBundleID", @"bundleIdentifier", @"displayIdentifier", @"leafIdentifier", @"nodeIdentifier"];
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![icon respondsToSelector:selector]) {
            continue;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id value = [icon performSelector:selector];
#pragma clang diagnostic pop
        if ([value isKindOfClass:NSString.class] && [value length]) {
            return value;
        }
    }

    NSArray<NSString *> *keys = @[@"applicationBundleID", @"bundleIdentifier", @"displayIdentifier", @"leafIdentifier", @"_applicationBundleID"];
    for (NSString *key in keys) {
        @try {
            id value = [icon valueForKey:key];
            if ([value isKindOfClass:NSString.class] && [value length]) {
                return value;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static UIImage *OMAOMImageForBundleIdentifier(NSString *bundleIdentifier) {
    if (!OMAOMBoolPreference(@"Enabled", YES) || !bundleIdentifier.length) {
        return nil;
    }

    OMAOMSetDiagnosticValue(@"LastBundle", bundleIdentifier);
    NSString *activeThemePath = OMAOMStringPreference(@"ActiveThemePath", OMAOMActiveIconsPath());
    NSString *path = OMAOMExistingIconPathForBundleIdentifier(bundleIdentifier, activeThemePath);
    if (!path) {
        path = OMAOMExistingIconPathForBundleIdentifier(bundleIdentifier, OMAOMActiveIconsPath());
    }
    if (!path) {
        OMAOMIconMissCount++;
        OMAOMSetDiagnosticValue(@"IconMisses", @(OMAOMIconMissCount));
        OMAOMSetDiagnosticValue(@"LastIconMiss", [NSString stringWithFormat:@"%@ in %@", bundleIdentifier, activeThemePath ?: @""]);
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        OMAOMIconMissCount++;
        OMAOMSetDiagnosticValue(@"IconMisses", @(OMAOMIconMissCount));
        OMAOMSetDiagnosticValue(@"LastIconMiss", [NSString stringWithFormat:@"empty image: %@", path]);
        return nil;
    }
    OMAOMIconHitCount++;
    OMAOMSetDiagnosticValue(@"IconHits", @(OMAOMIconHitCount));
    OMAOMSetDiagnosticValue(@"LastIconPath", path);
    return [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
}

static UIImage *OMAOMImageForIcon(id icon) {
    return OMAOMImageForBundleIdentifier(OMAOMBundleIdentifierForIcon(icon));
}

static id OMAOMIconFromView(UIView *view) {
    NSArray<NSString *> *keys = @[@"icon", @"_icon"];
    for (NSString *key in keys) {
        @try {
            id icon = [view valueForKey:key];
            if (icon) {
                return icon;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static void OMAOMApplyImageToImageViews(UIView *view, UIImage *image) {
    if (!view || !image) {
        return;
    }

    if ([view isKindOfClass:UIImageView.class]) {
        ((UIImageView *)view).image = image;
    }

    for (UIView *subview in view.subviews) {
        OMAOMApplyImageToImageViews(subview, image);
    }
}

static void OMAOMRefreshIconContainer(UIView *view) {
    id icon = OMAOMIconFromView(view);
    UIImage *image = OMAOMImageForIcon(icon);
    if (image) {
        OMAOMApplyImageToImageViews(view, image);
    }
}

static void OMAOMRefreshIconViewsInView(UIView *view, NSInteger *containerCount) {
    if (!view) {
        return;
    }

    if ([view isKindOfClass:NSClassFromString(@"SBIconView")] || [view isKindOfClass:NSClassFromString(@"SBIconImageView")]) {
        if (containerCount) {
            (*containerCount)++;
        }
        OMAOMRefreshIconContainer(view);
    }

    for (UIView *subview in view.subviews) {
        OMAOMRefreshIconViewsInView(subview, containerCount);
    }
}

static void OMAOMRefreshAllIconViews(void) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger windowCount = 0;
        NSInteger iconContainerCount = 0;
        for (UIWindow *window in OMAOMApplicationWindows()) {
            windowCount++;
            OMAOMRefreshIconViewsInView(window, &iconContainerCount);
        }
        OMAOMSetDiagnosticValue(@"WindowCount", @(windowCount));
        OMAOMSetDiagnosticValue(@"IconContainerCount", @(iconContainerCount));
    });
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMDebugEvent(@"darwin notification received");
    OMAOMApplyCurrentMode();
    OMAOMApplyProofLockWallpaperIfNeeded();
}

%hook SBApplicationIcon

- (id)getIconImage:(int)arg1 {
    UIImage *image = OMAOMImageForIcon(self);
    return image ?: %orig;
}

- (id)getCachedIconImage:(int)arg1 {
    UIImage *image = OMAOMImageForIcon(self);
    return image ?: %orig;
}

- (id)getUnmaskedIconImage:(int)arg1 {
    UIImage *image = OMAOMImageForIcon(self);
    return image ?: %orig;
}

%end

%hook SBIconImageView

- (void)setIcon:(id)icon {
    %orig;
    UIImage *image = OMAOMImageForIcon(icon);
    if (image) {
        OMAOMApplyImageToImageViews(self, image);
    }
}

- (void)layoutSubviews {
    %orig;

    id icon = nil;
    @try {
        icon = [self valueForKey:@"_icon"];
    } @catch (__unused NSException *exception) {
    }

    UIImage *image = OMAOMImageForIcon(icon);
    if (image) {
        OMAOMApplyImageToImageViews(self, image);
    }
}

%end

%hook SBIconView

- (void)setIcon:(id)icon {
    %orig;
    UIImage *image = OMAOMImageForIcon(icon);
    if (image) {
        OMAOMApplyImageToImageViews(self, image);
    }
}

- (void)layoutSubviews {
    %orig;
    OMAOMRefreshIconContainer(self);
}

%end

%hook UIWindow

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    OMAOMApplyCurrentMode();
}

%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    OMAOMEnsureDirectories();
    OMAOMSetDiagnosticValue(@"EngineLoaded", @"YES");
    OMAOMSetDiagnosticValue(@"LoadedAt", OMAOMNowNumber());
    OMAOMSetDiagnosticValue(@"HostBundle", NSBundle.mainBundle.bundleIdentifier ?: @"");
    OMAOMDebugEvent(@"SpringBoard hook loaded");
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMApplyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMPreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(__unused NSTimer *timer) {
        NSString *mode = OMAOMLastDetectedMode();
        NSString *last = OMAOMStringPreference(@"LastAppliedMode", @"");
        if (![mode isEqualToString:last]) {
            OMAOMApplyMode(mode);
        } else {
            OMAOMRefreshAllIconViews();
        }
    }];

    OMAOMApplyCurrentMode();
    OMAOMApplyProofLockWallpaperIfNeeded();
}

%end
