#import <Foundation/Foundation.h>

@class TGDocumentMediaAttachment;

typedef enum {
    TGMediaOriginTypeUndefined,
    TGMediaOriginTypeMessage,
    TGMediaOriginTypeSticker,
    TGMediaOriginTypeRecentSticker,
    TGMediaOriginTypeRecentGif,
    TGMediaOriginTypeProfilePhoto,
    TGMediaOriginTypeWebpage,
    TGMediaOriginTypeWallpaper,
    TGMediaOriginTypeFavoriteSticker,
    TGMediaOriginTypeRecentMask,
    TGMediaOriginTypeChatPhoto
} TGMediaOriginType;

@interface TGMediaOriginInfo : NSObject <NSCoding>

@property (nonatomic, readonly) TGMediaOriginType type;

@property (nonatomic, readonly, strong) NSData *fileReference;
@property (nonatomic, readonly, strong) NSDictionary *fileReferences;

@property (nonatomic, readonly, strong) NSNumber *cid;
@property (nonatomic, readonly, strong) NSNumber *mid;

@property (nonatomic, readonly, strong) NSNumber *stickerPackId;
@property (nonatomic, readonly, strong) NSNumber *stickerPackAccessHash;

@property (nonatomic, readonly, strong) NSNumber *profilePhotoUserId;
@property (nonatomic, readonly, strong) NSNumber *profilePhotoOffset;

@property (nonatomic, readonly, strong) NSNumber *chatPhotoPeerId;

@property (nonatomic, readonly, strong) NSString *webpageUrl;

@property (nonatomic, readonly, strong) NSNumber *wallpaperId;

- (NSData *)fileReferenceForVolumeId:(int64_t)volumeId localId:(int32_t)localId;
- (NSData *)fileReferenceForDocumentId:(int64_t)documentId accessHash:(int64_t)accessHash;
- (NSString *)key;

+ (instancetype)mediaOriginInfoWithStringRepresentation:(NSString *)string;
- (NSString *)stringRepresentation;

+ (instancetype)mediaOriginInfoWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences;
+ (instancetype)mediaOriginInfoWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences cid:(int64_t)cid mid:(int32_t)mid;
+ (instancetype)mediaOriginInfoWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences stickerPackId:(int64_t)packId accessHash:(int64_t)accessHash;
+ (instancetype)mediaOriginInfoForRecentStickerWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences;
+ (instancetype)mediaOriginInfoForFavoriteStickerWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences;
+ (instancetype)mediaOriginInfoForRecentGifWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences;
+ (instancetype)mediaOriginInfoForRecentMaskWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences;
+ (instancetype)mediaOriginInfoWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences userId:(int32_t)userId offset:(int32_t)offset;
+ (instancetype)mediaOriginInfoWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences url:(NSString *)url;
+ (instancetype)mediaOriginInfoWithFileReference:(NSData *)fileReference fileReferences:(NSDictionary *)fileReferences peerId:(int64_t)peerId;

+ (instancetype)mediaOriginInfoWithFileReferences:(NSDictionary *)fileReferences wallpaperId:(int32_t)wallpaperId;

+ (instancetype)mediaOriginInfoForDocumentAttachment:(TGDocumentMediaAttachment *)document;

@end
