include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OmarAutoModePrefs
OmarAutoModePrefs_FILES = OMAOMRootListController.m OMAOMIconPreviewController.m OMAOMProfileController.m OMAOMThemePickerController.m ../Shared/OMAOMShared.m
OmarAutoModePrefs_INSTALL_PATH = /Library/PreferenceBundles
OmarAutoModePrefs_CFLAGS = -fobjc-arc -Wall -F$(THEOS_PROJECT_DIR)/Frameworks
OmarAutoModePrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
OmarAutoModePrefs_PRIVATE_FRAMEWORKS = Preferences
OmarAutoModePrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/Frameworks
OmarAutoModePrefs_RESOURCE_FILES = Root.plist icon.png icon@2x.png icon@3x.png

include $(THEOS_MAKE_PATH)/bundle.mk
