#import <LegacyComponents/TGNavigationController.h>
#import <LegacyComponents/LegacyComponentsContext.h>

#import <LegacyComponents/TGMediaAssetsLibrary.h>
#import <LegacyComponents/TGSuggestionContext.h>

@class TGMediaAssetsPickerController;
@class TGViewController;

typedef enum
{
    TGMediaAssetsControllerSendMediaIntent,
    TGMediaAssetsControllerSendFileIntent,
    TGMediaAssetsControllerSetProfilePhotoIntent,
    TGMediaAssetsControllerSetCustomWallpaperIntent,
    TGMediaAssetsControllerPassportIntent,
    TGMediaAssetsControllerPassportMultipleIntent
} TGMediaAssetsControllerIntent;

@interface TGMediaAssetsPallete : NSObject

@property (nonatomic, readonly) bool isDark;
@property (nonatomic, readonly) UIColor *backgroundColor;
@property (nonatomic, readonly) UIColor *selectionColor;
@property (nonatomic, readonly) UIColor *separatorColor;
@property (nonatomic, readonly) UIColor *textColor;
@property (nonatomic, readonly) UIColor *secondaryTextColor;
@property (nonatomic, readonly) UIColor *accentColor;
@property (nonatomic, readonly) UIColor *barBackgroundColor;
@property (nonatomic, readonly) UIColor *barSeparatorColor;
@property (nonatomic, readonly) UIColor *navigationTitleColor;
@property (nonatomic, readonly) UIImage *badge;
@property (nonatomic, readonly) UIColor *badgeTextColor;
@property (nonatomic, readonly) UIImage *sendIconImage;

@property (nonatomic, readonly) UIColor *maybeAccentColor;

+ (instancetype)palleteWithDark:(bool)dark backgroundColor:(UIColor *)backgroundColor selectionColor:(UIColor *)selectionColor separatorColor:(UIColor *)separatorColor textColor:(UIColor *)textColor secondaryTextColor:(UIColor *)secondaryTextColor accentColor:(UIColor *)accentColor barBackgroundColor:(UIColor *)barBackgroundColor barSeparatorColor:(UIColor *)barSeparatorColor navigationTitleColor:(UIColor *)navigationTitleColor badge:(UIImage *)badge badgeTextColor:(UIColor *)badgeTextColor sendIconImage:(UIImage *)sendIconImage maybeAccentColor:(UIColor *)maybeAccentColor;

@end

@interface TGMediaAssetsController : TGNavigationController

@property (nonatomic, strong) TGMediaAssetsPallete *pallete;

@property (nonatomic, readonly) TGMediaEditingContext *editingContext;
@property (nonatomic, readonly) TGMediaSelectionContext *selectionContext;
@property (nonatomic, strong) TGSuggestionContext *suggestionContext;
@property (nonatomic, assign) bool localMediaCacheEnabled;
@property (nonatomic, assign) bool captionsEnabled;
@property (nonatomic, assign) bool allowCaptionEntities;
@property (nonatomic, assign) bool inhibitDocumentCaptions;
@property (nonatomic, assign) bool shouldStoreAssets;
@property (nonatomic, assign) bool hasTimer;
@property (nonatomic, assign) bool onlyCrop;
@property (nonatomic, assign) bool inhibitMute;

@property (nonatomic, assign) bool liveVideoUploadEnabled;
@property (nonatomic, assign) bool shouldShowFileTipIfNeeded;

@property (nonatomic, strong) NSString *recipientName;

@property (nonatomic, copy) NSDictionary *(^descriptionGenerator)(id, NSString *, NSArray *, NSString *);
@property (nonatomic, copy) void (^avatarCompletionBlock)(UIImage *image);
@property (nonatomic, copy) void (^completionBlock)(NSArray *signals);
@property (nonatomic, copy) void (^singleCompletionBlock)(id<TGMediaEditableItem> item, TGMediaEditingContext *editingContext);
@property (nonatomic, copy) void (^dismissalBlock)(void);

@property (nonatomic, copy) TGViewController *(^requestSearchController)(void);

@property (nonatomic, readonly) TGMediaAssetsPickerController *pickerController;
@property (nonatomic, readonly) bool allowGrouping;

- (UIBarButtonItem *)rightBarButtonItem;

- (NSArray *)resultSignalsWithCurrentItem:(TGMediaAsset *)currentItem descriptionGenerator:(id (^)(id, NSString *, NSArray *, NSString *))descriptionGenerator;

- (void)completeWithAvatarImage:(UIImage *)image;
- (void)completeWithCurrentItem:(TGMediaAsset *)currentItem;

+ (instancetype)controllerWithContext:(id<LegacyComponentsContext>)context assetGroup:(TGMediaAssetGroup *)assetGroup intent:(TGMediaAssetsControllerIntent)intent recipientName:(NSString *)recipientName saveEditedPhotos:(bool)saveEditedPhotos allowGrouping:(bool)allowGrouping;
+ (instancetype)controllerWithContext:(id<LegacyComponentsContext>)context assetGroup:(TGMediaAssetGroup *)assetGroup intent:(TGMediaAssetsControllerIntent)intent recipientName:(NSString *)recipientName saveEditedPhotos:(bool)saveEditedPhotos allowGrouping:(bool)allowGrouping inhibitSelection:(bool)inhibitSelection;

+ (TGMediaAssetType)assetTypeForIntent:(TGMediaAssetsControllerIntent)intent;

+ (NSArray *)resultSignalsForSelectionContext:(TGMediaSelectionContext *)selectionContext editingContext:(TGMediaEditingContext *)editingContext intent:(TGMediaAssetsControllerIntent)intent currentItem:(TGMediaAsset *)currentItem storeAssets:(bool)storeAssets useMediaCache:(bool)useMediaCache descriptionGenerator:(id (^)(id, NSString *, NSArray *, NSString *))descriptionGenerator saveEditedPhotos:(bool)saveEditedPhotos;

@end
