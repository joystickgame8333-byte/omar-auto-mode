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
