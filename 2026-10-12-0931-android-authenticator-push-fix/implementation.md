# 安卓 Authenticator Push 恢复 实施记录

**Goal:** 出厂重置后恢复 UPS Entra ID 账号(GD000012090@ups.com)的 Microsoft Authenticator Push 登录能力。
**Spec:** [spec.md](spec.md)

> 时间线均为本地时间(+8),即 UTC 01:31 起。

### Task 1: 故障定位 ✅ 09:09

- [x] 现象确认:UPS SSO 登录 console.cloud.google.com 时新手机无 Push;APP 内下拉刷新多次无效;OTP 方式被策略禁用
- [x] 定性:出厂重置销毁设备密钥 → 服务器端 MFA 注册死引用 → 新设备收不到审批请求;非通知栏/后台问题
- [x] 备用路径评估:OTP 被禁、无 FIDO2 → 仅剩 Push;客户端无法自救,须 Entra 侧重置或由存活会话重绑

### Task 2: 利用存活会话重绑 ✅ 09:31 前

- [x] 确认 Teams(teams.cloud.microsoft)旧 token 仍有效(遗产会话,与新登录互不影响)
- [x] 在已登录浏览器打开 https://mysignins.microsoft.com/security-info
- [x] 清理失效条目,重新 Add method → Microsoft Authenticator → 扫新手机二维码
- [x] 用户确认:调整后登录恢复成功

### Task 3: register device 观察(未确证)⚠️

- [x] 复测发现:Authenticator 添加账号时选 **skip registry** → 登录 Google Cloud Console Push 不弹
- [x] 改选 **register device** → Push 正常弹出,登录成功
- [ ] 因果未确证:可能是 CA 策略要求已注册设备才送达审批;也可能是重绑注册传播延迟,首次测试恰逢传播前。未做单变量复测(skip 后等待再测)

### Task 4: 归档 ✅

- [x] spec.md / implementation.md 入库,README 索引补行
- [x] commit + push main

## 遗留

- 建议公司侧加一种备用 MFA 方法(FIDO2 密钥/短信),防止下次丢机后无存活会话可救
- register device 因果如需确证:同一账号 skip registry 后等待 >30min 再测 Push 送达性
