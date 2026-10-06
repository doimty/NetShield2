include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = NetShield2
NetShield2_FILES = main.m NSFilterRemoval.m NSFilterRestart.m NSAppDelegate.m NSDashboard.m NSDashboard+Table.m NSDashboard+Configuration.m NSDashboard+Notifications.m NSHostsImportController.m NSHostsDownload.m ../Shared/NSHostsImport.m ../Shared/NSHostsParser.c ../Shared/NSPolicy.m ../Shared/NSStore.m ../Shared/NSStoreLock.m ../Shared/NSPolicyCache.m
NetShield2_RESOURCE_DIRS = Resources ../Shared/Resources
NetShield2_FRAMEWORKS = UIKit Foundation NetworkExtension UserNotifications UniformTypeIdentifiers
NetShield2_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Werror=unguarded-availability
NetShield2_CODESIGN_FLAGS = -SEntitlements.plist
NetShield2_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk
