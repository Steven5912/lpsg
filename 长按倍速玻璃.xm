// 长按倍速玻璃 — v16: 可见浅色基底 + 4下震动标记"已铺玻璃"
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
        @try {
            if ([UIBlurEffect respondsToSelector:@selector(effectWithStyle:)] &&
                UIBlurEffectStyleSystemMaterial != 999999) {
                eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            }
        } @catch(...) { eff = nil; }
    }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    return eff;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target) return;
    for (UIView *sub in target.subviews) if (sub.tag == 0x5A5A) return;
    CGFloat w = target.bounds.size.width, h = target.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    UIVisualEffect *eff = LJ_MakeEffect();
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame = target.bounds;
    vev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    vev.userInteractionEnabled = NO;
    // 可见浅色基底：无论模糊是否渲染，都能看到玻璃区域
    vev.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    target.backgroundColor = [UIColor clearColor];
    target.opaque = NO;
    [target insertSubview:vev atIndex:0];
    [target sendSubviewToBack:vev];
    vev.tag = 0x5A5A;
    static double lastGlass = 0;
    double now = CACurrentMediaTime();
    if (now - lastGlass > 3.0) { lastGlass = now; LJ_Vibrate(4); }
}

// 最宽容的容器选取：向上找第一个 >=16高 且 >=40宽的祖先
static UIView *LJ_PanelForLabel(UILabel *label){
    UIView *p = label;
    for (int i = 0; i < 6; i++) {
        if (!p.superview) break;
        p = p.superview;
        if (p.bounds.size.height >= 16 && p.bounds.size.width >= 40) return p;
    }
    return label.superview;
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
        UIView *panel = LJ_PanelForLabel(lab);
        if (panel) {
            // 只处理位于屏幕底部的面板：位置安全闸
            UIView *win = panel.window;
            if (!win) for (UIWindow *ww in LJ_AllWindows()) { win = ww; break; }
            if (win) {
                CGRect f = [panel convertRect:panel.bounds toView:win];
                CGFloat sh = win.bounds.size.height, sw = win.bounds.size.width;
                if (f.origin.y >= sh * 0.45 &&
                    f.size.height <= sh * 0.5 &&
                    f.size.width <= sw * 0.96 &&
                    f.size.width * f.size.height <= sw * sh * 0.5) {
                    LJ_ApplyGlass(panel);
                }
            }
        }
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
