#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/wait.h>

extern char **environ;

static NSString * const OTPrefsPath = @"/var/mobile/Library/Preferences/com.omaralasam.themeswitcher.plist";
static NSString * const OTSnowBoardUtilRootless = @"/var/jb/usr/local/bin/snowboardutil";
static NSString * const OTSnowBoardUtilRootful = @"/usr/local/bin/snowboardutil";
static const char *OTPreferencesChanged = "com.omaralasam.themeswitcher/preferences.changed";

static BOOL OTEnabled = YES;
static BOOL OTUseSystemAppearance = YES;
static NSInteger OTDayStartHour = 6;
static NSInteger OTNightStartHour = 18;
static NSInteger OTCheckInterval = 45;
static NSString *OTDayThemePath = nil;
static NSString *OTNightThemePath = nil;
static NSString *OTLastAppliedMode = nil;
static BOOL OTApplyInProgress = NO;

static NSString *OTStringValue(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *OTSnowBoardUtilPath(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm isExecutableFileAtPath:OTSnowBoardUtilRootless]) return OTSnowBoardUtilRootless;
    if ([fm isExecutableFileAtPath:OTSnowBoardUtilRootful]) return OTSnowBoardUtilRootful;
    return nil;
}

static void OTLoadPreferences(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:OTPrefsPath];
    if (![prefs isKindOfClass:NSDictionary.class]) prefs = @{};

    id enabled = prefs[@"Enabled"];
    OTEnabled = [enabled respondsToSelector:@selector(boolValue)] ? [enabled boolValue] : YES;

    id systemAppearance = prefs[@"UseSystemAppearance"];
    OTUseSystemAppearance = [systemAppearance respondsToSelector:@selector(boolValue)] ? [systemAppearance boolValue] : YES;

    id day = prefs[@"DayStartHour"];
    OTDayStartHour = [day respondsToSelector:@selector(integerValue)] ? [day integerValue] : 6;

    id night = prefs[@"NightStartHour"];
    OTNightStartHour = [night respondsToSelector:@selector(integerValue)] ? [night integerValue] : 18;

    id interval = prefs[@"CheckIntervalSeconds"];
    OTCheckInterval = [interval respondsToSelector:@selector(integerValue)] ? MAX(20, [interval integerValue]) : 45;

    OTDayThemePath = OTStringValue(prefs[@"DayThemePath"]);
    OTNightThemePath = OTStringValue(prefs[@"NightThemePath"]);
    OTLastAppliedMode = OTStringValue(prefs[@"LastAppliedMode"]);
}

static void OTSaveLastAppliedMode(NSString *mode) {
    if (!mode.length) return;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:OTPrefsPath];
    if (![prefs isKindOfClass:NSMutableDictionary.class]) {
        NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:OTPrefsPath];
        prefs = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    }

    prefs[@"LastAppliedMode"] = mode;
    [prefs writeToFile:OTPrefsPath atomically:YES];
    OTLastAppliedMode = mode;
}

static BOOL OTRunSnowBoardUtil(NSArray<NSString *> *arguments, BOOL *themeEnabled) {
    NSString *tool = OTSnowBoardUtilPath();
    if (!tool.length) return NO;

    NSMutableArray<NSString *> *allArguments = [NSMutableArray arrayWithObject:tool];
    [allArguments addObjectsFromArray:arguments];

    NSPipe *pipe = [NSPipe pipe];
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipe.fileHandleForReading.fileDescriptor);

    char **argv = calloc(allArguments.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < allArguments.count; i++) {
        argv[i] = strdup(allArguments[i].UTF8String);
    }

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, tool.fileSystemRepresentation, &actions, NULL, argv, environ);
    for (NSUInteger i = 0; i < allArguments.count; i++) {
        free(argv[i]);
    }
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    [pipe.fileHandleForWriting closeFile];

    NSData *outputData = [pipe.fileHandleForReading readDataToEndOfFile];
    int processStatus = 0;
    if (spawnStatus == 0) waitpid(pid, &processStatus, 0);

    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
    if (themeEnabled) {
        if ([output rangeOfString:@"is enabled" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            *themeEnabled = YES;
        } else if ([output rangeOfString:@"is disabled" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            *themeEnabled = NO;
        }
    }

    return spawnStatus == 0 && WIFEXITED(processStatus);
}

static BOOL OTQueryThemeEnabled(NSString *themePath) {
    BOOL enabled = NO;
    if (!themePath.length) return NO;
    OTRunSnowBoardUtil(@[@"-q", themePath], &enabled);
    return enabled;
}

static BOOL OTToggleThemeWithoutRefresh(NSString *themePath) {
    if (!themePath.length) return NO;
    return OTRunSnowBoardUtil(@[@"-t", themePath], NULL);
}

static void OTRefreshSnowBoard(void) {
    OTRunSnowBoardUtil(@[@"-r"], NULL);
}

static BOOL OTSystemLooksDark(void) {
    if (@available(iOS 12.0, *)) {
        UIUserInterfaceStyle style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        return style == UIUserInterfaceStyleDark;
    }
    return NO;
}

static BOOL OTTimeLooksDark(void) {
    NSDateComponents *components = [NSCalendar.currentCalendar components:NSCalendarUnitHour fromDate:NSDate.date];
    NSInteger hour = components.hour;
    if (OTDayStartHour < OTNightStartHour) {
        return hour >= OTNightStartHour || hour < OTDayStartHour;
    }
    return !(hour >= OTDayStartHour || hour < OTNightStartHour);
}

static NSString *OTCurrentMode(void) {
    return (OTUseSystemAppearance ? OTSystemLooksDark() : OTTimeLooksDark()) ? @"night" : @"day";
}

static void OTApplyIfNeeded(BOOL force) {
    if (OTApplyInProgress) return;
    OTApplyInProgress = YES;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        OTLoadPreferences();

        if (!OTEnabled) {
            OTApplyInProgress = NO;
            return;
        }

        NSString *mode = OTCurrentMode();
        if (!force && [mode isEqualToString:OTLastAppliedMode]) {
            OTApplyInProgress = NO;
            return;
        }

        NSString *target = [mode isEqualToString:@"night"] ? OTNightThemePath : OTDayThemePath;
        NSString *other = [mode isEqualToString:@"night"] ? OTDayThemePath : OTNightThemePath;

        if (!target.length) {
            OTApplyInProgress = NO;
            return;
        }

        BOOL changed = NO;
        if (!OTQueryThemeEnabled(target)) {
            changed = OTToggleThemeWithoutRefresh(target) || changed;
        }

        if (other.length && ![other isEqualToString:target] && OTQueryThemeEnabled(other)) {
            changed = OTToggleThemeWithoutRefresh(other) || changed;
        }

        if (changed || force) {
            OTRefreshSnowBoard();
        }

        OTSaveLastAppliedMode(mode);
        OTApplyInProgress = NO;
    });
}

%ctor {
    @autoreleasepool {
        OTLoadPreferences();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OTApplyIfNeeded(NO);

            [NSTimer scheduledTimerWithTimeInterval:OTCheckInterval repeats:YES block:^(__unused NSTimer *timer) {
                OTApplyIfNeeded(NO);
            }];
        });

        static int notifyToken = 0;
        notify_register_dispatch(OTPreferencesChanged, &notifyToken, dispatch_get_main_queue(), ^(__unused int token) {
            OTApplyIfNeeded(YES);
        });
    }
}
