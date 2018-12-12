#import "MTBackupAddressSignals.h"

#if defined(MtProtoKitDynamicFramework)
#   import <MTProtoKitDynamic/MTSignal.h>
#   import <MTProtoKitDynamic/MTQueue.h>
#   import <MTProtoKitDynamic/MTHttpRequestOperation.h>
#   import <MTProtoKitDynamic/MTEncryption.h>
#   import <MTProtoKitDynamic/MTRequestMessageService.h>
#   import <MTProtoKitDynamic/MTRequest.h>
#   import <MTProtoKitDynamic/MTContext.h>
#   import <MTProtoKitDynamic/MTApiEnvironment.h>
#   import <MTProtoKitDynamic/MTDatacenterAddress.h>
#   import <MTProtoKitDynamic/MTDatacenterAddressSet.h>
#   import <MTProtoKitDynamic/MTProto.h>
#   import <MTProtoKitDynamic/MTSerialization.h>
#   import <MTProtoKitDynamic/MTLogging.h>
#elif defined(MtProtoKitMacFramework)
#   import <MTProtoKitMac/MTSignal.h>
#   import <MTProtoKitMac/MTQueue.h>
#   import <MTProtoKitMac/MTHttpRequestOperation.h>
#   import <MTProtoKitMac/MTEncryption.h>
#   import <MTProtoKitMac/MTRequestMessageService.h>
#   import <MTProtoKitMac/MTRequest.h>
#   import <MTProtoKitMac/MTContext.h>
#   import <MTProtoKitMac/MTApiEnvironment.h>
#   import <MTProtoKitMac/MTDatacenterAddress.h>
#   import <MTProtoKitMac/MTDatacenterAddressSet.h>
#   import <MTProtoKitMac/MTProto.h>
#   import <MTProtoKitMac/MTSerialization.h>
#   import <MTProtoKitMac/MTLogging.h>
#else
#   import <MTProtoKit/MTSignal.h>
#   import <MTProtoKit/MTQueue.h>
#   import <MTProtoKit/MTHttpRequestOperation.h>
#   import <MTProtoKit/MTEncryption.h>
#   import <MTProtoKit/MTRequestMessageService.h>
#   import <MTProtoKit/MTRequest.h>
#   import <MTProtoKit/MTContext.h>
#   import <MTProtoKit/MTApiEnvironment.h>
#   import <MTProtoKit/MTDatacenterAddress.h>
#   import <MTProtoKit/MTDatacenterAddressSet.h>
#   import <MTProtoKit/MTProto.h>
#   import <MTProtoKit/MTSerialization.h>
#   import <MTProtoKit/MTLogging.h>
#endif

static NSData *base64_decode(NSString *str) {
    if ([NSData instancesRespondToSelector:@selector(initWithBase64EncodedString:options:)]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:str options:NSDataBase64DecodingIgnoreUnknownCharacters];
        return data;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [[NSData alloc] initWithBase64Encoding:[str stringByReplacingOccurrencesOfString:@"[^A-Za-z0-9+/=]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, [str length])]];
#pragma clang diagnostic pop
    }
}

@implementation MTBackupAddressSignals

+ (bool)checkIpData:(MTBackupDatacenterData *)data timestamp:(int32_t)timestamp source:(NSString *)source {
    if (data.timestamp >= timestamp + 60 * 20 || data.expirationDate <= timestamp - 60 * 20) {
        if (MTLogEnabled()) {
            MTLog(@"[Backup address fetch: backup config from %@ validity interval %d ... %d does not include current %d]", source, data.timestamp, data.expirationDate, timestamp);
        }
        return false;
    } else {
        return true;
    }
}

+ (MTSignal *)fetchBackupIpsResolveGoogle:(bool)isTesting phoneNumber:(NSString *)phoneNumber currentContext:(MTContext *)currentContext {
    NSArray *hosts = @[
        @"google.com",
        @"www.google.com",
        @"google.ru"
    ];
    NSDictionary *headers = @{@"Host": @"dns.google.com"};
    
    NSMutableArray *signals = [[NSMutableArray alloc] init];
    for (NSString *host in hosts) {
        MTSignal *signal = [[[MTHttpRequestOperation dataForHttpUrl:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/resolve?name=%@&type=16", host, isTesting ? @"tapv2.stel.com" : @"apv2.stel.com"]] headers:headers] mapToSignal:^MTSignal *(NSData *data) {
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([dict respondsToSelector:@selector(objectForKey:)]) {
                NSArray *answer = dict[@"Answer"];
                NSMutableArray *strings = [[NSMutableArray alloc] init];
                if ([answer respondsToSelector:@selector(objectAtIndex:)]) {
                    for (NSDictionary *value in answer) {
                        if ([value respondsToSelector:@selector(objectForKey:)]) {
                            NSString *part = value[@"data"];
                            if ([part respondsToSelector:@selector(characterAtIndex:)]) {
                                [strings addObject:part];
                            }
                        }
                    }
                    [strings sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
                        if (lhs.length > rhs.length) {
                            return NSOrderedAscending;
                        } else {
                            return NSOrderedDescending;
                        }
                    }];
                    
                    NSString *finalString = @"";
                    for (NSString *string in strings) {
                        finalString = [finalString stringByAppendingString:[string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]]];
                    }
                    
                    NSData *result = base64_decode(finalString);
                    NSMutableData *finalData = [[NSMutableData alloc] initWithData:result];
                    [finalData setLength:256];
                    MTBackupDatacenterData *datacenterData = MTIPDataDecode(finalData, phoneNumber);
                    if (datacenterData != nil && [self checkIpData:datacenterData timestamp:(int32_t)[currentContext globalTime] source:@"resolveGoogle"]) {
                        return [MTSignal single:datacenterData];
                    }
                }
            }
            return [MTSignal complete];
        }] catch:^MTSignal *(__unused id error) {
            return [MTSignal complete];
        }];
        if (signals.count != 0) {
            signal = [signal delay:signals.count onQueue:[[MTQueue alloc] init]];
        }
        [signals addObject:signal];
    }
    
    return [[MTSignal mergeSignals:signals] take:1];
}

