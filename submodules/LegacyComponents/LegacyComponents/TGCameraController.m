#import "TGCameraController.h"

#import "LegacyComponentsInternal.h"

#import <objc/runtime.h>

#import <LegacyComponents/UIDevice+PlatformInfo.h>

#import <LegacyComponents/TGPaintUtils.h>
#import <LegacyComponents/TGPhotoEditorUtils.h>
#import <LegacyComponents/TGPhotoEditorAnimation.h>

#import <LegacyComponents/PGCamera.h>
#import <LegacyComponents/PGCameraCaptureSession.h>
#import <LegacyComponents/PGCameraDeviceAngleSampler.h>
#import <LegacyComponents/PGCameraVolumeButtonHandler.h>

#import <LegacyComponents/TGCameraPreviewView.h>
#import <LegacyComponents/TGCameraMainPhoneView.h>
#import <LegacyComponents/TGCameraMainTabletView.h>
#import "TGCameraFocusCrosshairsControl.h"

#import <LegacyComponents/TGFullscreenContainerView.h>
#import <LegacyComponents/TGPhotoEditorController.h>

#import <LegacyComponents/TGModernGalleryController.h>
#import <LegacyComponents/TGMediaPickerGalleryModel.h>
#import <LegacyComponents/TGMediaPickerGalleryPhotoItem.h>
#import <LegacyComponents/TGMediaPickerGalleryVideoItem.h>
#import <LegacyComponents/TGMediaPickerGalleryVideoItemView.h>
#import <LegacyComponents/TGModernGalleryVideoView.h>

#import "TGMediaVideoConverter.h"
#import <LegacyComponents/TGMediaAssetImageSignals.h>
#import <LegacyComponents/PGPhotoEditorValues.h>
#import <LegacyComponents/TGVideoEditAdjustments.h>
#import <LegacyComponents/TGPaintingData.h>
#import <LegacyComponents/UIImage+TGMediaEditableItem.h>
#import <LegacyComponents/AVURLAsset+TGMediaItem.h>

#import <LegacyComponents/TGModernGalleryZoomableScrollViewSwipeGestureRecognizer.h>

#import <LegacyComponents/TGMediaAssetsLibrary.h>

#import <LegacyComponents/TGTimerTarget.h>

#import <LegacyComponents/TGMenuSheetController.h>

#import "TGMediaPickerGallerySelectedItemsModel.h"
#import "TGCameraCapturedPhoto.h"
#import "TGCameraCapturedVideo.h"

#import <LegacyComponents/TGAnimationUtils.h>

const CGFloat TGCameraSwipeMinimumVelocity = 600.0f;
const CGFloat TGCameraSwipeVelocityThreshold = 700.0f;
const CGFloat TGCameraSwipeDistanceThreshold = 128.0f;
const NSTimeInterval TGCameraMinimumClipDuration = 4.0f;

@implementation TGCameraControllerWindow

static CGPoint TGCameraControllerClampPointToScreenSize(__unused id self, __unused SEL _cmd, CGPoint point)
{
    CGSize screenSize = TGScreenSize();
    return CGPointMake(MAX(0, MIN(point.x, screenSize.width)), MAX(0, MIN(point.y, screenSize.height)));
}

+ (void)initialize
{
    static bool initialized = false;
    if (!initialized)
    {
        initialized = true;
        
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone && (iosMajorVersion() > 8 || (iosMajorVersion() == 8 && iosMinorVersion() >= 3)))
        {
            FreedomDecoration instanceDecorations[] =
            {
                { .name = 0x4ea0b831U,
                    .imp = (IMP)&TGCameraControllerClampPointToScreenSize,
                    .newIdentifier = FreedomIdentifierEmpty,
                    .newEncoding = FreedomIdentifierEmpty
                }
            };
            
            freedomClassAutoDecorate(0x913b3af6, NULL, 0, instanceDecorations, sizeof(instanceDecorations) / sizeof(instanceDecorations[0]));
        }
    }
}

@end

@interface TGCameraController () <UIGestureRecognizerDelegate>
{
    bool _standalone;
    
    TGCameraControllerIntent _intent;
    PGCamera *_camera;
    PGCameraVolumeButtonHandler *_buttonHandler;
    
    UIView *_autorotationCorrectionView;
    
    UIView *_backgroundView;
    TGCameraPreviewView *_previewView;
    TGCameraMainView *_interfaceView;
    UIView *_overlayView;
    TGCameraFocusCrosshairsControl *_focusControl;
    
    TGModernGalleryVideoView *_segmentPreviewView;
    bool _previewingSegment;
    
    UISwipeGestureRecognizer *_photoSwipeGestureRecognizer;
    UISwipeGestureRecognizer *_videoSwipeGestureRecognizer;
    TGModernGalleryZoomableScrollViewSwipeGestureRecognizer *_panGestureRecognizer;
    UIPinchGestureRecognizer *_pinchGestureRecognizer;
    
    CGFloat _dismissProgress;
    bool _dismissing;
    bool _finishedWithResult;
    
    TGMediaPickerGallerySelectedItemsModel *_selectedItemsModel;
    NSMutableArray<id<TGMediaEditableItem, TGMediaSelectableItem>> *_items;
    TGMediaEditingContext *_editingContext;
    TGMediaSelectionContext *_selectionContext;
    
    NSTimer *_switchToVideoTimer;
    NSTimer *_startRecordingTimer;
    bool _recordingByShutterHold;
    bool _stopRecordingOnRelease;
    bool _shownMicrophoneAlert;
    
    id<LegacyComponentsContext> _context;
    bool _saveEditedPhotos;
    bool _saveCapturedMedia;
    
    bool _shutterIsBusy;
}
@end

@implementation TGCameraController

- (instancetype)initWithContext:(id<LegacyComponentsContext>)context saveEditedPhotos:(bool)saveEditedPhotos saveCapturedMedia:(bool)saveCapturedMedia
{
    return [self initWithContext:context saveEditedPhotos:saveEditedPhotos saveCapturedMedia:saveCapturedMedia intent:TGCameraControllerGenericIntent];
}

- (instancetype)initWithContext:(id<LegacyComponentsContext>)context saveEditedPhotos:(bool)saveEditedPhotos saveCapturedMedia:(bool)saveCapturedMedia intent:(TGCameraControllerIntent)intent
{
    return [self initWithContext:context saveEditedPhotos:saveEditedPhotos saveCapturedMedia:saveCapturedMedia camera:[[PGCamera alloc] init] previewView:nil intent:intent];
}

- (instancetype)initWithContext:(id<LegacyComponentsContext>)context saveEditedPhotos:(bool)saveEditedPhotos saveCapturedMedia:(bool)saveCapturedMedia camera:(PGCamera *)camera previewView:(TGCameraPreviewView *)previewView intent:(TGCameraControllerIntent)intent
{
    self = [super initWithContext:context];
    if (self != nil)
    {
        _context = context;
        if (previewView == nil)
            _standalone = true;
        _intent = intent;
        _camera = camera;
        _previewView = previewView;
        
        _items = [[NSMutableArray alloc] init];
        
        if (_intent != TGCameraControllerGenericIntent)
            _allowCaptions = false;
        _saveEditedPhotos = saveEditedPhotos;
        _saveCapturedMedia = saveCapturedMedia;
    }
    return self;
}

- (void)dealloc
{
    _camera.beganModeChange = nil;
    _camera.finishedModeChange = nil;
    _camera.beganPositionChange = nil;
    _camera.finishedPositionChange = nil;
    _camera.beganAdjustingFocus = nil;
    _camera.finishedAdjustingFocus = nil;
    _camera.flashActivityChanged = nil;
    _camera.flashAvailabilityChanged = nil;
    _camera.beganVideoRecording = nil;
    _camera.finishedVideoRecording = nil;
    _camera.captureInterrupted = nil;
    _camera.requestedCurrentInterfaceOrientation = nil;
    _camera.deviceAngleSampler.deviceOrientationChanged = nil;

    PGCamera *camera = _camera;
    if (_finishedWithResult || _standalone)
        [camera stopCaptureForPause:false completion:nil];
    
    [[[LegacyComponentsGlobals provider] applicationInstance] setIdleTimerDisabled:false];
}

