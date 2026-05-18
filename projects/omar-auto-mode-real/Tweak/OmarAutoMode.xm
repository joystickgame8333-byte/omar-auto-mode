#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

@interface SBIconView : UIView
- (id)icon;
@end

static NSUInteger OMAOMIconViewProbeHitCount = 0;
static CFTimeInterval OMAOMLastIconViewProbeDiagnosticWrite = 0;

static NSNumber *OMAOMNowNumber(void) {
    return @([[NSDate date] timeIntervalSince1970]);
}

static void OMAOMDebugEvent(NSString *event) {
    OMAOMSetDiagnosticValue(@"LastEvent", event ?: @"");
    OMAOMSetDiagnosticValue(@"LastEventAt", OMAOMNowNumber());
}

static NSUInteger OMAOMPNGFileCountAtPath(NSString *path) {
    if (!path.length) {
        return 0;
    }

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

static BOOL OMAOMThemeNameLooksWrongForMode(NSString *path, NSString *mode) {
    NSString *name = path.lastPathComponent.lowercaseString ?: @"";
    if ([mode isEqualToString:@"dark"]) {
        return [name containsString:@"light"] || [name containsString:@"white"] || [name containsString:@"clear"];
    }
    return [name containsString:@"dark"] || [name containsString:@"night"] || [name containsString:@"black"];
}

static NSString *OMAOMThemePathForMode(NSString *mode, NSString *themeKey) {
    NSString *selected = OMAOMStringPreference(themeKey, OMAOMDefaultPathForKey(themeKey));
    NSUInteger selectedCount = OMAOMPNGFileCountAtPath(selected);
    NSString *fallback = OMAOMFallbackThemePathForMode(mode);
    NSUInteger fallbackCount = OMAOMPNGFileCountAtPath(fallback);

    if (fallback.length) {
        OMAOMSetDiagnosticValue(@"FallbackThemePath", fallback);
    }

    if (selectedCount > 0 && (!fallback.length || fallbackCount == 0 || !OMAOMThemeNameLooksWrongForMode(selected, mode))) {
        OMAOMSetDiagnosticValue(@"ThemeSource", @"selected");
        return selected;
    }

    if (fallback.length && fallbackCount > 0) {
        OMAOMSetDiagnosticValue(@"ThemeSource", selectedCount > 0 ? @"fallback-mismatch" : @"fallback-empty-selected");
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

    for (NSString *item in ([fm contentsOfDirectoryAtPath:source error:nil] ?: @[])) {
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

static id OMAOMPerformObjectSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }

    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id value = [object performSelector:selector];
#pragma clang diagnostic pop
        return value;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *OMAOMBundleIdentifierForObject(id object) {
    if ([object isKindOfClass:NSString.class] && [object length]) {
        return object;
    }

    NSArray<NSString *> *selectors = @[@"applicationBundleID", @"bundleIdentifier", @"displayIdentifier", @"leafIdentifier"];
    for (NSString *selectorName in selectors) {
        id value = OMAOMPerformObjectSelector(object, NSSelectorFromString(selectorName));
        if ([value isKindOfClass:NSString.class] && [value length]) {
            return value;
        }
    }
    return nil;
}

static NSString *OMAOMSubviewClassSummary(UIView *view) {
    if (!view) {
        return @"no view";
    }

    NSMutableArray<NSString *> *classes = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class) ?: @"Unknown";
        if (![classes containsObject:className]) {
            [classes addObject:className];
        }
        if (classes.count >= 8) {
            break;
        }
    }
    return classes.count ? [classes componentsJoinedByString:@","] : @"no subviews";
}

static void OMAOMRecordIconViewProbe(UIView *view, NSString *source) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        return;
    }

    OMAOMIconViewProbeHitCount++;

    CFTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (OMAOMIconViewProbeHitCount > 12 && now - OMAOMLastIconViewProbeDiagnosticWrite < 2.0) {
        return;
    }
    OMAOMLastIconViewProbeDiagnosticWrite = now;

    id icon = OMAOMPerformObjectSelector(view, @selector(icon));
    NSString *bundleIdentifier = OMAOMBundleIdentifierForObject(icon);

    OMAOMSetDiagnosticValue(@"IconViewProbeHits", @(OMAOMIconViewProbeHitCount));
    OMAOMSetDiagnosticValue(@"IconContainerCount", @(OMAOMIconViewProbeHitCount));
    OMAOMSetDiagnosticValue(@"IconHits", @(OMAOMIconViewProbeHitCount));
    OMAOMSetDiagnosticValue(@"IconMisses", @0);
    OMAOMSetDiagnosticValue(@"LastBundle", bundleIdentifier ?: @"SBIconView icon without bundle id");
    OMAOMSetDiagnosticValue(@"LastIconPath", @"probe only; image not changed");
    OMAOMSetDiagnosticValue(@"LastIconMiss", @"none in 2.5 probe");
    OMAOMSetDiagnosticValue(@"LastIconView", [NSString stringWithFormat:@"%@ via %@", NSStringFromClass(view.class), source ?: @"unknown"]);
    OMAOMSetDiagnosticValue(@"LastIconImageViewsApplied", @0);
    OMAOMSetDiagnosticValue(@"IconViewSubviews", OMAOMSubviewClassSummary(view));
    OMAOMSetDiagnosticValue(@"StandaloneState", @"SBIconView hook reached; image replacement disabled");
}

