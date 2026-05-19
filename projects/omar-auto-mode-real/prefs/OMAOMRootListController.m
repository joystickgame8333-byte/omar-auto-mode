#import "OMAOMRootListController.h"
#import "OMAOMIconPreviewController.h"
#import "OMAOMThemePickerController.h"
#import "../Shared/OMAOMShared.h"
#import <Preferences/PSSpecifier.h>
#import <spawn.h>

extern char **environ;

static NSUInteger OMAOMPrefsPNGFileCountAtPath(NSString *path) {
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

static NSArray<NSString *> *OMAOMPrefsThemeSearchRoots(void) {
    return @[
        OMAOMIconThemesPath(),
        @"/var/jb/Library/Themes",
        @"/Library/Themes",
    ];
}

static NSString *OMAOMPrefsFallbackThemePathForMode(NSString *mode) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *root in OMAOMPrefsThemeSearchRoots()) {
        NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
        for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            BOOL isDirectory = NO;
            if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
                [paths addObject:path];
            }
        }
    }

    NSArray<NSString *> *preferredWords = [mode isEqualToString:@"dark"] ? @[@"dark", @"night", @"black"] : @[@"light", @"clear", @"white"];
    for (NSString *path in paths) {
        NSString *name = path.lastPathComponent.lowercaseString;
        if (OMAOMPrefsPNGFileCountAtPath(path) == 0) {
            continue;
        }
        for (NSString *word in preferredWords) {
            if ([name containsString:word]) {
                return path;
            }
        }
    }

    for (NSString *path in paths) {
        if (OMAOMPrefsPNGFileCountAtPath(path) > 0) {
            return path;
        }
    }
    return nil;
}

static NSString *OMAOMPrefsDetectedMode(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        if (style == UIUserInterfaceStyleUnspecified) {
            style = UITraitCollection.currentTraitCollection.userInterfaceStyle;
        }
        return style == UIUserInterfaceStyleDark ? @"dark" : @"light";
    }
    return @"light";
}

@interface OMAOMRootListController ()
@property (nonatomic, copy) NSString *pendingWallpaperKey;
@end

@implementation OMAOMRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    OMAOMEnsureDirectories();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = key ? OMAOMPreference(key) : nil;
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) {
        return;
    }
    OMAOMSetPreference(key, value ?: @NO);
}

- (NSString *)currentModeValue {
    NSString *lastMode = OMAOMStringPreference(@"LastAppliedMode", @"Not Applied");
    return lastMode.capitalizedString;
}

- (NSString *)formattedDebugTimeForKey:(NSString *)key {
    id value = OMAOMPreference(key);
    NSTimeInterval interval = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    if (interval <= 0) {
        return @"Never";
    }

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:interval]];
}