- (void)loadView
{
    [super loadView];
    object_setClass(self.view, [TGFullscreenContainerView class]);
    
    CGSize screenSize = TGScreenSize();
    CGRect screenBounds = CGRectMake(0, 0, screenSize.width, screenSize.height);
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone)
        self.view.frame = screenBounds;
    
    _autorotationCorrectionView = [[UIView alloc] initWithFrame:screenBounds];
    _autorotationCorrectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_autorotationCorrectionView];
        
    _backgroundView = [[UIView alloc] initWithFrame:screenBounds];
    _backgroundView.backgroundColor = [UIColor blackColor];
    [_autorotationCorrectionView addSubview:_backgroundView];
    
    if (_previewView == nil)
    {
        _previewView = [[TGCameraPreviewView alloc] initWithFrame:[TGCameraController _cameraPreviewFrameForScreenSize:screenSize mode:PGCameraModePhoto]];
        [_camera attachPreviewView:_previewView];
        [_autorotationCorrectionView addSubview:_previewView];
    }
    
    _overlayView = [[UIView alloc] initWithFrame:screenBounds];
    _overlayView.clipsToBounds = true;
    _overlayView.frame = [TGCameraController _cameraPreviewFrameForScreenSize:screenSize mode:_camera.cameraMode];
    [_autorotationCorrectionView addSubview:_overlayView];
    
    UIInterfaceOrientation interfaceOrientation = [[LegacyComponentsGlobals provider] applicationStatusBarOrientation];
    
    if (interfaceOrientation == UIInterfaceOrientationPortrait)
        interfaceOrientation = [TGCameraController _interfaceOrientationForDeviceOrientation:_camera.deviceAngleSampler.deviceOrientation];
    
    __weak TGCameraController *weakSelf = self;
    _focusControl = [[TGCameraFocusCrosshairsControl alloc] initWithFrame:_overlayView.bounds];
    _focusControl.enabled = (_camera.supportsFocusPOI || _camera.supportsExposurePOI);
    _focusControl.stopAutomatically = (_focusControl.enabled && !_camera.supportsFocusPOI);
    _focusControl.previewView = _previewView;
    _focusControl.focusPOIChanged = ^(CGPoint point)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera setFocusPoint:point];
    };
    _focusControl.beganExposureChange = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera beginExposureTargetBiasChange];
    };
    _focusControl.exposureChanged = ^(CGFloat value)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera setExposureTargetBias:value];
    };
    _focusControl.endedExposureChange = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera endExposureTargetBiasChange];
    };
    [_focusControl setInterfaceOrientation:interfaceOrientation animated:false];
    [_overlayView addSubview:_focusControl];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        _panGestureRecognizer = [[TGModernGalleryZoomableScrollViewSwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panGestureRecognizer.delegate = self;
        _panGestureRecognizer.delaysTouchesBegan = true;
        _panGestureRecognizer.cancelsTouchesInView = false;
        [_overlayView addGestureRecognizer:_panGestureRecognizer];
    }
    
    _pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    _pinchGestureRecognizer.delegate = self;
    [_overlayView addGestureRecognizer:_pinchGestureRecognizer];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        _interfaceView = [[TGCameraMainPhoneView alloc] initWithFrame:screenBounds];
        [_interfaceView setInterfaceOrientation:interfaceOrientation animated:false];
    }
    else
    {
        _interfaceView = [[TGCameraMainTabletView alloc] initWithFrame:screenBounds];
        [_interfaceView setInterfaceOrientation:interfaceOrientation animated:false];
        
        CGSize referenceSize = [self referenceViewSizeForOrientation:interfaceOrientation];
        if (referenceSize.width > referenceSize.height)
            referenceSize = CGSizeMake(referenceSize.height, referenceSize.width);
        
        _interfaceView.transform = CGAffineTransformMakeRotation(TGRotationForInterfaceOrientation(interfaceOrientation));
        _interfaceView.frame = CGRectMake(0, 0, referenceSize.width, referenceSize.height);
    }
    if (_intent == TGCameraControllerPassportIdIntent)
        [_interfaceView setDocumentFrameHidden:false];
    _selectedItemsModel = [[TGMediaPickerGallerySelectedItemsModel alloc] initWithSelectionContext:nil items:[_items copy]];
    [_interfaceView setSelectedItemsModel:_selectedItemsModel];
    _selectedItemsModel.selectionUpdated = ^(bool reload, bool incremental, bool add, NSInteger index)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_interfaceView updateSelectedPhotosView:reload incremental:incremental add:add index:index];
        NSInteger count = strongSelf->_items.count;
        [strongSelf->_interfaceView updateSelectionInterface:count counterVisible:count > 0 animated:true];
    };
    _interfaceView.thumbnailSignalForItem = ^SSignal *(id item)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
            return [strongSelf _signalForItem:item];
        return nil;
    };
    _interfaceView.requestedVideoRecordingDuration = ^NSTimeInterval
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return 0.0;
        
        return strongSelf->_camera.videoRecordingDuration;
    };
    
    _interfaceView.cameraFlipped = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera togglePosition];
    };
    
    _interfaceView.cameraShouldLeaveMode = ^bool(__unused PGCameraMode mode)
    {
        return true;
    };
    _interfaceView.cameraModeChanged = ^(PGCameraMode mode)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera setCameraMode:mode];
    };
    
    _interfaceView.flashModeChanged = ^(PGCameraFlashMode mode)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_camera setFlashMode:mode];
    };
    
    _interfaceView.shutterPressed = ^(bool fromHardwareButton)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if (fromHardwareButton)
            [strongSelf->_interfaceView setShutterButtonHighlighted:true];
        
        [strongSelf shutterPressed];
    };
        
    _interfaceView.shutterReleased = ^(bool fromHardwareButton)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if (fromHardwareButton)
            [strongSelf->_interfaceView setShutterButtonHighlighted:false];
        
        if (strongSelf->_previewView.hidden)
            return;
        
        [strongSelf shutterReleased];
    };
    
    _interfaceView.cancelPressed = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
            [strongSelf cancelPressed];
    };
    _interfaceView.resultPressed = ^(NSInteger index)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
            [strongSelf presentResultControllerForItem:index == -1 ? nil : strongSelf->_items[index] completion:nil];
    };
    _interfaceView.itemRemoved = ^(NSInteger index)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            id item = [strongSelf->_items objectAtIndex:index];
            [strongSelf->_selectionContext setItem:item selected:false];
            [strongSelf->_items removeObjectAtIndex:index];
            [strongSelf->_selectedItemsModel removeSelectedItem:item];
            [strongSelf->_interfaceView setResults:[strongSelf->_items copy]];
        }
    };
    
    if (_intent != TGCameraControllerGenericIntent)
        [_interfaceView setHasModeControl:false];

    if (iosMajorVersion() >= 11)
    {
        _backgroundView.accessibilityIgnoresInvertColors = true;
        _interfaceView.accessibilityIgnoresInvertColors = true;
        _focusControl.accessibilityIgnoresInvertColors = true;
    }
    
    [_autorotationCorrectionView addSubview:_interfaceView];
    
    _photoSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    _photoSwipeGestureRecognizer.delegate = self;
    [_autorotationCorrectionView addGestureRecognizer:_photoSwipeGestureRecognizer];
    
    _videoSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    _videoSwipeGestureRecognizer.delegate = self;
    [_autorotationCorrectionView addGestureRecognizer:_videoSwipeGestureRecognizer];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        _photoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
        _videoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    }
    else
    {
        _photoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        _videoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
    }
    
    void (^buttonPressed)(void) = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        strongSelf->_interfaceView.shutterPressed(true);
    };

    void (^buttonReleased)(void) = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        strongSelf->_interfaceView.shutterReleased(true);
    };
    
    _buttonHandler = [[PGCameraVolumeButtonHandler alloc] initWithUpButtonPressedBlock:buttonPressed upButtonReleasedBlock:buttonReleased downButtonPressedBlock:buttonPressed downButtonReleasedBlock:buttonReleased];
    
    [self _configureCamera];
}

- (void)_configureCamera
{
    __weak TGCameraController *weakSelf = self;
    _camera.requestedCurrentInterfaceOrientation = ^UIInterfaceOrientation(bool *mirrored)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return UIInterfaceOrientationUnknown;
        
        if (strongSelf->_intent == TGCameraControllerPassportIdIntent)
            return UIInterfaceOrientationPortrait;
        
        if (mirrored != NULL)
        {
            TGCameraPreviewView *previewView = strongSelf->_previewView;
            if (previewView != nil)
                *mirrored = previewView.captureConnection.videoMirrored;
        }
        
        return [strongSelf->_interfaceView interfaceOrientation];
    };
    
    _camera.beganModeChange = ^(PGCameraMode mode, void(^commitBlock)(void))
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        strongSelf->_buttonHandler.ignoring = true;
        
        [strongSelf->_focusControl reset];
        strongSelf->_focusControl.active = false;
        
        strongSelf.view.userInteractionEnabled = false;
        
        PGCameraMode currentMode = strongSelf->_camera.cameraMode;
        bool generalModeNotChanged = (mode == PGCameraModePhoto && currentMode == PGCameraModeSquare) || (mode == PGCameraModeSquare && currentMode == PGCameraModePhoto) || (mode == PGCameraModeVideo && currentMode == PGCameraModeClip) || (mode == PGCameraModeClip && currentMode == PGCameraModeVideo);
        
        if ((mode == PGCameraModeVideo || mode == PGCameraModeClip) && !generalModeNotChanged)
        {
            [[LegacyComponentsGlobals provider] pauseMusicPlayback];
        }
        
        if (generalModeNotChanged)
        {
            if (commitBlock != nil)
                commitBlock();
        }
        else
        {
            strongSelf->_camera.zoomLevel = 0.0f;
            
            [strongSelf->_camera captureNextFrameCompletion:^(UIImage *image)
            {
                if (commitBlock != nil)
                    commitBlock();
                 
                image = TGCameraModeSwitchImage(image, CGSizeMake(image.size.width, image.size.height));
                 
                TGDispatchOnMainThread(^
                {
                    [strongSelf->_previewView beginTransitionWithSnapshotImage:image animated:true];
                });
            }];
        }
    };
    
    _camera.finishedModeChange = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        TGDispatchOnMainThread(^
        {
            [strongSelf->_previewView endTransitionAnimated:true];

            if (!strongSelf->_dismissing)
            {
                strongSelf.view.userInteractionEnabled = true;
                [strongSelf resizePreviewViewForCameraMode:strongSelf->_camera.cameraMode];
                
                strongSelf->_focusControl.active = true;
                [strongSelf->_interfaceView setFlashMode:strongSelf->_camera.flashMode];

                [strongSelf->_buttonHandler enableIn:1.5f];
                
                if (strongSelf->_camera.cameraMode == PGCameraModeVideo && ([PGCamera microphoneAuthorizationStatus] == PGMicrophoneAuthorizationStatusRestricted || [PGCamera microphoneAuthorizationStatus] == PGMicrophoneAuthorizationStatusDenied) && !strongSelf->_shownMicrophoneAlert)
                {
                    [[[LegacyComponentsGlobals provider] accessChecker] checkMicrophoneAuthorizationStatusForIntent:TGMicrophoneAccessIntentVideo alertDismissCompletion:nil];
                    strongSelf->_shownMicrophoneAlert = true;
                }
            }
        });
    };
    
    _camera.beganPositionChange = ^(bool targetPositionHasFlash, bool targetPositionHasZoom, void(^commitBlock)(void))
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_focusControl reset];
        
        [strongSelf->_interfaceView setHasFlash:targetPositionHasFlash];
        [strongSelf->_interfaceView setHasZoom:targetPositionHasZoom];
        strongSelf->_camera.zoomLevel = 0.0f;
        
        strongSelf.view.userInteractionEnabled = false;
        
        [strongSelf->_camera captureNextFrameCompletion:^(UIImage *image)
        {
            if (commitBlock != nil)
                commitBlock();
             
            image = TGCameraPositionSwitchImage(image, CGSizeMake(image.size.width, image.size.height));
             
            TGDispatchOnMainThread(^
            {
                [UIView transitionWithView:strongSelf->_previewView duration:0.4f options:UIViewAnimationOptionTransitionFlipFromLeft | UIViewAnimationOptionCurveEaseOut animations:^
                {
                    [strongSelf->_previewView beginTransitionWithSnapshotImage:image animated:false];
                } completion:^(__unused BOOL finished)
                {
                    strongSelf.view.userInteractionEnabled = true;
                }];
            });
        }];
    };
    
    _camera.finishedPositionChange = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        TGDispatchOnMainThread(^
        {
            [strongSelf->_previewView endTransitionAnimated:true];
            [strongSelf->_interfaceView setZoomLevel:0.0f displayNeeded:false];

            if (strongSelf->_camera.hasFlash && strongSelf->_camera.flashActive)
                [strongSelf->_interfaceView setFlashActive:true];
                                   
            strongSelf->_focusControl.enabled = (strongSelf->_camera.supportsFocusPOI || strongSelf->_camera.supportsExposurePOI);
            strongSelf->_focusControl.stopAutomatically = (strongSelf->_focusControl.enabled && !strongSelf->_camera.supportsFocusPOI);
        });
    };
    
    _camera.beganAdjustingFocus = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_focusControl playAutoFocusAnimation];
    };
    
    _camera.finishedAdjustingFocus = ^
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_focusControl stopAutoFocusAnimation];
    };
    
    _camera.flashActivityChanged = ^(bool active)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if (strongSelf->_camera.flashMode != PGCameraFlashModeAuto)
            active = false;
        
        TGDispatchOnMainThread(^
        {
            if (!strongSelf->_camera.isRecordingVideo)
                [strongSelf->_interfaceView setFlashActive:active];
        });
    };
    
    _camera.flashAvailabilityChanged = ^(bool available)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf->_interfaceView setFlashUnavailable:!available];
    };
    
    _camera.beganVideoRecording = ^(__unused bool moment)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        strongSelf->_focusControl.ignoreAutofocusing = true;
        [strongSelf->_interfaceView setRecordingVideo:true animated:true];
    };
    
    _camera.captureInterrupted = ^(AVCaptureSessionInterruptionReason reason)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps)
            [strongSelf beginTransitionOutWithVelocity:0.0f];
    };
    
    _camera.finishedVideoRecording = ^(__unused bool moment)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        strongSelf->_focusControl.ignoreAutofocusing = false;
        [strongSelf->_interfaceView setFlashMode:PGCameraFlashModeOff];
    };
    
    _camera.deviceAngleSampler.deviceOrientationChanged = ^(UIDeviceOrientation orientation)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        [strongSelf handleDeviceOrientationChangedTo:orientation];
    };
}

