# implementation — Rakazo 重启（机器档案）

时间线（2026-11-14，对应 repo Issue #5 / PR #6 / PR #7）：

1. 预检（端口/残留/gh ok；官方最新稳定 = v0.11.0）
2. clone + Issue #5 + worktree（~/Repos/worktrees/ 新规范）
3. PR #6：恢复 workflow + pin v0.11.0 + 解档横幅 + plans；CI 绿合并
4. DNS A/AAAA 重建（灰云）；`gh auth setup-git` 复核
5. deploy.sh 运行 → **host-setup 因 NOPASSWD 移除失败**（sudo -n 硬门禁）→ 诊断：/etc/sudoers.d 仅剩 README（12:00 变更）+ opencode deny sudo
6. 分工调整：agent 完成 installer --local（容器栈全 healthy、内部 health ok）+ deploy key/secret；root 三步打包为幂等脚本由用户终端执行（egress + vhost + LE 证书 2027-02-12 + reload）→ ALL DONE
7. 外部 200 + 证书 CN 验证；bootstrap 账号（Account verified，密码会话交付未落盘）
8. force dispatch run 43560250990 success（含 SSH deploy 步骤、空提交跳过路径复验）
9. PR #7：host-setup.sh 交互式 sudo 适配（sudo -v 门禁 + 去 -n）+ 验收回填；CI 绿合并
10. worktree 清理 ×2（reenable + sudo-interactive）；本档案 + ~/plans README 索引

验收：内部 ok:true/sandbox:docker；外部 200 + LE（→2027-02-12）；全服务 healthy @ app:v0.11.0；SIGNUPS_ENABLED=false + 账号已验证；dispatch 全绿；repo 零 secret。
