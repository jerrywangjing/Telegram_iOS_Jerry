#import "TGModernGalleryMessageImageItem.h"

#import "TGGenericPeerGalleryItem.h"

@class TGUser;
@class TGImageMediaAttachment;
@class TGMediaOriginInfo;

@interface TGGenericPeerMediaGalleryImageItem : TGModernGalleryMessageImageItem <TGGenericPeerGalleryItem>

@property (nonatomic, strong) id authorPeer;
@property (nonatomic) NSTimeInterval date;
@property (nonatomic) int32_t messageId;
@property (nonatomic) int64_t peerId;
@property (nonatomic, strong) NSString *caption;
@property (nonatomic, strong) NSArray *textCheckingResults;
@property (nonatomic, strong) NSArray *entities;
@property (nonatomic) int64_t groupedId;
@property (nonatomic, strong) NSArray *groupItems;
@property (nonatomic, strong) NSString *author;

- (instancetype)initWithImageId:(int64_t)imageId accessHash:(int64_t)accessHash orLocalId:(int64_t)localId peerId:(int64_t)peerId messageId:(int32_t)messageId legacyImageInfo:(TGImageInfo *)legacyImageInfo embeddedStickerDocuments:(NSArray *)embeddedStickerDocuments hasStickers:(bool)hasStickers originInfo:(TGMediaOriginInfo *)originInfo;
- (instancetype)initWithMedia:(TGImageMediaAttachment *)media localId:(int64_t)localId peerId:(int64_t)peerId messageId:(int32_t)messageId;

- (NSString *)filePath;

@end
