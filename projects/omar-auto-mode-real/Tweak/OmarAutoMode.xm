#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

@interface SBApplicationIcon : NSObject
@end

@interface SBIconView : UIView
@end

@interface SBIconImageView : UIView
@end

static NSInteger OMAOMIconHitCount = 0;
static NSInteger OMAOMIconMissCount = 0;
static NSInteger OMAOMIconContainerApplyCount = 0;

static NSCache<NSString *, UIImage *> *OMAOMIconImageCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 256;
    });
    return cache;
}

static NSNumber *OMAOMNowNumber(void) {
    return @([[NSDate date] timeIntervalSince1970]);
}

static void OMAOMDebugEvent(NSString *event) {
    OMAOMSetDiagnosticValue(@"LastEvent", event ?: @"");
    OMAOMSetDiagnosticValue(@"LastEventAt", OMAOMNowNumber());
}

static UIImage *OMAOMImageForIcon(id icon);

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
    OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"disabled in 2.0 icons-only");
    OMAOMSetDiagnosticValue(@"ProofWallpaperResult", @"disabled in 2.0 icons-only");
    OMAOMSetDiagnosticValue(@"WindowCount", @0);

    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        [OMAOMIconImageCache() removeAllObjects];
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
    if ([icon isKindOfClass:NSString.class] && [icon length]) {
        return icon;
    }

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

static id OMAOMIconObjectForView(UIView *view) {
    UIView *current = view;
    NSUInteger depth = 0;
    while (current && depth < 8) {
        NSArray<NSString *> *selectors = @[@"icon", @"applicationIcon", @"representedIcon", @"displayedIcon", @"leafIcon"];
        for (NSString *selectorName in selectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![current respondsToSelector:selector]) {
                continue;
            }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id value = [current performSelector:selector];
#pragma clang diagnostic pop
            if (OMAOMBundleIdentifierForIcon(value).length) {
                return value;
            }
        }

        NSArray<NSString *> *keys = @[@"icon", @"_icon", @"applicationIcon", @"representedIcon", @"displayedIcon", @"leafIcon"];
        for (NSString *key in keys) {
            @try {
                id value = [current valueForKey:key];
                if (OMAOMBundleIdentifierForIcon(value).length) {
                    return value;
                }
            } @catch (__unused NSException *exception) {
            }
        }

        current = current.superview;
        depth++;
    }
    return nil;
}

static BOOL OMAOMImageViewLooksLikeIconArtwork(UIImageView *imageView) {
    CGSize size = imageView.bounds.size;
    CGFloat minDimension = MIN(size.width, size.height);
    CGFloat maxDimension = MAX(size.width, size.height);
    if (minDimension < 32.0 || maxDimension > 190.0) {
        return NO;
    }
    return maxDimension / MAX(minDimension, 1.0) < 1.45;
}

static NSInteger OMAOMApplyImageToIconArtworkViews(UIView *view, UIImage *image) {
    if (!view || !image) {
        return 0;
    }

    NSInteger applied = 0;
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        if (OMAOMImageViewLooksLikeIconArtwork(imageView)) {
            if (imageView.image != image) {
                imageView.image = image;
            }
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            applied++;
        }
    }

    for (UIView *subview in view.subviews) {
        applied += OMAOMApplyImageToIconArtworkViews(subview, image);
    }
    return applied;
}

static void OMAOMApplyThemedImageToIconContainer(UIView *view) {
    id icon = OMAOMIconObjectForView(view);
    UIImage *image = OMAOMImageForIcon(icon);
    if (!image) {
        return;
    }

    NSInteger applied = OMAOMApplyImageToIconArtworkViews(view, image);
    if (applied <= 0) {
        return;
    }

    OMAOMIconContainerApplyCount++;
    OMAOMSetDiagnosticValue(@"IconContainerCount", @(OMAOMIconContainerApplyCount));
    OMAOMSetDiagnosticValue(@"LastIconView", NSStringFromClass(view.class));
    OMAOMSetDiagnosticValue(@"LastIconImageViewsApplied", @(applied));
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

    UIImage *cachedImage = [OMAOMIconImageCache() objectForKey:path];
    if (cachedImage) {
        OMAOMIconHitCount++;
        OMAOMSetDiagnosticValue(@"IconHits", @(OMAOMIconHitCount));
        OMAOMSetDiagnosticValue(@"LastIconPath", path);
        return cachedImage;
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

    [OMAOMIconImageCache() setObject:image forKey:path];
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

%hook SBIconView

- (void)layoutSubviews {
    %orig;
    OMAOMApplyThemedImageToIconContainer((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    OMAOMApplyThemedImageToIconContainer((UIView *)self);
}

- (void)setIcon:(id)icon {
    %orig;
    OMAOMApplyThemedImageToIconContainer((UIView *)self);
}

%end

%hook SBIconImageView

- (void)layoutSubviews {
    %orig;
    OMAOMApplyThemedImageToIconContainer((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    OMAOMApplyThemedImageToIconContainer((UIView *)self);
}

- (void)setIcon:(id)icon {
    %orig;
    OMAOMApplyThemedImageToIconContainer((UIView *)self);
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
            OMAOMSetDiagnosticValue(@"IconContainerCount", @0);
            OMAOMSetDiagnosticValue(@"LastIconView", @"not touched");
            OMAOMSetDiagnosticValue(@"LastIconImageViewsApplied", @0);
            OMAOMDebugEvent(@"2.0 icon-view engine loaded");
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMApplyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMPreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            OMAOMApplyCurrentModeProbe();

            [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(__unused NSTimer *timer) {
                OMAOMApplyCurrentModeProbe();
            }];
        });
    }
}
