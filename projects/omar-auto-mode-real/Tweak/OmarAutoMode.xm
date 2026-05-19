#import <UIKit/UIKit.h>
#import "../Shared/OMAOMShared.h"

@interface SBIconView : UIView
- (id)icon;
@end

static NSUInteger OMAOMIconViewProbeHitCount = 0;
static NSUInteger OMAOMIconOverlayAppliedCount = 0;
static NSUInteger OMAOMIconOverlayMissCount = 0;
static CFTimeInterval OMAOMLastIconViewProbeDiagnosticWrite = 0;
static BOOL OMAOMIsApplyingIconOverlay = NO;
static const NSInteger OMAOMIconOverlayTag = 260526;
static NSMutableDictionary<NSString *, UIImage *> *OMAOMIconImageCache;
static NSMutableSet<NSString *> *OMAOMMissingIconPathCache;
static NSString *OMAOMLastPreparedMode;
static NSString *OMAOMLastPreparedThemePath;
static BOOL OMAOMActiveIconsPrepared = NO;

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

static UIView *OMAOMFirstSubviewMatchingName(UIView *view, NSArray<NSString *> *needles) {
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class) ?: @"";
        for (NSString *needle in needles) {
            if ([className containsString:needle]) {
                return subview;
            }
        }
    }
    return nil;
}

static UIView *OMAOMIconOverlayContainerForView(UIView *view) {
    UIView *container = OMAOMFirstSubviewMatchingName(view, @[@"TouchPassThrough", @"IconImage", @"Icon"]);
    return container ?: view;
}

static UIView *OMAOMFindTaggedSubview(UIView *view, NSInteger tag) {
    if (view.tag == tag) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *match = OMAOMFindTaggedSubview(subview, tag);
        if (match) {
            return match;
        }
    }
    return nil;
}

static CGRect OMAOMOverlayFrameForContainer(UIView *container, UIView *iconView) {
    CGRect bounds = container.bounds;
    if (CGRectIsEmpty(bounds) || bounds.size.width <= 0 || bounds.size.height <= 0) {
        bounds = iconView.bounds;
    }

    CGFloat side = MIN(bounds.size.width, bounds.size.height);
    if (side <= 0) {
        return CGRectZero;
    }

    CGFloat x = (bounds.size.width - side) / 2.0;
    CGFloat y = (bounds.size.height - side) / 2.0;
    if (container == iconView && bounds.size.height > bounds.size.width * 1.2) {
        y = 0;
    }
    return CGRectIntegral(CGRectMake(x, y, side, side));
}

static void OMAOMResetIconImageCache(void) {
    OMAOMIconImageCache = [NSMutableDictionary dictionary];
    OMAOMMissingIconPathCache = [NSMutableSet set];
}

static UIImage *OMAOMImageAtPath(NSString *path) {
    if (!path.length) {
        return nil;
    }
    if (!OMAOMIconImageCache) {
        OMAOMResetIconImageCache();
    }
    UIImage *cached = OMAOMIconImageCache[path];
    if (cached) {
        return cached;
    }
    if ([OMAOMMissingIconPathCache containsObject:path]) {
        return nil;
    }

    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image) {
        OMAOMIconImageCache[path] = image;
    } else {
        [OMAOMMissingIconPathCache addObject:path];
    }
    return image;
}

static UIColor *OMAOMOverlayBackgroundColor(void) {
    NSString *mode = OMAOMLastDetectedMode();
    return [mode isEqualToString:@"dark"] ? UIColor.blackColor : UIColor.whiteColor;
}

static void OMAOMRestoreOriginalIconSubviews(UIView *container) {
    if (!container) {
        return;
    }

    for (UIView *subview in container.subviews) {
        if (subview.tag == OMAOMIconOverlayTag) {
            continue;
        }
        subview.hidden = NO;
    }
}

static void OMAOMRemoveIconOverlay(UIView *view) {
    UIView *overlay = OMAOMFindTaggedSubview(view, OMAOMIconOverlayTag);
    OMAOMRestoreOriginalIconSubviews(overlay.superview);
    [overlay removeFromSuperview];
}

