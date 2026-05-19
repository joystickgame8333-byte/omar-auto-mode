#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
#import <spawn.h>

extern char **environ;

static const char *OAINotification = "com.omaralasam.autoicons/preferences.changed";

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
@end

@interface OAIRootListController : PSListController
@end

@implementation OAIRootListController {
    NSArray *_specifiers;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    [super setPreferenceValue:value specifier:specifier];
    notify_post(OAINotification);
}

- (void)applyNow {
    notify_post(OAINotification);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Omar Auto Icons"
                                                                   message:@"Settings sent to SpringBoard."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    pid_t pid;
    const char *sbreload = "/var/jb/usr/bin/sbreload";
    const char *killall = "/var/jb/usr/bin/killall";
    const char *args[] = {sbreload, NULL};

    if (posix_spawn(&pid, sbreload, NULL, NULL, (char * const *)args, environ) != 0) {
        const char *fallbackArgs[] = {killall, "SpringBoard", NULL};
        posix_spawn(&pid, killall, NULL, NULL, (char * const *)fallbackArgs, environ);
    }
}

@end
