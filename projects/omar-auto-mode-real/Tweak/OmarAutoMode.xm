#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

@interface SBApplicationIcon : NSObject
@end

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

static NSString *OMAOMLastDetectedMode(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        if (style == UIUserInterfaceStyleUnspecified) {
            style = UITraitCollection.currentTraitCollection.userInterfaceStyle;
        }
        return style == UIUserInterfaceStyleDark ? @"dark" : @"light";
    }
    return @"light";
}

static NSArray<NSString *> *OMAOMThemeSearchRoots(void) {
    return @[
        OMAOMIconThemesPath(),
        @"/var/jb/Library/Themes",
        @"/Library/Themes",
    ];
}

static NSArray<NSString *> *OMAOMThemePathsFromRoot(NSString *root) {
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            [paths addObject:path];
        }
    }
    return paths;
}

static NSString *OMAOMFallbackThemePathForMode(NSString *mode) {
    NSMutableArray<NSString *> *allThemes = [NSMutableArray array];
    for (NSString *root in OMAOMThemeSearchRoots()) {
        [allThemes addObjectsFromArray:OMAOMThemePathsFromRoot(root)];
    }

    NSArray<NSString *> *preferredWords = [mode isEqualToString:@"dark"] ? @[@"dark", @"night", @"black"] : @[@"light", @"clear", @"white"];
    for (NSString *path in allThemes) {
        NSString *name = path.lastPathComponent.lowercaseString;
        if (OMAOMPNGFileCountAtPath(path) == 0) {
            continue;
        }
        for (NSString *word in preferredWords) {
            if ([name containsString:word]) {
                return path;
            }
        }
    }

    for (NSString *path in allThemes) {
        if (OMAOMPNGFileCountAtPath(path) > 0) {
            return path;
        }
    }
    return nil;
}

static NSString *OMAOMThemePathForMode(NSString *mode, NSString *themeKey) {
    NSString *selected = OMAOMStringPreference(themeKey, OMAOMDefaultPathForKey(themeKey));
    if (OMAOMPNGFileCountAtPath(selected) > 0) {
        OMAOMSetDiagnosticValue(@"ThemeSource", @"selected");
        return selected;
    }

    NSString *fallback = OMAOMFallbackThemePathForMode(mode);
    if (fallback.length) {
        OMAOMSetDiagnosticValue(@"ThemeSource", @"fallback");
        OMAOMSetDiagnosticValue(@"FallbackThemePath", fallback);
        return fallback;
    }

    OMAOMSetDiagnosticValue(@"ThemeSource", @"empty");
    return selected;
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

static void OMAOMApplyCurrentModeProbe(void) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        OMAOMDebugEvent(@"probe skipped: disabled");
        return;
    }

    OMAOMEnsureDirectories();
    OMAOMClearDiagnosticError();

    NSString *mode = OMAOMLastDetectedMode();
    NSString *themeKey = [mode isEqualToString:@"dark"] ? @"DarkIconTheme" : @"LightIconTheme";
    NSString *themePath = OMAOMThemePathForMode(mode, themeKey);

    OMAOMSetDiagnosticValue(@"LastApplyAt", OMAOMNowNumber());
    OMAOMSetDiagnosticValue(@"LastMode", mode);
    OMAOMSetDiagnosticValue(@"ThemeKey", themeKey);
    OMAOMSetDiagnosticValue(@"ThemePath", themePath);
    OMAOMSetDiagnosticValue(@"ThemePNGCount", @(OMAOMPNGFileCountAtPath(themePath)));
    OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"disabled in 1.8 icons-only");
    OMAOMSetDiagnosticValue(@"ProofWallpaperResult", @"disabled in 1.8 icons-only");
    OMAOMSetDiagnosticValue(@"WindowCount", @0);
    OMAOMSetDiagnosticValue(@"IconContainerCount", @0);

    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(OMAOMActiveIconsPath())));
        OMAOMDebugEvent(@"probe copied active theme");
    } else if ([NSFileManager.defaultManager fileExistsAtPath:themePath]) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(themePath)));
        OMAOMDebugEvent(@"probe using selected theme directly");
    } else {
        OMAOMDebugEvent(@"probe failed before active theme");
    }
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMDebugEvent(@"icons-only notification received");
    OMAOMApplyCurrentModeProbe();
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

    UIImage *image = [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
    if (!image) {
        OMAOMIconMissCount++;
        OMAOMSetDiagnosticValue(@"IconMisses", @(OMAOMIconMissCount));
        OMAOMSetDiagnosticValue(@"LastIconMiss", [NSString stringWithFormat:@"decode failed: %@", path]);
        return nil;
    }

    OMAOMIconHitCount++;
    OMAOMSetDiagnosticValue(@"IconHits", @(OMAOMIconHitCount));
    OMAOMSetDiagnosticValue(@"LastIconPath", path);
    return image;
}

static UIImage *OMAOMImageForIcon(id icon) {
    return OMAOMImageForBundleIdentifier(OMAOMBundleIdentifierForIcon(icon));
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

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            OMAOMEnsureDirectories();
            OMAOMSetDiagnosticValue(@"EngineLoaded", @"YES");
            OMAOMSetDiagnosticValue(@"LoadedAt", OMAOMNowNumber());
            OMAOMSetDiagnosticValue(@"HostBundle", NSBundle.mainBundle.bundleIdentifier ?: @"");
            OMAOMDebugEvent(@"1.8 icons-only engine loaded");
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMApplyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMPreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            OMAOMApplyCurrentModeProbe();

            [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(__unused NSTimer *timer) {
                OMAOMApplyCurrentModeProbe();
            }];
        });
    }
}
