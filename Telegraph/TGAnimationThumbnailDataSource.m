#import "TGAnimationThumbnailDataSource.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGPhotoThumbnailDataSource.h"

#import "TGWorkerPool.h"
#import "TGWorkerTask.h"
#import "TGMediaPreviewTask.h"

#import <LegacyComponents/TGMemoryImageCache.h>

#import <LegacyComponents/TGRemoteImageView.h>

#import <LegacyComponents/TGImageBlur.h>
#import <LegacyComponents/UIImage+TG.h>

#import "TGMediaStoreContext.h"

#import <AVFoundation/AVFoundation.h>

#import "TGPresentation.h"

#import "TGAppDelegate.h"

static TGWorkerPool *workerPool()
{
    static TGWorkerPool *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        instance = [[TGWorkerPool alloc] init];
    });
    
    return instance;
}

static ASQueue *taskManagementQueue()
{
    static ASQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        queue = [[ASQueue alloc] initWithName:"org.telegram.animationThumbnailTaskManagementQueue"];
    });
    
    return queue;
}

@implementation TGAnimationThumbnailDataSource

+ (void)load
{
    @autoreleasepool
    {
        [TGImageDataSource registerDataSource:[[self alloc] init]];
    }
}

- (bool)canHandleUri:(NSString *)uri
{
    return [uri hasPrefix:@"animation-thumbnail://"];
}

- (bool)canHandleAttributeUri:(NSString *)uri
{
    return [uri hasPrefix:@"animation-thumbnail://"];
}

- (id)loadDataAsyncWithUri:(NSString *)uri progress:(void (^)(float))progress partialCompletion:(void (^)(TGDataResource *resource))__unused partialCompletion completion:(void (^)(TGDataResource *))completion
{
    NSDictionary *args = [TGStringUtils argumentDictionaryInUrlString:[uri substringFromIndex:@"animation-thumbnail://?".length]];
    bool isFlat = [args[@"flat"] boolValue];
    int cornerRadius = [args[@"cornerRadius"] intValue];
    int position = [args[@"position"] intValue];
    
    TGMediaPreviewTask *previewTask = [[TGMediaPreviewTask alloc] init];
    
    [taskManagementQueue() dispatchOnQueue:^
    {
        TGWorkerTask *workerTask = [[TGWorkerTask alloc] initWithBlock:^(bool (^isCancelled)())
        {
            TGDataResource *result = [TGAnimationThumbnailDataSource _performLoad:uri isCancelled:isCancelled];
            
            if (result != nil && progress != nil)
                progress(1.0f);
            
            if (isCancelled != nil && isCancelled())
                return;
            
            if (completion != nil)
                completion(result != nil ? result : [TGAnimationThumbnailDataSource resultForUnavailableImage:isFlat cornerRadius:cornerRadius position:position]);
        }];
        
        if ([TGAnimationThumbnailDataSource _isDataLocallyAvailableForUri:uri])
        {
            [previewTask executeWithWorkerTask:workerTask workerPool:workerPool()];
        }
        else
        {
            if ([args[@"legacy-thumbnail-cache-url"] respondsToSelector:@selector(characterAtIndex:)])
            {
                static NSString *filesDirectory = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^
                {
                    filesDirectory = [[TGAppDelegate documentsPath] stringByAppendingPathComponent:@"files"];
                });
                
                NSString *fileDirectoryName = nil;
                if (args[@"id"] != nil)
                    fileDirectoryName = [[NSString alloc] initWithFormat:@"%" PRIx64 "", (int64_t)[args[@"id"] longLongValue]];
                else
                    fileDirectoryName = [[NSString alloc] initWithFormat:@"local%" PRIx64 "", (int64_t)[args[@"local-id"] longLongValue]];
                NSString *fileDirectory = [filesDirectory stringByAppendingPathComponent:fileDirectoryName];
                
                [[NSFileManager defaultManager] createDirectoryAtPath:fileDirectory withIntermediateDirectories:true attributes:nil error:nil];
                
                NSString *temporaryThumbnailImagePath = [fileDirectory stringByAppendingPathComponent:@"file-thumb.jpg"];
                
                NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
                TGMediaOriginInfo *originInfo = nil;
                if (args[@"origin_info"] != nil)
                {
                    originInfo = [TGMediaOriginInfo mediaOriginInfoWithStringRepresentation:args[@"origin_info"]];
                }
                else if (args[@"cid"] != nil)
                {
                    int64_t cid = [args[@"cid"] longLongValue];
                    int32_t mid = [args[@"mid"] intValue];
                    originInfo = [TGMediaOriginInfo mediaOriginInfoWithFileReference:nil fileReferences:nil cid:cid mid:mid];
                }
                
                if (originInfo != nil)
                    options[@"originInfo"] = originInfo;
                
                [previewTask executeWithTargetFilePath:temporaryThumbnailImagePath uri:args[@"legacy-thumbnail-cache-url"] options:options completion:^(bool success)
                {
                    if (success)
                    {
                        dispatch_async([TGCache diskCacheQueue], ^
                        {
                            [previewTask executeWithWorkerTask:workerTask workerPool:workerPool()];
                        });
                    }
                    else
                    {
                        if (completion != nil)
                            completion([TGAnimationThumbnailDataSource resultForUnavailableImage:isFlat cornerRadius:cornerRadius position:position]);
                    }
                } workerTask:workerTask];
            }
            else
            {
                if (completion != nil)
                    completion([TGAnimationThumbnailDataSource resultForUnavailableImage:isFlat cornerRadius:cornerRadius position:position]);
            }
        }
    }];
    
    return previewTask;
}

