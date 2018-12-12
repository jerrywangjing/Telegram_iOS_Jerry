#import "TGModernGalleryVideoItem.h"

#import "TGGenericPeerGalleryItem.h"

@class TGUser;
@class TGDocumentMediaAttachment;
@class TGMediaOriginInfo;

@interface TGGenericPeerMediaGalleryVideoItem : TGModernGalleryVideoItem <TGGenericPeerGalleryItem>

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
@property (nonatomic, strong) TGMediaOriginInfo *originInfo;

- (instancetype)initWithVideoMedia:(TGVideoMediaAttachment *)videoMedia peerId:(int64_t)peerId messageId:(int32_t)messageId;
- (instancetype)initWithDocument:(TGDocumentMediaAttachment *)documentMedia peerId:(int64_t)peerId messageId:(int32_t)messageId;

- (NSString *)filePath;

@end
