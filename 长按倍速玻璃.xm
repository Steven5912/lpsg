// 长按倍速玻璃 — v18: 液态玻璃药丸（文字周围留白+圆角+玻璃高光边缘）
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/message.h>

static void LJ_Vibrate(int n){
    for (int i = 0; i < n; i++) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        usleep(180000);
    }
}

static UIVisualEffect *LJ_MakeEffect(void){
    UIVisualEffect *eff = nil;
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        SEL s = NSSelectorFromString(@"effectWithStyle:");
        if (s && [ge respondsToSelector:s]) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            @try { eff = msg(ge, s, 0); } @catch(...) { eff = nil; }
        }
    }
    if (!eff) {
        @try { eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]; } @catch(...) { eff = nil; }
    }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    return eff;
}

// 在文字label周围铺一块液态玻璃药丸
static void LJ_ApplyGlassToLabel(UILabel *label){
    if (!label) return;
    UIView *parent = label.superview;
    if (!parent) return;
    CGRect f = label.frame;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    if (f.size.width <= 0 || f.size.height <= 0) return;
    if (f.size.width > sw * 0.95) return;
    for (UIView *sub in parent.subviews) if (sub.tag == 0x5A5A) return;

    // 在文字四周扩一圈留白，形成胶囊药丸
    CGRect pf = CGRectInset(f, -16, -9);
    pf.origin.x = MAX(4, pf.origin.x);
    if (CGRectGetMaxX(pf) > sw - 4) pf.origin.x = sw - 4 - pf.size.width;

    UIVisualEffect *eff = LJ_MakeEffect();
    if (!eff) return;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:eff];
    glass.frame = pf;
    glass.userInteractionEnabled = NO;
    glass.layer.cornerRadius = pf.size.height / 2.0;
    glass.clipsToBounds = YES;
    // 玻璃材质：柔和的半透明 + 高光边缘
    glass.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    glass.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    glass.layer.borderWidth = 0.6;
    glass.tag = 0x5A5A;
    NSUInteger idx = [parent.subviews indexOfObject:label];
    if (idx == NSNotFound) idx = 0;
    [parent insertSubview:glass atIndex:idx];

    static double lastGlass = 0;
    double now = CACurrentMediaTime();
    if (now - lastGlass > 3.0) { lastGlass = now; LJ_Vibrate(4); }
}

static UILabel *LJ_FindLabel(UIView *c, NSString *needle, int depth, BOOL *nearBottom){
    if (!c || depth > 16) return nil;
    for (UIView *sub in c.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)sub).text;
            if (t && [t containsString:needle]) {
                UIView *w = sub.window;
                if (w) {
                    CGRect f = [sub convertRect:sub.bounds toView:w];
                    if (f.origin.y > w.bounds.size.height * 0.5 && nearBottom) *nearBottom = YES;
                } else if (nearBottom) *nearBottom = YES;
                return (UILabel *)sub;
            }
        }
        UILabel *r = LJ_FindLabel(sub, needle, depth + 1, nearBottom);
        if (r) return r;
    }
    return nil;
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
        BOOL near = NO;
        UILabel *lab = LJ_FindLabel(w, @"松手", 0, &near);
        if (!lab) { near = NO; lab = LJ_FindLabel(w, @"锁定", 0, &near); }
        if (!lab) { near = NO; lab = LJ_FindLabel(w, @"倍速", 0, &near); }
        if (!lab || !near) continue;
        static double lastFound = 0;
        double now = CACurrentMediaTime();
        if (now - lastFound > 3.0) { lastFound = now; LJ_Vibrate(2); }
        LJ_ApplyGlassToLabel(lab);
    }
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LJ_Vibrate(1);
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
