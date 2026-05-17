#import "OMAOMThemePickerController.h"
#import "../Shared/OMAOMShared.h"

@interface OMAOMThemePickerController ()
@property (nonatomic, copy) NSString *preferenceKey;
@property (nonatomic, copy) NSArray<NSString *> *themePaths;
@end

@implementation OMAOMThemePickerController

- (instancetype)initWithPreferenceKey:(NSString *)preferenceKey title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _preferenceKey = [preferenceKey copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadThemes];
}

- (void)reloadThemes {
    OMAOMEnsureDirectories();
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSArray<NSString *> *roots = @[
        OMAOMIconThemesPath(),
        @"/var/jb/Library/Themes",
        @"/Library/Themes",
    ];

    for (NSString *root in roots) {
        NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
        for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            BOOL isDirectory = NO;
            if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory && ![paths containsObject:path]) {
                [paths addObject:path];
            }
        }
    }

    self.themePaths = paths;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.themePaths.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ThemeCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ThemeCell"];
    }

    if (!self.themePaths.count) {
        cell.textLabel.text = @"No Themes Found";
        cell.detailTextLabel.text = @"Put themes in OmarAutoMode/IconThemes or /var/jb/Library/Themes";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSString *path = self.themePaths[indexPath.row];
    NSString *selected = OMAOMStringPreference(self.preferenceKey, OMAOMDefaultPathForKey(self.preferenceKey));
    cell.textLabel.text = path.lastPathComponent;
    cell.detailTextLabel.text = path;
    cell.accessoryType = [selected isEqualToString:path] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.themePaths.count) {
        return;
    }

    NSString *path = self.themePaths[indexPath.row];
    OMAOMSetPreference(self.preferenceKey, path);
    OMAOMPostDarwinNotification(OMAOMApplyNotification);
    [self.tableView reloadData];
}

@end
