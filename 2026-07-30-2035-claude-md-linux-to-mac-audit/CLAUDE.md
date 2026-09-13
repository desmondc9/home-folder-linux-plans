## Overview

- When solving a problem, prioritize the best-fitting tool for the task. If the current system does not have that tool available, first try to install it or enable it rather than falling back to an inferior workaround, unless multiple installation attempts fail.

## Preferred CLI tools

- **ripgrep** (`rg`) is installed — prefer over `grep` for shell searches
- **fd** is installed — prefer over `find` for file discovery (macOS Homebrew ships the binary as `fd`; only Debian/Ubuntu's package renames it to `fdfind`)
- **sd** is installed — prefer over `sed` for find-and-replace in files
- **jq** is installed — use for JSON processing in shell pipelines
- **uv** is installed — prefer over `pip`, `conda` for managing and running Python scripts
  if uv is slow, add the pypi mirror into pyproject.toml to speed up package installation, for example:

  ```toml
  [tool.uv]
  index-url = "http://mirrors.aliyun.com/pypi/simple/"
  extra-index-url = ["https://pypi.org/simple"]
  ```

- **npm** is installed — prefer over `yarn` or `pnpm` for JavaScript/TypeScript package management
  if npm is slow, you can set the registry to a mirror to speed up package installation: `http://registry.npmmirror.com`

- **podman** is installed — prefer over `docker` for container management

## tmux-aware subagent display

Check whether the current shell is running inside tmux (`$TMUX` is set, or `tmux display-message -p '#S'` succeeds) before starting work that fans out into multiple subagents or an agent team (parallel `Agent` calls, `Workflow`, `dispatching-parallel-agents`, `subagent-driven-development`, etc.).

- **If inside tmux**: don't just run parallel agents silently in the background and report a final summary — use tmux to make the parallel work visible in real time:
  - 2-4 concurrent agents: give each one its own pane via `tmux split-window` (`-h` for side-by-side, no flag for stacked), and label each pane after its task with `tmux select-pane -t <pane> -T "<agent-label>"`.
  - More than ~4 agents, or long-running ones: one `tmux new-window -n "<agent-label>"` per agent instead of crowding panes.
  - Stream each agent's actual commands/output into its pane/window with `tmux send-keys -t <target> '<command>' Enter` rather than only piping a text summary at the end.
- **If not inside tmux**: don't spawn a tmux session just for this — that's a presentation nicety for when the user is already watching a tmux session (e.g. over Termius/frp), not a requirement. Fall back to the normal reporting behavior.
- This only changes how parallel work is *displayed*; it never changes what the agents are asked to do or their results.

## Network access from mainland China

I am based in mainland China. Some resources (Docker Hub, PyPI, npm, Maven, Gradle, GitHub, etc.) may be slow, time out, or be unreachable directly due to GFW restrictions.

If you hit connection failures, slow downloads, or timeouts when accessing such resources, choose the best fix instead of just retrying:

1. **Prefer a domestic mirror first** when one exists for the tool (e.g. Aliyun PyPI mirror, npmmirror registry, Aliyun/USTC Docker registry mirrors, Aliyun Maven mirror). Mirrors are faster and don't depend on the proxy being up.
2. **Fall back to the local proxy** when no good mirror exists or the mirror itself fails (e.g. GitHub, Docker Hub image pulls, Google/arbitrary web resources). Export before running the command:

   ```bash
   export http_proxy=http://127.0.0.1:10809
   export https_proxy=http://127.0.0.1:10809
   export all_proxy=socks5://127.0.0.1:10809

   export HTTP_PROXY=http://127.0.0.1:10809
   export HTTPS_PROXY=http://127.0.0.1:10809
   export ALL_PROXY=socks5://127.0.0.1:10809
   ```

3. For tools that ignore shell env proxy vars, configure their proxy settings explicitly rather than giving up — e.g. `~/.docker/config.json` for the Docker/Podman CLI itself; a macOS `launchd` service's `EnvironmentVariables` in its `.plist` (there is no systemd on macOS); or, since Podman's actual daemon runs inside a Linux VM (`podman machine`) that has its own network namespace separate from the host, configure the proxy *inside* that VM (`podman machine ssh`) rather than in `~/.zshrc`.
4. If both a mirror and the proxy fail, diagnose (check whether the local proxy at `127.0.0.1:10809` is actually running) before concluding the resource is unreachable.

## Development, testing, & debugging workflow

For any non-trivial feature or bug-fix task in a project repo (not quick one-off edits), follow this workflow so requirements are fully understood, code is traceable, everything is verifiable locally, and docs stay in sync. If the project has its own more specific process doc, prefer that but fall back to this playbook for anything it doesn't cover.

### Core principles

- **Context first**: consolidate all related repos into one parent repo so both AI and humans can see the full picture.
- **Parallel development**: isolate each task's workspace with `git worktree` to avoid conflicts.
- **Documentation-driven**: write down what to do, how, and why before touching code.
- **Test-first (TDD-style)**: write Gherkin feature files from the acceptance criteria during Brain Storming, before implementation. After implementation, generate E2E automation from those features and verify; on failure, root-cause and fix rather than skipping or loosening assertions.
- **Docs in sync**: after code changes, update `README.md`, `CLAUDE.md`, `AGENTS.md` accordingly.

### Kanban board (Azure DevOps / GitHub)

1. Before starting any feature, improvement, or bug fix, a corresponding Azure DevOps Feature/User Story/Task or GitHub Issue link must be provided. If the user hasn't provided one, ask for it before starting work.
2. When submitting the PR, it must be linked to that same Feature/User Story/Task or Issue.

### Repository structure (monorepo + Git submodules)

Keep all related repos in one parent repo (`<project-root>`), managed via Git Submodules:

```
<project-root>/
├── .gitmodules
├── .gitignore
├── backend/ frontend/ infrastructure/ middleware/ e2e/   # submodules
├── docs/
├── plans/                                                # spec.md / implementation-[phase].md per task, see below
├── features/                                             # Gherkin feature files per task, see below
├── README.md  CLAUDE.md  AGENTS.md
├── compose.yml
└── .worktrees/                                            # must be gitignored
```

Common commands:

```bash
git submodule update --init --recursive     # initialize
git submodule update --remote --merge       # update to latest
git submodule add <repository-url> <path>   # add a new submodule
```

`.gitignore` must exclude: `.worktrees/`, `.env*`, `*.log`, `.idea/`, `.vscode/`, `**/node_modules/`, `**/__pycache__/`.

The parent repo must provide a one-command local setup that brings up every service via Podman (`compose.yml` + a `Containerfile` per submodule). Before starting, verify: parent repo and submodules are cloned, `.env` is configured, `podman compose up -d` succeeds, key endpoints are reachable, and E2E tests can run locally.

### Single-task development cycle

Every new feature, improvement, or bug fix is treated as an independent task that goes through the full cycle; all artifacts produced live in that task's Git worktree.

```
Fetch latest code → Create Git worktree
  → A. Brain Storming    → spec.md + Gherkin features under ./features/ (e2e scenarios defined up front)
  → B. Write the plan    → implementation-[phase].md
  → C. Implement         → code changes + progress tracked in the plan doc
  → D. E2E testing       → generate/update automation from the Gherkin features, get every scenario passing (root-cause failures)
  → E. Update docs       → README.md / CLAUDE.md / AGENTS.md
  → F. Submit PR
```

#### Step 0: Fetch latest code + create a worktree

```bash
cd <project-root>
git fetch origin && git pull origin main
git submodule update --remote --merge

WORKTREE=".worktrees/$(date +%Y%m%d)-<topic>-$(whoami)"
git worktree add -b feature/<topic> "$WORKTREE"
cd "$WORKTREE" && git submodule update --init --recursive
```

Checklist: a Kanban work item (Azure DevOps Feature/User Story/Task or GitHub Issue) is linked for this task — ask the user for one if missing; switched into the new worktree; branch name is clear (`feature/xxx`, `fix/xxx`); submodules are available; local container environment starts.

#### Step A: Brain Storming

**Inputs** (the more the better): user story / requirement description, business context and goals, existing prototypes / design mockups / flowcharts, relevant meeting notes, similar feature implementations for reference, known constraints (security, performance, compliance, third-party integrations).

**Goal**: the AI searches the codebase, reads relevant docs, and clarifies open questions with the user, ultimately producing:

- `./plans/[timestamp]-[topic]/spec.md` — background and goals, scope (in/out), current-state analysis, solution design (architecture / data flow / API / database / frontend / config changes), key decisions and rationale, risks and mitigations, acceptance criteria, references.
- `./features/[module]/[name].feature` — Gherkin scenarios derived from spec.md's acceptance criteria, written before implementation (TDD-style) so Step D can use them directly. If acceptance criteria change during implementation, come back and update the feature files and sync spec.md.

Checklist: AI has fully understood the relevant codebase; ambiguous requirements confirmed with the user; spec.md is complete with testable acceptance criteria; Gherkin features are organized by module under `./features/`.

#### Step B: Write the plan

Turn spec.md into an executable implementation plan: `./plans/[timestamp]-[topic]/implementation-[phase].md` (one file per phase for multi-phase tasks; a single `implementation.md` otherwise). Each plan includes: goal (which part of spec.md it covers), dependencies, task list (`- [ ]`), file/module change table, API/database/config change details, verification approach.

Example:

```text
plans
├── 2026-05-15-voice-input-linux
│   ├── spec.md
│   └── implementations                           # multi-phase: one file per phase
│       ├── phase-0-scaffold.md
│       ├── phase-1-audio-vad-speech.md
│       └── phase-2-hotkey-paste.md
└── 2026-05-18-deb-release
    ├── spec.md
    └── implementation.md                         # single-phase: one file
```

Checklist: goal is clear; tasks are broken down to an executable granularity; every file has a clear task list; multi-phase tasks are split by phase.

#### Step C: Implement

Follow implementation-[phase].md to make the code changes, per these rules:

1. Track progress directly in the implementation doc (e.g. `- [x] Task 1: done (commit abc1234)`).
2. If the design turns out infeasible or needs adjustment, update spec.md immediately (confirm major changes with the user first).
3. Keep changes minimal — touch only code related to the current task; log opportunistic refactors as follow-up tasks instead of bundling them in.
4. Follow the project's existing code style; prefer reusing existing utilities/constants/error-handling patterns.
5. Verify locally after each key step (compile/run/test) before moving on; verify backend changes via local containers, frontend changes in a local browser.
6. For UI-driven work (web pages/screens with Vue.js/React, mobile app screens with iOS/Android), implement against a design reference — a Figma/Penpot/Stitch/Axure file, a PNG/JPG mockup, or an HTML demo — not directly from a prose requirements doc. If Brain Storming didn't turn one up, ask for one (or where to find it) before writing UI code rather than guessing layout/spacing/visual details.

Checklist: all planned tasks completed in code; implementation-[phase].md progress updated; spec.md updated if the design changed; local build passes; relevant unit/integration tests pass.

#### Step D: E2E testing

The Gherkin features were already written in Step A. This step implements/updates the corresponding automation in the `e2e/` submodule (`step_definitions/`, `pages/`, `tests/`) and runs every scenario locally:

```bash
podman compose up -d
cd e2e && pytest --gherkin-terminal-reporter -v
```

If acceptance criteria changed during implementation, first confirm and update the feature files under `./features/` (and sync spec.md) — the feature files drive the automation, not the other way around; never loosen a feature's description just to make a test pass.

**Root-causing failures** (never skip a scenario or loosen an assertion just to turn tests green):

1. Reproduce and localize the failure — which layer (UI / API / database / test script itself).
2. Determine the root-cause category: a requirements issue (feature description is wrong or stale → update the feature + spec.md), an implementation issue (fix it in backend/frontend/etc.), or a test-code issue (fix step definitions, page objects, test data, or environment config under `e2e/`).
3. Regardless of category, explain the failure, the root cause, and the proposed fix to the user and get confirmation before changing anything — especially when acceptance criteria are involved.
4. After fixing, rerun the full E2E suite to confirm the scenario and all others pass with no new regressions.

Checklist: feature files still accurately reflect acceptance criteria; automation implemented/updated; runs fully locally; all scenarios pass; any failures were root-caused and fixed with user confirmation; features and automation code are committed.

#### Step E: Update docs

| Doc | When to update |
|------|----------|
| `README.md` | project overview, quick start, directory structure, or local run instructions change |
| `CLAUDE.md` | context, conventions, or common commands relevant to AI-tool interaction change |
| `AGENTS.md` | agent skills, project conventions, dev process, or code standards change |
| `spec.md` | design changed during implementation |
| `implementation-[phase].md` | implementation progress updated |

#### Step F: Submit PR

Before submitting, confirm: all code changes are committed on the worktree branch; spec.md / implementation-[phase].md / feature files under `./features/` / e2e automation are all committed; local container environment and E2E tests pass; relevant docs are updated.

PR description should include: background (linked requirement) — the PR must be linked to the Kanban work item (Azure DevOps Feature/User Story/Task or GitHub Issue) provided at Step 0, summary of changes (feature + affected submodules), link to design docs, test checklist (unit/integration/E2E/Gherkin features), doc-update checklist (README/CLAUDE/AGENTS), notes.

**Clean up the worktree after the PR merges:**

```bash
cd <project-root>
git worktree remove .worktrees/<timestamp>-<topic>-<author>
git push origin --delete feature/<topic>   # optional
```

**Recursively check all parent and sub-folders for leftover worktrees** — not just the current repo. In umbrella repos that aggregate git submodules (e.g. `ups-hms-all-in-one`), AI agents may have created worktrees inside individual submodule directories (e.g. `e2e-test-web/.worktrees/`). All such worktrees must be cleaned up after their branches merge:

1. Run `git worktree list` in each relevant repo (umbrella + every submodule that was worked on) to discover registered worktrees.
2. For each worktree whose branch has been merged (confirm with `git log --oneline origin/main | head` — the merge commit should appear), run `git worktree remove <path>` then `git branch -d <branch>`.
3. Skip worktrees that still have uncommitted changes or whose branch has not yet merged.

### Directory & file naming quick reference

| Type | Path template |
|------|----------|
| Worktree | `.worktrees/[timestamp]-[topic]-[author]/` |
| Design doc | `./plans/[timestamp]-[topic]/spec.md` |
| Implementation plan | `./plans/[timestamp]-[topic]/implementation-[phase].md` |
| Gherkin | `./features/[module]/[name].feature` |
| E2E code | `e2e/step_definitions/`, `e2e/pages/`, `e2e/tests/` |