- (NSString *)debugStringForKey:(NSString *)key fallback:(NSString *)fallback {
    id value = OMAOMPreference(key);
    if ([value isKindOfClass:NSString.class] && [value length]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return fallback;
}

- (NSString *)diagnosticCodeValue {
    NSString *loaded = [self debugStringForKey:@"DebugEngineLoaded" fallback:@""];
    if (![loaded isEqualToString:@"YES"]) {
        return @"E-INJECT-NOLOAD";
    }

    NSString *error = [self debugStringForKey:@"DebugLastError" fallback:@""];
    if (error.length) {
        if ([error localizedCaseInsensitiveContainsString:@"Wallpaper"]) {
            return @"E-WALLPAPER";
        }
        if ([error localizedCaseInsensitiveContainsString:@"Theme"]) {
            return @"E-THEME";
        }
        return @"E-RUNTIME";
    }

    NSString *liveOverlay = [self debugStringForKey:@"DebugLiveIconOverlayEnabled" fallback:@""];
    if ([liveOverlay isEqualToString:@"NO"]) {
        return @"OK-PREVIEW";
    }

    NSInteger hits = [OMAOMPreference(@"DebugIconHits") integerValue];
    NSInteger misses = [OMAOMPreference(@"DebugIconMisses") integerValue];
    if (misses > 0 && hits == 0) {
        return @"E-ICON-NOTFOUND";
    }

    return @"OK-ENGINE";
}

- (NSString *)engineLoadedValue {
    NSString *loaded = [self debugStringForKey:@"DebugEngineLoaded" fallback:@"NO"];
    NSString *time = [self formattedDebugTimeForKey:@"DebugLoadedAt"];
    return [NSString stringWithFormat:@"%@ %@", loaded, time];
}

- (NSString *)lastEventValue {
    NSString *event = [self debugStringForKey:@"DebugLastEvent" fallback:@"No event"];
    NSString *time = [self formattedDebugTimeForKey:@"DebugLastEventAt"];
    return [NSString stringWithFormat:@"%@ - %@", event, time];
}

- (NSString *)lastErrorValue {
    return [self debugStringForKey:@"DebugLastError" fallback:@"None"];
}

- (NSString *)debugThemeValue {
    NSString *path = [self debugStringForKey:@"DebugThemePath" fallback:@"Not Set"];
    NSString *count = [self debugStringForKey:@"DebugThemePNGCount" fallback:@"0"];
    NSString *source = [self debugStringForKey:@"DebugThemeSource" fallback:@"unknown"];
    return [NSString stringWithFormat:@"%@ - %@ png - %@", path.lastPathComponent.length ? path.lastPathComponent : path, count, source];
}

- (NSString *)debugIconValue {
    NSString *hits = [self debugStringForKey:@"DebugIconHits" fallback:@"0"];
    NSString *misses = [self debugStringForKey:@"DebugIconMisses" fallback:@"0"];
    NSString *bundle = [self debugStringForKey:@"DebugLastBundle" fallback:@"No bundle"];
    return [NSString stringWithFormat:@"hit %@ / miss %@ - %@", hits, misses, bundle];
}

- (NSString *)debugWallpaperValue {
    return [self debugStringForKey:@"DebugLastWallpaperResult" fallback:@"Not called"];
}

- (NSString *)previewThemeValue {
    NSString *mode = [self currentPreviewMode];
    NSString *path = [self resolvedThemePathForMode:mode];
    NSUInteger count = OMAOMPrefsPNGFileCountAtPath(path);
    if (!path.length || count == 0) {
        return @"No theme image";
    }
    return [NSString stringWithFormat:@"%@ - %lu png", path.lastPathComponent, (unsigned long)count];
}

- (NSString *)lightThemeValue {
    return [self themeValueForKey:@"LightIconTheme"];
}

- (NSString *)darkThemeValue {
    return [self themeValueForKey:@"DarkIconTheme"];
}

- (NSString *)lightHomeWallpaperValue {
    return [self wallpaperValueForKey:@"LightHomeWallpaper"];
}

- (NSString *)lightLockWallpaperValue {
    return [self wallpaperValueForKey:@"LightLockWallpaper"];
}

- (NSString *)darkHomeWallpaperValue {
    return [self wallpaperValueForKey:@"DarkHomeWallpaper"];
}

- (NSString *)darkLockWallpaperValue {
    return [self wallpaperValueForKey:@"DarkLockWallpaper"];
}

- (NSString *)themesFolderValue {
    return OMAOMIconThemesPath();
}

- (NSString *)wallpapersFolderValue {
    return OMAOMWallpapersPath();
}

- (NSString *)standaloneStateValue {
    return [self debugStringForKey:@"DebugStandaloneState" fallback:@"Waiting for SpringBoard"];
}

- (NSString *)springBoardProbeValue {
    return [self debugStringForKey:@"DebugSpringBoardClassProbe" fallback:@"Not probed"];
}

- (NSString *)themeValueForKey:(NSString *)key {
    NSString *path = OMAOMStringPreference(key, OMAOMDefaultPathForKey(key));
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
        return [NSString stringWithFormat:@"%@ - %lu png", path.lastPathComponent, (unsigned long)OMAOMPrefsPNGFileCountAtPath(path)];
    }
    return @"Not Set";
}

