TARGET := iphone:clang:9.3:9.0
ARCHS := armv7 arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = StationRemote

StationRemote_FILES = $(wildcard Sources/*.m)
StationRemote_FRAMEWORKS = UIKit
StationRemote_CFLAGS = -fobjc-arc
StationRemote_RESOURCE_FILES = index.html legacy.css

include $(THEOS_MAKE_PATH)/application.mk
