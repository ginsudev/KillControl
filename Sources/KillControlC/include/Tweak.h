#include <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

#ifndef SPRINGBOARDSERVICES_H_
extern int SBSLaunchApplicationWithIdentifier(CFStringRef identifier, Boolean suspended);
#endif

@interface SBPBAppLayout : NSObject
@end

@interface SBPBDisplayItem : NSObject
@end

@interface SBAppLayout : NSObject
- (SBPBAppLayout *)protobufRepresentation;
@end

@interface SBFluidSwitcherIconImageContainerView : UIView
@end

@interface SBFluidSwitcherItemContainerHeaderView : UIView
@end

@interface SBReusableSnapshotItemContainer : UIView
@property (nonatomic,copy) NSArray * headerItems;
@property (nonatomic,readonly) double killingProgress;
- (void)setHeaderItems:(id)arg1 animated:(BOOL)arg2;
@end

@interface SBMainSwitcherViewController : UIViewController
+ (instancetype)sharedInstanceIfExists;
- (void)_removeAppLayout:(SBAppLayout *)layout forReason:(NSInteger)reason;
- (void)addAppLayoutForDisplayItem:(id)arg1 completion:(/*^block*/id)arg2 ;
- (NSArray<SBAppLayout *>*)appLayoutsForSwitcherContentController:(id)arg1;
- (void)fluidSwitcherGestureManager:(id)arg1 willEndDraggingWindowWithSceneIdentifier:(id)arg2 ;
- (BOOL)switcherContentController:(id)arg1 supportsKillingOfAppLayout:(id)arg2 ;
//New methods:
- (void)killControlKillApps:(NSArray<NSString*>*)apps;
@end

@interface SBLockStateAggregator : NSObject
+ (instancetype)sharedInstance;
- (unsigned long long)lockState;
@end

@interface RBSProcessIdentity : NSObject
@property(readonly, copy, nonatomic) NSString *executablePath;
@property(readonly, copy, nonatomic) NSString *embeddedApplicationIdentifier;
@end

@interface FBProcess : NSObject
@property (nonatomic,readonly) RBSProcessIdentity * identity;
@end

@interface FBProcessExecutionContext : NSObject
@property (nonatomic,copy) RBSProcessIdentity* identity;
@end

@interface FBProcessManager : NSObject
@end

@interface SBDisplayItem : NSObject
+ (instancetype)displayItemWithType:(long long)arg1 bundleIdentifier:(id)arg2 uniqueIdentifier:(id)arg3;
+ (instancetype)applicationDisplayItemWithBundleIdentifier:(id)arg1 sceneIdentifier:(id)arg2;
@end

@interface SBApplication : NSObject
@property (nonatomic,readonly) NSString * bundleIdentifier;
@end

@interface SBMediaController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)nowPlayingApplication;
- (BOOL)isPaused;
@end
