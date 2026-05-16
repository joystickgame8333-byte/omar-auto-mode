#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

static NSString *OMAOMLastDetectedMode(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
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

static void OMAOMApplyMode(NSString *mode) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        return;
    }

    OMAOMEnsureDirectories();

    NSString *themeKey = [mode isEqualToString:@"dark"] ? @"DarkIconTheme" : @"LightIconTheme";
    NSString *themePath = OMAOMStringPreference(themeKey, OMAOMDefaultPathForKey(themeKey));
    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        OMAOMSetPreference(@"LastAppliedMode", mode);
    }

    // Wallpaper and live icon rendering are native engines, not plist behavior.
    // The next implementation step is to wire this mode change into SpringBoard
    // wallpaper APIs and icon image hooks after the project compiles on-device.
}

static void OMAOMApplyCurrentMode(void) {
    OMAOMApplyMode(OMAOMLastDetectedMode());
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMApplyCurrentMode();
}

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
        }
    }];

    OMAOMApplyCurrentMode();
}

%end

