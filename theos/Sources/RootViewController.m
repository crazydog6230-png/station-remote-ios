#import "RootViewController.h"
#import <UIKit/UIKit.h>
#import "Glagol.h"
#import "Weather.h"

static NSString *const kBridgeJS =
@"(function(){"
 "function _send(o){var f=document.createElement('iframe');f.style.display='none';"
 "f.src='bridge://'+encodeURIComponent(JSON.stringify(o));"
 "document.documentElement.appendChild(f);"
 "setTimeout(function(){if(f.parentNode)f.parentNode.removeChild(f);},50);}"
 "window.api={"
 "state:function(){return JSON.stringify(window.__state||{});},"
 "config:function(){return JSON.stringify(window.__config||{});},"
 "weatherConfig:function(){return JSON.stringify(window.__weatherConfig||{});},"
 "saveConfig:function(s){_send({t:'save',v:s});},"
 "action:function(a,v){_send({t:'act',a:a,v:v||''});},"
 "sendText:function(s){_send({t:'text',v:s});},"
 "setCity:function(c){_send({t:'city',v:c});},"
 "setWake:function(w){},"
 "voiceToggle:function(){},"
 "openUrl:function(u){_send({t:'url',v:u});},"
 "oauthUrl:function(){return 'https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d';}"
 "};"
 "})();";

@interface RootViewController () <UIWebViewDelegate>
@property (nonatomic, strong) UIWebView *web;
@property (nonatomic, strong) Glagol *glagol;
@property (nonatomic, strong) Weather *weather;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation RootViewController

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.web = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.web.delegate = self;
    self.web.opaque = NO;
    self.web.backgroundColor = [UIColor blackColor];
    self.web.scalesPageToFit = NO;
    self.web.allowsInlineMediaPlayback = YES;
    self.web.mediaPlaybackRequiresUserAction = NO;
    [self.view addSubview:self.web];

    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.web loadRequest:[NSURLRequest requestWithURL:url]];
    }

    self.glagol = [[Glagol alloc] init];
    self.weather = [[Weather alloc] init];
    __weak typeof(self) weakSelf = self;
    self.glagol.onChange = ^{ [weakSelf pushState]; };
    self.weather.onChange = ^{ [weakSelf pushState]; };
    [self.weather start];
    [self.glagol start];

    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(pushState) userInfo:nil repeats:YES];
}

- (void)dealloc {
    [self.timer invalidate];
    self.web.delegate = nil;
}

- (void)evalJS:(NSString *)js {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.web stringByEvaluatingJavaScriptFromString:js];
    });
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    self.ready = YES;
    [self evalJS:kBridgeJS];
    [self pushConfig];
    [self pushState];
}

- (void)pushConfig {
    if (!self.ready) return;
    NSDictionary *c = [self.glagol configDictionary];
    NSDictionary *wc = @{@"manualCity": self.weather.city ?: @""};
    [self evalObject:c as:@"__config"];
    [self evalObject:wc as:@"__weatherConfig"];
}

- (void)pushState {
    if (!self.ready) return;
    NSMutableDictionary *s = [[self.glagol stateDictionary] mutableCopy];
    s[@"weather"] = [self.weather stateDictionary];
    s[@"audio"] = @{@"mode": @"station", @"error": @"", @"playing": @NO, @"trackId": @""};
    s[@"voice"] = @{@"listening": @NO, @"wake": @NO, @"ready": @NO, @"error": @"", @"hint": @""};
    [self evalObject:s as:@"__state"];
}

- (void)evalObject:(NSDictionary *)obj as:(NSString *)name {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self evalJS:[NSString stringWithFormat:@"window.%@ = %@;", name, json]];
}

#pragma mark - bridge

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    NSString *scheme = request.URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"bridge"]) {
        NSString *raw = request.URL.absoluteString;
        NSRange r = [raw rangeOfString:@"bridge://"];
        if (r.location != NSNotFound) {
            NSString *enc = [raw substringFromIndex:r.location + r.length];
            NSString *json = [enc stringByRemovingPercentEncoding];
            NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *body = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([body isKindOfClass:[NSDictionary class]]) [self handleBridge:body];
        }
        return NO;
    }
    return YES;
}

- (void)handleBridge:(NSDictionary *)body {
    NSString *type = body[@"t"];
    if ([type isEqualToString:@"save"]) {
        NSString *raw = body[@"v"];
        NSData *d = [raw dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *cfg = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if ([cfg isKindOfClass:[NSDictionary class]]) {
            [self.glagol saveConfig:cfg];
            [self pushConfig];
        }
    } else if ([type isEqualToString:@"act"]) {
        [self.glagol action:body[@"a"] value:body[@"v"]];
    } else if ([type isEqualToString:@"text"]) {
        [self.glagol sendText:body[@"v"]];
    } else if ([type isEqualToString:@"city"]) {
        [self.weather setCity:body[@"v"]];
    } else if ([type isEqualToString:@"url"]) {
        NSURL *u = [NSURL URLWithString:body[@"v"] ?: @""];
        if (u) [[UIApplication sharedApplication] openURL:u];
    }
}

@end
