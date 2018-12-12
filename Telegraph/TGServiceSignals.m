#import "TGServiceSignals.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TL/TLMetaScheme.h"
#import "TGTelegramNetworking.h"
#import "TGTelegraph.h"

#import "TLhelp_DeepLinkInfo$help_deepLinkInfo.h"
#import "TLRPChelp_getDeepLinkInfo.h"
#import "TLRPChelp_getPassportConfig.h"

#import "TGPassportLanguageMap.h"

#import "TGMessage+Telegraph.h"

@implementation TGDeepLinkInfo

- (instancetype)initWithTL:(TLhelp_DeepLinkInfo *)tl
{
    if ([tl isKindOfClass:[TLhelp_DeepLinkInfo$help_deepLinkInfo class]])
    {
        TLhelp_DeepLinkInfo$help_deepLinkInfo *info = (TLhelp_DeepLinkInfo$help_deepLinkInfo *)tl;
        self = [super init];
        if (self != nil)
        {
            _updateNeeded = info.flags & (1 << 0);
            _message = info.message;
            _entities = [TGMessage parseTelegraphEntities:info.entities];
        }
        return self;
    }
    return nil;
}

@end

@implementation TGServiceSignals

+ (SSignal *)appChangelogMessages:(NSString *)previousVersion {
    TLRPChelp_getAppChangelog$help_getAppChangelog *getAppChangelog = [[TLRPChelp_getAppChangelog$help_getAppChangelog alloc] init];
    /*NSString *versionString = [[NSString alloc] initWithFormat:@"%@ (%@)", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"], [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
    getAppChangelog.app_version = versionString;
    getAppChangelog.lang_code = [[NSLocale preferredLanguages] objectAtIndex:0];*/
    getAppChangelog.prev_app_version = previousVersion;
    
    return [[[TGTelegramNetworking instance] requestSignal:getAppChangelog] map:^id(TLUpdates *result) {
        if ([result isKindOfClass:[TLUpdates$updates class]]) {
            return ((TLUpdates$updates *)result).updates;
        } else if ([result isKindOfClass:[TLUpdates$updateShort class]]) {
            return @[((TLUpdates$updateShort *)result).update];
        } else {
            return nil;
        }
    }];
}

+ (SSignal *)reportSpam:(int64_t)peerId accessHash:(int64_t)accessHash {
    if (TGPeerIdIsSecretChat(peerId)) {
        return [[TGDatabaseInstance() modify:^id{
            TLRPCmessages_reportEncryptedSpam$messages_reportEncryptedSpam *reportEncryptedSpam = [[TLRPCmessages_reportEncryptedSpam$messages_reportEncryptedSpam alloc] init];
            TLInputEncryptedChat$inputEncryptedChat *inputChat = [[TLInputEncryptedChat$inputEncryptedChat alloc] init];
            TGConversation *conversation = [TGDatabaseInstance() loadConversationWithId:peerId];
            inputChat.chat_id = (int32_t)conversation.encryptedData.encryptedConversationId;
            inputChat.access_hash = conversation.encryptedData.accessHash;
            reportEncryptedSpam.peer = inputChat;
            
            TLRPCcontacts_block$contacts_block *block = [[TLRPCcontacts_block$contacts_block alloc] init];
            TGUser *user = [TGDatabaseInstance() loadUser:[TGDatabaseInstance() encryptedParticipantIdForConversationId:peerId]];
            TLInputUser$inputUser *inputUser = [[TLInputUser$inputUser alloc] init];
            inputUser.user_id = user.uid;
            inputUser.access_hash = user.phoneNumberHash;
            block.n_id = inputUser;
            
            return [SSignal mergeSignals:@[[[TGTelegramNetworking instance] requestSignal:reportEncryptedSpam], [[TGTelegramNetworking instance] requestSignal:block]]];
        }] switchToLatest];
    } else {
        TLInputPeer *inputPeer = nil;
        
        TLInputPeer$inputPeerUser *inputPeerUser = [[TLInputPeer$inputPeerUser alloc] init];
        inputPeerUser.user_id = (int32_t)peerId;
        inputPeerUser.access_hash = accessHash;
        inputPeer = inputPeerUser;
        
        if (inputPeer == nil) {
            return [SSignal complete];
        }
        
        TLRPCmessages_reportSpam$messages_reportSpam *reportSpam = [[TLRPCmessages_reportSpam$messages_reportSpam alloc] init];
        reportSpam.peer = inputPeer;
        
        TLRPCcontacts_block$contacts_block *block = [[TLRPCcontacts_block$contacts_block alloc] init];
        TLInputUser$inputUser *inputUser = [[TLInputUser$inputUser alloc] init];
        inputUser.user_id = (int32_t)peerId;
        inputUser.access_hash = accessHash;
        block.n_id = inputUser;
        
        return [SSignal mergeSignals:@[[[TGTelegramNetworking instance] requestSignal:reportSpam], [[TGTelegramNetworking instance] requestSignal:block]]];
    }
}

+ (SSignal *)deepLinkInfo:(NSString *)path {
    TLRPChelp_getDeepLinkInfo *getDeepLinkInfo = [[TLRPChelp_getDeepLinkInfo alloc] init];
    getDeepLinkInfo.path = path;
    
    return [[[TGTelegramNetworking instance] requestSignal:getDeepLinkInfo] map:^id(TLhelp_DeepLinkInfo *result) {
        return [[TGDeepLinkInfo alloc] initWithTL:result];
    }];
}

+ (SSignal *)passportLanguages:(int32_t)hash {
    TLRPChelp_getPassportConfig *getPassportConfig = [[TLRPChelp_getPassportConfig alloc] init];
    getPassportConfig.n_hash = hash;
    
    return [[[TGTelegramNetworking instance] requestSignal:getPassportConfig] map:^id(TLhelp_PassportConfig *result) {
        if ([result isKindOfClass:[TLhelp_PassportConfig$help_passportConfig class]])
        {
            TLhelp_PassportConfig$help_passportConfig *config = (TLhelp_PassportConfig$help_passportConfig *)result;
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[config.countries_langs.data dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            
            if ([dict isKindOfClass:[NSDictionary class]])
                return [[TGPassportLanguageMap alloc] initWithMap:dict hash:config.n_hash];
        }
        return nil;
    }];
}

@end
