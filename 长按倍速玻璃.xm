// 长按倍速玻璃 — v20: 清透液态玻璃（UIGlassEffect+无雾感基底+高光亮边）宽20左移1高6
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/message.h>

static void LJ_Vibrate(int n){
    for (int i = 0; i < n; i++) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        usleep(180000);
    }
}

// 真正的液态玻璃材质（UIGlassEffect），无白色雾感基底
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
        @try { eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]; } @catch(...) { eff = nil; }
    }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    return eff;
}

static void LJ_ApplyGlassToLabel(UILabel *label){
    if (!label) return;
    UIView *parent = label.superview;
    if (!parent) return;
    CGRect f = label.frame;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    if (f.size.width <= 0 || f.size.height <= 0) return;
    if (f.size.width > sw * 0.95) return;
    for (UIView *sub in parent.subviews) if (sub.tag == 0x5A5A) return;

    // 尺寸：左右留白20，上下留白6，整体左移1pt
    CGRect pf = CGRectInset(f, -20, -6);
    pf.origin.x -= 1;
    pf.origin.x = MAX(2, pf.origin.x);
    if (CGRectGetMaxX(pf) > sw - 2) pf.origin.x = sw - 2 - pf.size.width;

    UIVisualEffect *eff = LJ_MakeEffect();
    if (!eff) return;

    // 胶囊容器
    UIView *pill = [[UIView alloc] initWithFrame:pf];
    pill.tag = 0x5A5A;
    pill.userInteractionEnabled = NO;
    pill.layer.cornerRadius = pf.size.height / 2.0;
    pill.clipsToBounds = YES;

    // 液态玻璃
    UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame = pill.bounds;
    vev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [pill addSubview:vev];

    // 顶部高光（玻璃反光）
    CAGradientLayer *gl = [CAGradientLayer layer];
    gl.frame = pill.bounds;
    gl.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.38].CGColor,
                  (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations = @[@0.0f, @0.6f];
    gl.startPoint = CGPointMake(0, 0);
    gl.endPoint = CGPointMake(0, 1);
    [pill.layer addSublayer:gl];

    // 玻璃亮边
    pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    pill.layer.borderWidth = 0.7;

    NSUInteger idx = [parent.subviews indexOfObject:label];
    if (idx == NSNotFound) idx = 0;
    [parent insertSubview:pill atIndex:idx];

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
