#import <LegacyComponents/TGOverlayControllerWindow.h>
#import <LegacyComponents/TGOverlayController.h>
#import <LegacyComponents/LegacyComponentsContext.h>
#import <LegacyComponents/TGMediaSelectionContext.h>

@class PGCamera;
@class TGCameraPreviewView;
@class TGMediaSelectionContext;
@class TGMediaEditingContext;
@class TGSuggestionContext;
@class TGVideoEditAdjustments;

typedef enum {
    TGCameraControllerGenericIntent,
    TGCameraControllerPassportIntent,
    TGCameraControllerPassportIdIntent,
    TGCameraControllerPassportMultipleIntent,
    TGCameraControllerAvatarIntent
} TGCameraControllerIntent;

@interface TGCameraControllerWindow : TGOverlayControllerWindow

@end

@interface TGCameraController : TGOverlayController

@property (nonatomic, assign) bool liveUploadEnabled;
@property (nonatomic, assign) bool shouldStoreCapturedAssets;

@property (nonatomic, assign) bool allowCaptions;
@property (nonatomic, assign) bool allowCaptionEntities;
@property (nonatomic, assign) bool allowGrouping;
@property (nonatomic, assign) bool inhibitDocumentCaptions;
@property (nonatomic, assign) bool inhibitMultipleCapture;
@property (nonatomic, assign) bool inhibitMute;
@property (nonatomic, assign) bool hasTimer;
@property (nonatomic, strong) TGSuggestionContext *suggestionContext;
@property (nonatomic, assign) bool shortcut;

@property (nonatomic, strong) NSString *forcedCaption;
@property (nonatomic, strong) NSArray *forcedEntities;

@property (nonatomic, strong) NSString *recipientName;

@property (nonatomic, copy) void(^finishedWithResults)(TGOverlayController *controller, TGMediaSelectionContext *selectionContext, TGMediaEditingContext *editingContext, id<TGMediaSelectableItem> currentItem);
@property (nonatomic, copy) void(^finishedWithPhoto)(TGOverlayController *controller, UIImage *resultImage, NSString *caption, NSArray *entities, NSArray *stickers, NSNumber *timer);
@property (nonatomic, copy) void(^finishedWithVideo)(TGOverlayController *controller, NSURL *videoURL, UIImage *previewImage, NSTimeInterval duration, CGSize dimensions, TGVideoEditAdjustments *adjustments, NSString *caption, NSArray *entities, NSArray *stickers, NSNumber *timer);

@property (nonatomic, copy) CGRect(^beginTransitionOut)(void);
@property (nonatomic, copy) void(^finishedTransitionOut)(void);

- (instancetype)initWithContext:(id<LegacyComponentsContext>)context saveEditedPhotos:(bool)saveEditedPhotos saveCapturedMedia:(bool)saveCapturedMedia;
- (instancetype)initWithContext:(id<LegacyComponentsContext>)context saveEditedPhotos:(bool)saveEditedPhotos saveCapturedMedia:(bool)saveCapturedMedia intent:(TGCameraControllerIntent)intent;
- (instancetype)initWithContext:(id<LegacyComponentsContext>)context saveEditedPhotos:(bool)saveEditedPhotos saveCapturedMedia:(bool)saveCapturedMedia camera:(PGCamera *)camera previewView:(TGCameraPreviewView *)previewView intent:(TGCameraControllerIntent)intent;

+ (NSArray *)resultSignalsForSelectionContext:(TGMediaSelectionContext *)selectionContext editingContext:(TGMediaEditingContext *)editingContext currentItem:(id<TGMediaSelectableItem>)currentItem storeAssets:(bool)storeAssets saveEditedPhotos:(bool)saveEditedPhotos descriptionGenerator:(id (^)(id, NSString *, NSArray *, NSString *))descriptionGenerator;

- (void)beginTransitionInFromRect:(CGRect)rect;
- (void)_dismissTransitionForResultController:(TGOverlayController *)resultController;
- (void)beginTransitionOutWithVelocity:(CGFloat)velocity;

+ (UIInterfaceOrientation)_interfaceOrientationForDeviceOrientation:(UIDeviceOrientation)orientation;

+ (bool)useLegacyCamera;

@end
