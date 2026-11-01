# LibreChat Agent Events API 对接调研(暂停,等 v0.8.8 正式版)

**状态**:调研完成,实施暂停。本机 LibreChat v0.8.7 无此能力。

**恢复条件**:LibreChat v0.8.8 正式版发布后,将 `~/librechat-deploy/.env` 的
`LIBRECHAT_IMAGE_TAG` 从 `v0.8.7` 升级,然后按下方设计继续。

## 事实(2026-09-08 调研,来源:docs.librechat.ai + GitHub v0.8.8-rc2)

- 官方名称:**Agents API (Beta)** 的 **Agent Events** 子能力,不是 "Agent Events API"
- 需要版本:**v0.8.8-rc2 起**(`/api/agents/v1/events` 路由在该 tag 引入);v0.8.8 正式版当时未发布,最新稳定 = v0.8.7
- 开关:`librechat.yaml` 里 `interface.remoteAgents.use: true`(+ `create: true`);默认关
- 端点:
  - `POST /api/agents/v1/events`(`mode`: `fire` | `continue` | `steer`)
  - `GET  /api/agents/v1/events/{delivery_id}`(轮询投递状态)
  - `POST /api/agents/v1/events/bindings`
- 认证:`Authorization: Bearer <REMOTE_AGENTS_API_KEY>`(用户在 UI Settings → Data controls 生成,只能本人操作);**必须**带 `Idempotency-Key` 头
- 限流:`rateLimits.agentEvents`(env 兜底 `AGENT_EVENT_USER_MAX` / `AGENT_EVENT_USER_WINDOW`)
- 投递语义:durable(Mongo 持久化,用户不必开着会话);Event Actors 需 MongoDB checkpointer(`type: memory` 不兼容——本机用 Atlas Mongo,满足)
- UI 呈现:`fire` 事件触发目标 agent 一轮 turn,**界面显示的是 agent 回复而非裸事件**
- 文档:https://www.librechat.ai/docs/features/agents_api

### curl 形态(文档示例)

```bash
curl -X POST http://localhost:3080/api/agents/v1/events \
  -H "Authorization: Bearer $REMOTE_AGENTS_API_KEY" \
  -H "Idempotency-Key: openclaw-notify-001" \
  -H "Content-Type: application/json" \
  -d '{"mode":"fire","event":{"id":"evt-1","type":"notify.user","occurredAt":1786967999000,"payload":{"msg":"gateway alert"}},"target":{"agentId":"agent_abc123"},"input":"Tell the user: gateway alert"}'
```

## 已收敛的设计决策(grill Round 1 用户已拍板前的前提,待重启时确认)

| 决策点 | 倾向(未最终确认) |
|---|---|
| 升级策略 | side-by-side 测试栈(独立 compose project + 独立 Mongo 库名)验证链路 → 再原地升正式版 |
| 目标形态 | 专用"通知" agent(system prompt:input 原样输出),openclaw 把通知全文作 `input`;避免每条通知消耗一轮 openclaw LLM |
| 改造范围 | 晨报(07:50)+ 周报(周五 08:20)+ 流水线故障告警三件套 |
| 会话策略 | 固定"通知中心"会话 |
| key 存放 | `~/.openclaw/.env`(`REMOTE_AGENTS_API_KEY`,同 TAVILY 模式) |
| 文档落点 | git init `~/librechat-deploy`,CONTEXT.md + ADR 入库 |

## 与现有链路的关系

现有:LibreChat →(OpenAI 兼容端点 `http://host.docker.internal:18789/v1`)→ openclaw 网关,方向是 LibreChat 把 openclaw 当模型。Agent Events 是反向:openclaw → LibreChat 推事件。两者可组合(事件触发的 agent 的 model 可以就是 openclaw 端点)。
