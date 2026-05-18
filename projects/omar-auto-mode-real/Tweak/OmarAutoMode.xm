#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

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

static void OMAOMWriteMinimalInfoPlistIfMissing(NSString *themePath) {
    NSString *infoPath = [themePath stringByAppendingPathComponent:@"Info.plist"];
    if ([NSFileManager.defaultManager fileExistsAtPath:infoPath]) {
        return;
    }

    NSDictionary *info = @{
        @"Name": @"Omar Auto Mode Active",
        @"PackageName": @"Omar Auto Mode Active",
        @"Author": @"Omar",
    };
    [info writeToFile:infoPath atomically:YES];
}

static NSString *OMAOMSnowBoardLinkStatus(void) {
    NSString *target = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:OMAOMSnowBoardActiveThemeLinkPath() error:nil];
    if ([target isEqualToString:OMAOMSnowBoardActiveThemePath()]) {
        return @"linked";
    }

    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:OMAOMSnowBoardActiveThemeLinkPath() isDirectory:&isDirectory]) {
        return isDirectory ? @"occupied-by-folder" : @"occupied-by-file";
    }
    return @"missing";
}

static BOOL OMAOMActiveSnowBoardThemeNeedsRefresh(NSString *mode, NSString *sourcePath) {
    NSString *lastMode = OMAOMStringPreference(@"LastAppliedMode", @"");
    NSString *lastSource = OMAOMStringPreference(@"LastSourceThemePath", @"");
    NSUInteger sourceCount = OMAOMPNGFileCountAtPath(sourcePath);
    NSUInteger activeCount = OMAOMPNGFileCountAtPath(OMAOMSnowBoardActiveThemePath());
    if (![lastMode isEqualToString:mode] || ![lastSource isEqualToString:sourcePath]) {
        return YES;
    }
    if (sourceCount == 0 || activeCount != sourceCount) {
        return YES;
    }
    return NO;
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
    OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"disabled in 2.2 snowboard-bridge");
    OMAOMSetDiagnosticValue(@"ProofWallpaperResult", @"disabled in 2.2 snowboard-bridge");
    OMAOMSetDiagnosticValue(@"WindowCount", @0);
    OMAOMSetDiagnosticValue(@"IconContainerCount", @0);
    OMAOMSetDiagnosticValue(@"IconHits", @0);
    OMAOMSetDiagnosticValue(@"IconMisses", @0);
    OMAOMSetDiagnosticValue(@"LastBundle", @"handled by SnowBoard");
    OMAOMSetDiagnosticValue(@"LastIconPath", @"handled by SnowBoard");
    OMAOMSetDiagnosticValue(@"LastIconMiss", @"handled by SnowBoard");
    OMAOMSetDiagnosticValue(@"LastIconView", @"no SpringBoard icon hooks");
    OMAOMSetDiagnosticValue(@"LastIconImageViewsApplied", @0);
    OMAOMSetDiagnosticValue(@"SnowBoardActiveThemePath", OMAOMSnowBoardActiveThemePath());
    OMAOMSetDiagnosticValue(@"SnowBoardActiveThemeLinkPath", OMAOMSnowBoardActiveThemeLinkPath());
    OMAOMSetDiagnosticValue(@"SnowBoardLinkStatus", OMAOMSnowBoardLinkStatus());

    if (!OMAOMActiveSnowBoardThemeNeedsRefresh(mode, themePath)) {
        OMAOMSetDiagnosticValue(@"ActiveThemePath", OMAOMSnowBoardActiveThemePath());
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(OMAOMSnowBoardActiveThemePath())));
        OMAOMDebugEvent(@"2.2 SnowBoard active theme already current");
        return;
    }

    if (OMAOMCopyDirectory(themePath, OMAOMSnowBoardActiveThemePath())) {
        OMAOMWriteMinimalInfoPlistIfMissing(OMAOMSnowBoardActiveThemePath());
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"LastSourceThemePath", themePath);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", OMAOMSnowBoardActiveThemePath());
        OMAOMSetDiagnosticValue(@"ActiveThemePath", OMAOMSnowBoardActiveThemePath());
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(OMAOMSnowBoardActiveThemePath())));
        OMAOMDebugEvent(@"2.2 copied SnowBoard active theme");
    } else if ([NSFileManager.defaultManager fileExistsAtPath:themePath]) {
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"LastSourceThemePath", themePath);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(themePath)));
        OMAOMDebugEvent(@"2.2 SnowBoard active copy failed, using selected directly");
    } else {
        OMAOMDebugEvent(@"2.2 failed before active SnowBoard theme");
    }
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMDebugEvent(@"2.2 snowboard bridge notification received");
    OMAOMApplyCurrentModeProbe();
}

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
            OMAOMDebugEvent(@"2.2 snowboard bridge engine loaded");
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMApplyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMPreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            OMAOMApplyCurrentModeProbe();

            [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(__unused NSTimer *timer) {
                OMAOMApplyCurrentModeProbe();
            }];
        });
    }
}
