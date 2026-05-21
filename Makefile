TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmarThemeSwitcher
OmarThemeSwitcher_FILES = src/Tweak.xm
OmarThemeSwitcher_CFLAGS = -fobjc-arc
OmarThemeSwitcher_FRAMEWORKS = UIKit Foundation

BUNDLE_NAME = OmarThemeSwitcherPrefs
OmarThemeSwitcherPrefs_FILES = prefs/OTRootListController.m prefs/OTThemePickerController.m
OmarThemeSwitcherPrefs_CFLAGS = -fobjc-arc
OmarThemeSwitcherPrefs_FRAMEWORKS = UIKit Foundation
OmarThemeSwitcherPrefs_LDFLAGS = -undefined dynamic_lookup
OmarThemeSwitcherPrefs_INSTALL_PATH = /Library/PreferenceBundles
OmarThemeSwitcherPrefs_RESOURCE_DIRS = prefs/Resources

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
