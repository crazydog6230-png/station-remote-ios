#import <Foundation/Foundation.h>

@interface Glagol : NSObject
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) int port;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *error;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) double volume;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *cover;
@property (nonatomic, copy) NSString *trackId;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) double duration;
@property (nonatomic, copy) NSString *alice;
@property (nonatomic, strong) NSArray *devices;
@property (nonatomic, copy) void (^onChange)(void);

- (void)start;
- (void)stop;
- (void)action:(NSString *)what value:(NSString *)value;
- (void)sendText:(NSString *)text;
- (void)saveConfig:(NSDictionary *)cfg;
- (NSDictionary *)stateDictionary;
- (NSDictionary *)configDictionary;
@end
