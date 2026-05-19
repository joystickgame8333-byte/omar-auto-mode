TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmarAutoIcons
OmarAutoIcons_FILES = Tweak.xm
OmarAutoIcons_CFLAGS = -fobjc-arc
OmarAutoIcons_FRAMEWORKS = UIKit Foundation

BUNDLE_NAME = OmarAutoIconsPrefs
OmarAutoIconsPrefs_FILES = prefs/OAIRootListController.m
OmarAutoIconsPrefs_CFLAGS = -fobjc-arc
OmarAutoIconsPrefs_FRAMEWORKS = UIKit Foundation
OmarAutoIconsPrefs_LDFLAGS = -undefined dynamic_lookup
OmarAutoIconsPrefs_INSTALL_PATH = /Library/PreferenceBundles
OmarAutoIconsPrefs_RESOURCE_DIRS = prefs/Resources

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