static NSString *OMAOMSpringBoardClassProbe(void) {
    NSArray<NSString *> *classes = @[
        @"SBIcon",
        @"SBLeafIcon",
        @"SBApplicationIcon",
        @"SBIconView",
        @"SBIconImageView",
        @"SBHIconImageView",
        @"SBIconImageCache",
        @"SBIconImageInfo",
        @"SBIconModel",
        @"SBApplication",
        @"ISIcon",
        @"ISIconImageDescriptor",
    ];

    NSArray<NSString *> *selectors = @[
        @"applicationBundleID",
        @"bundleIdentifier",
        @"displayIdentifier",
        @"leafIdentifier",
        @"icon",
        @"setIcon:",
        @"getIconImage:",
        @"getCachedIconImage:",
        @"getUnmaskedIconImage:",
        @"generateIconImage:",
        @"iconImage",
        @"_iconImage",
        @"image",
        @"setImage:",
        @"layoutSubviews",
        @"didMoveToWindow",
    ];

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSUInteger classHits = 0;
    for (NSString *className in classes) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            [lines addObject:[NSString stringWithFormat:@"%@: missing", className]];
            continue;
        }

        classHits++;
        NSMutableArray<NSString *> *methodHits = [NSMutableArray array];
        for (NSString *selectorName in selectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([cls instancesRespondToSelector:selector]) {
                [methodHits addObject:selectorName];
            }
        }
        [lines addObject:[NSString stringWithFormat:@"%@: %@", className, methodHits.count ? [methodHits componentsJoinedByString:@","] : @"class-only"]];
    }

    return [NSString stringWithFormat:@"classes %lu/%lu | %@", (unsigned long)classHits, (unsigned long)classes.count, [lines componentsJoinedByString:@" | "]];
}

static void OMAOMApplyCurrentModeProbe(void) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        OMAOMDebugEvent(@"standalone probe skipped: disabled");
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
    OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"disabled in 2.4 standalone probe");
    OMAOMSetDiagnosticValue(@"ProofWallpaperResult", @"disabled in 2.4 standalone probe");
    OMAOMSetDiagnosticValue(@"WindowCount", @0);
    OMAOMSetDiagnosticValue(@"LastIconPath", @"probe only; image not changed");
    OMAOMSetDiagnosticValue(@"LastIconMiss", @"none in 2.5 probe");
    OMAOMSetDiagnosticValue(@"StandaloneState", @"SBIconView probe installed; image replacement disabled");
    OMAOMSetDiagnosticValue(@"SpringBoardClassProbe", OMAOMSpringBoardClassProbe());

    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"LastSourceThemePath", themePath);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(OMAOMActiveIconsPath())));
        OMAOMDebugEvent(@"2.4 standalone copied active icons and probed classes");
    } else if ([NSFileManager.defaultManager fileExistsAtPath:themePath]) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"LastSourceThemePath", themePath);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(themePath)));
        OMAOMDebugEvent(@"2.4 standalone using selected theme directly");
    } else {
        OMAOMDebugEvent(@"2.4 standalone failed before active icons");
    }
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMDebugEvent(@"2.5 standalone icon-view probe notification received");
    OMAOMApplyCurrentModeProbe();
}

%hook SBIconView

- (void)setIcon:(id)icon {
    %orig;
    OMAOMRecordIconViewProbe((UIView *)self, @"setIcon:");
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) {
        OMAOMRecordIconViewProbe((UIView *)self, @"didMoveToWindow");
    }
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
            OMAOMSetDiagnosticValue(@"IconViewProbeHits", @0);
            OMAOMSetDiagnosticValue(@"IconContainerCount", @0);
            OMAOMSetDiagnosticValue(@"IconHits", @0);
            OMAOMSetDiagnosticValue(@"IconMisses", @0);
            OMAOMSetDiagnosticValue(@"LastIconView", @"waiting for SBIconView");
            OMAOMSetDiagnosticValue(@"IconViewSubviews", @"waiting");
            OMAOMDebugEvent(@"2.5 standalone icon-view probe engine loaded");
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMApplyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMPreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            OMAOMApplyCurrentModeProbe();

            [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(__unused NSTimer *timer) {
                OMAOMApplyCurrentModeProbe();
            }];
        });
    }
}