+ (bool)_isDataLocallyAvailableForUri:(NSString *)uri
{
    NSDictionary *args = [TGStringUtils argumentDictionaryInUrlString:[uri substringFromIndex:@"animation-thumbnail://?".length]];
    
    NSString *imageUrl = args[@"legacy-thumbnail-cache-url"];
    if (imageUrl.length != 0)
    {
        if ([imageUrl hasPrefix:@"http://"] || [imageUrl hasPrefix:@"https://"])
        {
            return [[[TGMediaStoreContext instance] temporaryFilesCache] containsValueForKey:[imageUrl dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    if ((![args[@"id"] respondsToSelector:@selector(longLongValue)] && ![args[@"local-id"] respondsToSelector:@selector(longLongValue)]) || ![args[@"width"] respondsToSelector:@selector(intValue)] || ![args[@"height"] respondsToSelector:@selector(intValue)] || ![args[@"renderWidth"] respondsToSelector:@selector(intValue)] || ![args[@"renderHeight"] respondsToSelector:@selector(intValue)] || ![args[@"file-name"] respondsToSelector:@selector(characterAtIndex:)])
    {
        return false;
    }
    
    static NSString *filesDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        filesDirectory = [[TGAppDelegate documentsPath] stringByAppendingPathComponent:@"files"];
    });
    
    NSString *fileDirectoryName = nil;
    if (args[@"id"] != nil)
        fileDirectoryName = [[NSString alloc] initWithFormat:@"%" PRIx64 "", (int64_t)[args[@"id"] longLongValue]];
    else
        fileDirectoryName = [[NSString alloc] initWithFormat:@"local%" PRIx64 "", (int64_t)[args[@"local-id"] longLongValue]];
    NSString *fileDirectory = [filesDirectory stringByAppendingPathComponent:fileDirectoryName];
    
    CGSize size = CGSizeMake([args[@"width"] intValue], [args[@"height"] intValue]);
    CGSize renderSize = CGSizeMake([args[@"renderWidth"] intValue], [args[@"renderHeight"] intValue]);
    
    NSString *thumbnailPath = [fileDirectory stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"thumbnail-%dx%d-%dx%d.jpg", (int)size.width, (int)size.height, (int)renderSize.width, (int)renderSize.height]];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailPath isDirectory:NULL])
        return true;
    
    NSString *temporaryThumbnailImagePath = [fileDirectory stringByAppendingPathComponent:@"file-thumb.jpg"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:temporaryThumbnailImagePath])
        return true;
    
    NSString *filePath = [fileDirectory stringByAppendingPathComponent:args[@"file-name"]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:NULL])
        return true;
    
    if ([args[@"legacy-thumbnail-cache-url"] respondsToSelector:@selector(characterAtIndex:)])
    {
        NSString *legacyThumbnailImagePath = [[TGRemoteImageView sharedCache] pathForCachedData:args[@"legacy-thumbnail-cache-url"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:legacyThumbnailImagePath isDirectory:NULL])
            return true;
    }
    
    if (args[@"video-file-name"] != nil) {
        NSString *videoFilePath = [fileDirectory stringByAppendingPathComponent:args[@"video-file-name"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:videoFilePath isDirectory:NULL])
            return true;
    }
    
    return false;
}

