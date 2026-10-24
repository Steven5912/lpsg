// 长按倍速玻璃 — 从 DYKiller(液态玻璃) 移植到 siwenjiajia
// v12: 定时器 + 加载诊断横幅（确认插件是否真正加载）
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

static NSArray *LJ_AllWindows(void){
    NSMutableArray *arr = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w) [arr addObject:w];
            }
        }
    }
    return arr;
}

static void LJ_Scan(void){
    for (UIWindow *w in LJ_AllWindows()) {
        UILabel *lab = LJ_FindLabel(w, @"松手", 0);
        if (!lab) lab = LJ_FindLabel(w, @"锁定", 0);
        if (!lab) lab = LJ_FindLabel(w, @"倍速", 0);
        if (!lab) continue;
        UIView *panel = LJ_PanelForLabel(lab);
        if (panel) LJ_ApplyGlass(panel);
    }
}

static void LJ_ShowDiag(void){
    for (UIWindow *w in LJ_AllWindows()) {
        CGFloat wd = w.bounds.size.width;
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, wd - 40, 44)];
        lb.text = @"长按倍速玻璃插件已加载";
        lb.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:0.9 alpha:0.85];
        lb.textColor = [UIColor whiteColor];
        lb.font = [UIFont boldSystemFontOfSize:15];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.layer.cornerRadius = 10;
        lb.clipsToBounds = YES;
        lb.alpha = 0;
        [w addSubview:lb];
        [UIView animateWithDuration:0.3 animations:^{ lb.alpha = 1; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ lb.alpha = 0; } completion:^(BOOL f){ [lb removeFromSuperview]; }];
        });
        break;
    }
}

// ===== 主：定时器 =====
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LJ_ShowDiag();
        });
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){
            LJ_Scan();
        }];
    });
}

// ===== 备份触发：UIWindow/UIView/AFDFastSpeedView 钩子 =====
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
