ARCHS = armv7
TARGET = iphone:clang:10.3:6.0
TWEAK_NAME = MusicBackgroundEnhancer
MusicBackgroundEnhancer_FILES = Tweak.m
MusicBackgroundEnhancer_FRAMEWORKS = UIKit Foundation AVFoundation
MusicBackgroundEnhancer_CFLAGS = -fobjc-arc
MusicBackgroundEnhancer_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