+ (MTSignal *)fetchConfigFromAddress:(MTBackupDatacenterAddress *)address currentContext:(MTContext *)currentContext {
    MTApiEnvironment *apiEnvironment = [currentContext.apiEnvironment copy];
    
    NSMutableDictionary *datacenterAddressOverrides = [[NSMutableDictionary alloc] init];
    
    datacenterAddressOverrides[@(address.datacenterId)] = [[MTDatacenterAddress alloc] initWithIp:address.ip port:(uint16_t)address.port preferForMedia:false restrictToTcp:false cdn:false preferForProxy:false secret:address.secret];
    apiEnvironment.datacenterAddressOverrides = datacenterAddressOverrides;
    
    apiEnvironment.apiId = currentContext.apiEnvironment.apiId;
    apiEnvironment.layer = currentContext.apiEnvironment.layer;
    apiEnvironment = [apiEnvironment withUpdatedLangPackCode:currentContext.apiEnvironment.langPackCode];
    apiEnvironment.disableUpdates = true;
    apiEnvironment.langPack = currentContext.apiEnvironment.langPack;
    
    MTContext *context = [[MTContext alloc] initWithSerialization:currentContext.serialization apiEnvironment:apiEnvironment isTestingEnvironment:currentContext.isTestingEnvironment useTempAuthKeys:address.datacenterId != 0 ? currentContext.useTempAuthKeys : false];
    
    if (address.datacenterId != 0) {
        context.keychain = currentContext.keychain;
    }
    
    MTProto *mtProto = [[MTProto alloc] initWithContext:context datacenterId:address.datacenterId usageCalculationInfo:nil];
    if (address.datacenterId != 0) {
        mtProto.useTempAuthKeys = currentContext.useTempAuthKeys;
    }
    MTRequestMessageService *requestService = [[MTRequestMessageService alloc] initWithContext:context];
    [mtProto addMessageService:requestService];
    
    [mtProto resume];
    
    MTRequest *request = [[MTRequest alloc] init];
    
    NSData *getConfigData = nil;
    MTRequestDatacenterAddressListParser responseParser = [currentContext.serialization requestDatacenterAddressWithData:&getConfigData];
    
    [request setPayload:getConfigData metadata:@"getConfig" responseParser:responseParser];
    
    __weak MTContext *weakCurrentContext = currentContext;
    return [[MTSignal alloc] initWithGenerator:^id<MTDisposable>(MTSubscriber *subscriber) {
        [request setCompleted:^(MTDatacenterAddressListData *result, __unused NSTimeInterval completionTimestamp, id error)
         {
             if (error == nil) {
                 __strong MTContext *strongCurrentContext = weakCurrentContext;
                 if (strongCurrentContext != nil) {
                     [result.addressList enumerateKeysAndObjectsUsingBlock:^(NSNumber *nDatacenterId, NSArray *list, __unused BOOL *stop) {
                         MTDatacenterAddressSet *addressSet = [[MTDatacenterAddressSet alloc] initWithAddressList:list];
                         
                         MTDatacenterAddressSet *currentAddressSet = [context addressSetForDatacenterWithId:[nDatacenterId integerValue]];
                         
                         if (currentAddressSet == nil || ![addressSet isEqual:currentAddressSet])
                         {
                             if (MTLogEnabled()) {
                                 MTLog(@"[Backup address fetch: updating datacenter %d address set to %@]", [nDatacenterId intValue], addressSet);
                             }
                             
                             [strongCurrentContext updateAddressSetForDatacenterWithId:[nDatacenterId integerValue] addressSet:addressSet forceUpdateSchemes:true];
                             [subscriber putNext:@true];
                             [subscriber putCompletion];
                         }
                     }];
                 }
             } else {
                 [subscriber putCompletion];
             }
         }];
        
        [requestService addRequest:request];
        
        id requestId = request.internalId;
        return [[MTBlockDisposable alloc] initWithBlock:^{
            [requestService removeRequestByInternalId:requestId];
            [mtProto pause];
        }];
    }];
}

+ (MTSignal * _Nonnull)fetchBackupIps:(bool)isTestingEnvironment currentContext:(MTContext * _Nonnull)currentContext additionalSource:(MTSignal * _Nullable)additionalSource phoneNumber:(NSString * _Nullable)phoneNumber {
    NSMutableArray *signals = [[NSMutableArray alloc] init];
    [signals addObject:[self fetchBackupIpsResolveGoogle:isTestingEnvironment phoneNumber:phoneNumber currentContext:currentContext]];
    if (additionalSource != nil) {
        [signals addObject:additionalSource];
    }
    
    return [[[MTSignal mergeSignals:signals] take:1] mapToSignal:^MTSignal *(MTBackupDatacenterData *data) {
        if (data != nil && data.addressList.count != 0) {
            NSMutableArray *signals = [[NSMutableArray alloc] init];
            NSTimeInterval delay = 0.0;
            for (MTBackupDatacenterAddress *address in data.addressList) {
                MTSignal *signal = [self fetchConfigFromAddress:address currentContext:currentContext];
                if (delay > DBL_EPSILON) {
                    signal = [signal delay:delay onQueue:[[MTQueue alloc] init]];
                }
                [signals addObject:signal];
                delay += 5.0;
            }
            return [[MTSignal mergeSignals:signals] take:1];
        }
        return [MTSignal complete];
    }];
}

@end
