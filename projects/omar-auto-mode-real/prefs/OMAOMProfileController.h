#import <UIKit/UIKit.h>

@interface OMAOMProfileController : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
- (instancetype)initWithMode:(NSString *)mode title:(NSString *)title;
@end
