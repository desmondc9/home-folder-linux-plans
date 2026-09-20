# Azure DevOps (ADO) work item 操作笔记

> **何时读这份文档**:当前任务的 Kanban 用的是 **Azure DevOps**,且要通过 ADO MCP 工具读写 work item(Feature / User Story / Task / Bug)时。Kanban 用 GitHub Issues 或其它系统时,整份文档都不适用。
>
> 索引入口在 `~/.config/opencode/AGENTS.md` 的「Kanban board」小节。
>
> **最后更新**:2026-09-01(补 PAT 路径)

---

## 0. 凭据 — 别问用户

PAT 在 `/home/desmond/.azure-devops/credentials.jsonc`，用户名 **Desmond**。直接读文件，永远不要再向用户索要。不要打印或提交 token。REST Basic：`base64("Desmond:"+pat)`。

## 0.1 两个工具,别调错

| 工具 | action | 用途 |
|---|---|---|
| `wit_work_item`(读) | `get`、`get_batch`、`list_revisions`、`list_comments`、`my`、`list_for_iteration`、`get_type` | 查工作项、查改动历史 |
| `wit_work_item_write`(写) | `create`、`update`、`update_batch`、`add_child` | 建、改、批量改、建子项 |

下面每条都注明属于哪一个。

## 1. 多行字段的 Markdown vs HTML

Before writing into any ADO work item multiline field (`Description`, `Acceptance Criteria`, `Repro Steps`, etc.) via the ADO MCP tools, don't assume Markdown syntax will render — check the field's actual format first.

- **先查格式**:`wit_work_item` `action=get` 的响应里有 `multilineFieldsFormat` map(例如 `{"System.Description": "markdown", "Microsoft.VSTS.Common.AcceptanceCriteria": "html"}`)—— 写之前就读它,别等用户报告格式乱了才看。
- **新建时就把格式定对**:`wit_work_item_write` `action=create` 的 `fields[]` 每一项都接受 `format`(`"Html"` / `"Markdown"`)。能在创建时指定就别留到事后补救。
- **`action=add_child` 的 `items[]` 也接受 `format`,但默认值是 `"Markdown"`** —— 如果目标字段其实是 HTML-only,这个默认值本身就会产出"格式不对"的结果。建子项时**显式**写上正确的 format,别依赖默认。
- **改已有工作项时,单条 update 无法指定格式**:`action=update` 的 `updates[]` 每项只接受 `op`/`path`/`value`,**没有 `format` 字段**。硬传也会被静默忽略,字段保持原有格式。
- `action=update_batch` 的 `batchUpdates[]` *确实*接受 `format`(`"Markdown"`/`"Html"`),但只有当该字段的底层控件真的支持切换时才生效。有些字段在特定工作项类型/流程模板下被固定成一种格式 —— 例如 `Microsoft.VSTS.Common.AcceptanceCriteria` 即便显式传了 `format: "Markdown"`,`multilineFieldsFormat` 里仍然是 `"html"`。
- **Fix when a field is stuck as `"html"`:** write actual HTML markup (`<b>`, `<code>`, `<ol>`/`<li>`, nested `<ul>`) instead of Markdown syntax (`**bold**`, `` `code` ``, `1. item`). Markdown syntax written into an HTML-only field renders as literal text — visible asterisks/backticks/numbers — which is exactly what "格式不对" looks like to a user viewing the work item.

## 2. `add_child` 的服务端副作用

`wit_work_item_write` `action=add_child` can trigger org/project-configured automation as a side effect (e.g. auto-assign to a default owner, auto-create a linked child Task) — this is a server-side rule firing, not something the API call itself did wrong. Don't assume an unexpected `AssignedTo` change or an extra child work item means the call malfunctioned; use `wit_work_item` `action=list_revisions` to see exactly what each revision changed and attribute it correctly before "fixing" something that isn't broken.
