// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// 用 Logos %hook/%orig，Theos 编译 arm64e 时自动处理指针签名(PAC)
// v2: 复用 siwenjiajia 原生开关 sjj_video_long_press_glass_enabled_v1，
//     修好 UIGlassEffect 创建，并让目标视图背景透明透出玻璃
#import <UIKit/UIKit.h>

#define LJ_GLASS_KEY @"sjj_video_long_press_glass_enabled_v1"

static BOOL LJ_Enabled(void){
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    return v ? [ud boolForKey:LJ_GLASS_KEY] : YES; // 默认开启
}

// 玻璃材质：iOS26 液态玻璃 UIGlassEffect → siwenjiajia 自带视图 → 模糊玻璃
static UIView *LJ_MakeGlass(void){
    // 1) iOS26 液态玻璃 UIGlassEffect (effectWithStyle:0 = Standard)
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        SEL s = NSSelectorFromString(@"effectWithStyle:");
        if (s && [ge respondsToSelector:s]) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            UIVisualEffect *eff = msg(ge, s, 0);
            if (eff) {
                UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:eff];
                v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                v.userInteractionEnabled = NO;
                return v;
            }
        }
    }
    // 2) siwenjiajia 自带玻璃视图
    Class sjj = NSClassFromString(@"SJJLiquidGlassFlexView");
    if (sjj) {
        UIView *g = [[sjj alloc] initWithFrame:CGRectZero];
        if (g && [g isKindOfClass:[UIView class]]) {
            g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            g.userInteractionEnabled = NO;
            return g;
        }
    }
    // 3) 回退模糊玻璃
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.userInteractionEnabled = NO;
    return v;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target || !LJ_Enabled()) return;
    for (UIView *sub in target.subviews) if (sub.tag == 0x5A5A) return;
    UIView *glass = LJ_MakeGlass();
    if (!glass) return;
    glass.tag = 0x5A5A;
    glass.frame = target.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // 关键：目标视图背景设为透明，玻璃材质才能透出来
    target.backgroundColor = [UIColor clearColor];
    target.opaque = NO;
    [target insertSubview:glass atIndex:0];
    [target sendSubviewToBack:glass];
}

// ===== 一、长按倍速视图玻璃化 =====
%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    LJ_ApplyGlass((UIView *)self);
}
%end

// ===== 二、注入“抖音优化-增强与优化”菜单开关 =====
static NSInteger LJ_TargetSection(UITableView *tv){
    long n = [tv numberOfSections];
    return n > 0 ? n - 1 : 0; // 追加到最后一个分组
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
        cell.detailTextLabel.text = @"长按倍速时，倍速视图使用液态玻璃材质";
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

// ===== 三、默认开启（未设置过时默认打开） =====
%ctor {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    if (!v) [ud setBool:YES forKey:LJ_GLASS_KEY];
    [ud synchronize];
}
