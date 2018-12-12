#import "TGRecentStickersSignal.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGTelegraph.h"

#import "TGStickersSignals.h"
#import "TGDownloadMessagesSignal.h"

#import "TGAppDelegate.h"

#import "TGTelegramNetworking.h"
#import "TL/TLMetaScheme.h"

#import "TGDocumentMediaAttachment+Telegraph.h"
#import "TGMediaOriginInfo+Telegraph.h"

typedef enum {
    TGStickerSyncActionAdd,
    TGStickerSyncActionDelete
} TGStickerSyncActionType;

@interface TGStickerSyncAction : NSObject

@property (nonatomic, strong, readonly) TGDocumentMediaAttachment *document;
@property (nonatomic, readonly) TGStickerSyncActionType action;

@end

@implementation TGStickerSyncAction

- (instancetype)initWithDocument:(TGDocumentMediaAttachment *)document action:(TGStickerSyncActionType)action {
    self = [super init];
    if (self != nil) {
        _document = document;
        _action = action;
    }
    return self;
}

@end

@implementation TGRecentStickersSignal

+ (SQueue *)queue {
    static SQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[SQueue alloc] init];
    });
    return queue;
}

static bool _syncedStickers = false;

+ (SVariable *)_recentStickers {
    static SVariable *variable = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        variable = [[SVariable alloc] init];
        [variable set:[self _loadRecentStickers]];
    });
    [[self queue] dispatch:^{
        if (!_syncedStickers) {
            _syncedStickers = true;
            [self sync];
        }
    }];
    return variable;
}

+ (NSMutableArray *)_stickerActions {
    static NSMutableArray *array = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        array = [[NSMutableArray alloc] init];
    });
    return array;
}

+ (NSInteger)maxSavedStickers {
    NSData *data = [TGDatabaseInstance() customProperty:@"maxSavedStickers"];
    int32_t value = 0;
    
    if (data.length >= 4) {
        [data getBytes:&value length:4];
    }
    
    return value <= 0 ? 30 : value;
}

+ (void)_enqueueStickerAction:(TGStickerSyncAction *)action {
    [[self queue] dispatch:^{
        NSInteger index = -1;
        for (TGStickerSyncAction *listAction in [self _stickerActions]) {
            index++;
            if (listAction.document.documentId == action.document.documentId) {
                [[self _stickerActions] removeObjectAtIndex:index];
                break;
            }
        }
        
        [[self _stickerActions] addObject:action];
        
        [self sync];
    }];
}

+ (SSignal *)_loadRecentStickers {
    return [[[SSignal alloc] initWithGenerator:^id<SDisposable>(SSubscriber *subscriber) {
        NSData *data = [NSData dataWithContentsOfFile:[self filePath]];
        if (data == nil) {
            data = [[NSUserDefaults standardUserDefaults] objectForKey:@"recentStickers_v0"];
            if (data != nil)
            {
                [data writeToFile:[self filePath] atomically:true];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"recentStickers_v0"];
            }
        }
        if (data == nil) {
            [subscriber putNext:@{}];
            [subscriber putCompletion];
        } else {
            id object = nil;
            @try {
                object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            } @catch (NSException *e) {
            }
            if (object == nil) {
                [subscriber putNext:@{}];
                [subscriber putCompletion];
            } else {
                if ([object isKindOfClass:[NSArray class]])
                {
                    NSDictionary *dict = @{@"documents": object};
                    [subscriber putNext:dict];
                }
                else if ([object isKindOfClass:[NSDictionary class]])
                {
                    [subscriber putNext:object];
                }
                else
                {
                    [subscriber putNext:@{}];
                }
                [subscriber putCompletion];
            }
        }
        
        return nil;
    }] startOn:[self queue]];
}