#pragma mark - View Life Cycle

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [UIView animateWithDuration:0.3f animations:^
    {
        [_context setApplicationStatusBarAlpha:0.0f];
    }];
    
    [[[LegacyComponentsGlobals provider] applicationInstance] setIdleTimerDisabled:true];
    
    if (!_camera.isCapturing)
        [_camera startCaptureForResume:false completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [UIView animateWithDuration:0.3f animations:^
    {
        [_context setApplicationStatusBarAlpha:1.0f];
    }];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    if ([self shouldCorrectAutorotation])
        [self applyAutorotationCorrectingTransformForOrientation:[[LegacyComponentsGlobals provider] applicationStatusBarOrientation]];
}

- (bool)shouldCorrectAutorotation
{
    return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

- (void)applyAutorotationCorrectingTransformForOrientation:(UIInterfaceOrientation)orientation
{
    CGSize screenSize = TGScreenSize();
    CGRect screenBounds = CGRectMake(0, 0, screenSize.width, screenSize.height);
    
    _autorotationCorrectionView.transform = CGAffineTransformIdentity;
    _autorotationCorrectionView.frame = screenBounds;
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    switch (orientation)
    {
        case UIInterfaceOrientationPortraitUpsideDown:
            transform = CGAffineTransformMakeRotation(M_PI);
            break;
            
        case UIInterfaceOrientationLandscapeLeft:
            transform = CGAffineTransformMakeRotation(M_PI_2);
            break;
            
        case UIInterfaceOrientationLandscapeRight:
            transform = CGAffineTransformMakeRotation(-M_PI_2);
            break;
            
        default:
            break;
    }
    
    _autorotationCorrectionView.transform = transform;
    CGSize bounds = [_context fullscreenBounds].size;
    _autorotationCorrectionView.center = CGPointMake(bounds.width / 2, bounds.height / 2);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
        return UIInterfaceOrientationMaskAll;
    
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
        return true;
    
    return false;
}

- (void)setInterfaceHidden:(bool)hidden animated:(bool)animated
{
    if (animated)
    {
        if (hidden && _interfaceView.alpha < FLT_EPSILON)
            return;

        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @(_interfaceView.alpha);
        animation.toValue = @(hidden ? 0.0f : 1.0f);
        animation.duration = 0.2f;
        [_interfaceView.layer addAnimation:animation forKey:@"opacity"];
        
        _interfaceView.alpha = hidden ? 0.0f : 1.0f;
    }
    else
    {
        [_interfaceView.layer removeAllAnimations];
        _interfaceView.alpha = 0.0f;
    }
}

#pragma mark - 

- (void)startVideoRecording
{
    __weak TGCameraController *weakSelf = self;
    if (_camera.cameraMode == PGCameraModePhoto)
    {
        _switchToVideoTimer = nil;
        
        _camera.onAutoStartVideoRecording = ^
        {
            __strong TGCameraController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            strongSelf->_stopRecordingOnRelease = true;
            
            [strongSelf->_camera startVideoRecordingForMoment:false completion:^(NSURL *outputURL, __unused CGAffineTransform transform, CGSize dimensions, NSTimeInterval duration, bool success)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return;
                
                if (success)
                {
                    TGCameraCapturedVideo *capturedVideo = [[TGCameraCapturedVideo alloc] initWithURL:outputURL];
                    [strongSelf addResultItem:capturedVideo];
                    
                    if (![strongSelf maybePresentResultControllerForItem:capturedVideo completion:nil])
                    {
                        strongSelf->_camera.disabled = false;
                        [strongSelf->_interfaceView setRecordingVideo:false animated:true];
                    }
                }
                else
                {
                    [strongSelf->_interfaceView setRecordingVideo:false animated:false];
                }
            }];
        };
        _camera.autoStartVideoRecording = true;
        
        [_camera setCameraMode:PGCameraModeVideo];
        [_interfaceView setCameraMode:PGCameraModeVideo];
    }
    else if (_camera.cameraMode == PGCameraModeVideo)
    {
        _startRecordingTimer = nil;
        
        [_camera startVideoRecordingForMoment:false completion:^(NSURL *outputURL, __unused CGAffineTransform transform, CGSize dimensions, NSTimeInterval duration, bool success)
        {
            __strong TGCameraController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            if (success)
            {
                TGCameraCapturedVideo *capturedVideo = [[TGCameraCapturedVideo alloc] initWithURL:outputURL];
                [strongSelf addResultItem:capturedVideo];
                
                if (![strongSelf maybePresentResultControllerForItem:capturedVideo completion:nil])
                {
                    strongSelf->_camera.disabled = false;
                    [strongSelf->_interfaceView setRecordingVideo:false animated:true];
                }
            }
            else
            {
                [strongSelf->_interfaceView setRecordingVideo:false animated:false];
            }
        }];

        _stopRecordingOnRelease = true;
    }
}

- (void)shutterPressed
{
    PGCameraMode cameraMode = _camera.cameraMode;
    switch (cameraMode)
    {
        case PGCameraModePhoto:
        {
            if (_intent == TGCameraControllerGenericIntent)
            {
                _switchToVideoTimer = [TGTimerTarget scheduledMainThreadTimerWithTarget:self action:@selector(startVideoRecording) interval:0.25 repeat:false];
            }
        }
            break;
    
        case PGCameraModeVideo:
        {
            if (!_camera.isRecordingVideo)
            {
                _startRecordingTimer = [TGTimerTarget scheduledMainThreadTimerWithTarget:self action:@selector(startVideoRecording) interval:0.25 repeat:false];
            }
            else
            {
                _stopRecordingOnRelease = true;
            }
        }
            break;
            
        case PGCameraModeClip:
        {
        }
            break;
            
        default:
            break;
    }
}

- (void)shutterReleased
{
    [_switchToVideoTimer invalidate];
    _switchToVideoTimer = nil;
    
    [_startRecordingTimer invalidate];
    _startRecordingTimer = nil;
 
    if (_shutterIsBusy)
        return;
    
    __weak TGCameraController *weakSelf = self;
    PGCameraMode cameraMode = _camera.cameraMode;
    if (cameraMode == PGCameraModePhoto || cameraMode == PGCameraModeSquare)
    {
        _camera.disabled = true;

        _shutterIsBusy = true;
        if (![self willPresentResultController])
        {
            TGDispatchAfter(0.35, dispatch_get_main_queue(), ^
            {
                [_previewView blink];
            });
        }
        else
        {
            _buttonHandler.enabled = false;
            [_buttonHandler ignoreEventsFor:1.5f andDisable:true];
        }
        
        [_camera takePhotoWithCompletion:^(UIImage *result, PGCameraShotMetadata *metadata)
        {
            __strong TGCameraController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            TGDispatchOnMainThread(^
            {
                strongSelf->_shutterIsBusy = false;
                
                if (strongSelf->_intent == TGCameraControllerAvatarIntent)
                {
                    [strongSelf presentPhotoResultControllerWithImage:result metadata:metadata completion:^{}];
                }
                else
                {
                    TGCameraCapturedPhoto *capturedPhoto = [[TGCameraCapturedPhoto alloc] initWithImage:result metadata:metadata];
                    [strongSelf addResultItem:capturedPhoto];
                    
                    if (![strongSelf maybePresentResultControllerForItem:capturedPhoto completion:nil])
                        strongSelf->_camera.disabled = false;
                }
            });
        }];
    }
    else if (cameraMode == PGCameraModeVideo)
    {
        if (!_camera.isRecordingVideo)
        {
            [_buttonHandler ignoreEventsFor:1.0f andDisable:false];
            
            [_camera startVideoRecordingForMoment:false completion:^(NSURL *outputURL, __unused CGAffineTransform transform, CGSize dimensions, NSTimeInterval duration, bool success)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return;
                
                if (success)
                {
                    TGCameraCapturedVideo *capturedVideo = [[TGCameraCapturedVideo alloc] initWithURL:outputURL];
                    [strongSelf addResultItem:capturedVideo];
                    
                    if (![strongSelf maybePresentResultControllerForItem:capturedVideo completion:nil])
                    {
                        strongSelf->_camera.disabled = false;
                        [strongSelf->_interfaceView setRecordingVideo:false animated:true];
                    }
                }
                else
                {
                    [strongSelf->_interfaceView setRecordingVideo:false animated:false];
                }
            }];
        }
        else if (_stopRecordingOnRelease)
        {
            _stopRecordingOnRelease = false;
            
            _camera.disabled = true;
            [_camera stopVideoRecording];
            
            [_buttonHandler ignoreEventsFor:1.0f andDisable:[self willPresentResultController]];
        }
    }
}

