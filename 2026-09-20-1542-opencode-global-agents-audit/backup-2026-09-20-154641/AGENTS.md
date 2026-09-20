## Overview

- When solving a problem, prioritize the best-fitting tool for the task. If the current system does not have that tool available, first try to install it or enable it rather than falling back to an inferior workaround, unless multiple installation attempts fail.

## Preferred CLI tools

- **ripgrep** (`rg`) is installed — prefer over `grep` for shell searches
- **fd** (`fdfind`) is installed — prefer over `find` for file discovery
- **sd** is installed — prefer over `sed` for find-and-replace in files
- **bat** (`batcat`) is installed — prefer over `cat` for viewing file contents with syntax highlighting and better formatting
- **jq** is installed — use for JSON processing in shell pipelines
- **uv** is installed — prefer over `pip`, `conda` for managing and running Python scripts
- **rustup** is installed and manages Rust (`rustup update`, project pinning via `rust-toolchain.toml`) — never install or upgrade Rust toolchains manually
- **npm** is installed — prefer over `yarn` or `pnpm` for JavaScript/TypeScript package management
- **podman** is installed — prefer over `docker` for container management
- **podman compose** is installed with `docker-compose` (native binary runtime) — prefer over `podman-compose` (python-based compose runtime) for multi-container orchestration


## Network access from mainland China

