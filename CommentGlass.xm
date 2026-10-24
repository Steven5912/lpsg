// CommentGlass — 评论区液态玻璃（模糊玻璃模式）
// 功能：给抖音评论输入栏/评论面板叠加 iOS26 液态玻璃（模糊/磨砂样式），由 siwenjiajia「增强与优化」开关控制。
// 开关键：sjj_comment_section_glass_enabled_v1
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kCommentGlassPref = @"sjj_comment_section_glass_enabled_v1";
static const NSInteger kGlassTag = 0x5C5C;

static BOOL CG_IsEnabled(void){
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // 默认开启（便于演示），开关为 NO 时关闭
    id v = [d objectForKey:kCommentGlassPref];
    if (v == nil) return YES;
    return [v boolValue];
}

// 模糊液态玻璃效果：优先 iOS26 UIGlassEffect（液态），回退系统磨砂模糊
static UIVisualEffect *CG_FuzzyEffect(void){
    UIVisualEffect *eff = nil;
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        SEL s = NSSelectorFromString(@"effectWithStyle:");
        if (s) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            // 模糊样式候选：优先带雾面/磨砂的样式
            NSInteger styles[] = {1, 2, 0, 3};
            for (int i = 0; i < 4; i++) {
                @try { eff = msg(ge, s, styles[i]); } @catch(...) { eff = nil; }
                if (eff) break;
            }
        }
    }
    if (!eff) {
        @try { eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]; } @catch(...) { eff = nil; }
    }
    if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    return eff;
}

// 给目标视图叠加一块模糊玻璃背景（index 0），已有则校正，关闭则移除
static void CG_ApplyToView(UIView *view){
    if (!view || view.bounds.size.width < 1 || view.bounds.size.height < 1) return;
    if (!CG_IsEnabled()) {
        for (UIView *sub in view.subviews) {
            if (sub.tag == kGlassTag) { [sub removeFromSuperview]; return; }
        }
        return;
    }
    // 已有玻璃则校正 frame
    for (UIView *sub in view.subviews) {
        if (sub.tag == kGlassTag) {
            if (!CGRectEqualToRect(sub.frame, view.bounds)) sub.frame = view.bounds;
            return;
        }
    }
    UIVisualEffect *eff = CG_FuzzyEffect();
    if (!eff) return;
    UIVisualEffectView *vev = [[UIVisualEffectView alloc] initWithEffect:eff];
    vev.tag = kGlassTag;
    vev.frame = view.bounds;
    vev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    vev.userInteractionEnabled = NO;
    // 细描边增强「液态玻璃」质感
    vev.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    vev.layer.borderWidth = 0.5;
    if (view.subviews.count == 0) {
        [view addSubview:vev];
    } else {
        [view insertSubview:vev atIndex:0];
    }
}

// 递归找评论区相关宿主视图
static void CG_ScanView(UIView *v, int depth){
    if (!v || depth > 24) return;
    Class inputBG = NSClassFromString(@"AWECommentInputBackgroundView");
    Class inputC  = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
    if (inputBG && [v isKindOfClass:inputBG]) CG_ApplyToView(v);
    if (inputC  && [v isKindOfClass:inputC])  CG_ApplyToView(v);
    for (UIView *sub in v.subviews) CG_ScanView(sub, depth + 1);
}

