#import "TelegramMediaResources.h"

#import <LegacyComponents/TGStringUtils.h>
#import <LegacyComponents/TGMediaOriginInfo.h>

#import "TL/TLMetaScheme.h"

@interface CloudFileMediaResourceId : NSObject <MediaResourceId>

@property (nonatomic, readonly) int32_t datacenterId;
@property (nonatomic, readonly) int64_t volumeId;
@property (nonatomic, readonly) int32_t localId;
@property (nonatomic, readonly) int64_t secret;

@end

@implementation CloudFileMediaResourceId

- (instancetype)initWithDatacenterId:(int32_t)datacenterId volumeId:(int64_t)volumeId localId:(int32_t)localId secret:(int64_t)secret {
    self = [super init];
    if (self != nil) {
        _datacenterId = datacenterId;
        _volumeId = volumeId;
        _localId = localId;
        _secret = secret;
    }
    return self;
}

- (NSUInteger)hash {
    return _volumeId ^ _localId;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CloudFileMediaResourceId class]] && _datacenterId == ((CloudFileMediaResourceId *)object)->_datacenterId && _volumeId == ((CloudFileMediaResourceId *)object)->_volumeId && _localId == ((CloudFileMediaResourceId *)object)->_localId && _secret == ((CloudFileMediaResourceId *)object)->_secret;
}

- (NSString *)uniqueId {
    return [[NSString alloc] initWithFormat:@"telegram-cloud-file-%d-%lld-%d-%lld", _datacenterId, _volumeId, _localId, _secret];
}

- (instancetype)copyWithZone:(NSZone *)__unused zone {
    return self;
}

@end

@implementation CloudFileMediaResource

- (instancetype)initWithDatacenterId:(int32_t)datacenterId volumeId:(int64_t)volumeId localId:(int32_t)localId secret:(int64_t)secret size:(NSNumber *)size legacyCacheUrl:(NSString *)legacyCacheUrl legacyCachePath:(NSString *)legacyCachePath mediaType:(id)mediaType originInfo:(TGMediaOriginInfo *)originInfo identifier:(int64_t)identifier {
    self = [super init];
    if (self != nil) {
        _datacenterId = datacenterId;
        _volumeId = volumeId;
        _localId = localId;
        _secret = secret;
        _size = size;
        _legacyCacheUrl = legacyCacheUrl;
        _legacyCachePath = legacyCachePath;
        _mediaType = mediaType;
        _originInfo = originInfo;
                _identifier = identifier;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CloudFileMediaResource class]] && _datacenterId == ((CloudFileMediaResource *)object)->_datacenterId && _volumeId == ((CloudFileMediaResource *)object)->_volumeId && _localId == ((CloudFileMediaResource *)object)->_localId && _secret == ((CloudFileMediaResource *)object)->_secret;
}

- (id<MediaResourceId>)resourceId {
    return [[CloudFileMediaResourceId alloc] initWithDatacenterId:_datacenterId volumeId:_volumeId localId:_localId secret:_secret];
}

- (TLInputFileLocation *)apiInputLocation {
    TLInputFileLocation$inputFileLocation *location = [[TLInputFileLocation$inputFileLocation alloc] init];
    location.volume_id = _volumeId;
    location.local_id = _localId;
    location.secret = _secret;
    location.file_reference = [_originInfo fileReferenceForVolumeId:_volumeId localId:_localId];
    return location;
}

@end

@interface CloudDocumentMediaResourceId : NSObject <MediaResourceId>

@property (nonatomic, readonly) int64_t fileId;

@end

@implementation CloudDocumentMediaResourceId

- (instancetype)initWithFileId:(int64_t)fileId {
    self = [super init];
    if (self != nil) {
        _fileId = fileId;
    }
    return self;
}

- (NSUInteger)hash {
    return _fileId;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CloudDocumentMediaResourceId class]] && _fileId == ((CloudDocumentMediaResourceId *)object)->_fileId;
}

- (NSString *)uniqueId {
    return [[NSString alloc] initWithFormat:@"telegram-cloud-document-%lld", _fileId];
}

