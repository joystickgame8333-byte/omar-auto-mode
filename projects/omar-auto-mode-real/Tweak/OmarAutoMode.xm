#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

@interface SBApplicationIcon : NSObject
@end

@interface SBIconImageView : UIView
@end

@interface SBIconView : UIView
@end

static void OMAOMRefreshAllIconViews(void);

static NSString *OMAOMLastDetectedMode(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
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
        return NO;
    }

    NSString *tmp = [destination stringByAppendingString:@".tmp"];
    [fm removeItemAtPath:tmp error:nil];
    [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:source error:nil] ?: @[];
    for (NSString *item in items) {
        NSString *from = [source stringByAppendingPathComponent:item];
        NSString *to = [tmp stringByAppendingPathComponent:item];
        [fm copyItemAtPath:from toPath:to error:nil];
    }

    [fm removeItemAtPath:destination error:nil];
    return [fm moveItemAtPath:tmp toPath:destination error:nil];
}

static void OMAOMApplyWallpaperAtPath(NSString *path, NSInteger wallpaperMode) {
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }

    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) {
        return;
    }

    @try {
        NSBundle *photoLibrary = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PhotoLibrary.framework"];
        [photoLibrary load];

        Class wallpaperClass = NSClassFromString(@"PLStaticWallpaperImageViewController") ?: NSClassFromString(@"SBSUIWallpaperPreviewViewController");
        if (!wallpaperClass) {
            return;
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
            return;
        }

        [controller setValue:@(wallpaperMode) forKey:@"wallpaperMode"];
        [controller setValue:@YES forKey:@"saveWallpaperData"];
        if ([controller respondsToSelector:@selector(setWallpaperForLocations:)]) {
            [controller performSelector:@selector(setWallpaperForLocations:) withObject:@(wallpaperMode)];
        } else if ([controller respondsToSelector:@selector(_savePhoto)]) {
            [controller performSelector:@selector(_savePhoto)];
        }
#pragma clang diagnostic pop
    } @catch (__unused NSException *exception) {
    }
}

static void OMAOMApplyMode(NSString *mode) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        return;
    }

    OMAOMEnsureDirectories();

    NSString *themeKey = [mode isEqualToString:@"dark"] ? @"DarkIconTheme" : @"LightIconTheme";
    NSString *themePath = OMAOMStringPreference(themeKey, OMAOMDefaultPathForKey(themeKey));
    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", OMAOMActiveIconsPath());
    } else if ([NSFileManager.defaultManager fileExistsAtPath:themePath]) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", themePath);
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

    NSString *activeThemePath = OMAOMStringPreference(@"ActiveThemePath", OMAOMActiveIconsPath());
    NSString *path = OMAOMExistingIconPathForBundleIdentifier(bundleIdentifier, activeThemePath);
    if (!path) {
        path = OMAOMExistingIconPathForBundleIdentifier(bundleIdentifier, OMAOMActiveIconsPath());
    }
    if (!path) {
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        return nil;
    }
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

static void OMAOMRefreshIconViewsInView(UIView *view) {
    if (!view) {
        return;
    }

    if ([view isKindOfClass:NSClassFromString(@"SBIconView")] || [view isKindOfClass:NSClassFromString(@"SBIconImageView")]) {
        OMAOMRefreshIconContainer(view);
    }

    for (UIView *subview in view.subviews) {
        OMAOMRefreshIconViewsInView(subview);
    }
}

static void OMAOMRefreshAllIconViews(void) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            OMAOMRefreshIconViewsInView(window);
        }
    });
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMApplyCurrentMode();
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
}

%end