+ (int32_t)hashForDocumentsReverse:(NSArray *)documents {
    uint32_t acc = 0;
    
    for (TGDocumentMediaAttachment *document in [documents reverseObjectEnumerator]) {
        int64_t docId = document.documentId;
        acc = (acc * 20261) + (uint32_t)(docId >> 32);
        acc = (acc * 20261) + (uint32_t)(docId & 0xFFFFFFFF);
    }
    return (int32_t)(acc % 0x7FFFFFFF);
}

+ (void)sync {
    if (TGTelegraphInstance.clientUserId != 0) {
        [[self queue] dispatch:^{
            [TGTelegraphInstance.genericTasksSignalManager startStandaloneSignalIfNotRunningForKey:@"syncStickers" producer:^SSignal *{
                return [self _syncRecentStickers];
            }];
        }];
    }
}

+ (SSignal *)remoteRecentStickers {
    return [self _remoteRecentStickers:0];
}

+ (SSignal *)_remoteRecentStickers:(int32_t)hash {
    TLRPCmessages_getRecentStickers$messages_getRecentStickers *getRecentStickers = [[TLRPCmessages_getRecentStickers$messages_getRecentStickers alloc] init];
    getRecentStickers.n_hash = hash;
    
    return [[[TGTelegramNetworking instance] requestSignal:getRecentStickers] mapToSignal:^SSignal *(id result) {
        if ([result isKindOfClass:[TLmessages_RecentStickers$messages_recentStickers class]]) {
            TLmessages_RecentStickers$messages_recentStickers *recentStickers = result;
            
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            NSMutableArray *array = [[NSMutableArray alloc] init];
            NSMutableDictionary *dates = [[NSMutableDictionary alloc] init];
            [recentStickers.stickers enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id desc, NSUInteger index, __unused BOOL *stop) {
                int32_t date = [recentStickers.dates[index] int32Value];
                TGDocumentMediaAttachment *document = [[TGDocumentMediaAttachment alloc] initWithTelegraphDocumentDesc:desc];
                if (document.documentId != 0) {
                    document.originInfo = [TGMediaOriginInfo mediaOriginInfoForDocumentRecentSticker:desc];
                    
                    [array addObject:document];
                    
                    dates[@(document.documentId)] = @(date);
                }
            }];
            
            dict[@"documents"] = array;
            dict[@"dates"] = dates;
            
            int32_t localHash = [self hashForDocumentsReverse:array];
            if (localHash != recentStickers.n_hash)
                TGLog(@"(TGRecentStickersSignal hash mismatch)");
            
            [self _storeRecentStickers:dict];
            
            [[self _recentStickers] set:[SSignal single:dict]];
            
            return [SSignal single:dict];
        } else {
            return [SSignal single:nil];
        }
    }];
}

