#import "YTLitePlus.h"

NSBundle *YTLitePlusBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
 	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YTLitePlus" ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/YTLitePlus.bundle")];
    });
    return bundle;
}
NSBundle *tweakBundle = YTLitePlusBundle();

// Keychain fix
static NSString *accessGroupID() {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
                           @"bundleSeedID", kSecAttrAccount,
                           @"", kSecAttrService,
                           (id)kCFBooleanTrue, kSecReturnAttributes,
                           nil];
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound)
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status != errSecSuccess)
            return nil;
    NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];

    return accessGroup;
}

# pragma mark - Tweaks

// Activate FLEX
%hook YTAppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    BOOL didFinishLaunching = %orig;
	if (IsEnabled(@"flex_enabled")) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }
    return didFinishLaunching;
}
- (void)appWillResignActive:(id)arg1 {
    %orig;
	if (IsEnabled(@"flex_enabled")) {
        [[%c(FLEXManager) performSelector:@selector(sharedManager)] performSelector:@selector(showExplorer)];
    }
}
%end


/* TEMP-DISABLED
// Fix Google Sign in by @PoomSmart, @level3tjg & Dayanch96 (qnblackcat/uYouPlus#684)
BOOL isSelf() {
    NSArray *address = [NSThread callStackReturnAddresses];
    Dl_info info = {0};
    if (dladdr((void *)[address[2] longLongValue], &info) == 0) return NO;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    return [path hasPrefix:NSBundle.mainBundle.bundlePath];
}
%hook NSBundle
- (NSString *)bundleIdentifier {
    return isSelf() ? "com.google.ios.youtube" : %orig;
}
- (NSDictionary *)infoDictionary {
    NSDictionary *dict = %orig;
    if (!isSelf())
        return %orig;
    NSMutableDictionary *info = [dict mutableCopy];
    if (info[@"CFBundleIdentifier"]) info[@"CFBundleIdentifier"] = @"com.google.ios.youtube";
    if (info[@"CFBundleDisplayName"]) info[@"CFBundleDisplayName"] = @"YouTube";
    if (info[@"CFBundleName"]) info[@"CFBundleName"] = @"YouTube";
    return info;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (!isSelf())
        return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return @"com.google.ios.youtube";
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return @"YouTube";
    return %orig;
}
%end
*/

// Skips content warning before playing *some videos - @PoomSmart
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { [self confirmAlertDidPressConfirm]; }
%end


// A/B flags
%hook YTColdConfig 
- (BOOL)respectDeviceCaptionSetting { return NO; } // YouRememberCaption: https://poomsmart.github.io/repo/depictions/youremembercaption.html
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; } // Swipe right to dismiss the right panel in fullscreen mode
- (BOOL)commercePlatformClientEnablePopupWebviewInWebviewDialogController { return NO;}
%end

// Disable fullscreen engagement overlay - @bhackel
%group gDisableEngagementOverlay
%hook YTFullscreenEngagementOverlayController
- (void)setEnabled:(BOOL)enabled {
    %orig(NO);
}
%end
%end


// YTTapToSeek - https://github.com/bhackel/YTTapToSeek
%group gYTTapToSeek
    %hook YTInlinePlayerBarContainerView
    - (void)didPressScrubber:(id)arg1 {
        %orig;
        // Get access to the seekToTime method
        YTMainAppVideoPlayerOverlayViewController *mainAppController = [self.delegate valueForKey:@"_delegate"];
        YTPlayerViewController *playerViewController = [mainAppController valueForKey:@"parentViewController"];
        // Get the X position of this tap from arg1
        UIGestureRecognizer *gestureRecognizer = (UIGestureRecognizer *)arg1;
        CGPoint location = [gestureRecognizer locationInView:self];
        CGFloat x = location.x;
        // Get the associated proportion of time using scrubRangeForScrubX
        double timestampFraction = [self scrubRangeForScrubX:x];
        // Get the timestamp from the fraction
        double timestamp = [mainAppController totalTime] * timestampFraction;
        // Jump to the timestamp
        [playerViewController seekToTime:timestamp];
    }
    %end
%end


# pragma mark - ctor
%ctor {
    %init;
    // Access YouGroupSettings methods
    dlopen([[NSString stringWithFormat:@"%@/Frameworks/YouGroupSettings.dylib", [[NSBundle mainBundle] bundlePath]] UTF8String], RTLD_LAZY);
    // Access YouTube Plus methods
    dlopen([[NSString stringWithFormat:@"%@/Frameworks/YTLite.dylib",           [[NSBundle mainBundle] bundlePath]] UTF8String], RTLD_LAZY);

    if (IsEnabled(@"YTTapToSeek_enabled")) {
        %init(gYTTapToSeek);
    }
    if (IsEnabled(@"disableEngagementOverlay_enabled")) {
        %init(gDisableEngagementOverlay);
    }
}
