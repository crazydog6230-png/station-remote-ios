#import "Weather.h"
#import <math.h>

@interface Weather ()
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation Weather

- (instancetype)init {
    self = [super init];
    if (self) {
        _city = @"Москва";
        _code = 119;
    }
    return self;
}

- (void)start {
    [self fetch];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1800 target:self selector:@selector(fetch) userInfo:nil repeats:YES];
}

- (void)setCity:(NSString *)city {
    if (city.length > 0) self.city = city;
    [self fetch];
}

- (void)fetch {
    NSURL *url = [NSURL URLWithString:@"https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=55.752&lon=37.618"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"StationRemote/1.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) return;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *props = [obj isKindOfClass:[NSDictionary class]] ? obj[@"properties"] : nil;
        NSArray *series = [props isKindOfClass:[NSDictionary class]] ? props[@"timeseries"] : nil;
        if (![series isKindOfClass:[NSArray class]] || series.count == 0) return;
        NSDictionary *first = series[0];
        NSDictionary *instant = first[@"data"][@"instant"][@"details"];
        double t = [instant[@"air_temperature"] doubleValue];
        NSString *symbol = @"";
        NSDictionary *n1 = first[@"data"][@"next_1_hours"][@"summary"];
        if ([n1 isKindOfClass:[NSDictionary class]]) symbol = n1[@"symbol_code"] ?: @"";
        if (symbol.length == 0) {
            NSDictionary *n6 = first[@"data"][@"next_6_hours"][@"summary"];
            if ([n6 isKindOfClass:[NSDictionary class]]) symbol = n6[@"symbol_code"] ?: @"";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self.temp = (int)lround(t);
            self.code = [self codeForSymbol:symbol];
            self.ok = YES;
            if (self.onChange) self.onChange();
        });
    }] resume];
}

- (int)codeForSymbol:(NSString *)s {
    if ([s containsString:@"thunder"]) return 200;
    if ([s containsString:@"snow"]) return 338;
    if ([s containsString:@"sleet"]) return 338;
    if ([s containsString:@"rain"]) return 296;
    if ([s containsString:@"fog"]) return 143;
    if ([s containsString:@"clearsky"]) return 113;
    if ([s containsString:@"fair"] || [s containsString:@"partlycloudy"]) return 116;
    return 119;
}

- (NSDictionary *)stateDictionary {
    return @{
        @"ok": @(self.ok),
        @"temp": @(self.temp),
        @"code": @(self.code),
        @"city": self.city ?: @""
    };
}

@end
