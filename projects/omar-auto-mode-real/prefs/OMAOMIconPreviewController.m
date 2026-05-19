#import "OMAOMIconPreviewController.h"

static NSUInteger OMAOMPreviewPNGCountAtPath(NSString *path) {
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

static NSString *OMAOMPreviewRelativePath(NSString *path, NSString *root) {
    if ([path hasPrefix:root]) {
        NSString *relative = [path substringFromIndex:root.length];
        if ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        return relative;
    }
    return path.lastPathComponent;
}

static NSString *OMAOMPreviewBundleTitle(NSString *relativePath) {
    NSArray<NSString *> *parts = [relativePath componentsSeparatedByString:@"/"];
    NSUInteger bundlesIndex = [parts indexOfObject:@"Bundles"];
    if (bundlesIndex != NSNotFound && bundlesIndex + 1 < parts.count) {
        return parts[bundlesIndex + 1];
    }

    NSString *name = relativePath.lastPathComponent.stringByDeletingPathExtension;
    for (NSString *suffix in @[@"-large", @"@3x", @"@2x"]) {
        if ([name hasSuffix:suffix]) {
            name = [name substringToIndex:name.length - suffix.length];
        }
    }
    return name.length ? name : relativePath.lastPathComponent;
}

@interface OMAOMIconPreviewImageController : UIViewController
@property (nonatomic, copy) NSString *iconPath;
@property (nonatomic, copy) NSString *iconTitle;
@property (nonatomic, copy) NSString *iconDetail;
@end

@implementation OMAOMIconPreviewImageController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.iconTitle ?: @"Icon";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIImageView *imageView = [UIImageView new];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 24.0;
    imageView.image = [UIImage imageWithContentsOfFile:self.iconPath];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = self.iconTitle ?: @"Icon";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;

    UILabel *detailLabel = [UILabel new];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.text = self.iconDetail ?: self.iconPath;
    detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    detailLabel.textColor = UIColor.secondaryLabelColor;
    detailLabel.textAlignment = NSTextAlignmentCenter;
    detailLabel.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[imageView, titleLabel, detailLabel]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18.0;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:172.0],
        [imageView.heightAnchor constraintEqualToConstant:172.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40.0],
    ]];
}

@end

@interface OMAOMIconPreviewController ()
@property (nonatomic, copy) NSString *themePath;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *icons;
@end

@implementation OMAOMIconPreviewController

- (instancetype)initWithThemePath:(NSString *)themePath title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _themePath = [themePath copy];
        self.title = title ?: @"Theme Icons";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 72.0;
    [self reloadIcons];
}

- (void)reloadIcons {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *icons = [NSMutableArray array];
    NSDirectoryEnumerator<NSString *> *enumerator = [NSFileManager.defaultManager enumeratorAtPath:self.themePath];
    for (NSString *relative in enumerator) {
        if (![relative.pathExtension.lowercaseString isEqualToString:@"png"]) {
            continue;
        }

        NSString *path = [self.themePath stringByAppendingPathComponent:relative];
        NSString *title = OMAOMPreviewBundleTitle(relative);
        [icons addObject:@{
            @"title": title,
            @"relative": relative,
            @"path": path,
        }];
    }

    [icons sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, NSString *> *left, NSDictionary<NSString *, NSString *> *right) {
        NSComparisonResult titleResult = [left[@"title"] localizedCaseInsensitiveCompare:right[@"title"]];
        if (titleResult != NSOrderedSame) {
            return titleResult;
        }
        return [left[@"relative"] localizedCaseInsensitiveCompare:right[@"relative"]];
    }];
    self.icons = icons;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.icons.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSUInteger count = OMAOMPreviewPNGCountAtPath(self.themePath);
    NSString *name = self.themePath.lastPathComponent.length ? self.themePath.lastPathComponent : @"Theme";
    return [NSString stringWithFormat:@"%@ - %lu PNG", name, (unsigned long)count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.themePath;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IconPreviewCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"IconPreviewCell"];
    }

    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (!self.icons.count) {
        cell.textLabel.text = @"No PNG icons found";
        cell.detailTextLabel.text = @"Choose a theme folder that contains IconBundles or Bundles.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary<NSString *, NSString *> *item = self.icons[indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = OMAOMPreviewRelativePath(item[@"path"], self.themePath);
    UIImage *image = [UIImage imageWithContentsOfFile:item[@"path"]];
    cell.imageView.image = image;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.layer.cornerRadius = 10.0;
    cell.imageView.clipsToBounds = YES;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.icons.count) {
        return;
    }

    NSDictionary<NSString *, NSString *> *item = self.icons[indexPath.row];
    OMAOMIconPreviewImageController *controller = [OMAOMIconPreviewImageController new];
    controller.iconPath = item[@"path"];
    controller.iconTitle = item[@"title"];
    controller.iconDetail = OMAOMPreviewRelativePath(item[@"path"], self.themePath);
    [self.navigationController pushViewController:controller animated:YES];
}

@end