- (NSString *)wallpaperValueForKey:(NSString *)key {
    NSString *path = OMAOMStringPreference(key, OMAOMDefaultPathForKey(key));
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
        if (size > 0) {
            return [NSString stringWithFormat:@"Saved - %.1f MB", (double)size / (1024.0 * 1024.0)];
        }
        return @"Saved";
    }
    return @"Not Set";
}

- (NSString *)currentPreviewMode {
    NSString *debugMode = [self debugStringForKey:@"DebugLastMode" fallback:@""].lowercaseString;
    if ([debugMode isEqualToString:@"dark"] || [debugMode isEqualToString:@"light"]) {
        return debugMode;
    }

    NSString *lastMode = OMAOMStringPreference(@"LastAppliedMode", @"").lowercaseString;
    if ([lastMode isEqualToString:@"dark"] || [lastMode isEqualToString:@"light"]) {
        return lastMode;
    }
    return OMAOMPrefsDetectedMode();
}

- (NSString *)resolvedThemePathForMode:(NSString *)mode {
    NSString *key = [mode isEqualToString:@"dark"] ? @"DarkIconTheme" : @"LightIconTheme";
    NSString *selected = OMAOMStringPreference(key, OMAOMDefaultPathForKey(key));
    if (OMAOMPrefsPNGFileCountAtPath(selected) > 0) {
        return selected;
    }

    NSString *debugTheme = [self debugStringForKey:@"DebugThemePath" fallback:@""];
    if (OMAOMPrefsPNGFileCountAtPath(debugTheme) > 0) {
        return debugTheme;
    }

    NSString *fallback = OMAOMPrefsFallbackThemePathForMode(mode);
    return fallback ?: selected;
}

- (void)previewCurrentThemeIcons {
    [self previewThemeIconsForMode:[self currentPreviewMode] title:@"Current Mode Icons"];
}

- (void)previewLightThemeIcons {
    [self previewThemeIconsForMode:@"light" title:@"Light Icons"];
}

- (void)previewDarkThemeIcons {
    [self previewThemeIconsForMode:@"dark" title:@"Dark Icons"];
}

- (void)previewThemeIconsForMode:(NSString *)mode title:(NSString *)title {
    NSString *themePath = [self resolvedThemePathForMode:mode];
    if (OMAOMPrefsPNGFileCountAtPath(themePath) == 0) {
        [self showMessageWithTitle:@"No Icons Found" message:@"Choose a theme folder that contains PNG icons first."];
        return;
    }

    NSString *screenTitle = [NSString stringWithFormat:@"%@ - %@", title, themePath.lastPathComponent];
    OMAOMIconPreviewController *controller = [[OMAOMIconPreviewController alloc] initWithThemePath:themePath title:screenTitle];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)pickLightTheme {
    [self pushThemePickerForKey:@"LightIconTheme" title:@"Light Icon Theme"];
}

- (void)pickDarkTheme {
    [self pushThemePickerForKey:@"DarkIconTheme" title:@"Dark Icon Theme"];
}

- (void)pushThemePickerForKey:(NSString *)key title:(NSString *)title {
    OMAOMThemePickerController *controller = [[OMAOMThemePickerController alloc] initWithPreferenceKey:key title:title];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)pickLightHomeWallpaper {
    [self pickWallpaperForKey:@"LightHomeWallpaper"];
}

- (void)pickLightLockWallpaper {
    [self pickWallpaperForKey:@"LightLockWallpaper"];
}

- (void)pickDarkHomeWallpaper {
    [self pickWallpaperForKey:@"DarkHomeWallpaper"];
}

- (void)pickDarkLockWallpaper {
    [self pickWallpaperForKey:@"DarkLockWallpaper"];
}

