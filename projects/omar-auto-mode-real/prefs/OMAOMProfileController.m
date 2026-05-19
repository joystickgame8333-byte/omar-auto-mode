#import "OMAOMProfileController.h"
#import "OMAOMIconPreviewController.h"
#import "OMAOMThemePickerController.h"
#import "../Shared/OMAOMShared.h"
#import <spawn.h>

extern char **environ;

static NSUInteger OMAOMProfilePNGCountAtPath(NSString *path) {
    if (!path.length) {
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

static NSArray<NSString *> *OMAOMProfileIconSamples(NSString *path, NSUInteger limit) {
    if (!path.length) {
        return @[];
    }

    NSMutableArray<NSString *> *items = [NSMutableArray array];
    NSDirectoryEnumerator<NSString *> *enumerator = [NSFileManager.defaultManager enumeratorAtPath:path];
    for (NSString *item in enumerator) {
        if (![item.pathExtension.lowercaseString isEqualToString:@"png"]) {
            continue;
        }
        [items addObject:[path stringByAppendingPathComponent:item]];
        if (items.count >= limit) {
            break;
        }
    }
    return items;
}

static NSString *OMAOMProfileThemeKey(NSString *mode) {
    return [mode isEqualToString:@"dark"] ? @"DarkIconTheme" : @"LightIconTheme";
}

static NSString *OMAOMProfileHomeKey(NSString *mode) {
    return [mode isEqualToString:@"dark"] ? @"DarkHomeWallpaper" : @"LightHomeWallpaper";
}

static NSString *OMAOMProfileLockKey(NSString *mode) {
    return [mode isEqualToString:@"dark"] ? @"DarkLockWallpaper" : @"LightLockWallpaper";
}

@interface OMAOMProfileController ()
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, copy) NSString *pendingWallpaperKey;
@end

@implementation OMAOMProfileController

- (instancetype)initWithMode:(NSString *)mode title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _mode = [mode copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    OMAOMEnsureDirectories();
    self.tableView.rowHeight = 70.0;
    self.tableView.tableHeaderView = [self profileHeaderView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.tableView.tableHeaderView = [self profileHeaderView];
    [self.tableView reloadData];
}

- (NSString *)themePath {
    return OMAOMStringPreference(OMAOMProfileThemeKey(self.mode), OMAOMDefaultPathForKey(OMAOMProfileThemeKey(self.mode)));
}

- (NSString *)homeImagePath {
    return OMAOMStringPreference(OMAOMProfileHomeKey(self.mode), OMAOMDefaultPathForKey(OMAOMProfileHomeKey(self.mode)));
}

- (NSString *)lockImagePath {
    return OMAOMStringPreference(OMAOMProfileLockKey(self.mode), OMAOMDefaultPathForKey(OMAOMProfileLockKey(self.mode)));
}

- (UIView *)profileHeaderView {
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 280)];
    header.backgroundColor = UIColor.clearColor;

    UIView *phone = [[UIView alloc] initWithFrame:CGRectMake((width - 190.0) / 2.0, 18.0, 190.0, 238.0)];
    phone.backgroundColor = [self.mode isEqualToString:@"dark"] ? [UIColor colorWithWhite:0.05 alpha:1.0] : [UIColor colorWithRed:0.88 green:0.95 blue:1.0 alpha:1.0];
    phone.layer.cornerRadius = 34.0;
    phone.layer.borderWidth = 3.0;
    phone.layer.borderColor = ([self.mode isEqualToString:@"dark"] ? UIColor.blackColor : UIColor.whiteColor).CGColor;
    phone.clipsToBounds = YES;
    [header addSubview:phone];

    UIImage *wallpaper = [UIImage imageWithContentsOfFile:[self homeImagePath]];
    if (wallpaper) {
        UIImageView *wallpaperView = [[UIImageView alloc] initWithFrame:phone.bounds];
        wallpaperView.image = wallpaper;
        wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
        wallpaperView.alpha = [self.mode isEqualToString:@"dark"] ? 0.72 : 0.86;
        [phone addSubview:wallpaperView];
    }

    UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, phone.bounds.size.width, 26)];
    time.text = [self.mode isEqualToString:@"dark"] ? @"11:30" : @"9:41";
    time.textColor = [self.mode isEqualToString:@"dark"] ? UIColor.whiteColor : UIColor.blackColor;
    time.textAlignment = NSTextAlignmentCenter;
    time.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    [phone addSubview:time];

    NSArray<NSString *> *samples = OMAOMProfileIconSamples([self themePath], 8);
    CGFloat icon = 34.0;
    CGFloat gap = 13.0;
    CGFloat startX = (phone.bounds.size.width - (icon * 4.0) - (gap * 3.0)) / 2.0;
    for (NSUInteger index = 0; index < 8; index++) {
        CGFloat row = index / 4;
        CGFloat col = index % 4;
        CGRect frame = CGRectMake(startX + col * (icon + gap), 62.0 + row * 56.0, icon, icon);
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:frame];
        imageView.backgroundColor = [self.mode isEqualToString:@"dark"] ? [UIColor colorWithWhite:0.12 alpha:0.9] : [UIColor colorWithWhite:1.0 alpha:0.88];
        imageView.layer.cornerRadius = 9.0;
        imageView.clipsToBounds = YES;
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        if (index < samples.count) {
            imageView.image = [UIImage imageWithContentsOfFile:samples[index]];
        }
        [phone addSubview:imageView];
    }

    UIView *dock = [[UIView alloc] initWithFrame:CGRectMake(20.0, phone.bounds.size.height - 54.0, phone.bounds.size.width - 40.0, 42.0)];
    dock.backgroundColor = [self.mode isEqualToString:@"dark"] ? [UIColor colorWithWhite:0.22 alpha:0.75] : [UIColor colorWithWhite:1.0 alpha:0.65];
    dock.layer.cornerRadius = 18.0;
    [phone addSubview:dock];

    UILabel *summary = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 255.0, width - 40.0, 22.0)];
    summary.text = [NSString stringWithFormat:@"%@ - %lu icons", [self themePath].lastPathComponent ?: @"Theme", (unsigned long)OMAOMProfilePNGCountAtPath([self themePath])];
    summary.textColor = UIColor.secondaryLabelColor;
    summary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    summary.textAlignment = NSTextAlignmentCenter;
    [header addSubview:summary];

    return header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 2;
    }
    if (section == 1) {
        return 2;
    }
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Icon Theme";
    }
    if (section == 1) {
        return @"Images";
    }
    return @"Apply";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"Images are saved to the profile now. System wallpaper applying stays disabled until the icon engine is stable.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProfileCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProfileCell"];
    }

    cell.imageView.image = nil;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0 && indexPath.row == 0) {
        NSString *themePath = [self themePath];
        cell.textLabel.text = @"Choose Icon Theme";
        cell.detailTextLabel.text = themePath.lastPathComponent.length ? [NSString stringWithFormat:@"%@ - %lu png", themePath.lastPathComponent, (unsigned long)OMAOMProfilePNGCountAtPath(themePath)] : @"Not Set";
        NSString *sample = OMAOMProfileIconSamples(themePath, 1).firstObject;
        cell.imageView.image = [UIImage imageWithContentsOfFile:sample];
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        cell.textLabel.text = @"Preview Theme Icons";
        cell.detailTextLabel.text = @"Show the exact PNG icons inside this theme";
        cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        cell.textLabel.text = @"Home Screen Image";
        cell.detailTextLabel.text = [self imageSubtitleForPath:[self homeImagePath]];
        cell.imageView.image = [self thumbnailForImagePath:[self homeImagePath]];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        cell.textLabel.text = @"Lock Screen Image";
        cell.detailTextLabel.text = [self imageSubtitleForPath:[self lockImagePath]];
        cell.imageView.image = [self thumbnailForImagePath:[self lockImagePath]];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        cell.textLabel.text = @"Apply This Profile";
        cell.detailTextLabel.text = @"Prepare this theme and images for the current mode";
        cell.imageView.image = [UIImage systemImageNamed:@"checkmark.circle"];
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.textLabel.text = @"Respring";
        cell.detailTextLabel.text = @"Reload SpringBoard after changes";
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.clockwise"];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.layer.cornerRadius = 10.0;
    cell.imageView.clipsToBounds = YES;
    return cell;
}