GFW may make external resources (GitHub, Docker Hub, PyPI/uv, npm, Maven, Huggingface, Google/GCP, …) slow, timing out, or unreachable. On any such network failure — and **proactively before the first Google/GCP request** — read [`~/docs/network-access-china.md`](~/docs/network-access-china.md): domestic-mirror-first strategy with per-tool config (uv/npm/Docker/Maven), local proxy env vars for `127.0.0.1:10809` (mixed inbound; 10808 is retired — don't "correct" the port), and diagnosis when both mirror and proxy fail. Google/GCP requests don't fail fast under the GFW — they hang until the tool's own timeout and look like a stuck tool, so read that doc *before* the first Google/GCP fetch, not after a hang.

## Development, testing, & debugging workflow

Follow this workflow so requirements are fully understood, code is traceable, everything is verifiable locally, and docs stay in sync. If the project has its own more specific process doc, prefer that but fall back to this playbook for anything it doesn't cover.

For project-specific instructions, use the applicable `AGENTS.md` files first. OpenCode V2 loads them automatically. If the project has no `AGENTS.md`, explicitly look for and read `CLAUDE.md` as a compatibility fallback; OpenCode V2 does not load `CLAUDE.md` automatically. When creating a new project instruction file, create `AGENTS.md`.

The A–I cycle below describes **outcomes, not skill invocations**. Step names are not skill triggers — never auto-invoke a skill (e.g. superpowers') just because a step or section name resembles one; when a skill would genuinely help, ask me which ecosystem to use (superpowers / mattpocock / none) instead of defaulting to one.

**Where the boundary is** — the size of the change is not the test, what it touches is:

- **Anything that changes a project repo's code, schema, or config goes through the full cycle**, however small. A one-line bugfix still gets a worktree, a (brief) `spec.md`, a short `implementation.md`, and a PR — that is what the "every change size gets a plans entry" rule below means.
- **An investigation or audit that produces a conclusion worth keeping** gets a `plans/` entry too (a findings doc), even though there may be no code change and therefore no PR.
- **Nothing else needs it** — answering a question, reading code, a throwaway local experiment, editing a scratch file.

### Core principles

- **Context first**: consolidate all related repos into one parent repo so both AI and humans can see the full picture.
- **Parallel development**: isolate each task's workspace with `git worktree` to avoid conflicts.
- **Documentation-driven**: write down what to do, how, and why before touching code.
- **Test-first, unit-first**: turn acceptance criteria into unit tests during Requirements & design clarification / before implementation where practical; on failure, root-cause and fix rather than skipping or loosening assertions. E2E is deliberately not part of the dev loop — the rules and the reasoning are in Step E.
- **Docs in sync**: after code changes, update `README.md`, the applicable project instruction file (`AGENTS.md`, or `CLAUDE.md` only as its fallback), and `docs/*.md` as applicable.

### Kanban board (Azure DevOps / GitHub)

1. Before starting any feature, improvement, or bug fix, a corresponding Azure DevOps Feature/User Story/Task or GitHub Issue must exist and be linked. **If the user hasn't provided one, create it** using the available ADO/GitHub tools — draft the title/description/acceptance criteria from the conversation so far and confirm it with the user before starting code work — rather than blocking the task on the user going to create one themselves.
2. When submitting the PR, it must be linked to that same Feature/User Story/Task or Issue.
3. **If — and only if — the board is Azure DevOps and you're about to read/write work items through the ADO MCP tools, read `~/docs/ado-work-item-notes.md` first** (multiline fields' Markdown-vs-HTML format trap, and `add_child`'s server-side automation side effects). Not applicable to GitHub Issues or any other tracker.
4. **ADO PAT is already on disk** — `~/.azure-devops/credentials.jsonc`, username **Desmond**. Read it; never ask the user for the token. Never print or commit it.

### Repository structure — identify the monorepo's shape first

Not every "monorepo" is built the same way, and the right workflow (how to sync, where to commit, how to land a PR) depends on which shape it actually is — so determine the shape before doing anything else in an unfamiliar repo. Full per-shape detail (directory layouts, sync commands, the submodule pinned-branch trap) and the baseline `.gitignore` live in **`~/docs/repo-shapes-and-gitignore.md`**; read it when setting up in a repo you don't already know.

| Shape | How to detect | Workflow implication |
|---|---|---|
| **A** — single-repo monorepo | no `.gitmodules`, and `git log --all --grep="git-subtree-dir" -- .` is empty | **one branch, one PR** covers the whole change |
| **B** — `git subtree` | that `git log` grep hits | also **one branch, one PR**; reach for `git subtree pull/push` only when a component's upstream remote is actually configured |
| **C** — Git submodules | `.gitmodules` at the root (`git submodule status` lists the pins) | each submodule lands **its own PR to its own remote first**, then a **separate** umbrella PR bumps the pointer — never commit submodule file changes from the umbrella checkout (Step I) |

Shape C has one trap worth remembering before any "sync all submodules" step: a submodule's `.gitmodules`-pinned branch (often `main`) can lag far behind the branch its team actually merges into, so `git submodule update --remote --merge` can silently leave you on stale code — verify the pinned branch is current first.

Common to all three: `.gitignore` must cover `.worktrees/` (this workflow creates one per task — it must never be committed), build output (`**/target/`, `**/build/`, `**/.gradle/`, `**/dist/`, `**/out/`, `**/node_modules/`, …), env files and credentials, logs, test artifacts, IDE and OS metadata. The copy-pasteable list and its four traps (`.env*` swallowing the templates that must stay committed, never a blanket `*.jar` because the Gradle/Maven wrapper jars must stay tracked, `**/build/` and `**/bin/` colliding with real source dirs, and credential wildcards that miss a bare `foo.json`) are in the same doc.

The repo must provide a one-command local setup that brings up every service via Podman (`compose.yml` + a `Containerfile`/`Dockerfile` per component). Before starting, verify: the repo (and, for shape C, its submodules) is cloned, `.env` is configured, `podman compose up -d` succeeds, key endpoints are reachable, and E2E tests can run locally.

### Single-task development cycle

Every new feature, improvement, or bug fix is treated as an independent task that goes through the full cycle; all artifacts produced live in that task's Git worktree.

```
A. Fetch latest code       → git fetch/pull + create the task's Git worktree
B. Requirements & design clarification → spec.md + page/design mapping + capacity & infra baseline + unit-testable acceptance criteria (Gherkin optional — see Step E)
C. Write the plan          → implementation-[phase].md (one phase ≈ one small User Story)
D. Implement               → code changes + progress tracked in the plan doc
E. Unit & contract testing → module unit tests (real/spec-derived mock data) + frontend↔backend contract tests, all green (root-cause failures; e2e only on explicit request)
F. Manual review           → the worktree's own container stack (optional)
G. Performance & scalability verify gate → `~/docs/scalability-review-checklist.md` §12; record the conclusions in `spec.md` / `implementation.md`
H. Update docs             → `README.md` / applicable project instruction file / `docs/*.md`
I. Submit PR
```

#### Step A: Fetch latest code + create a worktree

```bash
cd <project-root>
# Determine the repo's real trunk from remote metadata and project documentation.
# It is NOT always `main`; many repos use `develop` while `main` is a lagging release branch.
git fetch origin

WORKTREE=".worktrees/$(date +%F-%H%M)-<topic>"
git worktree add -b feature/<topic> "$WORKTREE" origin/<default-branch>
cd "$WORKTREE"
git submodule update --init --recursive   # shape C only; initialize the commits pinned by the umbrella repo
```

Do not routinely run `git submodule update --remote --merge` while creating a task worktree. The umbrella repository's pinned submodule commits are its reproducible source of truth. Update a submodule to a newer remote commit only when the task explicitly includes a submodule version update, and first verify the submodule's actual trunk branch.

Checklist: a Kanban work item (Azure DevOps Feature/User Story/Task or GitHub Issue) is linked for this task — if none was provided, the agent drafts it, obtains user confirmation, creates it with an available tracker tool, and links it; switched into the new worktree created directly from fresh `origin/<default-branch>`; branch name is clear (`feature/xxx`, `fix/xxx`); submodules are initialized at the umbrella-pinned commits; local container environment starts. **A worktree is required even for changes that touch only umbrella-owned files** (root docs, `plans/`, config) and never enter a submodule — don't skip it just because there's no submodule pointer to bump; two tasks sharing one working tree can clobber each other's edits just as easily on docs as on code.

#### Step B: Requirements & design clarification

**Inputs** (the more the better): user story / requirement description, business context and goals, existing prototypes / design mockups / flowcharts (Figma/Penpot URLs, PNG/JPG screens), relevant meeting notes, similar feature implementations for reference, known constraints (security, performance, compliance, third-party integrations).

**Goal**: the AI searches the codebase, reads relevant docs, and clarifies open questions with the user, ultimately producing:

**Naming rule**: plans directories are `YYYY-MM-DD-HHMM-<topic>` (hour+minute keeps topics in true chronological order; never date-only). The spec file is always `spec.md`, never `design.md` — the old name was too easy to confuse with UI-design content. **Every change size** gets a plans entry — bounded fixes and bugfixes too (spec.md may be brief; implementation.md may be a short post-hoc record); ad-hoc scratch briefs elsewhere must be transcribed into `plans/` before merge.

- `./plans/YYYY-MM-DD-HHMM-[topic]/spec.md` — background and goals, scope (in/out), current-state analysis, solution design (architecture / data flow / API / database / frontend / config changes), key decisions and rationale, risks and mitigations, acceptance criteria, references.
- **A page/screen ↔ requirement mapping** — a section in spec.md, or its own `user-journey.md` for larger features: for every page or screen implied by the requirements doc, and every UI design screen (Figma frame URL, PNG/JPG mockup), map each to its corresponding requirement/user story and vice versa, then thread them into a complete user journey (entry point → screen → screen → outcome). This is what surfaces a screen with no backing requirement, or a requirement with no design counterpart, before implementation starts rather than mid-Step-D.
- **A three-layer data-flow specification, organized as JSON Schema (三层数据流)** — put it in the **Data Flow (数据流)** section of `spec.md`, or in a separate `data-flow.md` for a larger feature. Describe each layer: a) **UI/presentation layer**: the data visible to each page/component, including field names, types, and nullability; b) **DDD domain layer**: how the domain supplies data to the UI, including the aggregates involved, field mappings, cross-aggregate composition, and the sources of derived fields; c) **storage layer**: how the data is persisted, including table/document structures, indexes, and mappings to domain fields. Before documenting UI presentation data or domain data, **search existing assets first (搜旧)**: inspect previous requirement documents (older specs, the `~/plans` archive, and project docs) and existing code (UI components and DTOs, domain aggregates/models, and storage schemas). Classify each structure as **reuse (复用)**, **reuse with modification (修改后复用)**, or **new (全新)**, and record that decision in the data-flow document to avoid parallel implementations. Acceptance threshold: **every UI field is traceable across all three layers** (UI ↔ domain ↔ storage), each layer is marked reuse/modified/new, and the fields share the same source of truth as the Interface Schema in Step C.
- **An Event Storming (事件风暴) analysis covering write and read dimensions** — put it in the **Event Storming** section of `spec.md`, or in a separate `event-storming.md` for a larger feature (method reference: Wikipedia, “Event storming”). For the **write dimension**, list each chain as actor/role → command → event → subsequent policy, action, cascading event, or notification. For the **read dimension**, list each view the user needs and every query it supports, including sorting, searching, filtering, and pagination. Acceptance threshold: **every write action has a complete actor → command → event → follow-up chain, and every view has a query inventory**.
- **A capacity & infrastructure baseline** — a **Performance and Capacity (性能与容量)** section in `spec.md` (§0 of `~/docs/scalability-review-checklist.md`). Two parts, both **gathered before designing, not after**:
  1. **Baseline numbers, pulled from the observability stack first.** If the project has monitoring / tracing / logging that you can reach — GCP (Cloud Monitoring / Logging / Trace / Profiler, plus the DB's own statistics views), Azure (Application Insights / Log Analytics / Azure Monitor), Grafana + Prometheus / Loki / Tempo, Datadog, New Relic, Sentry — **go read the real numbers yourself** (read-only credentials; any *write* to a live environment needs the user's OK first). That covers current QPS, latency percentiles, error rates, instance counts, the slow-query/scan-row leaderboard, table row counts, and the release timeline. Only when no such tooling is reachable do you ask the user — and then ask the concrete questions in the checklist's §0.1, not "how much traffic do you have". Note in spec.md which environment and date the numbers came from.
  2. **The project's actual infrastructure** — what the system runs on is the denominator of every capacity estimate, so inventory it (checklist §0.2): compute (services, CPU/memory, min/max instances, **per-instance concurrency**, request timeout), database (engine, node count/size, regions, replicas, big-table row counts, existing indexes), cache, message bus (push/pull, ack deadline, DLQ), gateway / **WAF** / CDN, storage, scheduled jobs **and their trigger times**, network regions vs. where users actually are, the dev/uat/prod ladder (dev is usually a sandbox — use uat/prod as the baseline), the **hard limits** (per-statement SQL parameter cap, request timeouts, body-size caps, MQ message limits), and the **autoscaling ceilings** that bound the bill when something is misconfigured or gets hammered. Prefer a read-only CLI sweep (`gcloud … list`, `az … list`, `kubectl get`, `terraform show`) over asking; ask the user only for what the sweep can't reach (or for access). If the repo already carries an infra snapshot doc, read it and check its date before re-deriving.
- **Acceptance criteria → unit tests (Gherkin optional)**: spec.md's acceptance criteria must be testable by unit/integration tests (Step E). Gherkin feature files are **optional** — write them only when the team wants business-readable scenarios or an e2e run is planned; when written, they go under the relevant **`e2e-test-<platform>`** component's own `features/` directory (one such component per platform/target — `e2e-test-web`, `e2e-test-android`, `e2e-test-ios`, `e2e-test-mobile`, `e2e-test-wechat-mp`; e.g. `e2e-test-web/features/[module]/[name].feature`), **never** at the monorepo root and never in the wrong platform's directory. If acceptance criteria change during implementation, update the affected tests (and feature files, if any) and sync spec.md.

Checklist: AI has fully understood the relevant codebase; ambiguous requirements confirmed with the user; `spec.md` is complete with testable acceptance criteria; every requirement-document page and every design screen has a mapped counterpart, with no orphans on either side; the three-layer data flow and Event Storming analysis are documented (every UI field is traceable across all three layers; each layer is marked reuse/modified/new; the existing-assets search is complete; every write action has an actor → command → event → follow-up chain; and every view has a query inventory); acceptance criteria are unit-testable (any Gherkin feature files are organized by module under the correct `e2e-test-<platform>` component's `features/` directory); the capacity & infrastructure baseline is in `spec.md`, with its source platform, environment, and date cited; and the design demonstrably fits those numbers and hard limits.

#### Step C: Write the plan

Turn spec.md into an executable implementation plan: `./plans/YYYY-MM-DD-HHMM-[topic]/implementation-[phase].md` (one file per phase for multi-phase tasks; a single `implementation.md` otherwise). Each plan includes: goal (which part of spec.md it covers), dependencies, task list (`- [ ]`), file/module change table, API/database/config change details, verification approach.

**Size each phase like a single Agile User Story: ≤3 story points, completable within one day.** If a phase doesn't fit that, split it into more phases rather than writing one large implementation-[phase].md — this keeps progress checkable day by day and keeps each phase's PR small enough to review properly.

**When a later phase depends on an earlier one, the earlier phase's implementation plan must pre-define the shared interface schema up front** — don't leave it to be discovered mid-implementation of the dependent phase. Concretely, before marking a phase's tasks done, its plan should nail down (in a dedicated "Interface Schema" section) one row per field: the design's field name (e.g. the Figma component/variable name) ↔ the frontend's field/prop name ↔ the backend REST API's JSON field name ↔ the database column/schema name. A downstream phase then implements against a fixed contract instead of guessing it or re-deriving it from whatever the previous phase happened to ship.

Example:

```text
plans
├── 2026-07-15-1430-vendor-assignment-configuration  # multi-phase: one file per phase
│   ├── spec.md
│   ├── figma-screenshots/                            # design refs cited in spec.md's page/screen mapping
│   │   ├── hub-policy-optimized.png
│   │   ├── postal-registry-optimized.png
│   │   └── ...
│   ├── implementation-phase-0-gherkin-features.md
│   ├── implementation-phase-1-shared-infrastructure.md
│   ├── implementation-phase-2-hub-policy.md
│   ├── implementation-phase-3-postal-registry.md
│   └── ...                                          # implementation-phase-5-rules-pricing.md, implementation-phase-6a-decision-engine-simulation.md, etc.
└── 2026-08-05-0915-hub-policy-scroll-fix            # single-phase: one file
    ├── spec.md
    └── implementation.md
```

**Any phase that touches data access, batch writes, async/scheduled work, caching, or an external call carries its performance decisions in the plan, not in someone's head** — which indexes the new queries rely on and how they get created (index creation is a separate DB write, decoupled from the code release), the pagination strategy (keyset vs OFFSET), the batch chunk size and the engine parameter limit it's derived from, timeouts at each layer, cache key granularity and its eviction path, and the tenant/hub predicate. These are the inputs the Step G gate will check, so deciding them here is cheaper than rediscovering them at verify time.

Checklist: goal is clear; tasks are broken down to an executable granularity; every file has a clear task list; multi-phase tasks are split by phase, each sized to ≤3 points / one day; any phase other phases depend on has its interface schema defined and documented before being marked done; performance-relevant decisions (indexes, pagination, chunk sizes, timeouts, cache keys) are written down with the numbers they came from.

#### Step D: Implement

Follow implementation-[phase].md to make the code changes, per these rules:

1. Track progress directly in the implementation doc (e.g. `- [x] Task 1: done (commit abc1234)`).
2. If the design turns out infeasible or needs adjustment, update spec.md immediately (confirm major changes with the user first).
3. Keep changes minimal — touch only code related to the current task; log opportunistic refactors as follow-up tasks instead of bundling them in.
4. Follow the project's existing code style; prefer reusing existing utilities/constants/error-handling patterns.
5. Verify locally after each key step (compile/run/test) before moving on; verify backend changes via local containers, frontend changes in a local browser.
6. For UI-driven work (web pages/screens with Vue.js/React, mobile app screens with iOS/Android), implement against a design reference — a Figma/Penpot/Stitch/Axure file, a PNG/JPG mockup, or an HTML demo — not directly from a prose requirements doc. If Requirements & design clarification didn't turn one up, ask for one (or where to find it) before writing UI code rather than guessing layout/spacing/visual details.
7. Treat §1–§8 of `~/docs/scalability-review-checklist.md` as coding red lines while writing, not as a post-hoc review — the recurring ones are: no non-SARGable predicate (leading-wildcard `LIKE`, a function wrapping an indexed column, `NOT IN (subquery)`), no `ORDER BY` without `LIMIT`, no unbounded `findAll()`-then-filter-in-memory, bind parameters instead of string-concatenating values (concatenation breaks the DB's query-plan cache as well as being an injection hole), chunk batch DML under the engine's parameter cap, put a tenant/hub predicate on every read and write, and give every outbound call a timeout.

Checklist: all planned tasks completed in code; implementation-[phase].md progress updated; spec.md updated if the design changed; local build passes; relevant unit/integration tests pass.

#### Step E: Unit & contract testing (unit-first; no automatic e2e)

**E2E tests are NOT run automatically during development/debugging** — a serialized e2e suite takes too long for the dev loop. The quality gate is **unit tests in the affected components** (e.g. backend `./mvnw test`, frontend `npm run test:local`, or the project's equivalents); e2e runs only when the user explicitly asks, or in CI. Three rules for the unit tests:

1. **Mock data reflects reality and the spec but never contains copied operational data.** For a new feature, a behavior change, or a repro/regression ("retro") test, derive mock/fixture data from (a) **sanitized structural observations from Dev/UAT rows** (cite the source environment and query date in a comment/Javadoc, but never copy raw row values) and/or (b) **synthetic data that conforms to the feature's specification** (valid enum values, formats, and value ranges that a production row could actually have). Remove or replace all PII, credentials, tokens, customer identifiers, and commercially sensitive values before committing. Never commit raw production, Dev, or UAT data.
2. **The frontend↔backend contract is tested on both sides.** REST request/response shapes (JSON field names, types, nullability) and any websocket messages must have unit-test coverage so a field drift fails a test instead of silently breaking the UI: backend tests assert the exact shape the frontend consumes; frontend tests mock API responses in the backend's real shape. A change that alters an endpoint's request/response shape updates the counterpart side's test in the same change.
3. **Tests are organized by module.** Test files mirror the module structure of the code they cover (backend: test tree mirrors the main package tree, one test class per unit; frontend: colocated specs per the project's convention). Shared fixtures/helpers live in the owning module's own test utilities, not global catch-all helpers.

**Root-causing failures** (never skip a test or loosen an assertion just to turn tests green):

1. Reproduce and localize the failure — which layer (UI / API / database / test code itself).
2. Determine the root-cause category: a requirements issue (acceptance criteria wrong or stale → update spec.md), an implementation issue (fix it in backend/frontend/etc.), or a test-code issue (fix the test, its fixtures, or its data).
3. Regardless of category, explain the failure, the root cause, and the proposed fix to the user and get confirmation before changing anything — especially when acceptance criteria are involved.
4. After fixing, rerun the affected module's suite (then the full unit suite before the PR) to confirm no regressions.

**When e2e IS explicitly requested**: run it inside whichever `e2e-test-<platform>` component matches the feature (`e2e-test-web`, `e2e-test-android`, `e2e-test-ios`, `e2e-test-mobile`, `e2e-test-wechat-mp`, etc. — don't mix scenarios or automation across platforms). Gherkin `.feature` files, when they exist, stay the source of truth for acceptance criteria — automation traces back to them, never the reverse; they don't have to be directly executable: a valid pattern is documentation-only scenarios hand-mapped 1:1 to a spec tagged with the scenario's case ID in whatever framework that component already uses (e.g. `npx playwright test --grep "@case-XXX"`), or run directly via pytest-bdd/Cucumber (`e2e-test-web/step_definitions/`, `pages/`, `tests/`). Never loosen a feature's description just to make a test pass.

Checklist: new/changed behavior covered by module unit tests with real/spec-derived mock data; contract-shape changes covered on both sides; full local unit suite green; any failures root-caused and fixed with user confirmation; tests committed. (When e2e was requested: all scenarios pass, automation traces to the feature files, both committed.)

#### Step F: Manual review on the local container stack (optional)

After the unit suite is green, the human may want to eyeball the change on a live stack. You may start the **worktree's own local container stack** for manual review and verification (e.g. `podman compose -p <YYYY-MM-DD-HHMM-topic> -f compose.yml up -d` from inside the worktree — never the main checkout's stack, which belongs to other in-flight work):

- **Naming**: when more than one local stack may run at once, give each a distinct compose project name of `YYYY-MM-DD-HHMM-[topic]` — same format as the worktree dir — e.g. `podman compose -p 2026-08-29-1342-event-storming up -d`. Named stacks are easy to list, target, and tear down (`podman compose -p <name> down`) without touching neighbours.
- **Port conflicts**: multiple stacks on one host bind the same host ports — before starting a second stack, remap its published ports (compose override file, `-p` is not enough; ports are the collision surface) or shut the other stack down. Verify the stack's key endpoints with curl before handing the URL to the human.
- Record which project name/ports you started in the task's plan doc so cleanup is unambiguous: `podman compose -p <name> down` when review is done.

Checklist (only if a stack was started): the stack came up from **this** worktree; its compose project name matches the worktree; key endpoints verified with curl before handing a URL to the human; project name and ports recorded in the plan doc for Step I's cleanup.

#### Step G: Performance & scalability verify gate (mandatory)

Before the docs pass and the PR, run the verify gate in **`~/docs/scalability-review-checklist.md` §12**. This is the point of the whole thing: catch performance debt at the change that introduces it, instead of during a production slowness investigation months later.

1. **Trigger check** (§12.1). The gate applies if this change added or modified any of: a SQL/mapper/ORM query (reports and exports included), a list/pagination/search/export endpoint, a batch write (`saveAll`, batch insert/update, `IN (...)`), a scheduled job or message consumer, a cache read/write path, an external/third-party call, an upload-download or large-payload or gateway path, a table/column/index/migration — or if it materially raises the call frequency of an existing path. If **nothing** is triggered (pure copy change, docs, test refactor), say so explicitly in the PR description with the reason, and skip to Step H.
2. **Answer §12.2 point by point** — not tick-boxes, actual conclusions: index coverage for every new predicate and sort column, SARGability, pagination strategy, projection width, estimated scan rows **at production data volume** (not against a 100-row local DB), batch chunk size vs the engine's parameter cap, optimistic locking across *all* write paths, tenant/hub predicates, where async work runs and whether it shares instances with user traffic, timeouts and retry/DLQ behaviour at every layer, thread pools bounded, cache key granularity and eviction, contract field names and payload shape (double-encoded payloads and upload paths can trip a WAF at the LB, where the backend sees nothing), and which metric or log would reveal this path failing in production.
3. **Write the conclusions into the task's `spec.md` / `implementation-[phase].md` under a Performance and Capacity (性能与容量) section** (§12.3): triggers hit, estimated data volumes and scan sizes, the index list and how those indexes get created, the hard-limit numbers used and where they came from, plus any **deliberately accepted** performance debt with its follow-up work item. The PR description links to it.
4. Anything found but not fixed becomes a logged follow-up task, not a silent omission — and if the finding changes the design, update spec.md and confirm with the user (same rule as Step D).

**A whole-system scalability review is a different job from this gate** — when asked to review or audit whether a system scales (rather than whether one change is safe), walk the same checklist from §0 to §11 section by section and cross-check the target system against every item rather than reasoning from memory; don't narrow it to the slow-query/index/cache angle. The four most commonly skipped sections are §0 (capacity + infra inventory), §1 (statelessness), §9 (observability), §10 (validation).

Checklist: triggers evaluated and recorded; every triggered question answered with a conclusion; the Performance and Capacity (性能与容量) section is written into the plan docs; follow-ups logged; no known "gets slower as data grows" structure shipped without being named.

#### Step H: Update docs

| Doc | When to update |
|------|----------|
| `README.md` | project overview, quick start, directory structure, or local run instructions change |
| `AGENTS.md` | project context, agent skills, conventions, common commands, development process, or code standards change; create this file for new project instructions |
| `CLAUDE.md` | update only as the compatibility fallback when the project has no `AGENTS.md` |
| `spec.md` | design changed during implementation |
| `implementation-[phase].md` | implementation progress updated (including the Step G Performance and Capacity (性能与容量) section) |
| `docs/**/*.md` | any internal, operational related knowledge updates, including new guides or updates to existing documentation — **and the infra/capacity snapshot doc when Step B's inventory found it stale or filled a gap** |

#### Step I: Submit PR

**Shape C (Git submodules) only: land each submodule's change via its own PR to its own remote first, then a separate umbrella commit/PR that only bumps the pointer(s) — and only after the submodule PR has merged.** Never commit a submodule's file changes from the umbrella checkout (`cd` into the submodule, branch/commit/push there), and never push straight to a submodule's trunk branch. For a cross-repo feature touching multiple submodules, use the same branch name in each so the relationship stays obvious in `git log` and in PR titles. **Shapes A and B (single-repo / `git subtree`) skip all of this** — the umbrella repo's own single PR covers the whole change.

**Run the repo's local unit test suite before pushing and before opening the PR — never rely on CI to catch unit-test failures for you.** Run each affected repo's full local suite (e.g. `npm run test:local` for `web/`, `./mvnw test` for `backend/`) and only push/create the PR after it passes. CI-only failures are expensive to diagnose after the fact: a 2026-07-28 incident cost a full investigation cycle when a Jest spec that fired a real (unmocked) axios call failed *only* on the PR build, with the console reporter showing an empty `●` block and a random victim test per machine — the kind of failure that local full-suite runs surface immediately and deterministically. (If a suite is already red on the base branch for unrelated pre-existing reasons, note that explicitly in the PR description instead of treating it as a pass.)

Before submitting, confirm: all code changes are committed on the worktree branch; `spec.md` / `implementation-[phase].md` / unit tests (and any Gherkin feature files + e2e automation, when they exist) are all committed; the affected components' full local unit suites pass (e2e only when explicitly requested); **the Step G performance gate has been run and its Performance and Capacity (性能与容量) section is committed**; relevant docs are updated.

PR description should include: background (linked requirement) — the PR must be linked to the Kanban work item (Azure DevOps Feature/User Story/Task or GitHub Issue) provided or created at Step A, summary of changes (feature + affected components/submodules), link to design docs, test checklist (unit/integration/contract tests; E2E/Gherkin only when explicitly requested), **performance-gate outcome (triggers hit + conclusions, or an explicit "not triggered, because …")**, project-documentation update checklist (`README.md` and the applicable project instruction file), notes.

**Clean up the worktree after the PR merges:**

```bash
cd <project-root>
podman compose -p <YYYY-MM-DD-HHMM-topic> down   # if Step F started a named stack for this worktree
git worktree remove .worktrees/<timestamp>-<topic>
git branch -D feature/<topic>              # all PRs use squash merge; first confirm the PR merged
git push origin --delete feature/<topic>   # optional
```

If a Step F review stack is still running (`podman compose ls` / `docker compose ls` lists project names), tear it down by its recorded project name **before** removing the worktree — the compose file it reads lives inside the worktree, and removing the directory first leaves a stack that can only be stopped by container-id.

**Recursively check all parent and sub-folders for leftover worktrees** — not just the current repo. In umbrella repos that aggregate git submodules (e.g. `ups-hms-all-in-one`), AI agents may have created worktrees inside individual submodule directories (e.g. `e2e-test-web/.worktrees/`). All such worktrees must be cleaned up after their branches merge:

1. Run `git worktree list` in each relevant repo (umbrella + every submodule that was worked on) to discover registered worktrees.
2. For each worktree whose branch has actually merged, run `git worktree remove <path>` then `git branch -D <branch>`.
3. **Confirm "merged" from the PR's own status (or by diffing content) — never by looking for your commit SHA on the target branch.** A squash merge rewrites the branch's commits into one new commit, so `git log … | grep <sha>` and `git merge-base --is-ancestor` both report "not merged" for work that is fully merged, and `git branch -d` refuses to delete it for the same reason. Once the PR is confirmed merged, `git branch -D` is the correct way to remove a squash-merged branch. (Also mind the target branch: it may be `develop`, not `main`.)
4. Skip worktrees that still have uncommitted changes or whose branch has genuinely not merged yet.

**ALL PRs in my repos are Squash Merges — always.** Consequences (learned 2026-09-08, reading-app PR #74 conflict):

- **Never base a new branch on an unmerged feature branch** — after a squash merge, main does NOT contain the feature branch's commits, so any branch cut from it diverges forever and the PR conflicts on every touched file. Always cut new branches from a fresh `origin/<trunk>`.
- Branch deletion is always `git branch -D` (squash-merged branches are never ancestors of the trunk).

### Directory & file naming quick reference

| Type | Path template |
|------|----------|
| Worktree | `.worktrees/YYYY-MM-DD-HHMM-[topic]/` (timestamp = `date +%F-%H%M`, e.g. `2026-08-29-1342`; no author suffix needed — the branch/commit already record who) |
| Spec (the design doc — always named `spec.md`, never `design.md`) | `./plans/YYYY-MM-DD-HHMM-[topic]/spec.md` |
| Implementation plan | `./plans/YYYY-MM-DD-HHMM-[topic]/implementation-[phase].md` |
| Gherkin | `e2e-test-<platform>/features/[module]/[name].feature` (e.g. `e2e-test-web/`, `e2e-test-android/`, `e2e-test-ios/`, `e2e-test-mobile/`, `e2e-test-wechat-mp/` — never the monorepo root, never the wrong platform's component) |
| E2E code | `e2e-test-<platform>/step_definitions/`, `e2e-test-<platform>/pages/`, `e2e-test-<platform>/tests/` |
