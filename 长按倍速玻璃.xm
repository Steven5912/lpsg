// 长按倍速玻璃 — v15: 底部区域定位 + 最小容器 + 位置安全闸
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

// 位置安全闸：只允许玻璃屏幕底部区域、且非全屏
static BOOL LJ_OkPanel(UIView *target){
    UIView *w = target.window;
    if (!w) return NO;
    CGRect f = [target convertRect:target.bounds toView:w];
    CGFloat sh = w.bounds.size.height;
    CGFloat sw = w.bounds.size.width;
    // 必须位于屏幕底部 55% 以内
    if (f.origin.y < sh * 0.45) return NO;
    // 高度不超过半屏
    if (f.size.height > sh * 0.5) return NO;
    // 宽度不超过 96% 屏宽
    if (f.size.width > sw * 0.96) return NO;
    // 面积不超过半屏
    if (f.size.width * f.size.height > sw * sh * 0.5) return NO;
    return YES;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target) return;
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

// 向上找最小的"药丸容器"（24-260 高、>=60 宽）
static UIView *LJ_PanelForLabel(UILabel *label){
    UIView *p = label;
    for (int i = 0; i < 8; i++) {
        if (!p.superview) break;
        p = p.superview;
        CGFloat h = p.bounds.size.height, w = p.bounds.size.width;
        if (h >= 24 && h <= 260 && w >= 60) return p;
    }
    return nil;
}

// 递归找文字，返回其屏幕坐标是否在底部区域
static UILabel *LJ_FindLabel(UIView *c, NSString *needle, int depth, BOOL *nearBottom){
    if (!c || depth > 16) return nil;
    for (UIView *sub in c.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)sub).text;
            if (t && [t containsString:needle]) {
                UIView *w = sub.window;
                if (w) {
                    CGRect f = [sub convertRect:sub.bounds toView:w];
                    if (f.origin.y > w.bounds.size.height * 0.55 && nearBottom) *nearBottom = YES;
                }
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
        if (!lab) continue;
        if (!near) continue;  // 只处理底部区域的提示条
        static double lastFound = 0;
        double now = CACurrentMediaTime();
        if (now - lastFound > 3.0) { lastFound = now; LJ_Vibrate(2); }
        UIView *panel = LJ_PanelForLabel(lab);
        if (panel && LJ_OkPanel(panel)) LJ_ApplyGlass(panel);
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

%hook UIView
- (void)layoutSubviews {
    %orig;
    static Class afd = nil;
    if (!afd) afd = NSClassFromString(@"AFDFastSpeedView");
    if (afd && [self isKindOfClass:afd]) {
        UILabel *lab = LJ_FindLabel((UIView *)self, @"松手", 0, NULL);
        if (!lab) lab = LJ_FindLabel((UIView *)self, @"锁定", 0, NULL);
        if (!lab) lab = LJ_FindLabel((UIView *)self, @"倍速", 0, NULL);
        UIView *p = lab ? LJ_PanelForLabel(lab) : nil;
        if (p && LJ_OkPanel(p)) LJ_ApplyGlass(p);
    }
}
%end
