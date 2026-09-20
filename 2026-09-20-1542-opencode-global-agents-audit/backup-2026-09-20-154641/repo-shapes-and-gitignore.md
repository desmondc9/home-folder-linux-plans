# 仓库形态识别 + 基线 `.gitignore`

> **何时读这份文档**:在一个不熟悉的仓库里开工之前(`~/.config/opencode/AGENTS.md` 开发流程 **Step A** 之前),用来判定这个 "monorepo" 到底是哪种形态、据此决定怎么同步 / 在哪提交 / 怎么落 PR;以及新建仓库或补 `.gitignore` 时。
>
> 索引入口在 `~/.config/opencode/AGENTS.md` 的「Repository structure」小节 —— 那里有形态对照表和工作流结论,本文是展开细节。
>
> **最后更新**:2026-09-20(索引入口迁移至 `~/.config/opencode/AGENTS.md`)

---

## 1. 先判定形态

Not every "monorepo" is built the same way, and the right workflow (how to sync, where to commit, how to land a PR) depends on which shape it actually is. Before doing anything else in an unfamiliar repo, determine the shape:

- **Check for `.gitmodules` at the root.** If present, it's a **Git submodules** monorepo (shape C below) — `git submodule status` lists each pinned submodule and commit.
- **If no `.gitmodules`, check history for subtree merges**: `git log --all --grep="git-subtree-dir" -- .` (or check `.gitattributes`/the project's own docs for a mention of `git subtree`). A hit means it's a **`git subtree`** monorepo (shape B) — component directories were merged in via `git subtree add/pull`, each potentially still syncable with an upstream split repo.
- **Neither of the above** → it's a genuine **single-repo monorepo** (shape A) — every directory is native to this one repository, no nested `.git`, no subtree history.

## 2. Shape A — single-repo monorepo (new projects, no submodules/subtrees)

The common case for a project started as a monorepo from day one. All directories are plain, native to the one `.git`:

```
<project-root>/
├── .gitignore
├── backend/ frontend/ infrastructure/ middleware/   # plain directories, not submodules
├── e2e-test-web/ e2e-test-android/ e2e-test-ios/ ... # one e2e-test-<platform> per platform/target — see "Acceptance criteria → unit tests" in `~/.config/opencode/AGENTS.md` Step B
├── docs/
├── plans/                                            # spec.md / implementation-[phase].md per task — see `~/.config/opencode/AGENTS.md` Steps B–C
├── README.md  CLAUDE.md  AGENTS.md
├── compose.yml
└── .worktrees/                                       # must be gitignored
```

Workflow implication: **one branch, one PR** covers the whole change — no pointer-bump step, no per-component remote. Land everything through the project's single PR flow (`~/.config/opencode/AGENTS.md` Step I: Submit PR).

## 3. Shape B — `git subtree` monorepo (older projects that merged separate repos in)

Component directories were pulled in via `git subtree add --prefix=<dir> <remote> <branch>`, so each directory's history is genuinely part of this repo's history (unlike submodules — no separate `.git`, no pinned-commit pointer) — but some may still have a live upstream remote worth keeping in sync with.

- **Check whether a component still has a live upstream** before treating it as a purely local directory: `git remote -v` for a remote matching that directory's name/origin, or check the project's own docs for a "subtree remotes" list. If one exists, `git subtree pull --prefix=<dir> <remote> <branch> --squash` keeps it current; `git subtree push --prefix=<dir> <remote> <branch>` pushes a local fix back upstream.
- If no live upstream is configured (a one-time vendor import that's since diverged), treat the directory as plain repo content — edit and commit it like any other file, no subtree ceremony needed.
- Workflow implication: like shape A, changes land through **one branch, one PR** for the umbrella repo. Only reach for `git subtree push/pull` when a component's upstream sync is actually configured and the change is meant to flow both ways.

## 4. Shape C — Git submodules monorepo (older projects, separate repos pinned by commit)

Each component is genuinely its own repo with its own remote and history; the parent repo only stores a `.gitmodules` file and a pinned commit per submodule:

```
<project-root>/
├── .gitmodules
├── .gitignore
├── backend/ frontend/ infrastructure/ middleware/ e2e-test-web/ e2e-test-android/ ...   # submodules — each a separate repo, one e2e-test-<platform> per platform/target
├── docs/
├── plans/                                                # spec.md / implementation-[phase].md per task — see `~/.config/opencode/AGENTS.md` Steps B–C
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

**Before running `git submodule update --remote --merge` (or any blanket "sync all submodules" step), confirm each submodule's `.gitmodules`-pinned branch is actually its most-active branch.** A submodule's pinned default (often `main`) can lag weeks or thousands of commits behind a separate `develop`/trunk branch that carries its real day-to-day work — syncing "to latest" against the wrong branch leaves you on stale code with no error, and features already merged upstream can come back missing or broken in a way that looks like a product bug rather than a stale checkout. Check `git log --oneline -1 origin/<pinned-branch>` against the branch the team actually merges into (ask, or compare recent commit dates across candidate branches) before trusting a submodule sync — don't assume the pinned branch is current just because it's the default.

Workflow implication: **never** commit a submodule's file changes from the umbrella checkout. `cd` into the submodule, branch/commit/**push to its own remote**, land its own PR — then a **separate** umbrella commit/PR bumps the pointer, only after the submodule PR merges (full detail in `~/.config/opencode/AGENTS.md` Step I: Submit PR).

## 5. 三种形态通用:基线 `.gitignore`

`.gitignore` must exclude at least the following — **build output and dependency caches never belong in git**, and neither do credentials:

```gitignore
# workspace / tooling
.worktrees/
.claude/settings.local.json

# build output — JVM (Maven target/, Gradle build/ + .gradle/, Eclipse bin/)
**/target/
**/build/
**/.gradle/
**/bin/
*.class
*.hprof

# build output & caches — frontend / Node (Vite/webpack/rollup/tsc dist/, IntelliJ+Next out/)
**/node_modules/
**/dist/
**/out/
**/.vite/
**/.turbo/
**/.cache/
**/coverage/
npm-debug.log*
yarn-error.log*
pnpm-debug.log*

# build output & caches — Python
**/__pycache__/
*.py[cod]
.venv/
venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/
*.egg-info/

# test artifacts (Playwright and friends)
test-results/
playwright-report/
blob-report/
playwright/.cache/
.playwright-mcp/

# env & credentials
.env*
!.env.example
!.env.sample
!.env*.template
*.pem
*.p12
*.jks
*.keystore
*-sa*.json
*service-account*.json
*credentials*.json
*secret*.json
*gcp*.json
*.key.json

# logs
*.log
**/logs/

# IDE / editor
.idea/
.vscode/
*.iml
.settings/
.classpath
.project
*.swp
*~

# OS metadata (macOS Finder, Windows Explorer)
**/.DS_Store
.AppleDouble
Thumbs.db
Desktop.ini
```

Note the syntax while editing it: **one pattern per line, and `#` only starts a comment at the start of a line** — `**/target/   # Maven` is not a commented pattern, it's a literal pattern containing spaces and a hash, and it silently matches nothing.

Four things this list gets wrong if copied blindly:

- **`.env*` also swallows the templates that _should_ be committed** — hence the `!.env.example` / `!.env.sample` / `!.env*.template` negations above; keep them whenever you tighten the env rule. A repo with no committed env template is a repo nobody can set up. (Negations only work when the parent directory isn't itself excluded — git never descends into an ignored directory to un-ignore a file inside it.)
- **The build-tool wrapper jars must stay tracked.** `gradle/wrapper/gradle-wrapper.jar` and `.mvn/wrapper/maven-wrapper.jar` are how `./gradlew` / `./mvnw` bootstrap on a clean checkout; if a broad `*.jar` rule ever gets added, negate them (`!gradle/wrapper/gradle-wrapper.jar`). **Do not add a blanket `*.jar`** — that is the usual cause.
- **`**/build/` and `**/bin/` collide with real source directories** in some projects (a Go `bin/`, a JS package whose source lives in `build/`, a `scripts/bin/`). Check before adding, and narrow to the actual path (`backend/build/`) rather than deleting the rule wholesale.
- **The credential patterns are a safety net, not coverage.** Verified with `git check-ignore`: `*-sa*.json` matches `developer-cli-sa-prod.json` but **not** `sa-key.json` (no leading dash), and nothing here matches a bare `foo.json`. So the rule stands regardless of what the ignore file says: **name a credential file to match one of the patterns above, or keep it entirely outside the worktree (`~/`)** — never rely on the wildcard having thought of your filename.

Everything a build produces should be reproducible from a clean checkout — if something in the ignore list is genuinely needed by teammates or CI, publish it as a build artifact or a release asset, don't commit it.
