// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// 用 Logos %hook/%orig，Theos 编译 arm64e 时自动处理指针签名(PAC)
#import <UIKit/UIKit.h>

static BOOL LJ_Enabled(void){
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:@"SJWJLongPressSpeedGlass"];
    return v ? [ud boolForKey:@"SJWJLongPressSpeedGlass"] : YES; // 默认开启
}

// 玻璃材质：优先复用 siwenjiajia 自带 SJJLiquidGlassFlexView，回退 UIGlassEffect/模糊玻璃
static UIView *LJ_MakeGlass(void){
    Class sjj = NSClassFromString(@"SJJLiquidGlassFlexView");
    if (sjj) {
        UIView *g = [[sjj alloc] initWithFrame:CGRectZero];
        if (g && [g isKindOfClass:[UIView class]]) {
            g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            return g;
        }
    }
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        id effect = [ge effectWithStyle:UIBlurEffectStyleRegular];
        if (effect) {
            UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
            v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            return v;
        }
    }
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return v;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target || !LJ_Enabled()) return;
    for (UIView *sub in target.subviews) if (sub.tag == 0x5A5A) return;
    UIView *glass = LJ_MakeGlass();
    glass.tag = 0x5A5A;
    glass.frame = target.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
    return n > 0 ? n - 1 : 0; // 追加到最后一个分组（-1 改这里）
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
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"SJWJLongPressSpeedGlass"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
%end
