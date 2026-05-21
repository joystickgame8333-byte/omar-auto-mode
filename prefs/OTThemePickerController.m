#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static NSString * const OTPrefsPath = @"/var/mobile/Library/Preferences/com.omaralasam.themeswitcher.plist";
static const char *OTPreferencesChanged = "com.omaralasam.themeswitcher/preferences.changed";

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface OTThemePickerController : UITableViewController
@property (nonatomic, strong) PSSpecifier *specifier;
@end

@implementation OTThemePickerController {
    NSArray<NSDictionary *> *_themes;
    NSString *_preferenceKey;
    NSString *_selectedPath;
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    _specifier = specifier;
    _preferenceKey = [[specifier propertyForKey:@"themeKey"] copy] ?: @"DayThemePath";
    self.title = [[specifier propertyForKey:@"title"] copy] ?: @"Choose Theme";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [self loadSelectedPath];
    [self reloadThemes];
}

- (void)loadSelectedPath {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:OTPrefsPath];
    id value = prefs[_preferenceKey ?: @"DayThemePath"];
    _selectedPath = [value isKindOfClass:NSString.class] ? value : nil;
}

- (void)saveSelectedPath:(NSString *)path {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:OTPrefsPath];
    if (![prefs isKindOfClass:NSMutableDictionary.class]) {
        NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:OTPrefsPath];
        prefs = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    }

    if (path.length) {
        prefs[_preferenceKey ?: @"DayThemePath"] = path;
    } else {
        [prefs removeObjectForKey:_preferenceKey ?: @"DayThemePath"];
    }

    [prefs writeToFile:OTPrefsPath atomically:YES];
    _selectedPath = path;
    notify_post(OTPreferencesChanged);
}

- (NSArray<NSString *> *)themeSearchRoots {
    return @[
        @"/var/jb/Library/Themes",
        @"/Library/Themes"
    ];
}

- (NSString *)snowBoardPathForThemeAtPath:(NSString *)path root:(NSString *)root {
    NSString *name = path.lastPathComponent;
    if ([root isEqualToString:@"/var/jb/Library/Themes"]) {
        return [@"/Library/Themes" stringByAppendingPathComponent:name];
    }
    return path;
}

- (void)reloadThemes {
    NSMutableArray<NSDictionary *> *themes = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];

    for (NSString *root in self.themeSearchRoots) {
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *item in items) {
            if (![item.pathExtension.lowercaseString isEqualToString:@"theme"]) continue;
            if ([seenNames containsObject:item]) continue;
            [seenNames addObject:item];

            NSString *path = [root stringByAppendingPathComponent:item];
            BOOL isDirectory = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) continue;

            NSString *snowBoardPath = [self snowBoardPathForThemeAtPath:path root:root];
            [themes addObject:@{
                @"name": item.stringByDeletingPathExtension,
                @"displayPath": path,
                @"snowBoardPath": snowBoardPath
            }];
        }
    }

    _themes = [themes sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : MAX(1, _themes.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Current" : @"Installed Themes";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1 && !_themes.count) {
        return @"No .theme folders were found in /var/jb/Library/Themes or /Library/Themes.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ThemeCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ThemeCell"];
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;

    if (indexPath.section == 0) {
        cell.textLabel.text = _selectedPath.length ? _selectedPath.lastPathComponent.stringByDeletingPathExtension : @"No theme selected";
        cell.detailTextLabel.text = _selectedPath.length ? _selectedPath : @"Choose one installed SnowBoard theme.";
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        return cell;
    }

    if (!_themes.count) {
        cell.textLabel.text = @"No themes found";
        cell.detailTextLabel.text = @"Install a SnowBoard theme first.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary *theme = _themes[indexPath.row];
    NSString *path = theme[@"snowBoardPath"];
    cell.textLabel.text = theme[@"name"];
    cell.detailTextLabel.text = theme[@"displayPath"];
    cell.accessoryType = [_selectedPath isEqualToString:path] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || !_themes.count) return;

    NSDictionary *theme = _themes[indexPath.row];
    [self saveSelectedPath:theme[@"snowBoardPath"]];
    [self.tableView reloadData];
}

@end
