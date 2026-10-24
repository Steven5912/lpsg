// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// v4: 不用 siwenjiajia 自带整屏玻璃(那会糊全屏)，只给自己 key + 只铺底部面板
#import <UIKit/UIKit.h>
#import <objc/message.h>

// 自己的开关（绝不动 siwenjiajia 的 sjj_video_long_press_glass_enabled_v1，那是整屏玻璃）
#define LJ_GLASS_KEY @"SJWJLongPressSpeedGlass"

static BOOL LJ_Enabled(void){
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    return v ? [ud boolForKey:LJ_GLASS_KEY] : YES; // 默认开启
}

// 轻量液态玻璃材质（不遮挡视频）
static UIView *LJ_MakeGlass(void){
    // 1) iOS26 液态玻璃 UIGlassEffect
    Class ge = NSClassFromString(@"UIGlassEffect");
    if (ge) {
        SEL s = NSSelectorFromString(@"effectWithStyle:");
        if (s && [ge respondsToSelector:s]) {
            id (*msg)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
            id eff = msg(ge, s, 0); // Standard
            if (eff) {
                UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:eff];
                v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                v.userInteractionEnabled = NO;
                return v;
            }
        }
    }
    // 2) 回退：超薄磨砂（半透明，能看到视频）
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
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
    target.backgroundColor = [UIColor clearColor];
    target.opaque = NO;
    [target insertSubview:glass atIndex:0];
    [target sendSubviewToBack:glass];
}

// ===== 递归查找包含"松手/下滑"文字的 UILabel =====
static UILabel *LJ_FindLabel(UIView *c, NSString *needle){
    if (!c) return nil;
    for (UIView *sub in c.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)sub).text;
            if (t && [t containsString:needle]) return (UILabel *)sub;
        }
        UILabel *r = LJ_FindLabel(sub, needle);
        if (r) return r;
    }
    return nil;
}

// ===== 从 label 向上找面板容器（大小合适的一层，绝不回退到全屏视图） =====
static UIView *LJ_PanelForLabel(UILabel *label){
    if (!label) return nil;
    UIView *v = label;
    for (int i = 0; i < 5; i++) {
        UIView *p = v.superview;
        if (!p) break;
        CGFloat w = p.bounds.size.width, h = p.bounds.size.height;
        // 面板特征：宽>=80 且 高36~250（明确不是全屏）
        if (w >= 80 && h >= 36 && h <= 250) return p;
        v = p;
    }
    return nil; // 找不到就什么都不做，绝不全屏
}

// ===== 一、只给底部倍速面板铺玻璃 =====
%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    UIView *sv = (UIView *)self;
    UILabel *lab = LJ_FindLabel(sv, @"松手");
    if (!lab) lab = LJ_FindLabel(sv, @"下滑");
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

// ===== 三、默认开启自己的开关（不碰 siwenjiajia 的整屏玻璃开关） =====
%ctor {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:LJ_GLASS_KEY];
    if (!v) [ud setBool:YES forKey:LJ_GLASS_KEY];
    [ud synchronize];
}