- (void)pickWallpaperForKey:(NSString *)key {
    self.pendingWallpaperKey = key;

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showMessageWithTitle:@"Photos Unavailable" message:@"The photo library picker is not available right now."];
        return;
    }

    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSString *key = self.pendingWallpaperKey;
    self.pendingWallpaperKey = nil;
    __block NSString *messageTitle = @"Wallpaper Not Saved";
    __block NSString *message = @"No image was returned from Photos.";

    if (image && key) {
        NSString *path = OMAOMDefaultPathForKey(key);
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *data = UIImagePNGRepresentation(image);
        if ([data writeToFile:path atomically:YES]) {
            OMAOMSetPreference(key, path);
            OMAOMSetDiagnosticValue(@"LastWallpaperResult", [NSString stringWithFormat:@"saved %@ only", key]);
            OMAOMSetDiagnosticValue(@"LastWallpaperPath", path);
            OMAOMSetDiagnosticValue(@"ProofWallpaperResult", @"system apply disabled for stability");
            messageTitle = @"Wallpaper Saved";
            message = @"The image was saved in Omar Auto Mode. System wallpaper applying is still disabled so SpringBoard stays stable while icon theming is being fixed.";
        } else {
            OMAOMSetDiagnosticError([NSString stringWithFormat:@"Wallpaper save failed: %@", path.lastPathComponent]);
            OMAOMSetDiagnosticValue(@"LastWallpaperResult", @"save failed");
            OMAOMSetDiagnosticValue(@"LastWallpaperPath", path);
            message = @"The image could not be written to the Omar Auto Mode folder.";
        }
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self reloadSpecifiers];
        [self showMessageWithTitle:messageTitle message:message];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    self.pendingWallpaperKey = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyNow {
    OMAOMSetPreference(@"ManualApplyRequestedAt", @([[NSDate date] timeIntervalSince1970]));
    OMAOMPostDarwinNotification(OMAOMApplyNotification);
    [self showMessageWithTitle:@"Apply Requested" message:@"Omar Auto Mode prepared the matching icon theme for the current iOS appearance. Live icon overlay is off unless you enable the experimental switch."];
}

- (void)runEngineProbe {
    OMAOMSetPreferenceSilently(@"ProofLockWallpaperApplied", @NO);
    OMAOMSetPreferenceSilently(@"ProbeRequestedAt", @([[NSDate date] timeIntervalSince1970]));
    OMAOMSetDiagnosticValue(@"LastEvent", @"engine probe sent from Settings");
    OMAOMSetDiagnosticValue(@"ProofWallpaperPath", OMAOMProofLockWallpaperPath());
    OMAOMPostDarwinNotification(OMAOMApplyNotification);
    [self showMessageWithTitle:@"Probe Requested" message:@"A safe refresh was sent to SpringBoard. It prepares the selected theme and removes old overlay squares unless the experimental overlay switch is enabled."];
}

