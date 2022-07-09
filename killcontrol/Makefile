ARCHS = arm64 arm64e
TARGET = iphone:clang:14.4:14

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = killcontrol

killcontrol_LIBRARIES = gscommon
killcontrol_EXTRA_FRAMEWORKS = AltList
killcontrol_FILES = $(shell find Sources/killcontrol -name '*.swift') $(shell find Sources/killcontrolC -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
killcontrol_INSTALL_PATH = /Library/PreferenceBundles
killcontrol_SWIFTFLAGS = -ISources/killcontrolC/include
killcontrol_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