- (instancetype)copyWithZone:(NSZone *)__unused zone {
    return self;
}

@end

@implementation CloudDocumentMediaResource

- (instancetype)initWithDatacenterId:(int32_t)datacenterId fileId:(int64_t)fileId accessHash:(int64_t)accessHash size:(NSNumber *)size mediaType:(id)mediaType originInfo:(TGMediaOriginInfo *)originInfo identifier:(int64_t)identifier {
    self = [super init];
    if (self != nil) {
        _datacenterId = datacenterId;
        _fileId = fileId;
        _accessHash = accessHash;
        _size = size;
        _mediaType = mediaType;
        _originInfo = originInfo;
        _identifier = identifier;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CloudDocumentMediaResource class]] && _datacenterId == ((CloudDocumentMediaResource *)object)->_datacenterId && _fileId == ((CloudDocumentMediaResource *)object)->_fileId && _accessHash == ((CloudDocumentMediaResource *)object)->_accessHash;
}

- (id<MediaResourceId>)resourceId {
    return [[CloudDocumentMediaResourceId alloc] initWithFileId:_fileId];
}

- (TLInputFileLocation *)apiInputLocation {
    TLInputFileLocation$inputDocumentFileLocation *location = [[TLInputFileLocation$inputDocumentFileLocation alloc] init];
    location.n_id = _fileId;
    location.access_hash = _accessHash;
    location.file_reference = [_originInfo fileReference];
    return location;
}

@end

@interface CloudSecureMediaResourceId : NSObject <MediaResourceId>

@property (nonatomic, readonly) NSString *fileHash;
@property (nonatomic, readonly) int64_t fileId;
@property (nonatomic, readonly) bool thumbnail;

@end

@implementation CloudSecureMediaResourceId

- (instancetype)initWithFileHash:(NSString *)fileHash fileId:(int64_t)fileId thumbnail:(bool)thumbnail {
    self = [super init];
    if (self != nil) {
        _fileHash = fileHash;
        _fileId = fileId;
        _thumbnail = thumbnail;
    }
    return self;
}

- (NSUInteger)hash {
    return _fileHash.hash;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CloudSecureMediaResourceId class]] && TGObjectCompare(_fileHash, ((CloudSecureMediaResourceId *)object)->_fileHash) && _thumbnail == ((CloudSecureMediaResourceId *)object)->_thumbnail;
}

- (NSString *)uniqueId {
    NSString *uniqueId = [[NSString alloc] initWithFormat:@"telegram-secure-document-%@", _fileHash];
    if (_thumbnail)
        uniqueId = [uniqueId stringByAppendingString:@"-thumb"];
    return uniqueId;
}

- (instancetype)copyWithZone:(NSZone *)__unused zone {
    return self;
}

@end

@implementation CloudSecureMediaResource

- (instancetype)initWithDatacenterId:(int32_t)datacenterId fileId:(int64_t)fileId accessHash:(int64_t)accessHash size:(NSNumber *)size fileHash:(NSData *)fileHash thumbnail:(bool)thumbnail mediaType:(id)mediaType {
    self = [super init];
    if (self != nil) {
        _datacenterId = datacenterId;
        _fileId = fileId;
        _accessHash = accessHash;
        _size = size;
        _fileHash = fileHash;
        _thumbnail = thumbnail;
        _mediaType = mediaType;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CloudSecureMediaResource class]] && [_fileHash isEqual:((CloudSecureMediaResource *)object)->_fileHash] && _thumbnail == ((CloudSecureMediaResource *)object)->_thumbnail;
}

- (id<MediaResourceId>)resourceId {
    return [[CloudSecureMediaResourceId alloc] initWithFileHash:[_fileHash stringByEncodingInHex] fileId:_fileId thumbnail:_thumbnail];
}

- (TLInputFileLocation *)apiInputLocation {
    if (_thumbnail)
        return nil;
    TLInputFileLocation$inputSecureFileLocation *location = [[TLInputFileLocation$inputSecureFileLocation alloc] init];
    location.n_id = _fileId;
    location.access_hash = _accessHash;
    return location;
}

@end