- (void)showDiagnostics {
    NSArray<NSString *> *lines = @[
        [NSString stringWithFormat:@"Code: %@", [self diagnosticCodeValue]],
        [NSString stringWithFormat:@"Engine: %@", [self engineLoadedValue]],
        [NSString stringWithFormat:@"Event: %@", [self lastEventValue]],
        [NSString stringWithFormat:@"Error: %@", [self lastErrorValue]],
        [NSString stringWithFormat:@"Mode: %@", [self debugStringForKey:@"DebugLastMode" fallback:@"Unknown"]],
        [NSString stringWithFormat:@"Theme: %@", [self debugStringForKey:@"DebugThemePath" fallback:@"Not Set"]],
        [NSString stringWithFormat:@"Theme source: %@", [self debugStringForKey:@"DebugThemeSource" fallback:@"unknown"]],
        [NSString stringWithFormat:@"Fallback theme: %@", [self debugStringForKey:@"DebugFallbackThemePath" fallback:@"None"]],
        [NSString stringWithFormat:@"Active: %@", [self debugStringForKey:@"DebugActiveThemePath" fallback:@"Not Set"]],
        [NSString stringWithFormat:@"Theme PNGs: %@", [self debugStringForKey:@"DebugThemePNGCount" fallback:@"0"]],
        [NSString stringWithFormat:@"Active PNGs: %@", [self debugStringForKey:@"DebugActiveThemePNGCount" fallback:@"0"]],
        [NSString stringWithFormat:@"Live overlay: %@", [self debugStringForKey:@"DebugLiveIconOverlayEnabled" fallback:@"Unknown"]],
        [NSString stringWithFormat:@"Icons: %@", [self debugIconValue]],
        [NSString stringWithFormat:@"Last icon path: %@", [self debugStringForKey:@"DebugLastIconPath" fallback:@"Not Found"]],
        [NSString stringWithFormat:@"Last miss: %@", [self debugStringForKey:@"DebugLastIconMiss" fallback:@"None"]],
        [NSString stringWithFormat:@"Icon view: %@ / applied %@", [self debugStringForKey:@"DebugLastIconView" fallback:@"Not touched"], [self debugStringForKey:@"DebugLastIconImageViewsApplied" fallback:@"0"]],
        [NSString stringWithFormat:@"Icon view hits: %@", [self debugStringForKey:@"DebugIconViewProbeHits" fallback:@"0"]],
        [NSString stringWithFormat:@"Overlay container: %@", [self debugStringForKey:@"DebugIconOverlayContainer" fallback:@"Not applied"]],
        [NSString stringWithFormat:@"Visible refresh: %@", [self debugStringForKey:@"DebugVisibleIconRefreshCount" fallback:@"0"]],
        [NSString stringWithFormat:@"Auto switch: %@", [self debugStringForKey:@"DebugAutoSwitchState" fallback:@"Not checked"]],
        [NSString stringWithFormat:@"Icon subviews: %@", [self debugStringForKey:@"DebugIconViewSubviews" fallback:@"Not seen"]],
        [NSString stringWithFormat:@"Standalone: %@", [self debugStringForKey:@"DebugStandaloneState" fallback:@"Unknown"]],
        [NSString stringWithFormat:@"Class probe: %@", [self debugStringForKey:@"DebugSpringBoardClassProbe" fallback:@"Not probed"]],
        [NSString stringWithFormat:@"Windows: %@", [self debugStringForKey:@"DebugWindowCount" fallback:@"0"]],
        [NSString stringWithFormat:@"Icon containers: %@", [self debugStringForKey:@"DebugIconContainerCount" fallback:@"0"]],
        [NSString stringWithFormat:@"Wallpaper: %@", [self debugWallpaperValue]],
        [NSString stringWithFormat:@"Wallpaper path: %@", [self debugStringForKey:@"DebugLastWallpaperPath" fallback:@"Not Set"]],
        [NSString stringWithFormat:@"Proof: %@", [self debugStringForKey:@"DebugProofWallpaperResult" fallback:@"Not called"]],
        [NSString stringWithFormat:@"Proof path: %@", [self debugStringForKey:@"DebugProofWallpaperPath" fallback:OMAOMProofLockWallpaperPath()]],
    ];
    [self showMessageWithTitle:@"Diagnostics" message:[lines componentsJoinedByString:@"\n"]];
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring"
                                                                   message:@"Apply changes by restarting SpringBoard?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self runRespringCommand];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runRespringCommand {
    NSArray<NSString *> *commands = @[
        @"/var/jb/usr/bin/sbreload",
        @"/var/jb/usr/bin/ldrestart",
        @"/usr/bin/sbreload",
    ];

    for (NSString *command in commands) {
        if (![NSFileManager.defaultManager isExecutableFileAtPath:command]) {
            continue;
        }
        pid_t pid;
        const char *argv[] = { command.fileSystemRepresentation, NULL };
        posix_spawn(&pid, command.fileSystemRepresentation, NULL, NULL, (char *const *)argv, environ);
        return;
    }
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
