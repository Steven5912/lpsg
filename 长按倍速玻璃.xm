// 长按倍速玻璃 — v25: 倍速提示一出现立刻铺玻璃（hook setText + 0.08s 快速扫描兜底）
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
        if (s) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            NSInteger styles[] = {1, 0, 2};
            for (int i = 0; i < 3; i++) {
                @try { eff = msg(ge, s, styles[i]); } @catch(...) { eff = nil; }
                if (eff) break;
            }
        }
    }
    if (!eff) {
        @try { eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]; } @catch(...) { eff = nil; }
    }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    return eff;
}

static CGRect LJ_FindArrowLeft(UIView *parent, UILabel *textLabel){
    CGRect tf = textLabel.frame;
    CGRect best = CGRectNull;
    for (UIView *sub in parent.subviews) {
        if (sub == textLabel) continue;
        CGRect sf = sub.frame;
        if (CGRectGetMaxX(sf) >= tf.origin.x + 20) continue;
        if (CGRectGetMaxY(sf) < tf.origin.y || sf.origin.y > CGRectGetMaxY(tf)) continue;
        BOOL arrowText = NO;
        if ([sub isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)sub).text;
            if (t) arrowText = ([t containsString:@"↓"]||[t containsString:@"∨"]||[t containsString:@"⇣"]||[t containsString:@"▼"]||[t containsString:@"▽"]);
        }
        BOOL small = sf.size.width <= 30 && sf.size.height <= 34;
        if (arrowText || small) {
            if (CGRectIsNull(best) || sf.origin.x < best.origin.x) best = sf;
        }
    }
    return best;
}

static BOOL LJ_IsNearBottom(UIView *v){
    UIView *w = v.window;
    if (!w) return YES;
    CGRect f = [v convertRect:v.bounds toView:w];
    return f.origin.y > w.bounds.size.height * 0.5;
}

static void LJ_ApplyGlassToLabel(UILabel *label){
    if (!label) return;
    UIView *parent = label.superview;
    if (!parent) return;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    if (label.text.length == 0) return;
    for (UIView *sub in parent.subviews) if (sub.tag == 0x5A5A) return;

    CGRect tf = label.frame;
    UIFont *font = label.font ?: [UIFont systemFontOfSize:13];
    CGSize ts = [label.text boundingRectWithSize:CGSizeMake(sw, 200)
                        options:NSStringDrawingUsesLineFragmentOrigin
                        attributes:@{NSFontAttributeName: font}
                        context:nil].size;
    CGFloat textW = ceil(ts.width);
    CGFloat textH = ceil(ts.height);

    CGFloat textMidX;
    NSTextAlignment al = label.textAlignment;
    if (al == NSTextAlignmentLeft)      textMidX = tf.origin.x + textW / 2.0;
    else if (al == NSTextAlignmentRight) textMidX = CGRectGetMaxX(tf) - textW / 2.0;
    else                                 textMidX = CGRectGetMidX(tf);

    CGRect arrow = LJ_FindArrowLeft(parent, label);
    CGFloat hintLeft = textMidX - textW / 2.0;
    CGFloat hintRight = textMidX + textW / 2.0;
    if (!CGRectIsNull(arrow)) hintLeft = MIN(hintLeft, arrow.origin.x);
    CGFloat centerX = (hintLeft + hintRight) / 2.0;

    CGFloat pw = (hintRight - hintLeft) + 40;
    CGFloat ph = textH + 12;
    if (pw < 60) pw = 60;
    if (ph < 28) ph = 28;

    CGRect pf;
    pf.size = CGSizeMake(pw, ph);
    pf.origin.x = centerX - pw / 2.0;
    pf.origin.y = CGRectGetMidY(tf) - ph / 2.0;
    pf.origin.x = MAX(2, pf.origin.x);
    if (CGRectGetMaxX(pf) > sw - 2) pf.origin.x = sw - 2 - pf.size.width;

    UIVisualEffect *eff = LJ_MakeEffect();
    if (!eff) return;

    UIView *pill = [[UIView alloc] initWithFrame:pf];
    pill.tag = 0x5A5A;
    pill.userInteractionEnabled = NO;
    pill.layer.cornerRadius = pf.size.height / 2.0;
    pill.clipsToBounds = YES;

    UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
    vev.frame = pill.bounds;
    vev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [pill addSubview:vev];

    CAGradientLayer *gl = [CAGradientLayer layer];
    gl.frame = pill.bounds;
    gl.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                  (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gl.locations = @[@0.0f, @0.20f];
    gl.startPoint = CGPointMake(0, 0);
    gl.endPoint = CGPointMake(0, 1);
    [pill.layer addSublayer:gl];

    pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    pill.layer.borderWidth = 0.5;

    NSUInteger idx = [parent.subviews indexOfObject:label];
    if (idx == NSNotFound) idx = 0;
    [parent insertSubview:pill atIndex:idx];

    static double lastGlass = 0;
    double now = CACurrentMediaTime();
    if (now - lastGlass > 3.0) { lastGlass = now; LJ_Vibrate(4); }
}

static BOOL LJ_IsHintText(NSString *t){
    if (!t) return NO;
    return ([t containsString:@"松手"] || [t containsString:@"锁定"] || [t containsString:@"下滑"]);
}

static UILabel *LJ_FindLabel(UIView *c, NSString *needle, int depth){
    if (!c || depth > 16) return nil;
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
        if (!lab) lab = LJ_FindLabel(w, @"下滑", 0);
        if (!lab || !LJ_IsNearBottom(lab)) continue;
        static double lastFound = 0;
        double now = CACurrentMediaTime();
        if (now - lastFound > 3.0) { lastFound = now; LJ_Vibrate(2); }
        LJ_ApplyGlassToLabel(lab);
    }
}

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (LJ_IsHintText(self.text)) {
        UILabel *lab = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (LJ_IsNearBottom(lab)) LJ_ApplyGlassToLabel(lab);
        });
    }
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LJ_Vibrate(1);
        });
        [NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *t){
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
