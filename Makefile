export THEOS_DEVICE_IP = localhost
export THEOS_DEVICE_PORT = 2222
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LongPressSpeedGlass
LongPressSpeedGlass_FILES = 长按倍速玻璃.xm
LongPressSpeedGlass_FRAMEWORKS = UIKit
LongPressSpeedGlass_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
