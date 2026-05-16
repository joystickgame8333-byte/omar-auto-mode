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

NSString *OMAOMIconThemesPath(void) {
    return [OMAOMRootPath() stringByAppendingPathComponent:@"IconThemes"];
}

NSString *OMAOMWallpapersPath(void) {
    return [OMAOMRootPath() stringByAppendingPathComponent:@"Wallpapers"];
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

id OMAOMPreference(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)OMAOMPreferencesIdentifier));
}

void OMAOMSetPreference(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)OMAOMPreferencesIdentifier);
    CFPreferencesAppSynchronize((__bridge CFStringRef)OMAOMPreferencesIdentifier);
    OMAOMPostDarwinNotification(OMAOMPreferencesChangedNotification);
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
        [OMAOMIconThemesPath() stringByAppendingPathComponent:@"Light"],
        [OMAOMIconThemesPath() stringByAppendingPathComponent:@"Dark"],
        [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Light"],
        [OMAOMWallpapersPath() stringByAppendingPathComponent:@"Dark"],
    ];
    for (NSString *path in paths) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

void OMAOMPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
}

