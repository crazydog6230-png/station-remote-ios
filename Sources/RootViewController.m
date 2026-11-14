#import "RootViewController.h"
#import <WebKit/WebKit.h>
#import "Glagol.h"
#import "Weather.h"

static NSString *const kBridgeJS =
@"(function(){"
 "window.api = {"
 "  state: function(){ return JSON.stringify(window.__state || {}); },"
 "  config: function(){ return JSON.stringify(window.__config || {}); },"
 "  weatherConfig: function(){ return JSON.stringify(window.__weatherConfig || {}); },"
 "  saveConfig: function(s){ window.webkit.messageHandlers.cmd.postMessage({t:'save', v:s}); },"
 "  action: function(a, v){ window.webkit.messageHandlers.cmd.postMessage({t:'act', a:a, v:v || ''}); },"
 "  sendText: function(s){ window.webkit.messageHandlers.cmd.postMessage({t:'text', v:s}); },"
 "  setCity: function(c){ window.webkit.messageHandlers.cmd.postMessage({t:'city', v:c}); },"
 "  setWake: function(w){},"
 "  voiceToggle: function(){},"
 "  openUrl: function(u){ window.webkit.messageHandlers.cmd.postMessage({t:'url', v:u}); },"
 "  oauthUrl: function(){ return 'https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d'; }"
 "};"
 "})();";

@interface RootViewController () <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
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

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:kBridgeJS
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                              forMainFrameOnly:YES];
    [ucc addUserScript:script];
    [ucc addScriptMessageHandler:self name:@"cmd"];
    cfg.userContentController = ucc;

    self.web = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.web.navigationDelegate = self;
    self.web.opaque = NO;
    self.web.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.web];

    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.web loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
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
    [[self.web configuration].userContentController removeScriptMessageHandlerForName:@"cmd"];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.ready = YES;
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
    NSString *js = [NSString stringWithFormat:@"window.%@ = %@;", name, json];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.web evaluateJavaScript:js completionHandler:nil];
    });
}

#pragma mark - bridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;
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
        NSString *a = body[@"a"];
        NSString *v = body[@"v"];
        [self.glagol action:a value:v];
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