static void CG_ScanWindows(void){
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *wins = [NSMutableArray array];
    void (^add)(UIWindow *) = ^(UIWindow *w){
        if (w && ![seen containsObject:[NSValue valueWithNonretainedObject:w]]) {
            [seen addObject:[NSValue valueWithNonretainedObject:w]];
            [wins addObject:w];
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
    for (UIWindow *w in wins) CG_ScanView(w, 0);
}

// ================= 菜单开关注入（siwenjiajia「增强与优化」末尾） =================
static Class gSwitchClass = nil;
static Class gFoldClass = nil;
static BOOL gInjected = NO;
static BOOL gInEnhance = NO;
static BOOL gFoundEnhance = NO;
static id   gContainer = nil;
static CGFloat gEnhanceLastY = 0;

static Class CG_FindClassWithSel(SEL s){
    int n = objc_getClassList(NULL, 0);
    Class *buf = (Class *)malloc(sizeof(Class) * n);
    objc_getClassList(buf, n);
    Class found = nil;
    for (int i = 0; i < n; i++) {
        if (class_getInstanceMethod(buf[i], s)) { found = buf[i]; break; }
    }
    free(buf);
    return found;
}

// 尝试把开关追加到增强与优化末尾
static void CG_TryInject(id self){
    if (gInjected || !gContainer) return;
    // 在最后一个增强开关下面追加一行
    CGFloat rowH = 48.0;
    CGFloat y = gEnhanceLastY + rowH;
    @try {
        SEL sel = NSSelectorFromString(@"addSwitch:y:title:tag:on:");
        void (*fn)(id, SEL, id, CGFloat, id, NSInteger, BOOL) = (void (*)(id, SEL, id, CGFloat, id, NSInteger, BOOL))objc_msgSend;
        fn(self, sel, gContainer, y, @"评论区液态玻璃", 0x5C5C, CG_IsEnabled());
        gInjected = YES;
    } @catch(...) { }
}

static void (*orig_addSwitch)(id, SEL, id, CGFloat, id, NSInteger, BOOL);
static void hook_addSwitch(id self, SEL _cmd, id container, CGFloat y, id title, NSInteger tag, BOOL on){
    orig_addSwitch(self, _cmd, container, y, title, tag, on);
    if (gInEnhance) { gContainer = container; gEnhanceLastY = y; }
}

static void (*orig_addFold)(id, SEL, id, CGFloat, id, id, NSInteger, BOOL);
static void hook_addFold(id self, SEL _cmd, id container, CGFloat y, id title, id subtitle, NSInteger tag, BOOL expanded){
    // 上一个分组结束（若为增强，则把开关补到其末尾）
    if (gInEnhance && !gInjected) CG_TryInject(self);
    gInEnhance = NO;
    orig_addFold(self, _cmd, container, y, title, subtitle, tag, expanded);
    // 识别「增强与优化」分组
    NSString *t = title;
    if ([t isKindOfClass:[NSString class]]) {
        if ([t containsString:@"增强"] || [t containsString:@"优化"] || [t containsString:@"Enhance"] || [t containsString:@"Optimize"]) {
            gInEnhance = YES; gFoundEnhance = YES; gContainer = container;
        }
    }
}

// 兜底：设置页出现后仍未注入则尝试
static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated){
    orig_viewDidAppear(self, _cmd, animated);
    if (gFoundEnhance && !gInjected) {
        dispatch_async(dispatch_get_main_queue(), ^{ CG_TryInject(self); });
    }
}

%hook AWECommentInputBackgroundView
- (void)layoutSubviews {
    %orig;
    CG_ApplyToView((UIView *)self);
}
%end

%ctor {
    SEL sw = NSSelectorFromString(@"addSwitch:y:title:tag:on:");
    SEL fd = NSSelectorFromString(@"addFoldGroupHeader:y:title:subtitle:tag:expanded:");
    SEL va = NSSelectorFromString(@"viewDidAppear:");
    gSwitchClass = CG_FindClassWithSel(sw);
    gFoldClass   = CG_FindClassWithSel(fd);
    if (gSwitchClass) {
        MSHookMessageEx(gSwitchClass, sw, (IMP)&hook_addSwitch, (IMP *)&orig_addSwitch);
        if (class_getInstanceMethod(gSwitchClass, va)) {
            MSHookMessageEx(gSwitchClass, va, (IMP)&hook_viewDidAppear, (IMP *)&orig_viewDidAppear);
        }
    }
    if (gFoldClass) {
        MSHookMessageEx(gFoldClass, fd, (IMP)&hook_addFold, (IMP *)&orig_addFold);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *t){
            CG_ScanWindows();
        }];
    });
}
