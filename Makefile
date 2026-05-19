TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmarAutoIcons
OmarAutoIcons_FILES = Tweak.xm
OmarAutoIcons_CFLAGS = -fobjc-arc
OmarAutoIcons_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
