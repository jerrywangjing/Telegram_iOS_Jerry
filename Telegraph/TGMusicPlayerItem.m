#import "TGMusicPlayerItem.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGBotContextExternalResult.h"
#import "TGBotContextMediaResult.h"

@interface TGMusicPlayerItem () {
    bool _isVoice;
}

@end

@implementation TGMusicPlayerItem

+ (instancetype)itemWithMessage:(TGMessage *)message author:(TGUser *)author
{
    TGDocumentMediaAttachment *document = nil;
    for (id attachment in message.mediaAttachments)
    {
        if ([attachment isKindOfClass:[TGDocumentMediaAttachment class]])
        {
            document = attachment;
            if (document.originInfo == nil)
                document.originInfo = [TGMediaOriginInfo mediaOriginInfoWithFileReference:nil fileReferences:nil cid:message.cid mid:message.mid];
            break;
        } else if ([attachment isKindOfClass:[TGAudioMediaAttachment class]]) {
            TGMusicPlayerItem *item = [[TGMusicPlayerItem alloc] initWithKey:@(message.mid) media:attachment peerId:message.cid author:author date:(int32_t)message.date performer:nil title:nil duration:((TGAudioMediaAttachment *)attachment).duration];
            item->_peerId = message.fromUid;
            item->_isVoice = true;
            return item;
        } else if ([attachment isKindOfClass:[TGWebPageMediaAttachment class]]) {
            document = ((TGWebPageMediaAttachment *)attachment).document;
            if (document.originInfo == nil)
                document.originInfo = [TGMediaOriginInfo mediaOriginInfoWithFileReference:nil fileReferences:nil url:((TGWebPageMediaAttachment *)attachment).url];
            break;
        } else if ([attachment isKindOfClass:[TGVideoMediaAttachment class]]) {
            if (((TGVideoMediaAttachment *)attachment).roundMessage) {
                if (((TGVideoMediaAttachment *)attachment).originInfo == nil)
                    ((TGVideoMediaAttachment *)attachment).originInfo = [TGMediaOriginInfo mediaOriginInfoWithFileReference:nil fileReferences:nil cid:message.cid mid:message.mid];
                
                TGMusicPlayerItem *item = [[TGMusicPlayerItem alloc] initWithKey:@(message.mid) media:attachment peerId:message.cid author:author date:(int32_t)message.date performer:nil title:nil duration:((TGVideoMediaAttachment *)attachment).duration];
                item->_peerId = message.fromUid;
                item->_isVoice = true;
                return item;
            }
        }
    }
    
    if (document != nil) {
        for (id attribute in document.attributes)
        {
            if ([attribute isKindOfClass:[TGDocumentAttributeAudio class]])
            {
                TGDocumentAttributeAudio *audio = attribute;
                TGMusicPlayerItem *item = [[TGMusicPlayerItem alloc] initWithKey:@(message.mid) media:document peerId:message.cid author:author date:(int32_t)message.date performer:audio.performer title:audio.title duration:audio.duration];\
                item->_peerId = message.fromUid;
                item->_isVoice = audio.isVoice;
                return item;
            }
            else if ([attribute isKindOfClass:[TGDocumentAttributeVideo class]])
            {
                TGDocumentAttributeVideo *video = attribute;
                if (video.isRoundMessage)
                {
                    TGMusicPlayerItem *item = [[TGMusicPlayerItem alloc] initWithKey:@(message.mid) media:document peerId:message.cid author:author date:(int32_t)message.date performer:nil title:nil duration:video.duration];
                    item->_peerId = message.fromUid;
                    item->_isVoice = true;
                    return item;
                }
            }
        }
    }
    
    return nil;
}

+ (instancetype)itemWithBotContextResult:(TGBotContextResult *)result {
    if ([result isKindOfClass:[TGBotContextMediaResult class]]) {
        TGDocumentMediaAttachment *document = ((TGBotContextMediaResult *)result).document;
        if (document != nil) {
            for (id attribute in document.attributes) {
                if ([attribute isKindOfClass:[TGDocumentAttributeAudio class]]) {
                    TGDocumentAttributeAudio *audio = attribute;
                    TGMusicPlayerItem *item = [[TGMusicPlayerItem alloc] initWithKey:result.resultId media:document peerId:0 author:nil date:0 performer:audio.performer title:audio.title duration:audio.duration];
                    item->_isVoice = ((TGDocumentAttributeAudio *)attribute).isVoice;
                    return item;
                }
            }
        }
    } else if ([result isKindOfClass:[TGBotContextExternalResult class]]) {
        TGBotContextExternalResult *externalResult = (TGBotContextExternalResult *)result;
        NSArray *contentTypes = @[
            @"audio/mpeg",
            @"audio/ogg",
            @"audio/aac"
        ];
        if (([externalResult.type isEqualToString:@"audio"] || [externalResult.type isEqualToString:@"voice"]) && externalResult.content.mimeType != nil && [contentTypes containsObject:externalResult.content.mimeType]) {
            TGMusicPlayerItem *item  = [[TGMusicPlayerItem alloc] initWithKey:result.resultId media:result peerId:0 author:nil date:0 performer:externalResult.pageDescription title:externalResult.title duration:externalResult.duration];
            item->_isVoice = false;
            return item;
        }
    }

    return nil;
}

+ (instancetype)itemWithInstantDocument:(TGDocumentMediaAttachment *)document {
    for (id attribute in document.attributes)
    {
        if ([attribute isKindOfClass:[TGDocumentAttributeAudio class]])
        {
            TGDocumentAttributeAudio *audio = attribute;
            TGMusicPlayerItem *item = [[TGMusicPlayerItem alloc] initWithKey:@(document.documentId) media:document peerId:0 author:nil date:0 performer:audio.performer title:audio.title duration:audio.duration];
            item->_isVoice = audio.isVoice;
            return item;
        }
    }
    return nil;
}

- (instancetype)initWithKey:(id<NSObject, NSCopying>)key media:(id)media peerId:(int64_t)peerId author:(TGUser *)author date:(int32_t)date performer:(NSString *)performer title:(NSString *)title duration:(int32_t)duration
{
    self = [super init];
    if (self != nil)
    {
        _key = key;
        _media = media;
        _conversationId = peerId;
        _author = author;
        _date = date;
        _performer = performer;
        _title = title;
        _duration = duration;
    }
    return self;
}

- (bool)isVoice {
    return _isVoice;
}

- (bool)isVideo {
    return [self.media isKindOfClass:[TGVideoMediaAttachment class]] || ([self.media isKindOfClass:[TGDocumentMediaAttachment class]] && ((TGDocumentMediaAttachment *)self.media).isRoundVideo);
}

- (TGImageInfo *)thumbnailInfo {
    if ([self.media isKindOfClass:[TGVideoMediaAttachment class]])
        return ((TGVideoMediaAttachment *)self.media).thumbnailInfo;
    return nil;
}

@end
