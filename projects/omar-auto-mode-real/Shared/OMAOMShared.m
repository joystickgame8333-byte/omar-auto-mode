#import "OMAOMShared.h"
#import <CoreFoundation/CoreFoundation.h>

NSString *const OMAOMPreferencesIdentifier = @"com.omaralasam.automode";
NSString *const OMAOMApplyNotification = @"com.omaralasam.automode/apply";
NSString *const OMAOMPreferencesChangedNotification = @"com.omaralasam.automode/preferences.changed";

NSString *OMAOMRootPath(void) {
    return @"/var/mobile/Library/OmarAutoMode";
}

NSString *OMAOMActiveIconsPath(void) {
    return [OMAOMRootPath() stringByAppendingPathComponent:@"ActiveIcons"];
}

NSString *OMAOMSnowBoardActiveThemePath(void) {
    return [OMAOMRootPath() stringByAppendingPathComponent:@"ActiveSnowBoard.theme"];
}

NSString *OMAOMSnowBoardActiveThemeLinkPath(void) {
    return @"/var/jb/Library/Themes/Omar Auto Mode Active.theme";
}

NSString *OMAOMIconThemesPath(void) {
    return [OMAOMRootPath() stringByAppendingPathComponent:@"IconThemes"];
}

NSString *OMAOMWallpapersPath(void) {
    return [OMAOMRootPath() stringByAppendingPathComponent:@"Wallpapers"];
}

NSString *OMAOMProofLockWallpaperPath(void) {
    return @"/var/jb/Library/Application Support/OmarAutoMode/ProofLock.png";
}

NSString *OMAOMDefaultPathForKey(NSString *key) {
    NSDictionary *defaults = @{
        @"LightIconTheme": [OMAOMIconThemesPath() stringByAppendingPathComponent:@"Light"],
        @"DarkIconTheme": [OMAOMIconThemesPath() stringByAppendingPathComponent:@"Dark"],
        @"LightHomeWallpaper": [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Light/Home.png"],
        @"LightLockWallpaper": [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Light/Lock.png"],
        @"DarkHomeWallpaper": [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Dark/Home.png"],
        @"DarkLockWallpaper": [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Dark/Lock.png"],
    };
    return defaults[key] ?: @"";
}

NSArray<NSString *> *OMAOMCandidateIconPathsForBundleIdentifier(NSString *bundleIdentifier, NSString *themePath) {
    if (!bundleIdentifier.length || !themePath.length) {
        return @[];
    }

    NSString *iconBundles = [themePath stringByAppendingPathComponent:@"IconBundles"];
    NSString *bundleFolder = [[themePath stringByAppendingPathComponent:@"Bundles"] stringByAppendingPathComponent:bundleIdentifier];

    return @[
        [iconBundles stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-large.png", bundleIdentifier]],
        [iconBundles stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@3x.png", bundleIdentifier]],
        [iconBundles stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.png", bundleIdentifier]],
        [iconBundles stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", bundleIdentifier]],
        [bundleFolder stringByAppendingPathComponent:@"AppIcon60x60@3x.png"],
        [bundleFolder stringByAppendingPathComponent:@"AppIcon60x60@2x.png"],
        [bundleFolder stringByAppendingPathComponent:@"AppIcon@3x.png"],
        [bundleFolder stringByAppendingPathComponent:@"AppIcon@2x.png"],
        [bundleFolder stringByAppendingPathComponent:@"AppIcon.png"],
        [bundleFolder stringByAppendingPathComponent:@"Icon@3x.png"],
        [bundleFolder stringByAppendingPathComponent:@"Icon@2x.png"],
        [bundleFolder stringByAppendingPathComponent:@"Icon.png"],
        [themePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-large.png", bundleIdentifier]],
        [themePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", bundleIdentifier]],
    ];
}

NSString *OMAOMExistingIconPathForBundleIdentifier(NSString *bundleIdentifier, NSString *themePath) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in OMAOMCandidateIconPathsForBundleIdentifier(bundleIdentifier, themePath)) {
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
            return path;
        }
    }
    return nil;
}

id OMAOMPreference(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)OMAOMPreferencesIdentifier));
}

static void OMAOMWritePreference(NSString *key, id value, BOOL notify) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)OMAOMPreferencesIdentifier);
    CFPreferencesAppSynchronize((__bridge CFStringRef)OMAOMPreferencesIdentifier);
    if (notify) {
        OMAOMPostDarwinNotification(OMAOMPreferencesChangedNotification);
    }
}

void OMAOMSetPreference(NSString *key, id value) {
    OMAOMWritePreference(key, value, YES);
}

void OMAOMSetPreferenceSilently(NSString *key, id value) {
    OMAOMWritePreference(key, value, NO);
}

void OMAOMSetDiagnosticValue(NSString *key, id value) {
    if (!key.length) {
        return;
    }
    NSString *diagnosticKey = [@"Debug" stringByAppendingString:key];
    OMAOMSetPreferenceSilently(diagnosticKey, value ?: @"");
}

void OMAOMSetDiagnosticError(NSString *value) {
    OMAOMSetDiagnosticValue(@"LastError", value ?: @"");
}

void OMAOMClearDiagnosticError(void) {
    OMAOMSetDiagnosticError(@"");
}

BOOL OMAOMBoolPreference(NSString *key, BOOL fallback) {
    id value = OMAOMPreference(key);
    return value ? [value boolValue] : fallback;
}

NSString *OMAOMStringPreference(NSString *key, NSString *fallback) {
    id value = OMAOMPreference(key);
    return [value isKindOfClass:NSString.class] && [value length] ? value : fallback;
}

void OMAOMEnsureDirectories(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *paths = @[
        OMAOMRootPath(),
        OMAOMActiveIconsPath(),
        OMAOMSnowBoardActiveThemePath(),
        [OMAOMIconThemesPath() stringByAppendingPathComponent:@"Light"],
        [OMAOMIconThemesPath() stringByAppendingPathComponent:@"Dark"],
        [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Light"],
        [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Dark"],
        [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Proof"],
    ];
    for (NSString *path in paths) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

void OMAOMPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
}
