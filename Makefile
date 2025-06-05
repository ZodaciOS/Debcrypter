export TARGET = iphone:clang:latest:latest
export ARCHS = arm64
export INSTALL_TARGET_PROCESSES = none
export PACKAGE_VERSION = 0.0.1

include $(THEOS)/makefiles/common.mk

TOOL_NAME = DebGrabber
DebGrabber_FILES = main.mm
DebGrabber_INSTALL_PATH = /var/jb/usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
