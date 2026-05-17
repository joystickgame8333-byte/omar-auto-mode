#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

extern NSString *const OMAOMPreferencesIdentifier;
extern NSString *const OMAOMApplyNotification;
extern NSString *const OMAOMPreferencesChangedNotification;

NSString *OMAOMRootPath(void);
NSString *OMAOMActiveIconsPath(void);
NSString *OMAOMIconThemesPath(void);
NSString *OMAOMWallpapersPath(void);
NSString *OMAOMDefaultPathForKey(NSString *key);
NSArray<NSString *> *OMAOMCandidateIconPathsForBundleIdentifier(NSString *bundleIdentifier, NSString *themePath);
NSString *_Nullable OMAOMExistingIconPathForBundleIdentifier(NSString *bundleIdentifier, NSString *themePath);

id _Nullable OMAOMPreference(NSString *key);
void OMAOMSetPreference(NSString *key, id value);
void OMAOMSetPreferenceSilently(NSString *key, id value);
BOOL OMAOMBoolPreference(NSString *key, BOOL fallback);
NSString *OMAOMStringPreference(NSString *key, NSString *fallback);

void OMAOMEnsureDirectories(void);
void OMAOMPostDarwinNotification(NSString *name);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
