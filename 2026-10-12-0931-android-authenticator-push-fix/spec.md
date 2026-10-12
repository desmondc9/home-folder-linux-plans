# 安卓手机重置后 Microsoft Authenticator Push 恢复(UPS Entra ID)

日期: 2026-10-12 · 状态: 已解决(登录恢复;register device 与 Push 的因果关系未确证)· 实施记录: [implementation.md](implementation.md)
- 环境: 一加 15(2026-10-08 出厂重置,见 [android-rejoin-tailnet](../2026-10-08-1435-android-rejoin-tailnet/spec.md));UPS 工作账号 GD000012090@ups.com(desmondchen@ups.com),由 Microsoft Entra ID 管理 SSO;目标应用 https://console.cloud.google.com/(Chrome);操作机 WSL2 Ubuntu @ YAOSHI15PRO

## 背景与故障

手机重置抹掉了 Authenticator 内的设备密钥,之后:

1. UPS SSO 登录 Google Cloud Console 时,新手机 Authenticator **不再弹出 Push 审批**(下拉刷新无数次无效);
2. SSO 页面的 OTP(验证码)方式显示**无法使用**——UPS 的 Entra 策略禁用了 OTP,只剩 Push 一条路;
3. 矛盾点:同一浏览器登录 https://teams.cloud.microsoft/ 正常——是旧会话 token 未过期,不代表 MFA 方法还活着。

根因:Push 审批依赖手机在 Entra ID 中仍注册为 MFA 方法;出厂重置销毁了设备端密钥,服务器端注册变成死引用。纯客户端无法自救。

## 解决路径(无需 IT 工单的关键前提)

趁 Teams 的旧会话 token 还活着:

1. Chrome 打开 https://mysignins.microsoft.com/security-info (aka.ms/mysecurityinfo);
2. 删除/清理失效的旧 Authenticator 条目,重新 Add method → Microsoft Authenticator,扫新手机二维码;
3. 若该页要求旧设备批准(正常安全设计),才需走 UPS IT 重置 MFA / 发 Temporary Access Pass——本次未走到这步。

## 关键观察(未确证)

重新往 Authenticator 添加工作账号时,APP 问是否 **register device**:
- 选 **skip registry**(跳过设备注册)→ 之后登录 Google Cloud Console,**Push 不弹出**(下拉刷新也无);
- 改选 **register device** → Push 正常弹出,登录成功。

无法确定 register device 是真实原因还是巧合(也可能是 mysecurityinfo 侧注册生效有传播延迟,第一次测试恰在传播完成前)。合理机制假设:UPS 的 Conditional Access 策略要求合规/已注册设备,Push 审批仅对满足设备要求的会话送达;skip registry 时设备不以合规身份出现在 Entra,审批请求被策略层拦下,客户端自然"看不到请求"而非"收不到通知"。

## 备忘(可迁移经验)

- 手机重置后 Push 不弹 ≠ 通知问题,先想"设备端密钥已毁、服务器端注册已死";
- 抢救窗口 = 任一仍有旧 token 的浏览器会话 → 马上去 mysignins.microsoft.com/security-info 重绑;
- Authenticator 云备份**不备份工作/学校账号**(Entra 管理),换机/重置后只能靠上述窗口或 IT 重置;
- 公司策略禁 OTP 时,Push 是唯一 MFA 路径,注册时选 register device 更稳妥(即使因果未确证,成本为零)。