- (void)cancelPressed
{
    if (_items.count > 0)
    {
        __weak TGCameraController *weakSelf = self;
        
        TGMenuSheetController *controller = [[TGMenuSheetController alloc] initWithContext:_context dark:false];
        controller.dismissesByOutsideTap = true;
        controller.narrowInLandscape = true;
        __weak TGMenuSheetController *weakController = controller;
        
        NSArray *items = @
        [
         [[TGMenuSheetButtonItemView alloc] initWithTitle:TGLocalized(@"Camera.Discard") type:TGMenuSheetButtonTypeDefault action:^
          {
              __strong TGMenuSheetController *strongController = weakController;
              if (strongController == nil)
                  return;
              
              __strong TGCameraController *strongSelf = weakSelf;
              if (strongSelf == nil)
                  return;
              
              [strongController dismissAnimated:true manual:false completion:nil];
              [strongSelf beginTransitionOutWithVelocity:0.0f];
          }],
         [[TGMenuSheetButtonItemView alloc] initWithTitle:TGLocalized(@"Common.Cancel") type:TGMenuSheetButtonTypeCancel action:^
          {
              __strong TGMenuSheetController *strongController = weakController;
              if (strongController != nil)
                  [strongController dismissAnimated:true];
          }]
         ];
        
        [controller setItemViews:items];
        controller.sourceRect = ^
        {
            __strong TGCameraController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return CGRectZero;
            
            UIButton *cancelButton = strongSelf->_interfaceView->_cancelButton;
            return [cancelButton convertRect:cancelButton.bounds toView:strongSelf.view];
        };
        controller.permittedArrowDirections = UIPopoverArrowDirectionAny;
        [controller presentInViewController:self sourceView:self.view animated:true];
    }
    else
    {
        [self beginTransitionOutWithVelocity:0.0f];
    }
}

#pragma mark - Result

- (void)addResultItem:(id<TGMediaEditableItem, TGMediaSelectableItem>)item
{
    [_items addObject:item];
}

- (bool)willPresentResultController
{
    return _items.count == 0 || (_items.count > 0 && (_items.count + 1) % 10 == 0);
}

- (bool)shouldPresentResultController
{
    return _items.count == 1 || (_items.count > 0 && _items.count % 10 == 0);
}

- (bool)maybePresentResultControllerForItem:(id<TGMediaEditableItem, TGMediaSelectableItem>)editableItem completion:(void (^)(void))completion
{
    if ([self shouldPresentResultController])
    {
        [self presentResultControllerForItem:editableItem completion:^
        {
            [_selectedItemsModel addSelectedItem:editableItem];
            [_selectionContext setItem:editableItem selected:true];
            [_interfaceView setResults:[_items copy]];
            if (completion != nil)
                completion();
        }];
        return true;
    }
    else
    {
        [_selectedItemsModel addSelectedItem:editableItem];
        [_selectionContext setItem:editableItem selected:true];
        [_interfaceView setResults:[_items copy]];
        return false;
    }
}

- (NSArray *)prepareGalleryItemsForResults:(void (^)(TGMediaPickerGalleryItem *))enumerationBlock
{
    NSMutableArray *galleryItems = [[NSMutableArray alloc] init];
    for (id<TGMediaEditableItem, TGMediaSelectableItem> item in _items)
    {
        TGMediaPickerGalleryItem<TGModernGallerySelectableItem, TGModernGalleryEditableItem> *galleryItem = nil;
        if ([item isKindOfClass:[TGCameraCapturedPhoto class]])
        {
            galleryItem = [[TGMediaPickerGalleryPhotoItem alloc] initWithAsset:item];
        }
        else if ([item isKindOfClass:[TGCameraCapturedVideo class]])
        {
            galleryItem = [[TGMediaPickerGalleryVideoItem alloc] initWithAsset:item];
        }

        galleryItem.selectionContext = _selectionContext;
        galleryItem.editingContext = _editingContext;
        
        if (enumerationBlock != nil)
            enumerationBlock(galleryItem);
        
        if (galleryItem != nil)
            [galleryItems addObject:galleryItem];
    }
    
    return galleryItems;
}

- (void)presentResultControllerForItem:(id<TGMediaEditableItem, TGMediaSelectableItem>)editableItem completion:(void (^)(void))completion
{
    TGMediaEditingContext *editingContext = _editingContext;
    if (editingContext == nil)
    {
        editingContext = [[TGMediaEditingContext alloc] init];
        if (self.forcedCaption != nil)
            [editingContext setForcedCaption:self.forcedCaption entities:self.forcedEntities];
        _editingContext = editingContext;
        _interfaceView.editingContext = editingContext;
    }
    TGMediaSelectionContext *selectionContext = _selectionContext;
    if (selectionContext == nil)
    {
        selectionContext = [[TGMediaSelectionContext alloc] initWithGroupingAllowed:self.allowGrouping];
        if (self.allowGrouping)
            selectionContext.grouping = ![[[NSUserDefaults standardUserDefaults] objectForKey:@"TG_mediaGroupingDisabled_v0"] boolValue];
        _selectionContext = selectionContext;
    }
    
    if (editableItem == nil)
        editableItem = _items.lastObject;
    
    [[[LegacyComponentsGlobals provider] applicationInstance] setIdleTimerDisabled:false];

    id<LegacyComponentsOverlayWindowManager> windowManager = nil;
    id<LegacyComponentsContext> windowContext = nil;
    windowManager = [_context makeOverlayWindowManager];
    windowContext = [windowManager context];
    
    if (_intent == TGCameraControllerPassportIdIntent)
    {
        TGCameraCapturedPhoto *photo = (TGCameraCapturedPhoto *)editableItem;
        CGSize size = photo.originalSize;
        CGFloat height = size.width * 0.704f;
        PGPhotoEditorValues *values = [PGPhotoEditorValues editorValuesWithOriginalSize:size cropRect:CGRectMake(0, floor((size.height - height) / 2.0f), size.width, height) cropRotation:0.0f cropOrientation:UIImageOrientationUp cropLockedAspectRatio:0.0f cropMirrored:false toolValues:nil paintingData:nil sendAsGif:false];
        
        SSignal *cropSignal = [[photo originalImageSignal:0.0] map:^UIImage *(UIImage *image)
        {
            UIImage *croppedImage = TGPhotoEditorCrop(image, nil, UIImageOrientationUp, 0.0f, values.cropRect, false, TGPhotoEditorResultImageMaxSize, size, true);
            return croppedImage;
        }];
        
        [cropSignal startWithNext:^(UIImage *image)
        {
            CGSize fillSize = TGPhotoThumbnailSizeForCurrentScreen();
            fillSize.width = CGCeil(fillSize.width);
            fillSize.height = CGCeil(fillSize.height);
            
            CGSize size = TGScaleToFillSize(image.size, fillSize);
            
            UIGraphicsBeginImageContextWithOptions(size, true, 0.0f);
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
            
            [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
            
            UIImage *thumbnailImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            [editingContext setAdjustments:values forItem:photo];
            [editingContext setImage:image thumbnailImage:thumbnailImage forItem:photo synchronous:true];
        }];
    }

    __weak TGCameraController *weakSelf = self;
    TGModernGalleryController *galleryController = [[TGModernGalleryController alloc] initWithContext:windowContext];
    galleryController.adjustsStatusBarVisibility = false;
    galleryController.hasFadeOutTransition = true;
    
    __block id<TGModernGalleryItem> focusItem = nil;
    NSArray *galleryItems = [self prepareGalleryItemsForResults:^(TGMediaPickerGalleryItem *item)
    {
        if (focusItem == nil && [item.asset isEqual:editableItem])
        {
            focusItem = item;
            
            if ([item.asset isKindOfClass:[TGCameraCapturedVideo class]])
            {
                AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:((TGCameraCapturedVideo *)item.asset).avAsset];
                generator.appliesPreferredTrackTransform = true;
                generator.maximumSize = CGSizeMake(640.0f, 640.0f);
                CGImageRef imageRef = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];
                UIImage *thumbnailImage = [[UIImage alloc] initWithCGImage:imageRef];
                CGImageRelease(imageRef);
                
                item.immediateThumbnailImage = thumbnailImage;
            }
        }
    }];
    
    bool hasCamera = !self.inhibitMultipleCapture && ((_intent == TGCameraControllerGenericIntent && !_shortcut) || (_intent == TGCameraControllerPassportMultipleIntent));
    TGMediaPickerGalleryModel *model = [[TGMediaPickerGalleryModel alloc] initWithContext:windowContext items:galleryItems focusItem:focusItem selectionContext:_items.count > 1 ? selectionContext : nil editingContext:editingContext hasCaptions:self.allowCaptions allowCaptionEntities:self.allowCaptionEntities hasTimer:self.hasTimer onlyCrop:_intent == TGCameraControllerPassportIntent || _intent == TGCameraControllerPassportIdIntent || _intent == TGCameraControllerPassportMultipleIntent inhibitDocumentCaptions:self.inhibitDocumentCaptions hasSelectionPanel:true hasCamera:hasCamera recipientName:self.recipientName];
    model.inhibitMute = self.inhibitMute;
    model.controller = galleryController;
    model.suggestionContext = self.suggestionContext;
    
    model.willFinishEditingItem = ^(id<TGMediaEditableItem> editableItem, id<TGMediaEditAdjustments> adjustments, id representation, bool hasChanges)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;

        if (hasChanges)
        {
            [editingContext setAdjustments:adjustments forItem:editableItem];
            [editingContext setTemporaryRep:representation forItem:editableItem];
        }
    };

    model.didFinishEditingItem = ^(id<TGMediaEditableItem> editableItem, __unused id<TGMediaEditAdjustments> adjustments, UIImage *resultImage, UIImage *thumbnailImage)
    {
        [editingContext setImage:resultImage thumbnailImage:thumbnailImage forItem:editableItem synchronous:false];
    };

    model.saveItemCaption = ^(id<TGMediaEditableItem> editableItem, NSString *caption, NSArray *entities)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
            [strongSelf->_editingContext setCaption:caption entities:entities forItem:editableItem];
    };

    model.interfaceView.hasSwipeGesture = false;
    galleryController.model = model;
    
    __weak TGModernGalleryController *weakGalleryController = galleryController;
    __weak TGMediaPickerGalleryModel *weakModel = model;

    if (_items.count > 1)
        [model.interfaceView updateSelectionInterface:selectionContext.count counterVisible:(selectionContext.count > 0) animated:false];
    else
        [model.interfaceView updateSelectionInterface:1 counterVisible:false animated:false];
    model.interfaceView.thumbnailSignalForItem = ^SSignal *(id item)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
            return [strongSelf _signalForItem:item];
        return nil;
    };
    model.interfaceView.donePressed = ^(TGMediaPickerGalleryItem *item)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;

        TGMediaPickerGalleryModel *strongModel = weakModel;
        if (strongModel == nil)
            return;

        __strong TGModernGalleryController *strongController = weakGalleryController;
        if (strongController == nil)
            return;

        if ([item isKindOfClass:[TGMediaPickerGalleryVideoItem class]])
        {
            TGMediaPickerGalleryVideoItemView *itemView = (TGMediaPickerGalleryVideoItemView *)[strongController itemViewForItem:item];
            [itemView stop];
            [itemView setPlayButtonHidden:true animated:true];
        }
        
        if (strongSelf->_selectionContext.allowGrouping)
            [[NSUserDefaults standardUserDefaults] setObject:@(!strongSelf->_selectionContext.grouping) forKey:@"TG_mediaGroupingDisabled_v0"];

        if (strongSelf.finishedWithResults != nil)
            strongSelf.finishedWithResults(strongController, strongSelf->_selectionContext, strongSelf->_editingContext, item.asset);
        
        if (strongSelf->_shortcut)
            return;

        [strongSelf _dismissTransitionForResultController:strongController];
    };

    CGSize snapshotSize = TGScaleToFill(CGSizeMake(480, 640), CGSizeMake(self.view.frame.size.width, self.view.frame.size.width));
    UIView *snapshotView = [_previewView snapshotViewAfterScreenUpdates:false];
    snapshotView.contentMode = UIViewContentModeScaleAspectFill;
    snapshotView.frame = CGRectMake(_previewView.center.x - snapshotSize.width / 2, _previewView.center.y - snapshotSize.height / 2, snapshotSize.width, snapshotSize.height);
    snapshotView.hidden = true;
    [_previewView.superview insertSubview:snapshotView aboveSubview:_previewView];

    galleryController.beginTransitionIn = ^UIView *(__unused TGMediaPickerGalleryItem *item, __unused TGModernGalleryItemView *itemView)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            TGModernGalleryController *strongGalleryController = weakGalleryController;
            strongGalleryController.view.alpha = 0.0f;
            [UIView animateWithDuration:0.3f animations:^
             {
                 strongGalleryController.view.alpha = 1.0f;
                 strongSelf->_interfaceView.alpha = 0.0f;
             }];
            return snapshotView;
        }
        return nil;
    };

    galleryController.finishedTransitionIn = ^(__unused TGMediaPickerGalleryItem *item, __unused TGModernGalleryItemView *itemView)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        
        TGMediaPickerGalleryModel *strongModel = weakModel;
        if (strongModel == nil)
            return;

        [strongModel.interfaceView setSelectedItemsModel:strongModel.selectedItemsModel];
        
        [strongSelf->_camera stopCaptureForPause:true completion:nil];

        snapshotView.hidden = true;

        if (completion != nil)
            completion();
    };

    galleryController.beginTransitionOut = ^UIView *(__unused TGMediaPickerGalleryItem *item, __unused TGModernGalleryItemView *itemView)
    {
        __strong TGCameraController *strongSelf = weakSelf;
        if (strongSelf != nil)
        {
            TGMediaPickerGalleryModel *strongModel = weakModel;
            if (strongModel == nil)
                return nil;
            
            [[[LegacyComponentsGlobals provider] applicationInstance] setIdleTimerDisabled:true];

            if (strongSelf->_camera.cameraMode == PGCameraModeVideo)
                [strongSelf->_interfaceView setRecordingVideo:false animated:false];
        
            strongSelf->_buttonHandler.enabled = true;
            [strongSelf->_buttonHandler ignoreEventsFor:2.0f andDisable:false];

            strongSelf->_camera.disabled = false;
            [strongSelf->_camera startCaptureForResume:true completion:nil];

            [UIView animateWithDuration:0.3f delay:0.1f options:UIViewAnimationOptionCurveLinear animations:^
            {
                strongSelf->_interfaceView.alpha = 1.0f;
            } completion:nil];
            
            if (!strongModel.interfaceView.capturing)
            {
                [strongSelf->_items removeAllObjects];
                [strongSelf->_interfaceView setResults:nil];
                [strongSelf->_selectionContext clear];
                [strongSelf->_selectedItemsModel clear];
                
                [strongSelf->_interfaceView updateSelectionInterface:0 counterVisible:false animated:false];
            }

            return snapshotView;
        }
        return nil;
    };

    galleryController.completedTransitionOut = ^
    {
        [snapshotView removeFromSuperview];

        TGModernGalleryController *strongGalleryController = weakGalleryController;
        if (strongGalleryController != nil && strongGalleryController.overlayWindow == nil)
        {
            TGNavigationController *navigationController = (TGNavigationController *)strongGalleryController.navigationController;
            TGOverlayControllerWindow *window = (TGOverlayControllerWindow *)navigationController.view.window;
            if ([window isKindOfClass:[TGOverlayControllerWindow class]])
                [window dismiss];
        }
    };

    TGOverlayController *contentController = galleryController;
    if (_shortcut)
    {
        contentController = [[TGOverlayController alloc] initWithContext:_context];

        TGNavigationController *navigationController = [TGNavigationController navigationControllerWithControllers:@[galleryController]];
        galleryController.navigationBarShouldBeHidden = true;

        [contentController addChildViewController:navigationController];
        [contentController.view addSubview:navigationController.view];
    }

    TGOverlayControllerWindow *controllerWindow = [[TGOverlayControllerWindow alloc] initWithManager:windowManager parentController:self contentController:contentController];
    controllerWindow.hidden = false;
    controllerWindow.windowLevel = self.view.window.windowLevel + 0.0001f;
    galleryController.view.clipsToBounds = true;
}

