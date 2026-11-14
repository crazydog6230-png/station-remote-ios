#import <Foundation/Foundation.h>

@protocol WSDelegate <NSObject>
- (void)wsDidOpen:(id)ws;
- (void)ws:(id)ws didReceiveText:(NSString *)text;
- (void)ws:(id)ws didFail:(NSString *)reason;
@end

@interface WS : NSObject
- (instancetype)initWithHost:(NSString *)host
                        port:(int)port
                       token:(NSString *)deviceToken
                    delegate:(id<WSDelegate>)delegate;
- (void)connect;
- (void)close;
- (void)sendCommand:(NSDictionary *)payload;
@property (nonatomic, readonly) BOOL opened;
@end
