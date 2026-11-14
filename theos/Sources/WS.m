#import "WS.h"
#import <stdlib.h>

@interface WS () <NSStreamDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) int port;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, weak) id<WSDelegate> delegate;
@property (nonatomic, strong) NSInputStream *in;
@property (nonatomic, strong) NSOutputStream *out;
@property (nonatomic, strong) NSMutableData *buf;
@property (nonatomic, assign) BOOL handshaked;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, assign) BOOL opened;
@end

@implementation WS

- (instancetype)initWithHost:(NSString *)host port:(int)port token:(NSString *)deviceToken delegate:(id<WSDelegate>)delegate {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _token = [deviceToken copy];
        _delegate = delegate;
        _buf = [NSMutableData data];
    }
    return self;
}

- (void)connect {
    self.closed = NO;
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, &readStream, &writeStream);
    if (!readStream || !writeStream) {
        [self fail:@"не удалось открыть сокет"];
        return;
    }
    NSDictionary *ssl = @{
        (id)kCFStreamSSLLevel: (id)kCFStreamSocketSecurityLevelNegotiatedSSL,
        (id)kCFStreamSSLValidatesCertificateChain: @NO
    };
    NSInputStream *in = (__bridge_transfer NSInputStream *)readStream;
    NSOutputStream *out = (__bridge_transfer NSOutputStream *)writeStream;
    [in setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    [out setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    [in setProperty:ssl forKey:(id)kCFStreamPropertySSLSettings];
    [out setProperty:ssl forKey:(id)kCFStreamPropertySSLSettings];
    in.delegate = self;
    out.delegate = self;
    [in scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [out scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    self.in = in;
    self.out = out;
    [in open];
    [out open];
}

- (void)close {
    self.closed = YES;
    [self.in close];
    [self.out close];
    self.in = nil;
    self.out = nil;
}

- (void)fail:(NSString *)reason {
    if (self.closed) return;
    self.closed = YES;
    [self.in close];
    [self.out close];
    if ([self.delegate respondsToSelector:@selector(ws:didFail:)]) {
        [self.delegate ws:self didFail:reason];
    }
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    if (self.closed) return;
    if (event == NSStreamEventOpenCompleted) {
        if (stream == self.out && !self.handshaked) {
            [self sendHandshake];
        }
        return;
    }
    if (event == NSStreamEventErrorOccurred) {
        [self fail:@"ошибка соединения"];
        return;
    }
    if (event == NSStreamEventEndEncountered) {
        [self fail:@"станция закрыла соединение"];
        return;
    }
    if (event == NSStreamEventHasBytesAvailable && stream == self.in) {
        uint8_t tmp[4096];
        while ([self.in hasBytesAvailable]) {
            NSInteger n = [self.in read:tmp maxLength:sizeof(tmp)];
            if (n <= 0) break;
            [self.buf appendBytes:tmp length:(NSUInteger)n];
        }
        [self process];
    }
}

- (void)sendHandshake {
    uint8_t raw[16];
    arc4random_buf(raw, sizeof(raw));
    NSString *key = [[NSData dataWithBytes:raw length:sizeof(raw)] base64EncodedStringWithOptions:0];
    NSString *req = [NSString stringWithFormat:
        @"GET / HTTP/1.1\r\nHost: %@:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
         "Sec-WebSocket-Key: %@\r\nSec-WebSocket-Version: 13\r\n\r\n",
        self.host, self.port, key];
    [self writeData:[req dataUsingEncoding:NSASCIIStringEncoding]];
}

- (void)process {
    if (!self.handshaked) {
        NSRange r = [self.buf rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding]
                                  options:0 range:NSMakeRange(0, self.buf.length)];
        if (r.location == NSNotFound) return;
        NSString *head = [[NSString alloc] initWithData:[self.buf subdataWithRange:NSMakeRange(0, r.location + 4)]
                                               encoding:NSISOLatin1StringEncoding];
        [self.buf replaceBytesInRange:NSMakeRange(0, r.location + 4) withBytes:NULL length:0];
        if ([head rangeOfString:@" 101"].location == NSNotFound) {
            [self fail:@"сервер не переключился на WebSocket"];
            return;
        }
        self.handshaked = YES;
        self.opened = YES;
        if ([self.delegate respondsToSelector:@selector(wsDidOpen:)]) {
            [self.delegate wsDidOpen:self];
        }
        [self sendCommand:@{@"command": @"softwareVersion"}];
    }
    while (self.buf.length >= 2) {
        const uint8_t *b = self.buf.bytes;
        int opcode = b[0] & 0x0F;
        BOOL masked = (b[1] & 0x80) != 0;
        NSUInteger len = b[1] & 0x7F;
        NSUInteger pos = 2;
        if (len == 126) {
            if (self.buf.length < 4) return;
            len = ((NSUInteger)b[2] << 8) | b[3];
            pos = 4;
        } else if (len == 127) {
            if (self.buf.length < 10) return;
            len = 0;
            for (int i = 0; i < 8; i++) len = (len << 8) | b[2 + i];
            pos = 10;
        }
        NSUInteger need = pos + (masked ? 4 : 0) + len;
        if (self.buf.length < need) return;
        NSData *payload = [self.buf subdataWithRange:NSMakeRange(pos + (masked ? 4 : 0), len)];
        [self.buf replaceBytesInRange:NSMakeRange(0, need) withBytes:NULL length:0];
        if (opcode == 0x9) {
            [self sendFrame:0xA payload:payload];
        } else if (opcode == 0x8) {
            [self fail:@"станция закрыла соединение"];
            return;
        } else if (opcode == 0x1) {
            NSString *text = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            if (text && [self.delegate respondsToSelector:@selector(ws:didReceiveText:)]) {
                [self.delegate ws:self didReceiveText:text];
            }
        }
    }
}

- (void)sendCommand:(NSDictionary *)payload {
    if (!self.opened || self.closed) return;
    NSDictionary *env = @{
        @"conversationToken": self.token ?: @"",
        @"id": [[NSUUID UUID] UUIDString],
        @"payload": payload ?: @{},
        @"sentTime": @((long long)([[NSDate date] timeIntervalSince1970] * 1000))
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:env options:0 error:nil];
    if (!data) return;
    [self sendFrame:0x1 payload:data];
}

- (void)sendFrame:(int)opcode payload:(NSData *)payload {
    if (!self.out) return;
    NSMutableData *frame = [NSMutableData data];
    uint8_t b0 = 0x80 | (uint8_t)opcode;
    [frame appendBytes:&b0 length:1];
    NSUInteger len = payload.length;
    if (len < 126) {
        uint8_t b1 = 0x80 | (uint8_t)len;
        [frame appendBytes:&b1 length:1];
    } else if (len < 65536) {
        uint8_t b[3] = {0x80 | 126, (uint8_t)(len >> 8), (uint8_t)(len & 0xFF)};
        [frame appendBytes:b length:3];
    } else {
        uint8_t b[9];
        b[0] = 0x80 | 127;
        for (int i = 0; i < 8; i++) b[1 + i] = (uint8_t)(((uint64_t)len >> (8 * (7 - i))) & 0xFF);
        [frame appendBytes:b length:9];
    }
    uint8_t mask[4];
    arc4random_buf(mask, 4);
    [frame appendBytes:mask length:4];
    NSMutableData *masked = [NSMutableData dataWithLength:len];
    uint8_t *src = (uint8_t *)payload.bytes;
    uint8_t *dst = (uint8_t *)masked.mutableBytes;
    for (NSUInteger i = 0; i < len; i++) dst[i] = src[i] ^ mask[i % 4];
    [frame appendData:masked];
    [self writeData:frame];
}

- (void)writeData:(NSData *)data {
    if (!self.out) return;
    const uint8_t *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left > 0) {
        NSInteger n = [self.out write:bytes maxLength:left];
        if (n <= 0) {
            [self fail:@"ошибка записи"];
            return;
        }
        bytes += n;
        left -= (NSUInteger)n;
    }
}

@end
