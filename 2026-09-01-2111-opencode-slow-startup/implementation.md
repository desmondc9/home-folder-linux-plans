# 实施记录 — opencode 启动加速

## 任务

- [x] 建立可重复的启动耗时反馈回路
- [x] 复现并最小化(确认与工作目录、插件、MCP、DB 无关)
- [x] 定位根因(syscall trace)
- [x] 验证候选修复(差分实验)
- [x] 落地 wrapper 并端到端验证
- [x] 记录归档

## 反馈回路

两层,互相印证:

**1) server-ready 探针**(快,用于差分实验):启动 `opencode serve --port N`,
轮询 `GET /config` 直到有响应并计时。

```bash
opencode serve --port $PORT --print-logs --log-level DEBUG "$@" &
for i in $(seq 1 1200); do
  curl -s -m 0.4 --noproxy '*' "http://127.0.0.1:$PORT/config" -o /dev/null && break
  sleep 0.05
done
```

> **回路陷阱(已踩)**:探针最初用 `-m 2`。opencode 的 **第一个** HTTP 请求会被吞掉
> (端口已 bind、实例尚未 attach,请求挂在 backlog 里不被应答),只有重试才被服务。
> 于是每次测量都稳定多出 ~2.18s,看起来像一个真实的启动阶段。把 `-m 2` 改成 `-m 9`
> 后该「阶段」变成 9.2s —— 证明是探针假象,不是被测对象的耗时。
> **教训:一个稳定复现的数字,不等于一个真实的现象。**

**2) TTFD 真实路径**(权威,用于验收):opencode 自带 `OPENCODE_SHOW_TTFD=1`,
在 pty 里跑真 TUI 直接读它打印的首帧耗时。

```bash
( OPENCODE_SHOW_TTFD=1 timeout -s INT 22 script -qc "opencode" /dev/null > out.raw 2>&1 ) </dev/null
grep -aoE '[0-9.]+ms' out.raw | head -1
```

## 定位过程

1. DEBUG 日志做时间戳差分,发现 5.2s 的空窗落在「读完配置」与「all LSPs are disabled」之间,
   窗口内**一条日志都没有**。
2. `strace -f -tt -e trace=openat,connect,execve` + 主动发请求触发 bootstrap。
   (第一次 strace 只跟到 `listening` 就没动静 —— 因为 `serve` 是**收到首个 HTTP 请求
   才创建 instance**;不发请求就 trace 不到 bootstrap。)
3. trace 里直接抓到元凶:
   ```
   execve("/usr/bin/az", ["az","cognitiveservices","account","list","--output","json","--only-show-errors"])
   execve("/usr/bin/../../opt/az/bin/python3", ["...","-Im","azure.cli",...])
   connect(... 443, 4.150.240.10 / 20.9.155.152 ...)   # Azure 管理端点 + 遥测上报
   ```
   az 于 +2.94s 启动,其遥测子进程到 +7.75s 仍在跑。
4. 单独计时:`az cognitiveservices account list ...` = **5.707s**。
5. 差分确认:PATH 前置一个立即 `exit 1` 的 `az` stub → 8.0s 降到 2.83s,5.2s 窗口消失。
6. 从 184MB 二进制里 `strings` 出打包源码,读到精确触发条件与短路条件(见 spec.md)。

## 变更

新增 `~/.local/bin/opencode`(可执行 wrapper):

- 若 `AZURE_RESOURCE_NAME` 与 `AZURE_RESOURCE_GROUP` 均未设置,注入
  `AZURE_RESOURCE_NAME=opencode-skip-az-probe`
- 扫描 PATH 找到真实 `opencode`(跳过 wrapper 自身所在目录,避免递归),`exec` 之
- 头部注释写明根因、实测数字、回滚方式、以及「`disabled_providers` 无效」这一陷阱

未改动 `~/.config/opencode/opencode.json`、未改动 shell rc、未改动 Azure CLI 配置。

## 验证结果

| 检查项 | 结果 |
|---|---|
| TTFD(修复前) | 8158 ms / 8163 ms |
| TTFD(修复后) | 2473 ms / 2617 ms |
| 启动全程 `cognitiveservices` execve 次数 | 0 |
| `az account show` | 正常 |
| 用户 shell 中 `$AZURE_RESOURCE_NAME` | 空(未泄漏) |
| `opencode --version` 经 wrapper | 1.18.25 |

## 回归测试的「缝」

不适用:被测对象是第三方预编译二进制,本仓库无代码可挂测试。
替代手段 = 上面的 TTFD 一行命令,可随时复测;wrapper 头部注释已记录基线数字,
将来 opencode 升级后若 TTFD 回到 ~8s,说明上游改了短路条件,按注释重新诊断。

## 后续可选项(未做,收益小)

- 剩余 2.5s 全在 opencode 自身 bun 启动 + instance bootstrap,本地配置已榨干。
- `OPENCODE_DISABLE_MODELS_FETCH=1`:**不改善启动延迟**(该刷新是后台 fork),
  但可省掉每次启动 + 每小时一次的 4.4MB models.dev 下载,GFW 环境下可考虑;
  代价是模型目录不再自动更新。
- `~/.cache/opencode` 已 1.3G、`~/.local/share/opencode` 1.5G(其中 `opencode.db` 526MB)。
  **与启动速度无关(已实测排除)**,纯占盘,可另行清理。
- 上游可提 issue:该 az 探测应加超时、并发化,或纳入 `disabled_providers` 约束。
