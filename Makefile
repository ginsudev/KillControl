ARCHS = arm64 arm64e
THEOS_DEVICE_IP = root@localhost -p 2222
INSTALL_TARGET_PROCESSES = SpringBoard
TARGET = iphone:clang:14.4:14
PACKAGE_VERSION = 1.0.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KillControl

KillControl_PRIVATE_FRAMEWORKS = SpringBoard SpringBoardServices
KillControl_FILES = $(shell find Sources/KillControl -name '*.swift') $(shell find Sources/KillControlC -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
KillControl_SWIFTFLAGS = -ISources/KillControlC/include
KillControl_CFLAGS = -fobjc-arc -ISources/KillControlC/include

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += killcontrol
include $(THEOS_MAKE_PATH)/aggregate.mk