+ (SSignal *)_syncRecentStickers {
    return [[SSignal defer:^SSignal *{
        NSArray *actions = [[NSArray alloc] initWithArray:[self _stickerActions]];
        [[self _stickerActions] removeAllObjects];
        
        SSignal *actionsSignal = [SSignal complete];
        
        for (TGStickerSyncAction *action in actions) {
            SSignal *(^saveStickerSignal)(TGMediaOriginInfo *) = ^SSignal *(TGMediaOriginInfo *originInfo)
            {
                TLRPCmessages_saveRecentSticker$messages_saveRecentSticker *saveSticker = [[TLRPCmessages_saveRecentSticker$messages_saveRecentSticker alloc] init];
                TLInputDocument$inputDocument *inputDocument = [[TLInputDocument$inputDocument alloc] init];
                inputDocument.n_id = action.document.documentId;
                inputDocument.access_hash = action.document.accessHash;
                inputDocument.file_reference = [originInfo fileReference];
                saveSticker.n_id = inputDocument;
                switch (action.action) {
                    case TGStickerSyncActionAdd:
                        saveSticker.unsave = false;
                        break;
                    case TGStickerSyncActionDelete:
                        saveSticker.unsave = true;
                        break;
                }
                return [[TGTelegramNetworking instance] requestSignal:saveSticker];
            };
            
            SSignal *saveActionSignal = [saveStickerSignal(action.document.originInfo) catch:^SSignal *(id error) {
                int32_t errorCode = [[TGTelegramNetworking instance] extractNetworkErrorCode:error];
                NSString *errorText = [[TGTelegramNetworking instance] extractNetworkErrorType:error];
                
                if ([errorText hasPrefix:@"FILE_REFERENCE_"] && errorCode == 400 && action.document.originInfo != nil) {
                    return [[TGDownloadMessagesSignal updatedOriginInfo:action.document.originInfo identifier:action.document.documentId] mapToSignal:^SSignal *(TGMediaOriginInfo *updatedOriginInfo) {
                        return saveStickerSignal(updatedOriginInfo);
                    }];
                } else {
                    return [SSignal fail:error];
                }
            }];
            
            actionsSignal = [actionsSignal then:[[saveActionSignal mapToSignal:^SSignal *(__unused id next) {
                return [SSignal complete];
            }] catch:^SSignal *(__unused id error) {
                return [SSignal complete];
            }]];
        }
        
        return [[actionsSignal then:[[self _loadRecentStickers] mapToSignal:^SSignal *(NSDictionary *dict) {
            return [[self _remoteRecentStickers:[self hashForDocumentsReverse:dict[@"documents"]]] mapToSignal:^SSignal *(__unused id value) {
                return [SSignal complete];
            }];
        }]] then:[[SSignal defer:^SSignal *{
            if ([self _stickerActions].count == 0) {
                return [SSignal complete];
            } else {
                return [self _syncRecentStickers];
            }
        }] startOn:[self queue]]];
    }] startOn:[self queue]];
}

+ (NSString *)filePath {
    return [[TGAppDelegate documentsPath] stringByAppendingPathComponent:@"recentStickers.data"];
}

+ (void)_storeRecentStickers:(NSDictionary *)array {
    [[self queue] dispatch:^{
        [[NSKeyedArchiver archivedDataWithRootObject:array] writeToFile:[self filePath] atomically:true];
    }];
}

+ (void)clearRecentStickers {
    [[self queue] dispatch:^{
        [self _storeRecentStickers:@{}];
        [[self _recentStickers] set:[SSignal single:@{}]];
        [[self _stickerActions] removeAllObjects];
        _syncedStickers = false;
    }];
}

+ (void)addRecentStickerFromDocument:(TGDocumentMediaAttachment *)document {
    if (document.documentId == 0) {
        return;
    }
    
    TGDocumentMediaAttachment *addedDocument = [document copy];
    addedDocument.originInfo = [TGMediaOriginInfo mediaOriginInfoForRecentStickerWithFileReference:document.originInfo.fileReference fileReferences:document.originInfo.fileReferences];
    
    SSignal *signal = [[[[self _recentStickers] signal] take:1] map:^id(NSDictionary *dict) {
        NSMutableDictionary *updatedDict = [dict mutableCopy];
        NSMutableArray *updatedDocuments = [[NSMutableArray alloc] initWithArray:updatedDict[@"documents"]];
        NSMutableDictionary *updatedDates = [[NSMutableDictionary alloc] initWithDictionary:updatedDict[@"dates"]];
        NSInteger index = -1;
        int64_t documentId = addedDocument.documentId;
        
        int32_t currentTime = (int32_t)[[NSDate date] timeIntervalSince1970];
        updatedDates[@(documentId)] = @(currentTime);
        
        for (TGDocumentMediaAttachment *document in updatedDocuments) {
            index++;
            if (document.documentId == documentId) {
                [updatedDocuments removeObjectAtIndex:index];
                break;
            }
        }

        [updatedDocuments addObject:addedDocument];
        NSUInteger limit = [self maxSavedStickers];
        if (updatedDocuments.count > limit) {
            [updatedDocuments removeObjectsInRange:NSMakeRange(0, updatedDocuments.count - limit)];
        }
        updatedDict[@"documents"] = updatedDocuments;
        updatedDict[@"dates"] = updatedDates;
        [self _storeRecentStickers:updatedDict];
        
        return updatedDict;
    }];
    [signal startWithNext:^(id next) {
        [[self _recentStickers] set:[SSignal single:next]];
    }];
    
    [self _enqueueStickerAction:[[TGStickerSyncAction alloc] initWithDocument:document action:TGStickerSyncActionAdd]];
}