- (SSignal *)_signalForItem:(id<TGMediaEditableItem>)item
{
    SSignal *assetSignal = [item thumbnailImageSignal];
    if (_editingContext == nil)
        return assetSignal;
    
    return [[_editingContext thumbnailImageSignalForItem:item] mapToSignal:^SSignal *(id result)
    {
        if (result != nil)
            return [SSignal single:result];
        else
            return assetSignal;
    }];
}

#pragma mark - Legacy Photo Result

- (void)presentPhotoResultControllerWithImage:(UIImage *)image metadata:(PGCameraShotMetadata *)metadata completion:(void (^)(void))completion
{
    [[[LegacyComponentsGlobals provider] applicationInstance] setIdleTimerDisabled:false];
 
    if (image == nil || image.size.width < FLT_EPSILON)
    {
        [self beginTransitionOutWithVelocity:0.0f];
        return;
    }
    
    id<LegacyComponentsOverlayWindowManager> windowManager = nil;
    id<LegacyComponentsContext> windowContext = nil;
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        windowManager = [_context makeOverlayWindowManager];
        windowContext = [windowManager context];
    } else {
        windowContext = _context;
    }
    
    __weak TGCameraController *weakSelf = self;
    TGOverlayController *overlayController = nil;
    
    _focusControl.ignoreAutofocusing = true;
    
    switch (_intent)
    {
        case TGCameraControllerAvatarIntent:
        {
            TGPhotoEditorController *controller = [[TGPhotoEditorController alloc] initWithContext:windowContext item:image intent:(TGPhotoEditorControllerFromCameraIntent | TGPhotoEditorControllerAvatarIntent) adjustments:nil caption:nil screenImage:image availableTabs:[TGPhotoEditorController defaultTabsForAvatarIntent] selectedTab:TGPhotoEditorCropTab];
            __weak TGPhotoEditorController *weakController = controller;
            controller.beginTransitionIn = ^UIView *(CGRect *referenceFrame, __unused UIView **parentView)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return nil;
                
                strongSelf->_previewView.hidden = true;
                *referenceFrame = strongSelf->_previewView.frame;
                
                UIImageView *imageView = [[UIImageView alloc] initWithFrame:strongSelf->_previewView.frame];
                imageView.image = image;
                
                return imageView;
            };
            
            controller.beginTransitionOut = ^UIView *(CGRect *referenceFrame, __unused UIView **parentView)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return nil;
                
                CGRect startFrame = CGRectZero;
                if (referenceFrame != NULL)
                {
                    startFrame = *referenceFrame;
                    *referenceFrame = strongSelf->_previewView.frame;
                }
                
                [strongSelf transitionBackFromResultControllerWithReferenceFrame:startFrame];
                
                return strongSelf->_previewView;
            };
            
            controller.didFinishEditing = ^(PGPhotoEditorValues *editorValues, UIImage *resultImage, __unused UIImage *thumbnailImage, bool hasChanges)
            {
                if (!hasChanges)
                    return;
                
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return;
                
                TGDispatchOnMainThread(^
                {
                    if (strongSelf.finishedWithPhoto != nil)
                        strongSelf.finishedWithPhoto(nil, resultImage, nil, nil, nil, nil);
                    
                    if (strongSelf.shouldStoreCapturedAssets)
                    {
                        [strongSelf _savePhotoToCameraRollWithOriginalImage:image editedImage:[editorValues toolsApplied] ? resultImage : nil];
                    }
                    
                    __strong TGPhotoEditorController *strongController = weakController;
                    if (strongController != nil)
                    {
                        [strongController updateStatusBarAppearanceForDismiss];
                        [strongSelf _dismissTransitionForResultController:(TGOverlayController *)strongController];
                    }
                });
            };
            
            controller.requestThumbnailImage = ^(id<TGMediaEditableItem> editableItem)
            {
                return [editableItem thumbnailImageSignal];
            };
            
            controller.requestOriginalScreenSizeImage = ^(id<TGMediaEditableItem> editableItem, NSTimeInterval position)
            {
                return [editableItem screenImageSignal:position];
            };
            
            controller.requestOriginalFullSizeImage = ^(id<TGMediaEditableItem> editableItem, NSTimeInterval position)
            {
                return [editableItem originalImageSignal:position];
            };
            
            overlayController = (TGOverlayController *)controller;
        }
            break;
            
        default:
        {
            TGCameraPhotoPreviewController *controller = _shortcut ? [[TGCameraPhotoPreviewController alloc] initWithContext:windowContext image:image metadata:metadata recipientName:self.recipientName backButtonTitle:TGLocalized(@"Camera.Retake") doneButtonTitle:TGLocalized(@"Common.Next") saveCapturedMedia:_saveCapturedMedia saveEditedPhotos:_saveEditedPhotos] : [[TGCameraPhotoPreviewController alloc] initWithContext:windowContext image:image metadata:metadata recipientName:self.recipientName saveCapturedMedia:_saveCapturedMedia saveEditedPhotos:_saveEditedPhotos];
            controller.allowCaptions = self.allowCaptions;
            controller.shouldStoreAssets = self.shouldStoreCapturedAssets;
            controller.suggestionContext = self.suggestionContext;
            controller.hasTimer = self.hasTimer;
            
            __weak TGCameraPhotoPreviewController *weakController = controller;
            controller.beginTransitionIn = ^CGRect
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return CGRectZero;
                
                strongSelf->_previewView.hidden = true;
                
                return strongSelf->_previewView.frame;
            };
            
            controller.finishedTransitionIn = ^
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf != nil)
                    [strongSelf->_camera stopCaptureForPause:true completion:nil];
            };
            
            controller.beginTransitionOut = ^CGRect(CGRect referenceFrame)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return CGRectZero;
                
                [strongSelf->_camera startCaptureForResume:true completion:nil];
                
                return [strongSelf transitionBackFromResultControllerWithReferenceFrame:referenceFrame];
            };
            
            controller.retakePressed = ^
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return;
                
                [[[LegacyComponentsGlobals provider] applicationInstance] setIdleTimerDisabled:true];
            };
            
            controller.sendPressed = ^(TGOverlayController *controller, UIImage *resultImage, NSString *caption, NSArray *entities, NSArray *stickers, NSNumber *timer)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return;
                
                if (strongSelf.finishedWithPhoto != nil)
                    strongSelf.finishedWithPhoto(controller, resultImage, caption, entities, stickers, timer);
                
                if (strongSelf->_shortcut)
                    return;
                
                __strong TGOverlayController *strongController = weakController;
                if (strongController != nil)
                    [strongSelf _dismissTransitionForResultController:strongController];
            };
            
            overlayController = controller;
        }
            break;
    }
    
    if (windowManager != nil)
    {
        TGOverlayController *contentController = overlayController;
        if (_shortcut)
        {
            contentController = [[TGOverlayController alloc] init];
            
            TGNavigationController *navigationController = [TGNavigationController navigationControllerWithControllers:@[overlayController]];
            overlayController.navigationBarShouldBeHidden = true;
            [contentController addChildViewController:navigationController];
            [contentController.view addSubview:navigationController.view];
        }
        
        TGOverlayControllerWindow *controllerWindow = [[TGOverlayControllerWindow alloc] initWithManager:windowManager parentController:self contentController:contentController];
        controllerWindow.windowLevel = self.view.window.windowLevel + 0.0001f;
        controllerWindow.hidden = false;
    }
    else
    {
        [self addChildViewController:overlayController];
        [self.view addSubview:overlayController.view];
    }
    
    if (completion != nil)
        completion();
    
    [UIView animateWithDuration:0.3f animations:^
    {
        _interfaceView.alpha = 0.0f;
    }];
}