- (void)cancelTaskById:(id)taskId
{
    [taskManagementQueue() dispatchOnQueue:^
    {
        if ([taskId isKindOfClass:[TGMediaPreviewTask class]])
        {
            TGMediaPreviewTask *previewTask = taskId;
            [previewTask cancel];
        }
    }];
}

+ (TGDataResource *)resultForUnavailableImage:(bool)isFlat cornerRadius:(int)cornerRadius position:(int)position
{
    return [TGPhotoThumbnailDataSource resultForUnavailableImage:isFlat cornerRadius:cornerRadius position:position];
}

- (id)loadAttributeSyncForUri:(NSString *)uri attribute:(NSString *)attribute
{
    if ([attribute isEqualToString:@"placeholder"])
    {
        NSDictionary *args = [TGStringUtils argumentDictionaryInUrlString:[uri substringFromIndex:@"animation-thumbnail://?".length]];
        bool isFlat = [args[@"flat"] boolValue];
        int cornerRadius = [args[@"cornerRadius"] intValue];
        int position = [args[@"position"] intValue];
        
        UIImage *reducedImage = [[TGMediaStoreContext instance] mediaReducedImage:uri attributes:NULL];
        
        if (reducedImage != nil)
            return reducedImage;
        
        NSNumber *averageColor = [[TGMediaStoreContext instance] mediaImageAverageColor:uri];
        if (averageColor != nil)
        {
            UIImage *image = nil;
            if (isFlat && cornerRadius > 0)
                image = TGAverageColorAttachmentWithCornerRadiusImage(UIColorRGB([averageColor intValue]), !isFlat, cornerRadius, position);
            else
                image = TGAverageColorAttachmentImage(UIColorRGB([averageColor intValue]), !isFlat, position);
            return image;
        }
        
        static NSMutableDictionary *normalPlaceholders = nil;
        static NSMutableDictionary *flatPlaceholders = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^
        {
            normalPlaceholders = [[NSMutableDictionary alloc] init];
            flatPlaceholders = [[NSMutableDictionary alloc] init];
        });
        
        TGPresentation *presentation = TGPresentation.current;
        UIColor *color = presentation.pallete.backgroundColor;
        if (position == 0)
        {
            if (isFlat)
            {
                NSNumber *key = @(presentation.currentId + cornerRadius);
                UIImage *flatPlaceholder = flatPlaceholders[key];
                if (flatPlaceholder == nil)
                {
                    if (cornerRadius == 0)
                        flatPlaceholder = TGAverageColorAttachmentImage(color, false, 0);
                    else
                        flatPlaceholder = TGAverageColorAttachmentWithCornerRadiusImage(color, false, cornerRadius, 0);
                    
                    flatPlaceholders[key] = flatPlaceholder;
                }
                return flatPlaceholder;
            }
            else
            {
                NSNumber *key = @(presentation.currentId);
                UIImage *normalPlaceholder = normalPlaceholders[key];
                if (normalPlaceholder == nil)
                {
                    normalPlaceholder = TGAverageColorAttachmentImage(color, true, 0);
                    normalPlaceholders[key] = normalPlaceholder;
                }
                return normalPlaceholder;
            }
        }
        else
        {
            if (isFlat)
            {
                if (cornerRadius == 0)
                    return TGAverageColorAttachmentImage(color, false, position);
                else
                    return TGAverageColorAttachmentWithCornerRadiusImage(color, false, cornerRadius, position);
            }
            else
            {
                return TGAverageColorAttachmentImage(color, true, position);
            }
        }
    }
    
    return nil;
}