+ (void)addRemoteRecentStickerFromDocuments:(NSArray *)addedDocuments sync:(bool)sync {
    SSignal *signal = [[[[self _recentStickers] signal] take:1] map:^id(NSDictionary *dict) {
        NSMutableDictionary *updatedDict = [dict mutableCopy];
        NSMutableArray *updatedDocuments = [[NSMutableArray alloc] initWithArray:updatedDict[@"documents"]];
        NSMutableDictionary *updatedDates = [[NSMutableDictionary alloc] initWithDictionary:updatedDict[@"dates"]];
        
        int32_t currentTime = (int32_t)[[NSDate date] timeIntervalSince1970];
        for (TGDocumentMediaAttachment *document in addedDocuments) {
            TGDocumentMediaAttachment *addedDocument = [document copy];
            addedDocument.originInfo = [TGMediaOriginInfo mediaOriginInfoForRecentStickerWithFileReference:document.originInfo.fileReference fileReferences:document.originInfo.fileReferences];
            
            int64_t documentId = addedDocument.documentId;
            NSInteger index = -1;
            for (TGDocumentMediaAttachment *document in updatedDocuments) {
                index++;
                if (document.documentId == documentId) {
                    [updatedDocuments removeObjectAtIndex:index];
                    break;
                }
            }
            [updatedDocuments addObject:addedDocument];
            
            updatedDates[@(addedDocument.documentId)] = @(currentTime);
        }
        NSUInteger limit = [self maxSavedStickers];
        if (updatedDocuments.count > limit) {
            [updatedDocuments removeObjectsInRange:NSMakeRange(0, updatedDocuments.count - limit)];
        }
        updatedDict[@"documents"] = updatedDocuments;
        updatedDict[@"dates"] = updatedDates;
        [self _storeRecentStickers:updatedDict];
        
        return updatedDict;
    }];
    [signal startWithNext:^(id next) {
        [[self _recentStickers] set:[SSignal single:next]];
    }];
    
    if (sync) {
        for (TGDocumentMediaAttachment *addedDocument in addedDocuments) {
            [self _enqueueStickerAction:[[TGStickerSyncAction alloc] initWithDocument:addedDocument  action:TGStickerSyncActionAdd]];
        }
    }
}

+ (void)removeRecentStickerByDocumentId:(int64_t)documentId {
    SSignal *signal = [[[[self _recentStickers] signal] take:1] map:^id(NSDictionary *dict) {
        NSMutableDictionary *updatedDict = [dict mutableCopy];
        NSMutableArray *updatedDocuments = [[NSMutableArray alloc] initWithArray:updatedDict[@"documents"]];
        NSInteger index = -1;
        for (TGDocumentMediaAttachment *document in updatedDocuments) {
            index++;
            if (document.documentId == documentId) {
                [self _enqueueStickerAction:[[TGStickerSyncAction alloc] initWithDocument:document action:TGStickerSyncActionDelete]];
                [updatedDocuments removeObjectAtIndex:index];
                break;
            }
        }
        updatedDict[@"documents"] = updatedDocuments;
        
        [self _storeRecentStickers:updatedDict];
        
        return updatedDict;
    }];
    [signal startWithNext:^(id next) {
        [[self _recentStickers] set:[SSignal single:next]];
    }];
}

+ (SSignal *)recentStickers {
    return [[self _recentStickers] signal];
}

@end
