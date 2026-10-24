// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// v6: 硬性安全——只给"小而像提示面板"的视图铺玻璃，绝不给大视图/视频层铺
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define LJ_GLASS_KEY @"SJWJLongPressSpeedGlass"

static BOOL LJ_Enabled(void){
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    return v ? [ud boolForKey:LJ_GLASS_KEY] : YES;
}

// 轻量液态玻璃材质
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

// 安全闸：目标必须是"小而像提示面板"的视图，否则一律不铺（绝不误伤全屏/视频层）
static BOOL LJ_IsSmallPanel(UIView *target){
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat w = target.bounds.size.width, h = target.bounds.size.height;
    if (w <= 0 || h <= 0) return NO;
    if (h < 28 || h > 170) return NO;      // 高度适中（排除视频层/全屏）
    if (w < 60 || w > sw * 0.92) return NO; // 宽度适中
    if (w * h > sw * sh * 0.5) return NO;   // 面积不超过半屏
    return YES;
}

static void LJ_ApplyGlass(UIView *target){
    if (!target || !LJ_Enabled()) return;
    if (!LJ_IsSmallPanel(target)) return;   // 硬性：不是小面板就不铺
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

// ===== 递归查找包含指定文字的 UILabel（限深度防卡顿） =====
static UILabel *LJ_FindLabel(UIView *c, NSString *needle, int depth){
    if (!c || depth > 8) return nil;
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

// ===== 从 self 向上沿父级链各层搜索标签（优先最特异的词） =====
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

// ===== 从 label 向上找"小而像提示面板"的容器（最多3层，找不到返回nil） =====
static UIView *LJ_PanelForLabel(UILabel *label){
    if (!label) return nil;
    UIView *v = label;
    for (int i = 0; i < 3; i++) {
        UIView *p = v.superview;
        if (!p) break;
        if (LJ_IsSmallPanel(p)) return p;
        v = p;
    }
    return nil; // 找不到就不铺，绝不误伤大视图
}

// ===== 一、只给底部倍速面板铺玻璃 =====
%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    UILabel *lab = LJ_FindLabelInChain((UIView *)self);
    if (!lab) return;
    UIView *panel = LJ_PanelForLabel(lab);
    if (panel) LJ_ApplyGlass(panel);
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
