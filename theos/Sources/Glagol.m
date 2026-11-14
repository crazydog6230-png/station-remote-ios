#import "Glagol.h"
#import "WS.h"

static NSString *const kOauthClientId = @"23cabbbdc6cd418abb4b39c32c41195d";

@interface Glagol () <WSDelegate>
@property (nonatomic, strong) WS *ws;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL connecting;
@end

@implementation Glagol

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _token = [d stringForKey:@"token"] ?: @"";
        _deviceId = [d stringForKey:@"deviceId"] ?: @"";
        _platform = [d stringForKey:@"platform"] ?: @"";
        _name = [d stringForKey:@"name"] ?: @"";
        _host = [d stringForKey:@"host"] ?: @"";
        _port = (int)[d integerForKey:@"port"];
        if (_port <= 0) _port = 1961;
        _volume = 0.5;
        _status = @"idle";
        _error = @"";
        _title = @"";
        _artist = @"";
        _cover = @"";
        _trackId = @"";
        _alice = @"";
        _devices = @[];
    }
    return self;
}

- (void)start {
    if (self.started) {
        [self connect];
        return;
    }
    self.started = YES;
    [self connect];
}

- (void)stop {
    self.started = NO;
    [self.ws close];
    self.ws = nil;
}

- (void)connect {
    if (!self.started) return;
    if (self.token.length == 0) {
        self.status = @"no_token";
        [self notify];
        return;
    }
    if (self.deviceId.length == 0) {
        self.status = @"loading";
        [self fetchDevices];
        return;
    }
    if (self.host.length == 0) {
        self.status = @"no_host";
        [self notify];
        return;
    }
    if (self.connecting) return;
    self.connecting = YES;
    self.status = @"connecting";
    [self notify];
    __weak typeof(self) weakSelf = self;
    [self fetchDeviceToken:^(NSString *deviceToken, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self.connecting = NO;
            if (!deviceToken) {
                self.status = @"idle";
                self.error = error ?: @"не удалось получить токен устройства";
                [self notify];
                [self scheduleReconnect];
                return;
            }
            [self openWs:deviceToken];
        });
    }];
}

- (void)openWs:(NSString *)deviceToken {
    [self.ws close];
    self.ws = [[WS alloc] initWithHost:self.host port:self.port token:deviceToken delegate:self];
    [self.ws connect];
}

- (void)scheduleReconnect {
    if (!self.started) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (self && self.started && !self.ws.opened) [self connect];
    });
}

- (void)notify {
    if (self.onChange) self.onChange();
}

#pragma mark - WSDelegate

- (void)wsDidOpen:(id)ws {
    self.status = @"ready";
    self.error = @"";
    [self notify];
}

- (void)ws:(id)ws didReceiveText:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *state = obj[@"state"];
    if ([state isKindOfClass:[NSDictionary class]]) [self applyState:state];
    [self notify];
}

- (void)ws:(id)ws didFail:(NSString *)reason {
    self.ws = nil;
    self.status = @"idle";
    self.error = reason ?: @"";
    [self notify];
    [self scheduleReconnect];
}

#pragma mark - state

- (void)applyState:(NSDictionary *)st {
    if (st[@"playing"] != nil) self.playing = [st[@"playing"] boolValue];
    if (st[@"volume"] != nil) {
        double v = [st[@"volume"] doubleValue];
        if (v >= 0 && v <= 1.5) self.volume = v;
    }
    if (st[@"aliceState"] != nil) self.alice = [st[@"aliceState"] stringValue];
    NSDictionary *p = st[@"playerState"];
    if (![p isKindOfClass:[NSDictionary class]]) {
        self.title = @"";
        self.artist = @"";
        self.cover = @"";
        self.trackId = @"";
        self.progress = 0;
        self.duration = 0;
        return;
    }
    self.title = [p[@"title"] isKindOfClass:[NSString class]] ? p[@"title"] : @"";
    self.artist = [p[@"subtitle"] isKindOfClass:[NSString class]] ? p[@"subtitle"] : @"";
    self.trackId = [p[@"id"] isKindOfClass:[NSString class]] ? p[@"id"] : @"";
    self.progress = [p[@"progress"] doubleValue];
    self.duration = [p[@"duration"] doubleValue];
    NSDictionary *extra = p[@"extra"];
    NSString *cu = [extra isKindOfClass:[NSDictionary class]] ? extra[@"coverURI"] : nil;
    if ([cu isKindOfClass:[NSString class]] && cu.length > 0) {
        NSString *url = [cu stringByReplacingOccurrencesOfString:@"%%" withString:@"600x600"];
        if ([url hasPrefix:@"//"]) url = [@"https:" stringByAppendingString:url];
        else if (![url hasPrefix:@"http"]) url = [@"https://" stringByAppendingString:url];
        self.cover = url;
    } else {
        self.cover = @"";
    }
}

#pragma mark - cloud