- (void)_savePhotoToCameraRollWithOriginalImage:(UIImage *)originalImage editedImage:(UIImage *)editedImage
{
    if (!_saveEditedPhotos || originalImage == nil)
        return;
    
    SSignal *savePhotoSignal = _saveCapturedMedia ? [[TGMediaAssetsLibrary sharedLibrary] saveAssetWithImage:originalImage] : [SSignal complete];
    if (_saveEditedPhotos && editedImage != nil)
        savePhotoSignal = [savePhotoSignal then:[[TGMediaAssetsLibrary sharedLibrary] saveAssetWithImage:editedImage]];
    
    [savePhotoSignal startWithNext:nil];
}

- (void)_saveVideoToCameraRollWithURL:(NSURL *)url completion:(void (^)(void))completion
{
    if (!_saveCapturedMedia)
        return;
    
    [[[TGMediaAssetsLibrary sharedLibrary] saveAssetWithVideoAtUrl:url] startWithNext:nil error:^(__unused NSError *error)
    {
        if (completion != nil)
            completion();
    } completed:completion];
}

- (CGRect)transitionBackFromResultControllerWithReferenceFrame:(CGRect)referenceFrame
{
    _camera.disabled = false;
    
    _buttonHandler.enabled = true;
    [_buttonHandler ignoreEventsFor:2.0f andDisable:false];
    _previewView.hidden = false;
    
    _focusControl.ignoreAutofocusing = false;
    
    CGRect targetFrame = _previewView.frame;

    _previewView.frame = referenceFrame;
    POPSpringAnimation *animation = [TGPhotoEditorAnimation prepareTransitionAnimationForPropertyNamed:kPOPViewFrame];
    animation.fromValue = [NSValue valueWithCGRect:referenceFrame];
    animation.toValue = [NSValue valueWithCGRect:targetFrame];
    [_previewView pop_addAnimation:animation forKey:@"frame"];
    
    [UIView animateWithDuration:0.3f delay:0.1f options:UIViewAnimationOptionCurveLinear animations:^
    {
        _interfaceView.alpha = 1.0f;
    } completion:nil];
    
    _interfaceView.previewViewFrame = _previewView.frame;
    [_interfaceView layoutPreviewRelativeViews];
    
    return targetFrame;
}

#pragma mark - Transition

- (void)beginTransitionInFromRect:(CGRect)rect
{
    [_autorotationCorrectionView insertSubview:_previewView aboveSubview:_backgroundView];
    
    _previewView.frame = rect;
    
    _backgroundView.alpha = 0.0f;
    _interfaceView.alpha = 0.0f;
    
    [UIView animateWithDuration:0.3f animations:^
    {
        _backgroundView.alpha = 1.0f;
        _interfaceView.alpha = 1.0f;
    }];
    
    CGRect fromFrame = rect;
    CGRect toFrame = [TGCameraController _cameraPreviewFrameForScreenSize:TGScreenSize() mode:_camera.cameraMode];

    if (!CGRectEqualToRect(fromFrame, CGRectZero))
    {
        POPSpringAnimation *frameAnimation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewFrame];
        frameAnimation.fromValue = [NSValue valueWithCGRect:fromFrame];
        frameAnimation.toValue = [NSValue valueWithCGRect:toFrame];
        frameAnimation.springSpeed = 20;
        frameAnimation.springBounciness = 1;
        [_previewView pop_addAnimation:frameAnimation forKey:@"frame"];
    }
    else
    {
        _previewView.frame = toFrame;
    }
    
    _interfaceView.previewViewFrame = toFrame;
    [_interfaceView layoutPreviewRelativeViews];
}

- (void)beginTransitionOutWithVelocity:(CGFloat)velocity
{
    _dismissing = true;
    self.view.userInteractionEnabled = false;
    
    _focusControl.active = false;
    
    [UIView animateWithDuration:0.3f animations:^
    {
        [_context setApplicationStatusBarAlpha:1.0f];
    }];
    
    [self setInterfaceHidden:true animated:true];
    
    [UIView animateWithDuration:0.25f animations:^
    {
        _backgroundView.alpha = 0.0f;
    }];
    
    CGRect referenceFrame = CGRectZero;
    if (self.beginTransitionOut != nil)
        referenceFrame = self.beginTransitionOut();
    
    __weak TGCameraController *weakSelf = self;
    if (_standalone)
    {
        [self simpleTransitionOutWithVelocity:velocity completion:^
        {
            __strong TGCameraController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            [strongSelf dismiss];
        }];
        return;
    }

    bool resetNeeded = _camera.isResetNeeded;
    if (resetNeeded)
        [_previewView beginResetTransitionAnimated:true];

    [_camera resetSynchronous:false completion:^
    {
        TGDispatchOnMainThread(^
        {
            if (resetNeeded)
                [_previewView endResetTransitionAnimated:true];
        });
    }];
    
    [_previewView.layer removeAllAnimations];
    
    if (!CGRectIsEmpty(referenceFrame))
    {
        POPSpringAnimation *frameAnimation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewFrame];
        frameAnimation.fromValue = [NSValue valueWithCGRect:_previewView.frame];
        frameAnimation.toValue = [NSValue valueWithCGRect:referenceFrame];
        frameAnimation.springSpeed = 20;
        frameAnimation.springBounciness = 1;
        frameAnimation.completionBlock = ^(__unused POPAnimation *animation, __unused BOOL finished)
        {
            __strong TGCameraController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;

            if (strongSelf.finishedTransitionOut != nil)
                strongSelf.finishedTransitionOut();

            [strongSelf dismiss];
        };
        [_previewView pop_addAnimation:frameAnimation forKey:@"frame"];
    }
    else
    {
        if (self.finishedTransitionOut != nil)
            self.finishedTransitionOut();
        
        [self dismiss];
    }
}

- (void)_dismissTransitionForResultController:(TGOverlayController *)resultController
{
    _finishedWithResult = true;
    
    [_context setApplicationStatusBarAlpha:1.0f];
    
    self.view.hidden = true;
    
    [resultController.view.layer animatePositionFrom:resultController.view.layer.position to:CGPointMake(resultController.view.layer.position.x, resultController.view.layer.position.y + resultController.view.bounds.size.height) duration:0.3 timingFunction:kCAMediaTimingFunctionSpring removeOnCompletion:false completion:^(__unused bool finished) {
        [resultController dismiss];
        [self dismiss];
    }];
    
    return;
    
    [UIView animateWithDuration:0.3f delay:0.0f options:(7 << 16) animations:^
    {
        resultController.view.frame = CGRectOffset(resultController.view.frame, 0, resultController.view.frame.size.height);
    } completion:^(__unused BOOL finished)
    {
        [resultController dismiss];
        [self dismiss];
    }];
}

- (void)simpleTransitionOutWithVelocity:(CGFloat)velocity completion:(void (^)())completion
{
    self.view.userInteractionEnabled = false;
    
    const CGFloat minVelocity = 2000.0f;
    if (ABS(velocity) < minVelocity)
        velocity = (velocity < 0.0f ? -1.0f : 1.0f) * minVelocity;
    CGFloat distance = (velocity < FLT_EPSILON ? -1.0f : 1.0f) * self.view.frame.size.height;
    CGRect targetFrame = (CGRect){{_previewView.frame.origin.x, distance}, _previewView.frame.size};
    
    [UIView animateWithDuration:ABS(distance / velocity) animations:^
    {
        _previewView.frame = targetFrame;
    } completion:^(__unused BOOL finished)
    {
        if (completion)
            completion();
    }];
}

