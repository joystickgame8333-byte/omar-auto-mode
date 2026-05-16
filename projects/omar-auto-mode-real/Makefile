ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmarAutoMode
OmarAutoMode_FILES = Tweak/OmarAutoMode.xm Shared/OMAOMShared.m
OmarAutoMode_CFLAGS = -fobjc-arc -Wall
OmarAutoMode_FRAMEWORKS = UIKit Foundation CoreFoundation

SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

