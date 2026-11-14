#import <Foundation/Foundation.h>

@interface Weather : NSObject
@property (nonatomic, assign) BOOL ok;
@property (nonatomic, assign) int temp;
@property (nonatomic, assign) int code;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy) void (^onChange)(void);
- (void)start;
- (void)setCity:(NSString *)city;
- (NSDictionary *)stateDictionary;
@end