- (void)_updateDismissTransitionMovementWithDistance:(CGFloat)distance animated:(bool)animated
{
    CGRect originalFrame = [TGCameraController _cameraPreviewFrameForScreenSize:TGScreenSize() mode:_camera.cameraMode];
    CGRect frame = (CGRect){ { originalFrame.origin.x, originalFrame.origin.y + distance }, originalFrame.size };
    if (animated)
    {
        [UIView animateWithDuration:0.3 animations:^
        {
            _previewView.frame = frame;
        }];
    }
    else
    {
        _previewView.frame = frame;
    }
}

- (void)_updateDismissTransitionWithProgress:(CGFloat)progress animated:(bool)animated
{
    CGFloat alpha = 1.0f - MAX(0.0f, MIN(1.0f, progress * 4.0f));
    CGFloat transitionProgress = MAX(0.0f, MIN(1.0f, progress * 2.0f));
    
    if (transitionProgress > FLT_EPSILON)
    {
        [self setInterfaceHidden:true animated:true];
        _focusControl.active = false;
    }
    else if (animated)
    {
        [self setInterfaceHidden:false animated:true];
        _focusControl.active = true;
    }
    
    if (animated)
    {
        [UIView animateWithDuration:0.3 animations:^
        {
            _backgroundView.alpha = alpha;
        }];
    }
    else
    {
        _backgroundView.alpha = alpha;
    }
}

- (void)resizePreviewViewForCameraMode:(PGCameraMode)mode
{
    CGRect frame = [TGCameraController _cameraPreviewFrameForScreenSize:TGScreenSize() mode:mode];
    _interfaceView.previewViewFrame = frame;
    [_interfaceView layoutPreviewRelativeViews];
    [_interfaceView updateForCameraModeChangeAfterResize];
    
    [UIView animateWithDuration:0.3f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionLayoutSubviews animations:^
    {
        _previewView.frame = frame;
        _overlayView.frame = frame;
    } completion:nil];
}

- (void)handleDeviceOrientationChangedTo:(UIDeviceOrientation)deviceOrientation
{
    if (_camera.isRecordingVideo || _intent == TGCameraControllerPassportIdIntent)
        return;
    
    UIInterfaceOrientation orientation = [TGCameraController _interfaceOrientationForDeviceOrientation:deviceOrientation];
    if ([_interfaceView isKindOfClass:[TGCameraMainPhoneView class]])
    {
        [_interfaceView setInterfaceOrientation:orientation animated:true];
    }
    else
    {
        if (orientation == UIInterfaceOrientationUnknown)
            return;
        
        switch (deviceOrientation)
        {
            case UIDeviceOrientationPortrait:
            {
                _photoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
                _videoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
            }
                break;
            case UIDeviceOrientationPortraitUpsideDown:
            {
                _photoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
                _videoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
            }
                break;
            case UIDeviceOrientationLandscapeLeft:
            {
                _photoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
                _videoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
            }
                break;
            case UIDeviceOrientationLandscapeRight:
            {
                _photoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
                _videoSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
            }
                break;
                
            default:
                break;
        }
        
        [_interfaceView setInterfaceOrientation:orientation animated:false];
        CGSize referenceSize = [self referenceViewSizeForOrientation:orientation];
        if (referenceSize.width > referenceSize.height)
            referenceSize = CGSizeMake(referenceSize.height, referenceSize.width);
        
        self.view.userInteractionEnabled = false;
        [UIView animateWithDuration:0.5f delay:0.0f options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionLayoutSubviews animations:^
        {
            _interfaceView.transform = CGAffineTransformMakeRotation(TGRotationForInterfaceOrientation(orientation));
            _interfaceView.frame = CGRectMake(0, 0, referenceSize.width, referenceSize.height);
            [_interfaceView setNeedsLayout];
        } completion:^(BOOL finished)
        {
            if (finished)
                self.view.userInteractionEnabled = true;
        }];
    }
    
    [_focusControl setInterfaceOrientation:orientation animated:true];
}

#pragma mark - Gesture Recognizers

- (CGFloat)dismissProgressForSwipeDistance:(CGFloat)distance
{
    return MAX(0.0f, MIN(1.0f, ABS(distance / 150.0f)));
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)gestureRecognizer
{
    PGCameraMode newMode = PGCameraModeUndefined;
    if (gestureRecognizer == _photoSwipeGestureRecognizer)
    {
        newMode = PGCameraModePhoto;
    }
    else if (gestureRecognizer == _videoSwipeGestureRecognizer)
    {
        newMode = PGCameraModeVideo;
    }
    
    if (newMode != PGCameraModeUndefined && _camera.cameraMode != newMode)
    {
        [_camera setCameraMode:newMode];
        [_interfaceView setCameraMode:newMode];
    }
}

- (void)handlePan:(TGModernGalleryZoomableScrollViewSwipeGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state)
    {
        case UIGestureRecognizerStateChanged:
        {
            _dismissProgress = [self dismissProgressForSwipeDistance:[gestureRecognizer swipeDistance]];
            [self _updateDismissTransitionWithProgress:_dismissProgress animated:false];
            [self _updateDismissTransitionMovementWithDistance:[gestureRecognizer swipeDistance] animated:false];
        }
            break;
            
        case UIGestureRecognizerStateEnded:
        {
            CGFloat swipeVelocity = [gestureRecognizer swipeVelocity];
            if (ABS(swipeVelocity) < TGCameraSwipeMinimumVelocity)
                swipeVelocity = (swipeVelocity < 0.0f ? -1.0f : 1.0f) * TGCameraSwipeMinimumVelocity;
            
            __weak TGCameraController *weakSelf = self;
            bool(^transitionOut)(CGFloat) = ^bool(CGFloat swipeVelocity)
            {
                __strong TGCameraController *strongSelf = weakSelf;
                if (strongSelf == nil)
                    return false;
                
                [strongSelf beginTransitionOutWithVelocity:swipeVelocity];
                
                return true;
            };
            
            if ((ABS(swipeVelocity) < TGCameraSwipeVelocityThreshold && ABS([gestureRecognizer swipeDistance]) < TGCameraSwipeDistanceThreshold) || !transitionOut(swipeVelocity))
            {
                _dismissProgress = 0.0f;
                [self _updateDismissTransitionWithProgress:0.0f animated:true];
                [self _updateDismissTransitionMovementWithDistance:0.0f animated:true];
            }
        }
            break;
            
        case UIGestureRecognizerStateCancelled:
        {
            _dismissProgress = 0.0f;
            [self _updateDismissTransitionWithProgress:0.0f animated:true];
            [self _updateDismissTransitionMovementWithDistance:0.0f animated:true];
        }
            break;
            
        default:
            break;
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state)
    {
        case UIGestureRecognizerStateChanged:
        {
            CGFloat delta = (gestureRecognizer.scale - 1.0f) / 1.5f;
            CGFloat value = MAX(0.0f, MIN(1.0f, _camera.zoomLevel + delta));
            
            [_camera setZoomLevel:value];
            [_interfaceView setZoomLevel:value displayNeeded:true];
            
            gestureRecognizer.scale = 1.0f;
        }
            break;
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        {
            [_interfaceView zoomChangingEnded];
        }
            break;
            
        default:
            break;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer == _panGestureRecognizer)
        return !_camera.isRecordingVideo && _items.count == 0;
    else if (gestureRecognizer == _photoSwipeGestureRecognizer || gestureRecognizer == _videoSwipeGestureRecognizer)
        return _intent == TGCameraControllerGenericIntent && !_camera.isRecordingVideo;
    else if (gestureRecognizer == _pinchGestureRecognizer)
        return _camera.isZoomAvailable;
    
    return true;
}

+ (CGRect)_cameraPreviewFrameForScreenSize:(CGSize)screenSize mode:(PGCameraMode)mode
{
    CGFloat widescreenWidth = MAX(screenSize.width, screenSize.height);

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone)
    {
        switch (mode)
        {
            case PGCameraModeVideo:
            {
                if (widescreenWidth == 812.0f)
                    return CGRectMake(0, 77, screenSize.width, screenSize.height - 77 - 68);
                else
                    return CGRectMake(0, 0, screenSize.width, screenSize.height);
            }
                break;
            
            case PGCameraModeSquare:
            case PGCameraModeClip:
            {
                CGRect rect = [self _cameraPreviewFrameForScreenSize:screenSize mode:PGCameraModePhoto];
                CGFloat topOffset = CGRectGetMidY(rect) - rect.size.width / 2;
                
                if (widescreenWidth - 480.0f < FLT_EPSILON)
                    topOffset = 40.0f;
                
                return CGRectMake(0, floor(topOffset), rect.size.width, rect.size.width);
            }
                break;
            
            default:
            {
                if (widescreenWidth == 812.0f)
                    return CGRectMake(0, 121, screenSize.width, screenSize.height - 121 - 191);
                if (widescreenWidth >= 736.0f - FLT_EPSILON)
                    return CGRectMake(0, 44, screenSize.width, screenSize.height - 50 - 136);
                else if (widescreenWidth >= 667.0f - FLT_EPSILON)
                    return CGRectMake(0, 44, screenSize.width, screenSize.height - 44 - 123);
                else if (widescreenWidth >= 568.0f - FLT_EPSILON)
                    return CGRectMake(0, 40, screenSize.width, screenSize.height - 40 - 101);
                else
                    return CGRectMake(0, 0, screenSize.width, screenSize.height);
            }
                break;
        }
    }
    else
    {
        if (mode == PGCameraModeSquare)
            return CGRectMake(0, (screenSize.height - screenSize.width) / 2, screenSize.width, screenSize.width);
        
        return CGRectMake(0, 0, screenSize.width, screenSize.height);
    }
}

+ (UIInterfaceOrientation)_interfaceOrientationForDeviceOrientation:(UIDeviceOrientation)orientation
{
    switch (orientation)
    {
        case UIDeviceOrientationPortrait:
            return UIInterfaceOrientationPortrait;
            
        case UIDeviceOrientationPortraitUpsideDown:
            return UIInterfaceOrientationPortraitUpsideDown;
            
        case UIDeviceOrientationLandscapeLeft:
            return UIInterfaceOrientationLandscapeRight;
            
        case UIDeviceOrientationLandscapeRight:
            return UIInterfaceOrientationLandscapeLeft;
            
        default:
            return UIInterfaceOrientationUnknown;
    }
}

