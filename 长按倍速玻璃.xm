// 长按倍速玻璃 — v14: 分步震动诊断（加载1下/找到文字2下/铺玻璃3下）
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/message.h>

static void LJ_Vibrate(int n){
    for (int i = 0; i < n; i++) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        usleep(180000);
    }
}

static UIView *LJ_MakeGlass(void){
    UIVisualEffect *eff = nil;
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        SEL s = NSSelectorFromString(@"effectWithStyle:");
        if (s && [ge respondsToSelector:s]) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            eff = msg(ge, s, 0);
        }
    }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:eff];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.userInteractionEnabled = NO;
    return v;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target) return;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat w = target.bounds.size.width, h = target.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    if (h > 170) return;
    if (w * h > sw * sh * 0.5) return;
    for (UIView *sub in target.subviews) if (sub.tag == 0x5A5A) return;
    UIView *glass = LJ_MakeGlass();
    if (!glass) return;
    glass.tag = 0x5A5A;
    glass.frame = target.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    target.backgroundColor = [UIColor clearColor];
    target.opaque = NO;
    [target insertSubview:glass atIndex:0];
    [target sendSubviewToBack:glass];
    static double lastGlass = 0;
    double now = CACurrentMediaTime();
    if (now - lastGlass > 3.0) { lastGlass = now; LJ_Vibrate(3); }
}

static UILabel *LJ_FindLabel(UIView *c, NSString *needle, int depth){
    if (!c || depth > 14) return nil;
    for (UIView *sub in c.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)sub).text;
            if (t && [t containsString:needle]) return (UILabel *)sub;
        }
        UILabel *r = LJ_FindLabel(sub, needle, depth + 1);
        if (r) return r;
    }
    return nil;
}

static UIView *LJ_PanelForLabel(UILabel *label){
    if (!label) return nil;
    UIView *p = label.superview;
    if (!p) return nil;
    if (p.bounds.size.height < 20 || p.bounds.size.width < 40) {
        for (int i = 0; i < 6; i++) {
            p = p.superview;
            if (!p) break;
            if (p.bounds.size.height >= 20 && p.bounds.size.width >= 40) break;
        }
    }
    return p;
}

static NSArray *LJ_AllWindows(void){
    NSMutableArray *arr = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    void (^add)(UIWindow *) = ^(UIWindow *w){
        if (w && ![seen containsObject:[NSValue valueWithNonretainedObject:w]]) {
            [seen addObject:[NSValue valueWithNonretainedObject:w]];
            [arr addObject:w];
        }
    };
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)sc).windows) add(w);
            }
        }
    }
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(windows)]) for (UIWindow *w in [app windows]) add(w);
    if (app.delegate && [app.delegate respondsToSelector:@selector(window)]) {
        UIWindow *w = [app.delegate performSelector:@selector(window)];
        if (w) add(w);
    }
    return arr;
}

static void LJ_Scan(void){
    for (UIWindow *w in LJ_AllWindows()) {
        UILabel *lab = LJ_FindLabel(w, @"松手", 0);
        if (!lab) lab = LJ_FindLabel(w, @"锁定", 0);
        if (!lab) lab = LJ_FindLabel(w, @"倍速", 0);
        if (!lab) continue;
        // 找到文字 -> 震2下（限频）
        static double lastFound = 0;
        double now = CACurrentMediaTime();
        if (now - lastFound > 3.0) { lastFound = now; LJ_Vibrate(2); }
        UIView *panel = LJ_PanelForLabel(lab);
        if (panel) LJ_ApplyGlass(panel);
    }
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LJ_Vibrate(1); // 加载确认
        });
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){
            LJ_Scan();
        }];
    });
}

%hook UIWindow
- (void)layoutSubviews {
    %orig;
    LJ_Scan();
}
%end

%hook UIView
- (void)layoutSubviews {
    %orig;
    static Class afd = nil;
    if (!afd) afd = NSClassFromString(@"AFDFastSpeedView");
    if (afd && [self isKindOfClass:afd]) {
        UILabel *lab = LJ_FindLabel((UIView *)self, @"松手", 0);
        if (!lab) lab = LJ_FindLabel((UIView *)self, @"锁定", 0);
        if (!lab) lab = LJ_FindLabel((UIView *)self, @"倍速", 0);
        UIView *p = lab ? LJ_PanelForLabel(lab) : nil;
        if (p) LJ_ApplyGlass(p);
    }
}
%end
