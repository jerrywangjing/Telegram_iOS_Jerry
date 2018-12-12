

#import <Foundation/Foundation.h>

@interface MTDatacenterAddress : NSObject <NSCoding>

@property (nonatomic, strong, readonly) NSString *host;
@property (nonatomic, strong, readonly) NSString *ip;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) bool preferForMedia;
@property (nonatomic, readonly) bool restrictToTcp;
@property (nonatomic, readonly) bool cdn;
@property (nonatomic, readonly) bool preferForProxy;
@property (nonatomic, readonly) NSData *secret;

- (instancetype)initWithIp:(NSString *)ip port:(uint16_t)port preferForMedia:(bool)preferForMedia restrictToTcp:(bool)restrictToTcp cdn:(bool)cdn preferForProxy:(bool)preferForProxy secret:(NSData *)secret;

- (BOOL)isEqualToAddress:(MTDatacenterAddress *)other;
- (BOOL)isIpv6;

@end