static BOOL OMAOMApplyIconOverlay(UIView *view, NSString *source) {
    if (!OMAOMBoolPreference(@"Enabled", YES)) {
        OMAOMRemoveIconOverlay(view);
        return NO;
    }
    if (OMAOMIsApplyingIconOverlay || !view) {
        return NO;
    }

    OMAOMIsApplyingIconOverlay = YES;
    BOOL applied = NO;
    BOOL countedMiss = NO;
    @try {
        OMAOMIconViewProbeHitCount++;

        id icon = OMAOMPerformObjectSelector(view, @selector(icon));
        NSString *bundleIdentifier = OMAOMBundleIdentifierForObject(icon);
        if (!bundleIdentifier.length) {
            countedMiss = YES;
            OMAOMRemoveIconOverlay(view);
            OMAOMSetDiagnosticValue(@"LastIconMiss", @"SBIconView icon without bundle id");
        } else {
            NSString *iconPath = OMAOMExistingIconPathForBundleIdentifier(bundleIdentifier, OMAOMActiveIconsPath());
            if (!iconPath.length) {
                countedMiss = YES;
                OMAOMRemoveIconOverlay(view);
                OMAOMSetDiagnosticValue(@"LastBundle", bundleIdentifier);
                OMAOMSetDiagnosticValue(@"LastIconMiss", [NSString stringWithFormat:@"no active png for %@", bundleIdentifier]);
            } else {
                UIImage *image = OMAOMImageAtPath(iconPath);
                if (!image) {
                    countedMiss = YES;
                    OMAOMRemoveIconOverlay(view);
                    OMAOMSetDiagnosticValue(@"LastBundle", bundleIdentifier);
                    OMAOMSetDiagnosticValue(@"LastIconMiss", [NSString stringWithFormat:@"png load failed for %@", iconPath.lastPathComponent]);
                } else {
                    UIView *container = OMAOMIconOverlayContainerForView(view);
                    CGRect frame = OMAOMOverlayFrameForContainer(container, view);
                    if (CGRectIsEmpty(frame)) {
                        countedMiss = YES;
                        OMAOMSetDiagnosticValue(@"LastBundle", bundleIdentifier);
                        OMAOMSetDiagnosticValue(@"LastIconMiss", @"empty icon frame");
                    } else {
                        UIImageView *overlay = (UIImageView *)[container viewWithTag:OMAOMIconOverlayTag];
                        if (![overlay isKindOfClass:UIImageView.class]) {
                            [overlay removeFromSuperview];
                            overlay = [[UIImageView alloc] initWithFrame:frame];
                            overlay.tag = OMAOMIconOverlayTag;
                            overlay.userInteractionEnabled = NO;
                            overlay.clipsToBounds = YES;
                            overlay.contentMode = UIViewContentModeScaleAspectFit;
                            overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                            [container addSubview:overlay];
                        }

                        overlay.frame = frame;
                        overlay.backgroundColor = OMAOMOverlayBackgroundColor();
                        overlay.opaque = YES;
                        overlay.image = image;
                        overlay.hidden = NO;
                        OMAOMRestoreOriginalIconSubviews(container);
                        [container bringSubviewToFront:overlay];

                        OMAOMIconOverlayAppliedCount++;
                        applied = YES;
                        OMAOMSetDiagnosticValue(@"LastBundle", bundleIdentifier);
                        OMAOMSetDiagnosticValue(@"LastIconPath", iconPath);
                        OMAOMSetDiagnosticValue(@"LastIconMiss", @"none");
                        OMAOMSetDiagnosticValue(@"LastIconView", [NSString stringWithFormat:@"%@ via %@", NSStringFromClass(view.class), source ?: @"unknown"]);
                        OMAOMSetDiagnosticValue(@"IconViewSubviews", OMAOMSubviewClassSummary(view));
                        OMAOMSetDiagnosticValue(@"IconOverlayContainer", NSStringFromClass(container.class) ?: @"unknown");
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        countedMiss = YES;
        OMAOMSetDiagnosticError([NSString stringWithFormat:@"Icon overlay exception: %@", exception.reason ?: exception.name]);
        applied = NO;
    } @finally {
        OMAOMIsApplyingIconOverlay = NO;
    }
    if (countedMiss) {
        OMAOMIconOverlayMissCount++;
    }

    CFTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (OMAOMIconViewProbeHitCount <= 12 || now - OMAOMLastIconViewProbeDiagnosticWrite >= 2.0) {
        OMAOMLastIconViewProbeDiagnosticWrite = now;
        OMAOMSetDiagnosticValue(@"IconViewProbeHits", @(OMAOMIconViewProbeHitCount));
        OMAOMSetDiagnosticValue(@"IconContainerCount", @(OMAOMIconViewProbeHitCount));
        OMAOMSetDiagnosticValue(@"IconHits", @(OMAOMIconOverlayAppliedCount));
        OMAOMSetDiagnosticValue(@"IconMisses", @(OMAOMIconOverlayMissCount));
        OMAOMSetDiagnosticValue(@"LastIconImageViewsApplied", @(OMAOMIconOverlayAppliedCount));
        OMAOMSetDiagnosticValue(@"StandaloneState", applied ? @"SBIconView overlay applied; labels restored" : @"SBIconView overlay checked; labels restored on miss");
    }

    return applied;
}

static NSUInteger OMAOMRefreshIconViewsInView(UIView *view) {
    if (!view) {
        return 0;
    }

    NSUInteger refreshed = 0;
    Class iconViewClass = NSClassFromString(@"SBIconView");
    if (iconViewClass && [view isKindOfClass:iconViewClass]) {
        if (OMAOMApplyIconOverlay(view, @"visible refresh")) {
            refreshed++;
        }
    }

    for (UIView *subview in view.subviews) {
        refreshed += OMAOMRefreshIconViewsInView(subview);
    }
    return refreshed;
}

static NSArray<UIWindow *> *OMAOMApplicationWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
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

static NSUInteger OMAOMRefreshVisibleIconViews(void) {
    NSArray<UIWindow *> *windows = OMAOMApplicationWindows();
    NSUInteger refreshed = 0;
    for (UIWindow *window in windows) {
        refreshed += OMAOMRefreshIconViewsInView(window);
    }
    OMAOMSetDiagnosticValue(@"WindowCount", @(windows.count));
    OMAOMSetDiagnosticValue(@"VisibleIconRefreshCount", @(refreshed));
    return refreshed;
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

static void OMAOMApplyCurrentModeProbe(BOOL force) {
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
    OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"disabled in 2.9 icons-only overlay");
    OMAOMSetDiagnosticValue(@"ProofWallpaperResult", @"disabled in 2.9 icons-only overlay");
    if (OMAOMIconViewProbeHitCount == 0) {
        OMAOMSetDiagnosticValue(@"LastIconPath", @"waiting for SBIconView overlay");
        OMAOMSetDiagnosticValue(@"LastIconMiss", @"waiting for icon layout");
    }
    OMAOMSetDiagnosticValue(@"StandaloneState", @"SBIconView overlay engine installed; labels preserved");
    OMAOMSetDiagnosticValue(@"SpringBoardClassProbe", OMAOMSpringBoardClassProbe());

    BOOL shouldPrepare = force || !OMAOMActiveIconsPrepared || ![OMAOMLastPreparedMode isEqualToString:mode] || ![OMAOMLastPreparedThemePath isEqualToString:themePath];
    if (!shouldPrepare) {
        OMAOMSetDiagnosticValue(@"AutoSwitchState", @"already prepared; idle to avoid slowing SpringBoard");
        return;
    }

    if (OMAOMCopyDirectory(themePath, OMAOMActiveIconsPath())) {
        OMAOMResetIconImageCache();
        OMAOMActiveIconsPrepared = YES;
        OMAOMLastPreparedMode = [mode copy];
        OMAOMLastPreparedThemePath = [themePath copy];
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"LastSourceThemePath", themePath);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePath", OMAOMActiveIconsPath());
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(OMAOMActiveIconsPath())));
        NSUInteger refreshed = OMAOMRefreshVisibleIconViews();
        OMAOMSetDiagnosticValue(@"AutoSwitchState", [NSString stringWithFormat:@"prepared %@; refreshed %lu visible icons", mode, (unsigned long)refreshed]);
        OMAOMDebugEvent(@"2.9 standalone prepared active icons and refreshed overlays");
    } else if ([NSFileManager.defaultManager fileExistsAtPath:themePath]) {
        OMAOMResetIconImageCache();
        OMAOMActiveIconsPrepared = YES;
        OMAOMLastPreparedMode = [mode copy];
        OMAOMLastPreparedThemePath = [themePath copy];
        OMAOMSetPreferenceSilently(@"LastAppliedMode", mode);
        OMAOMSetPreferenceSilently(@"LastSourceThemePath", themePath);
        OMAOMSetPreferenceSilently(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePath", themePath);
        OMAOMSetDiagnosticValue(@"ActiveThemePNGCount", @(OMAOMPNGFileCountAtPath(themePath)));
        NSUInteger refreshed = OMAOMRefreshVisibleIconViews();
        OMAOMSetDiagnosticValue(@"AutoSwitchState", [NSString stringWithFormat:@"using source directly; refreshed %lu visible icons", (unsigned long)refreshed]);
        OMAOMDebugEvent(@"2.9 standalone using selected theme directly");
    } else {
        OMAOMSetDiagnosticValue(@"AutoSwitchState", @"prepare failed before active icons");
        OMAOMDebugEvent(@"2.9 standalone failed before active icons");
    }
}

static void OMAOMDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OMAOMDebugEvent(@"2.9 standalone icon overlay notification received");
    OMAOMApplyCurrentModeProbe(YES);
}

%hook SBIconView

- (void)setIcon:(id)icon {
    %orig;
    OMAOMApplyIconOverlay((UIView *)self, @"setIcon:");
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) {
        OMAOMApplyIconOverlay((UIView *)self, @"didMoveToWindow");
    }
}

- (void)layoutSubviews {
    %orig;
    OMAOMApplyIconOverlay((UIView *)self, @"layoutSubviews");
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
            OMAOMSetDiagnosticValue(@"LastIconImageViewsApplied", @0);
            OMAOMDebugEvent(@"2.9 standalone SBIconView overlay engine loaded");
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMApplyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMAOMDarwinCallback, (__bridge CFStringRef)OMAOMPreferencesChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            OMAOMApplyCurrentModeProbe(YES);

            [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(__unused NSTimer *timer) {
                OMAOMApplyCurrentModeProbe(NO);
            }];
        });
    }
}
