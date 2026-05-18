#import "OMAOMRootListController.h"
#import "OMAOMThemePickerController.h"
#import "../Shared/OMAOMShared.h"
#import <Preferences/PSSpecifier.h>
#import <spawn.h>

extern char **environ;

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
        return path.lastPathComponent;
    }
    return @"Not Set";
}

- (NSString *)wallpaperValueForKey:(NSString *)key {
    NSString *path = OMAOMStringPreference(key, OMAOMDefaultPathForKey(key));
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        return path.lastPathComponent;
    }
    return @"Not Set";
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

    if (image && key) {
        NSString *path = OMAOMDefaultPathForKey(key);
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *data = UIImagePNGRepresentation(image);
        if ([data writeToFile:path atomically:YES]) {
            OMAOMSetPreference(key, path);
        }
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self reloadSpecifiers];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    self.pendingWallpaperKey = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyNow {
    OMAOMSetPreference(@"ManualApplyRequestedAt", @([[NSDate date] timeIntervalSince1970]));
    OMAOMPostDarwinNotification(OMAOMApplyNotification);
    [self showMessageWithTitle:@"Apply Requested" message:@"Omar Auto Mode is applying the matching setup for the current iOS appearance. Respring if cached icons do not refresh immediately."];
}

- (void)runEngineProbe {
    OMAOMSetPreferenceSilently(@"ProofLockWallpaperApplied", @NO);
    OMAOMSetPreferenceSilently(@"ProbeRequestedAt", @([[NSDate date] timeIntervalSince1970]));
    OMAOMSetDiagnosticValue(@"LastEvent", @"engine probe sent from Settings");
    OMAOMSetDiagnosticValue(@"ProofWallpaperPath", OMAOMProofLockWallpaperPath());
    OMAOMPostDarwinNotification(OMAOMApplyNotification);
    [self showMessageWithTitle:@"Probe Requested" message:@"A standalone-safe refresh was sent to SpringBoard. It uses SBIconView overlays and leaves the system icon image untouched. Open Diagnostics after a few seconds."];
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
        [NSString stringWithFormat:@"Icons: %@", [self debugIconValue]],
        [NSString stringWithFormat:@"Last icon path: %@", [self debugStringForKey:@"DebugLastIconPath" fallback:@"Not Found"]],
        [NSString stringWithFormat:@"Last miss: %@", [self debugStringForKey:@"DebugLastIconMiss" fallback:@"None"]],
        [NSString stringWithFormat:@"Icon view: %@ / applied %@", [self debugStringForKey:@"DebugLastIconView" fallback:@"Not touched"], [self debugStringForKey:@"DebugLastIconImageViewsApplied" fallback:@"0"]],
        [NSString stringWithFormat:@"Icon view hits: %@", [self debugStringForKey:@"DebugIconViewProbeHits" fallback:@"0"]],
        [NSString stringWithFormat:@"Overlay container: %@", [self debugStringForKey:@"DebugIconOverlayContainer" fallback:@"Not applied"]],
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
