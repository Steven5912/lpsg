// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// v9: 钩全局 UIView.layoutSubviews（必然触发）+ 强制开启 + 直接给文字容器铺玻璃
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define LJ_GLASS_KEY @"SJWJLongPressSpeedGlass"

// 强制开启（排除开关未生效的失败可能）
static BOOL LJ_Enabled(void){ return YES; }

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
    if (!target || !LJ_Enabled()) return;
    // 安全闸：高度不超170、面积不超半屏（排除视频层/全屏）
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

static UILabel *LJ_FindSpeedLabel(UIView *sv){
    UIWindow *win = sv.window;
    NSArray *needles = @[@"松手", @"锁定", @"倍速"];
    // 先在速度视图及其父级链找
    UIView *cur = sv;
    for (int i = 0; i < 4; i++) {
        if (!cur) break;
        for (NSString *n in needles) {
            UILabel *lab = LJ_FindLabel(cur, n, 0);
            if (lab) return lab;
        }
        cur = cur.superview;
    }
    // 再搜整个窗口
    if (win) {
        for (NSString *n in needles) {
            UILabel *lab = LJ_FindLabel(win, n, 0);
            if (lab) return lab;
        }
    }
    return nil;
}

// 直接给"下滑松手锁定2倍速"文字所在的容器铺玻璃（即图二的面板）
static UIView *LJ_PanelForLabel(UILabel *label){
    if (!label) return nil;
    UIView *p = label.superview;
    if (!p) return nil;
    // 直接容器太小则向上找稍大的
    if (p.bounds.size.height < 20 || p.bounds.size.width < 40) {
        for (int i = 0; i < 5; i++) {
            p = p.superview;
            if (!p) break;
            if (p.bounds.size.height >= 20 && p.bounds.size.width >= 40) break;
        }
    }
    return p;
}

// ===== 核心：找到速度视图并铺玻璃 =====
static void LJ_Process(UIView *sv){
    UILabel *lab = LJ_FindSpeedLabel(sv);
    if (!lab) return;
    UIView *panel = LJ_PanelForLabel(lab);
    if (panel) LJ_ApplyGlass(panel);
}

// 触发1：全局 UIView.layoutSubviews（子类经 super 必然触发）
%hook UIView
- (void)layoutSubviews {
    %orig;
    static Class afd = nil;
    if (!afd) afd = NSClassFromString(@"AFDFastSpeedView");
    if (afd && [self isKindOfClass:afd]) {
        LJ_Process((UIView *)self);
    }
}
%end

// 触发2：直接钩 AFDFastSpeedView（备份）
%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    LJ_Process((UIView *)self);
}
%end

// ===== 注入“抖音优化-增强与优化”菜单开关 =====
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

// ===== 默认开启 =====
%ctor {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:LJ_GLASS_KEY];
    [ud synchronize];
}