- (NSString *)imageSubtitleForPath:(NSString *)path {
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
        return size > 0 ? [NSString stringWithFormat:@"Saved - %.1f MB", (double)size / (1024.0 * 1024.0)] : @"Saved";
    }
    return @"Not Set";
}

- (UIImage *)thumbnailForImagePath:(NSString *)path {
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image) {
        return image;
    }
    return [UIImage systemImageNamed:@"photo"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == 0) {
        OMAOMThemePickerController *controller = [[OMAOMThemePickerController alloc] initWithPreferenceKey:OMAOMProfileThemeKey(self.mode) title:self.title];
        [self.navigationController pushViewController:controller animated:YES];
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        NSString *themePath = [self themePath];
        if (OMAOMProfilePNGCountAtPath(themePath) == 0) {
            [self showMessageWithTitle:@"No Icons Found" message:@"Choose an icon theme with PNG files first."];
            return;
        }
        OMAOMIconPreviewController *controller = [[OMAOMIconPreviewController alloc] initWithThemePath:themePath title:themePath.lastPathComponent];
        [self.navigationController pushViewController:controller animated:YES];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [self pickWallpaperForKey:OMAOMProfileHomeKey(self.mode)];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        [self pickWallpaperForKey:OMAOMProfileLockKey(self.mode)];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        OMAOMSetPreference(@"LastAppliedMode", self.mode);
        OMAOMPostDarwinNotification(OMAOMApplyNotification);
        [self showMessageWithTitle:@"Profile Sent" message:@"The profile was sent to SpringBoard. The theme is prepared safely; wallpaper system applying is still disabled."];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        [self runRespringCommand];
    }
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

    NSString *title = @"Image Not Saved";
    NSString *message = @"No image was returned from Photos.";
    if (image && key.length) {
        NSString *path = OMAOMDefaultPathForKey(key);
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *data = UIImagePNGRepresentation(image);
        if ([data writeToFile:path atomically:YES]) {
            OMAOMSetPreference(key, path);
            OMAOMSetDiagnosticValue(@"LastWallpaperResult", [NSString stringWithFormat:@"saved %@ only", key]);
            OMAOMSetDiagnosticValue(@"LastWallpaperPath", path);
            title = @"Image Saved";
            message = @"The image is saved in this profile.";
        } else {
            OMAOMSetDiagnosticError([NSString stringWithFormat:@"Image save failed: %@", path.lastPathComponent]);
            message = @"The image could not be saved.";
        }
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        self.tableView.tableHeaderView = [self profileHeaderView];
        [self.tableView reloadData];
        [self showMessageWithTitle:title message:message];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    self.pendingWallpaperKey = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
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