+ (bool)useLegacyCamera
{
    return iosMajorVersion() < 7 || [UIDevice currentDevice].platformType == UIDevice4iPhone || [UIDevice currentDevice].platformType == UIDevice4GiPod;
}

+ (NSArray *)resultSignalsForSelectionContext:(TGMediaSelectionContext *)selectionContext editingContext:(TGMediaEditingContext *)editingContext currentItem:(id<TGMediaSelectableItem>)currentItem storeAssets:(bool)storeAssets saveEditedPhotos:(bool)saveEditedPhotos descriptionGenerator:(id (^)(id, NSString *, NSArray *, NSString *))descriptionGenerator
{
    NSMutableArray *signals = [[NSMutableArray alloc] init];
    NSMutableArray *selectedItems = selectionContext.selectedItems != nil ? [selectionContext.selectedItems mutableCopy] : [[NSMutableArray alloc] init];
    if (selectedItems.count == 0 && currentItem != nil)
        [selectedItems addObject:currentItem];
    
    if (storeAssets)
    {
        NSMutableArray *fullSizeSignals = [[NSMutableArray alloc] init];
        for (id<TGMediaEditableItem> item in selectedItems)
        {
            if ([editingContext timerForItem:item] == nil)
            {
                SSignal *saveMedia = [SSignal defer:^SSignal *
                {
                    if ([item isKindOfClass:[TGCameraCapturedPhoto class]])
                    {
                        TGCameraCapturedPhoto *photo = (TGCameraCapturedPhoto *)item;
                        return [SSignal single:@{@"type": @"photo", @"url": photo.url}];
                    }
                    else if ([item isKindOfClass:[TGCameraCapturedVideo class]])
                    {
                        TGCameraCapturedVideo *video = (TGCameraCapturedVideo *)item;
                        return [SSignal single:@{@"type": @"video", @"url": video.avAsset.URL}];
                    }
                    
                    return [SSignal complete];
                }];
                
                [fullSizeSignals addObject:saveMedia];
                
                if (saveEditedPhotos)
                {
                    [fullSizeSignals addObject:[[[editingContext fullSizeImageUrlForItem:item] filter:^bool(id result)
                    {
                        return [result isKindOfClass:[NSURL class]];
                    }] mapToSignal:^SSignal *(NSURL *url)
                    {
                        return [SSignal single:@{@"type": @"photo", @"url": url}];
                    }]];
                }
            }
        }
        
        SSignal *combinedSignal = nil;
        SQueue *queue = [SQueue concurrentDefaultQueue];
        
        for (SSignal *signal in fullSizeSignals)
        {
            if (combinedSignal == nil)
                combinedSignal = [signal startOn:queue];
            else
                combinedSignal = [[combinedSignal then:signal] startOn:queue];
        }
        
        [[[combinedSignal deliverOn:[SQueue mainQueue]] mapToSignal:^SSignal *(NSDictionary *desc)
        {
            if ([desc[@"type"] isEqualToString:@"photo"])
            {
                return [[TGMediaAssetsLibrary sharedLibrary] saveAssetWithImageAtUrl:desc[@"url"]];
            }
            else if ([desc[@"type"] isEqualToString:@"video"])
            {
                return [[TGMediaAssetsLibrary sharedLibrary] saveAssetWithVideoAtUrl:desc[@"url"]];
            }
            else
            {
                return [SSignal complete];
            }
        }] startWithNext:nil];
    }
    
    static dispatch_once_t onceToken;
    static UIImage *blankImage;
    dispatch_once(&onceToken, ^
    {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), true, 0.0f);
        
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, 1, 1));
        
        blankImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    
    SSignal *(^inlineThumbnailSignal)(id<TGMediaEditableItem>) = ^SSignal *(id<TGMediaEditableItem> item)
    {
        return [item thumbnailImageSignal];
    };
    
    NSNumber *groupedId;
    NSInteger i = 0;
    if (selectionContext.grouping && selectedItems.count > 1)
        groupedId = @([TGCameraController generateGroupedId]);
    
    bool hasAnyTimers = false;
    if (editingContext != nil)
    {
        for (id<TGMediaEditableItem> item in selectedItems)
        {
            if ([editingContext timerForItem:item] != nil)
            {
                hasAnyTimers = true;
                break;
            }
        }
    }
    
    for (id<TGMediaEditableItem> asset in selectedItems)
    {
        if ([asset isKindOfClass:[TGCameraCapturedPhoto class]])
        {
            NSString *caption = [editingContext captionForItem:asset];
            NSArray *entities = [editingContext entitiesForItem:asset];
            id<TGMediaEditAdjustments> adjustments = [editingContext adjustmentsForItem:asset];
            NSNumber *timer = [editingContext timerForItem:asset];

            SSignal *inlineSignal = [[asset screenImageSignal:0.0] map:^id(UIImage *originalImage)
            {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                dict[@"type"] = @"editedPhoto";
                dict[@"image"] = originalImage;
                                         
                if (timer != nil)
                    dict[@"timer"] = timer;
                else if (groupedId != nil && !hasAnyTimers)
                    dict[@"groupedId"] = groupedId;

                id generatedItem = descriptionGenerator(dict, caption, entities, nil);
                return generatedItem;
            }];
            
            SSignal *assetSignal = inlineSignal;
            SSignal *imageSignal = assetSignal;
            if (editingContext != nil)
            {
                imageSignal = [[[[[editingContext imageSignalForItem:asset withUpdates:true] filter:^bool(id result)
                {
                    return result == nil || ([result isKindOfClass:[UIImage class]] && !((UIImage *)result).degraded);
                }] take:1] mapToSignal:^SSignal *(id result)
                {
                    if (result == nil)
                    {
                        return [SSignal fail:nil];
                    }
                    else if ([result isKindOfClass:[UIImage class]])
                    {
                        UIImage *image = (UIImage *)result;
                        image.edited = true;
                        return [SSignal single:image];
                    }
                    
                    return [SSignal complete];
                }] onCompletion:^
                {
                    __strong TGMediaEditingContext *strongEditingContext = editingContext;
                    [strongEditingContext description];
                }];
            }
            
            [signals addObject:[[imageSignal map:^NSDictionary *(UIImage *image)
            {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                dict[@"type"] = @"editedPhoto";
                dict[@"image"] = image;
                
                if (adjustments.paintingData.stickers.count > 0)
                    dict[@"stickers"] = adjustments.paintingData.stickers;
                
                if (timer != nil)
                    dict[@"timer"] = timer;
                else if (groupedId != nil && !hasAnyTimers)
                    dict[@"groupedId"] = groupedId;
                
                id generatedItem = descriptionGenerator(dict, caption, entities, nil);
                return generatedItem;
            }] catch:^SSignal *(__unused id error)
            {
                return inlineSignal;
            }]];
            
            i++;
        }
        else if ([asset isKindOfClass:[TGCameraCapturedVideo class]])
        {
            TGCameraCapturedVideo *video = (TGCameraCapturedVideo *)asset;
            
            TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[editingContext adjustmentsForItem:asset];
            NSString *caption = [editingContext captionForItem:asset];
            NSArray *entities = [editingContext entitiesForItem:asset];
            NSNumber *timer = [editingContext timerForItem:asset];
            
            UIImage *(^cropVideoThumbnail)(UIImage *, CGSize, CGSize, bool) = ^UIImage *(UIImage *image, CGSize targetSize, CGSize sourceSize, bool resize)
            {
                if ([adjustments cropAppliedForAvatar:false] || adjustments.hasPainting)
                {
                    CGRect scaledCropRect = CGRectMake(adjustments.cropRect.origin.x * image.size.width / adjustments.originalSize.width, adjustments.cropRect.origin.y * image.size.height / adjustments.originalSize.height, adjustments.cropRect.size.width * image.size.width / adjustments.originalSize.width, adjustments.cropRect.size.height * image.size.height / adjustments.originalSize.height);
                    return TGPhotoEditorCrop(image, adjustments.paintingData.image, adjustments.cropOrientation, 0, scaledCropRect, adjustments.cropMirrored, targetSize, sourceSize, resize);
                }
                
                return image;
            };
            
            CGSize imageSize = TGFillSize(asset.originalSize, CGSizeMake(384, 384));
            SSignal *trimmedVideoThumbnailSignal = [[TGMediaAssetImageSignals videoThumbnailForAVAsset:video.avAsset size:imageSize timestamp:CMTimeMakeWithSeconds(adjustments.trimStartValue, NSEC_PER_SEC)] map:^UIImage *(UIImage *image)
            {
                    return cropVideoThumbnail(image, TGScaleToFill(asset.originalSize, CGSizeMake(256, 256)), asset.originalSize, true);
            }];
            
            SSignal *videoThumbnailSignal = [inlineThumbnailSignal(asset) map:^UIImage *(UIImage *image)
            {
                return cropVideoThumbnail(image, image.size, image.size, false);
            }];
            
            SSignal *thumbnailSignal = adjustments.trimStartValue > FLT_EPSILON ? trimmedVideoThumbnailSignal : videoThumbnailSignal;
            
            TGMediaVideoConversionPreset preset = [TGMediaVideoConverter presetFromAdjustments:adjustments];
            CGSize dimensions = [TGMediaVideoConverter dimensionsFor:asset.originalSize adjustments:adjustments preset:preset];
            NSTimeInterval duration = adjustments.trimApplied ? (adjustments.trimEndValue - adjustments.trimStartValue) : video.videoDuration;
            
            [signals addObject:[thumbnailSignal map:^id(UIImage *image)
            {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                dict[@"type"] = @"cameraVideo";
                dict[@"url"] = video.avAsset.URL;
                dict[@"previewImage"] = image;
                dict[@"adjustments"] = adjustments;
                dict[@"dimensions"] = [NSValue valueWithCGSize:dimensions];
                dict[@"duration"] = @(duration);
                
                if (adjustments.paintingData.stickers.count > 0)
                    dict[@"stickers"] = adjustments.paintingData.stickers;
                if (timer != nil)
                    dict[@"timer"] = timer;
                else if (groupedId != nil && !hasAnyTimers)
                    dict[@"groupedId"] = groupedId;
                
                id generatedItem = descriptionGenerator(dict, caption, entities, nil);
                return generatedItem;
            }]];
            
            i++;
        }
     
        if (groupedId != nil && i == 10)
        {
            i = 0;
            groupedId = @([TGCameraController generateGroupedId]);
        }
    }
    return signals;
}

+ (int64_t)generateGroupedId
{
    int64_t value;
    arc4random_buf(&value, sizeof(int64_t));
    return value;
}

@end
