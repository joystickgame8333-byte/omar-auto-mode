#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
#import <spawn.h>

extern char **environ;

static const char *OTPreferencesChanged = "com.omaralasam.themeswitcher/preferences.changed";

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
@end

@interface OTRootListController : PSListController
@end

@implementation OTRootListController {
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
    notify_post(OTPreferencesChanged);
}

- (void)applyNow {
    notify_post(OTPreferencesChanged);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Omar Theme Switcher"
                                                                   message:@"Sent to SpringBoard. SnowBoard will refresh if the selected theme needs to change."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openSnowBoard {
    NSURL *url = [NSURL URLWithString:@"prefs:root=SnowBoard"];
    UIApplication *application = UIApplication.sharedApplication;
    if ([application canOpenURL:url]) {
        [application openURL:url options:@{} completionHandler:nil];
    }
}

- (void)respring {
    pid_t pid = 0;
    const char *sbreload = "/var/jb/usr/bin/sbreload";
    const char *fallback = "/var/jb/usr/bin/killall";
    const char *args[] = {sbreload, NULL};

    if (posix_spawn(&pid, sbreload, NULL, NULL, (char * const *)args, environ) != 0) {
        const char *fallbackArgs[] = {fallback, "SpringBoard", NULL};
        posix_spawn(&pid, fallback, NULL, NULL, (char * const *)fallbackArgs, environ);
    }
}

@end
