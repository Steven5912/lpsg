// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// v8: 全窗口搜标签 + 底部判断放宽 + 延迟重查捕捉后出现的标签
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define LJ_GLASS_KEY @"SJWJLongPressSpeedGlass"

static BOOL LJ_Enabled(void){
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    return v ? [ud boolForKey:LJ_GLASS_KEY] : YES;
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

// 是否位于屏幕底部区域（无窗口时放宽，靠高度+面积闸兜底）
static BOOL LJ_IsBottomArea(UIView *target){
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    UIWindow *win = target.window;
    CGRect f = target.bounds;
    if (win) {
        f = [target convertRect:target.bounds toView:win];
        CGFloat bottomGap = sh - CGRectGetMaxY(f);
        return bottomGap >= -20 && bottomGap < sh * 0.30;
    }
    return YES;
}

// 安全面板：高度适中 + 面积不超半屏 + 尽量位于底部；排除视频层/中间层/全屏
static BOOL LJ_IsSafePanel(UIView *target){
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat w = target.bounds.size.width, h = target.bounds.size.height;
    if (w <= 0 || h <= 0) return NO;
    if (h < 20 || h > 170) return NO;
    if (w < 40) return NO;
    if (w * h > sw * sh * 0.5) return NO;
    if (!LJ_IsBottomArea(target)) return NO;
    return YES;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target || !LJ_Enabled()) return;
    if (!LJ_IsSafePanel(target)) return;
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
}

static UILabel *LJ_FindLabel(UIView *c, NSString *needle, int depth){
    if (!c || depth > 10) return nil;
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

static UILabel *LJ_FindLabelInChain(UIView *sv){
    NSArray *needles = @[@"松手", @"锁定", @"倍速"];
    for (NSString *n in needles) {
        UIView *cur = sv;
        for (int i = 0; i < 4; i++) {
            if (!cur) break;
            UILabel *lab = LJ_FindLabel(cur, n, 0);
            if (lab) return lab;
            cur = cur.superview;
        }
    }
    return nil;
}

// 全局找标签：先自身链，再整个窗口
static UILabel *LJ_FindSpeedLabel(UIView *sv){
    UILabel *lab = LJ_FindLabelInChain(sv);
    if (lab) return lab;
    UIWindow *win = sv.window;
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (win) {
        lab = LJ_FindLabel(win, @"松手", 0);
        if (!lab) lab = LJ_FindLabel(win, @"锁定", 0);
        if (!lab) lab = LJ_FindLabel(win, @"倍速", 0);
    }
    return lab;
}

static UIView *LJ_PanelForLabel(UILabel *label){
    if (!label) return nil;
    UIView *v = label;
    for (int i = 0; i < 6; i++) {
        UIView *p = v.superview;
        if (!p) break;
        if (LJ_IsSafePanel(p)) return p;
        v = p;
    }
    return nil;
}

// ===== 一、只给底部倍速面板铺玻璃 =====
%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    UIView *sv = (UIView *)self;
    UILabel *lab = LJ_FindSpeedLabel(sv);
    UIView *panel = lab ? LJ_PanelForLabel(lab) : nil;
    if (panel) LJ_ApplyGlass(panel);
    else {
        // 布局瞬间标签可能未出现，延迟重查一次
        __weak typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *sv2 = (UIView *)ws;
            if (!sv2) return;
            UILabel *lab2 = LJ_FindSpeedLabel(sv2);
            UIView *p2 = lab2 ? LJ_PanelForLabel(lab2) : nil;
            if (p2) LJ_ApplyGlass(p2);
        });
    }
}
%end

// ===== 二、注入“抖音优化-增强与优化”菜单开关 =====
static NSInteger LJ_TargetSection(UITableView *tv){
    long n = [tv numberOfSections];
    return n > 0 ? n - 1 : 0;
}

%hook siwenjiajiaPanel
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    NSInteger n = %orig;
    if (section == LJ_TargetSection(tv)) return n + 1;
    return n;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger target = LJ_TargetSection(tv);
    NSInteger last = [(id)self tableView:tv numberOfRowsInSection:target] - 1;
    if (ip.section == target && ip.row == last) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"LongPressSpeedGlassCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"LongPressSpeedGlassCell"];
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
            sw.tag = 0x5B5B;
            [sw addTarget:self action:@selector(LJ_ToggleSpeedGlass:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        cell.textLabel.text = @"长按倍速玻璃";
        cell.detailTextLabel.text = @"长按倍速时，仅底部倍速面板使用液态玻璃材质";
        ((UISwitch *)[cell viewWithTag:0x5B5B]).on = LJ_Enabled();
        return cell;
    }
    return %orig;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger target = LJ_TargetSection(tv);
    NSInteger last = [(id)self tableView:tv numberOfRowsInSection:target] - 1;
    if (ip.section == target && ip.row == last) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        return;
    }
    %orig;
}
- (void)LJ_ToggleSpeedGlass:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:LJ_GLASS_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
%end

// ===== 三、默认开启自己的开关 =====
%ctor {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    if (!v) [ud setBool:YES forKey:LJ_GLASS_KEY];
    [ud synchronize];
}