- (TGDataResource *)loadDataSyncWithUri:(NSString *)uri canWait:(bool)canWait acceptPartialData:(bool)__unused acceptPartialData asyncTaskId:(__autoreleasing id *)__unused asyncTaskId progress:(void (^)(float))__unused progress partialCompletion:(void (^)(TGDataResource *))__unused partialCompletion completion:(void (^)(TGDataResource *))__unused completion
{
    if (uri == nil)
        return nil;
    
    UIImage *cachedImage = [[TGMediaStoreContext instance] mediaImage:uri attributes:nil];
    if (cachedImage != nil)
        return [[TGDataResource alloc] initWithImage:cachedImage decoded:true];
    
    if (!canWait)
        return nil;
    
    return [TGAnimationThumbnailDataSource _performLoad:uri isCancelled:nil];
}

+ (TGDataResource *)_performLoad:(NSString *)uri isCancelled:(bool (^)())isCancelled
{
    if (isCancelled && isCancelled())
    {
        TGLog(@"[TGPhotoMediaPreviewImageDataSource cancelled while loading %@]", uri);
        return nil;
    }
    
    NSDictionary *args = [TGStringUtils argumentDictionaryInUrlString:[uri substringFromIndex:@"animation-thumbnail://?".length]];
    
    if ((![args[@"id"] respondsToSelector:@selector(longLongValue)] && ![args[@"local-id"] respondsToSelector:@selector(longLongValue)]) || ![args[@"width"] respondsToSelector:@selector(intValue)] || ![args[@"height"] respondsToSelector:@selector(intValue)] || ![args[@"renderWidth"] respondsToSelector:@selector(intValue)] || ![args[@"renderHeight"] respondsToSelector:@selector(intValue)] || ![args[@"file-name"] respondsToSelector:@selector(characterAtIndex:)])
    {
        return nil;
    }
    
    static NSString *filesDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        filesDirectory = [[TGAppDelegate documentsPath] stringByAppendingPathComponent:@"files"];
    });
    
    NSString *fileDirectoryName = nil;
    if (args[@"id"] != nil)
        fileDirectoryName = [[NSString alloc] initWithFormat:@"%" PRIx64 "", (int64_t)[args[@"id"] longLongValue]];
    else
        fileDirectoryName = [[NSString alloc] initWithFormat:@"local%" PRIx64 "", (int64_t)[args[@"local-id"] longLongValue]];
    NSString *fileDirectory = [filesDirectory stringByAppendingPathComponent:fileDirectoryName];
    
    CGSize size = CGSizeMake([args[@"width"] intValue], [args[@"height"] intValue]);
    CGSize renderSize = CGSizeMake([args[@"renderWidth"] intValue], [args[@"renderHeight"] intValue]);
    
    NSString *thumbnailPath = [fileDirectory stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"thumbnail-%dx%d-%dx%d.jpg", (int)size.width, (int)size.height, (int)renderSize.width, (int)renderSize.height]];
    
    UIImage *thumbnailSourceImage = [[UIImage alloc] initWithContentsOfFile:thumbnailPath];
    bool lowQualityThumbnail = false;
    
    if (thumbnailSourceImage == nil)
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:fileDirectory withIntermediateDirectories:true attributes:nil error:nil];
        
        NSString *filePath = [fileDirectory stringByAppendingPathComponent:args[@"file-name"]];
        NSString *videoFilePath = nil;
        if (args[@"video-file-name"] != nil) {
            videoFilePath = [fileDirectory stringByAppendingPathComponent:args[@"video-file-name"]];
        }
        NSString *temporaryThumbnailImagePath = [fileDirectory stringByAppendingPathComponent:@"file-thumb.jpg"];
        
        UIImage *image = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:videoFilePath isDirectory:NULL]) {
            if ([videoFilePath pathExtension].length == 0) {
                [[NSFileManager defaultManager] createSymbolicLinkAtPath:[videoFilePath stringByAppendingPathExtension:@"mov"] withDestinationPath:[videoFilePath pathComponents].lastObject error:nil];
                videoFilePath = [videoFilePath stringByAppendingPathExtension:@"mov"];
            }
            
            AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoFilePath]];
            
            AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            imageGenerator.maximumSize = CGSizeMake(800, 800);
            imageGenerator.appliesPreferredTrackTransform = true;
            NSError *imageError = nil;
            CGImageRef imageRef = [imageGenerator copyCGImageAtTime:CMTimeMake(0, asset.duration.timescale) actualTime:NULL error:&imageError];
            image = [[UIImage alloc] initWithCGImage:imageRef];
            if (imageRef != NULL) {
                CGImageRelease(imageRef);
            }
        }
        
        if (image == nil && [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:NULL]) {
            image = [[UIImage alloc] initWithContentsOfFile:filePath];
        }
        
        if (image == nil) {
            image = [[UIImage alloc] initWithContentsOfFile:temporaryThumbnailImagePath];
            
            if (image != nil)
                lowQualityThumbnail = true;
        }
        
        if (image == nil)
        {
            if ([args[@"legacy-thumbnail-cache-url"] respondsToSelector:@selector(characterAtIndex:)])
            {
                NSString *legacyThumbnailImagePath = [[TGRemoteImageView sharedCache] pathForCachedData:args[@"legacy-thumbnail-cache-url"]];
                image = [[UIImage alloc] initWithContentsOfFile:legacyThumbnailImagePath];
                
                if (image != nil)
                {
                    [[NSFileManager defaultManager] copyItemAtPath:legacyThumbnailImagePath toPath:temporaryThumbnailImagePath error:nil];
                }
            }
            
            if (image != nil)
                lowQualityThumbnail = true;
        }
        
        if (image == nil)
        {
            NSString *imageUrl = args[@"legacy-thumbnail-cache-url"];
            if (imageUrl.length != 0)
            {
                if ([imageUrl hasPrefix:@"http://"] || [imageUrl hasPrefix:@"https://"])
                {
                    NSData *imageData = [[[TGMediaStoreContext instance] temporaryFilesCache] getValueForKey:[imageUrl dataUsingEncoding:NSUTF8StringEncoding]];
                    if (imageData != nil)
                        image = [[UIImage alloc] initWithData:imageData];
                }
            }
            
            if (image != nil)
                lowQualityThumbnail = true;
        }
        
        if (image != nil)
        {
            const float cacheFactor = 0.85f;
            CGSize cachedImageSize = CGSizeMake(CGCeil(size.width * cacheFactor), CGCeil(size.height * cacheFactor));
            CGSize cachedRenderSize = CGSizeMake(CGCeil(renderSize.width * cacheFactor), CGCeil(renderSize.height * cacheFactor));
            UIGraphicsBeginImageContextWithOptions(cachedImageSize, true, 2.0f);
            
            CGRect imageRect = CGRectMake((cachedImageSize.width - cachedRenderSize.width) / 2.0f, (cachedImageSize.height - cachedRenderSize.height) / 2.0f, cachedRenderSize.width, cachedRenderSize.height);
            [image drawInRect:imageRect blendMode:kCGBlendModeCopy alpha:1.0f];
            
            thumbnailSourceImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            if (thumbnailSourceImage != nil && !lowQualityThumbnail)
            {
                NSData *thumbnailSourceData = UIImageJPEGRepresentation(thumbnailSourceImage, 0.8f);
                [thumbnailSourceData writeToFile:thumbnailPath atomically:true];
            }
        }
    }
    else
    {
        UIGraphicsBeginImageContextWithOptions(size, true, 2.0f);
        
        CGRect imageRect = CGRectMake(0.0f, 0.0f, size.width, size.height);
        [thumbnailSourceImage drawInRect:imageRect blendMode:kCGBlendModeCopy alpha:1.0f];
        
        thumbnailSourceImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    bool isFlat = [args[@"flat"] boolValue];
    int cornerRadius = [args[@"cornerRadius"] intValue];
    int position = [args[@"position"] intValue];
    
    if (thumbnailSourceImage != nil)
    {
        UIImage *thumbnailImage = nil;
        
        NSNumber *averageColor = [[TGMediaStoreContext instance] mediaImageAverageColor:uri];
        bool needsAverageColor = averageColor == nil;
        uint32_t averageColorValue = [averageColor intValue];
        
        if (lowQualityThumbnail) {
            if (isFlat && cornerRadius != 0)
                thumbnailImage = TGBlurredAttachmentWithCornerRadiusImage(thumbnailSourceImage, size, needsAverageColor ? &averageColorValue : NULL, !isFlat, cornerRadius, position);
            else
                thumbnailImage = TGBlurredAttachmentImage(thumbnailSourceImage, size, needsAverageColor ? &averageColorValue : NULL, !isFlat, position);
        }
        else {
            if (isFlat && cornerRadius != 0)
                thumbnailImage = TGLoadedAttachmentWithCornerRadiusImage(thumbnailSourceImage, size, needsAverageColor ? &averageColorValue : NULL, !isFlat, cornerRadius, 0, position);
            else
                thumbnailImage = TGLoadedAttachmentImage(thumbnailSourceImage, size, needsAverageColor ? &averageColorValue : NULL, !isFlat, position);
        }
        
        if (thumbnailImage != nil)
        {
            [[TGMediaStoreContext instance] setMediaImageAverageColorForKey:uri averageColor:@(averageColorValue)];
            if (!lowQualityThumbnail)
                [[TGMediaStoreContext instance] setMediaImageForKey:uri image:thumbnailImage attributes:nil];
            
            NSDictionary *imageAttachments = [thumbnailImage attachmentsDictionary];
            
            [[TGMediaStoreContext instance] inMediaReducedImageCacheGenerationQueue:^
            {
                __autoreleasing NSDictionary *attributes = nil;
                bool alreadyCached = [[TGMediaStoreContext instance] mediaReducedImage:uri attributes:&attributes];
                bool cachedLowQualityThumbnail = [attributes[@"lowQuality"] boolValue];
                
                if (!alreadyCached || (cachedLowQualityThumbnail && !lowQualityThumbnail))
                {
                    UIImage *cachedImage = nil;
                    if (isFlat && cornerRadius > 0)
                        cachedImage = TGReducedAttachmentWithCornerRadiusImage(thumbnailImage, size, !isFlat, cornerRadius, position);
                    else
                        cachedImage = TGReducedAttachmentImage(thumbnailImage, size, !isFlat, position);
                    [cachedImage setAttachmentsFromDictionary:imageAttachments];
                    
                    if (cachedImage != nil)
                    {
                        [[TGMediaStoreContext instance] setMediaReducedImageForKey:uri reducedImage:cachedImage attributes:@{@"lowQuality": @(lowQualityThumbnail)}];
                    }
                }
            }];
            
            return [[TGDataResource alloc] initWithImage:thumbnailImage decoded:true];
        }
    }
    
    return nil;
}

@end