- (void)fetchDevices {
    NSURL *url = [NSURL URLWithString:@"https://quasar.yandex.net/glagol/device_list"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[@"OAuth " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"YandexStation/1.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            if (err) {
                self.status = @"idle";
                self.error = err.localizedDescription;
                [self notify];
                [self scheduleReconnect];
                return;
            }
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *arr = [obj isKindOfClass:[NSDictionary class]] ? obj[@"devices"] : nil;
            if (![arr isKindOfClass:[NSArray class]]) arr = @[];
            self.devices = arr;
            if (self.deviceId.length == 0 && arr.count == 1) {
                NSDictionary *d = arr[0];
                self.deviceId = [d[@"id"] isKindOfClass:[NSString class]] ? d[@"id"] : @"";
                self.platform = [d[@"platform"] isKindOfClass:[NSString class]] ? d[@"platform"] : self.platform;
                self.name = [d[@"name"] isKindOfClass:[NSString class]] ? d[@"name"] : self.name;
                [self persist];
                [self connect];
            } else if (self.deviceId.length == 0) {
                self.status = @"no_device";
            }
            [self notify];
        });
    }] resume];
}

- (void)fetchDeviceToken:(void (^)(NSString *token, NSString *error))completion {
    NSString *u = [NSString stringWithFormat:
        @"https://quasar.yandex.net/glagol/token?device_id=%@&platform=%@",
        [self urlEnc:self.deviceId], [self urlEnc:self.platform]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    [req setValue:[@"OAuth " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"YandexStation/1.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            completion(nil, err.localizedDescription);
            return;
        }
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *t = [obj isKindOfClass:[NSDictionary class]] ? obj[@"token"] : nil;
        if (![t isKindOfClass:[NSString class]] || t.length == 0) {
            completion(nil, @"пустой токен устройства");
            return;
        }
        completion(t, nil);
    }] resume];
}

- (NSString *)urlEnc:(NSString *)s {
    return [s stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
}

#pragma mark - commands

- (void)action:(NSString *)what value:(NSString *)value {
    if ([what isEqualToString:@"refresh"]) {
        self.devices = @[];
        [self fetchDevices];
        return;
    }
    if ([what isEqualToString:@"reconnect"]) {
        [self connect];
        return;
    }
    if (!self.ws.opened) return;
    if ([what isEqualToString:@"playPause"]) {
        [self.ws sendCommand:@{@"command": self.playing ? @"stop" : @"play"}];
    } else if ([what isEqualToString:@"next"]) {
        [self.ws sendCommand:@{@"command": @"next"}];
    } else if ([what isEqualToString:@"prev"]) {
        [self.ws sendCommand:@{@"command": @"prev"}];
    } else if ([what isEqualToString:@"volume"]) {
        double v = [[value stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
        if (v < 0) v = 0;
        if (v > 1) v = 1;
        self.volume = v;
        [self.ws sendCommand:@{@"command": @"setVolume", @"volume": @(v)}];
        [self notify];
    } else if ([what isEqualToString:@"mute"]) {
        double v = self.volume > 0.001 ? 0 : 0.5;
        self.volume = v;
        [self.ws sendCommand:@{@"command": @"setVolume", @"volume": @(v)}];
        [self notify];
    }
}

- (void)sendText:(NSString *)text {
    if (!self.ws.opened || text.length == 0) return;
    [self.ws sendCommand:@{@"command": @"sendText", @"text": text}];
}

- (void)saveConfig:(NSDictionary *)cfg {
    if (cfg[@"token"] != nil) self.token = [cfg[@"token"] description];
    if (cfg[@"deviceId"] != nil) self.deviceId = [cfg[@"deviceId"] description];
    if (cfg[@"platform"] != nil) self.platform = [cfg[@"platform"] description];
    if (cfg[@"name"] != nil) self.name = [cfg[@"name"] description];
    if (cfg[@"host"] != nil) self.host = [cfg[@"host"] description];
    [self persist];
    [self.ws close];
    self.ws = nil;
    [self connect];
}

- (void)persist {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.token forKey:@"token"];
    [d setObject:self.deviceId forKey:@"deviceId"];
    [d setObject:self.platform forKey:@"platform"];
    [d setObject:self.name forKey:@"name"];
    [d setObject:self.host forKey:@"host"];
    [d setInteger:self.port forKey:@"port"];
    [d synchronize];
}

#pragma mark - JSON

- (NSDictionary *)stateDictionary {
    NSMutableDictionary *o = [NSMutableDictionary dictionary];
    o[@"status"] = self.status ?: @"idle";
    o[@"error"] = self.error ?: @"";
    o[@"tokenSet"] = @(self.token.length > 0);
    o[@"deviceId"] = self.deviceId ?: @"";
    o[@"deviceName"] = self.name ?: @"";
    o[@"host"] = self.host ?: @"";
    o[@"playing"] = @(self.playing);
    o[@"volume"] = @(self.volume);
    o[@"title"] = self.title ?: @"";
    o[@"artist"] = self.artist ?: @"";
    o[@"cover"] = self.cover ?: @"";
    o[@"trackId"] = self.trackId ?: @"";
    o[@"progress"] = @(self.progress);
    o[@"duration"] = @(self.duration);
    o[@"alice"] = self.alice ?: @"";
    o[@"devices"] = self.devices ?: @[];
    o[@"ts"] = @((long long)([[NSDate date] timeIntervalSince1970] * 1000));
    return o;
}

- (NSDictionary *)configDictionary {
    return @{
        @"token": self.token ?: @"",
        @"deviceId": self.deviceId ?: @"",
        @"platform": self.platform ?: @"",
        @"name": self.name ?: @"",
        @"host": self.host ?: @"",
        @"port": @(self.port)
    };
}

@end
