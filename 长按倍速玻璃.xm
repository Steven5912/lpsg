// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// v10: 用必然存在的 UIWindow 钩子扫窗口找文字铺玻璃，绕开晚加载类钩子失效问题
#import <UIKit/UIKit.h>
#import <objc/message.h>

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
    if (!target) return;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat w = target.bounds.size.width, h = target.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    if (h > 170) return;              // 排除视频层/全屏
    if (w * h > sw * sh * 0.5) return; // 面积不超半屏
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

static UIView *LJ_PanelForLabel(UILabel *label){
    if (!label) return nil;
    UIView *p = label.superview;
    if (!p) return nil;
    if (p.bounds.size.height < 20 || p.bounds.size.width < 40) {
        for (int i = 0; i < 5; i++) {
            p = p.superview;
            if (!p) break;
            if (p.bounds.size.height >= 20 && p.bounds.size.width >= 40) break;
        }
    }
    return p;
}

// 主逻辑：在窗口内找"松手/锁定/倍速"文字并铺玻璃
static void LJ_ProcessWindow(UIWindow *win){
    if (!win) return;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 0.25) return; // 节流，避免频繁扫
    last = now;
    UILabel *lab = LJ_FindLabel(win, @"松手", 0);
    if (!lab) lab = LJ_FindLabel(win, @"锁定", 0);
    if (!lab) lab = LJ_FindLabel(win, @"倍速", 0);
    if (!lab) return;
    UIView *panel = LJ_PanelForLabel(lab);
    if (panel) LJ_ApplyGlass(panel);
}

// 主触发：UIWindow 必然存在、必然在布局时触发
%hook UIWindow
- (void)layoutSubviews {
    %orig;
    LJ_ProcessWindow((UIWindow *)self);
}
%end

// 备份触发：全局 UIView（AFDFastSpeedView 出现时）
%hook UIView
- (void)layoutSubviews {
    %orig;
    static Class afd = nil;
    if (!afd) afd = NSClassFromString(@"AFDFastSpeedView");
    if (afd && [self isKindOfClass:afd]) {
        UILabel *lab = LJ_FindLabel((UIView *)self, @"松手", 0);
        if (!lab) lab = LJ_FindLabel((UIView *)self, @"锁定", 0);
        if (!lab) lab = LJ_FindLabel((UIView *)self, @"倍速", 0);
        UIView *p = lab ? LJ_PanelForLabel(lab) : nil;
        if (p) LJ_ApplyGlass(p);
    }
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
        ((UISwitch *)[cell viewWithTag:0x5B5B]).on = YES;
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

%ctor {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:@"SJWJLongPressSpeedGlass"];
    [ud synchronize];
}
