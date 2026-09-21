# home 目录直接 git 化(git init ~)是否合适(调研)

> 2026-09-21,研究型调研。问题:WSL2 Ubuntu 26.04 上,把 `~` 直接变成一个 git 仓库(`git init ~`,`.git` 放家目录)是否合适;对照 bare repo / chezmoi / yadm / GNU stow / 分仓库管理等方案,全部论断给出一手出处(git 官方文档、各工具官方站)。本文件只做调研落盘,不改动机器、不执行任何 git 写操作。

## 1. 问题背景

- 环境:WSL2 Ubuntu 26.04 @ Windows 11(mirrored networking);zsh + oh-my-zsh、nvim(LazyVim)、opencode CLI、podman。
- 动机:用户想把家目录纳入版本管理(至少"能追踪 ~/docs 今天刚写的未版本化更新"),在考虑"直接 `git init ~`"。
- 本机现状盘点(2026-09-21 只读实测,均为本机事实):

| 项 | 实测值 |
|---|---|
| `~/.git` 是否存在 | 否(尚未 init) |
| `~` 顶层条目数 | 66 个(`ls -A ~ \| wc -l`) |
| `~/Repos` | 23 G;depth≤3 内 **10 个** `.git` 仓库(含 `ups-hms-all-in-one`(带 submodule 的 umbrella)、带 `node_modules` 的 monorepo) |
| `~/plans` | 独立 git 仓库(`.git` 7.7 M),已推 GitHub `desmondc9/home-folder-linux-plans` |
| `~/docs` | **不是** git 仓库(96 K,当天有未版本化更新) |
| 家目录敏感物 | `~/.gcp/` 3 个 GCP SA 私钥 JSON、`~/.azure`、`~/.azure-china`、`~/.azure-global`、`~/.azure_ai_foundry`(MSAL token cache)、`~/.azure-devops/credentials.jsonc`(ADO PAT)、`~/.ssh/` |
| 其他大/杂目录 | `~/.local` 6.2 G、`~/.cache` 415 M、`~/Backups` 13 M、`~/lazygit` 等 |
| 容器状态 | 不在 `~` 下(podman) |

## 2. 各方案与一手证据

### 2.1 直接 `git init ~`(普通仓库,`.git` 在家目录)

机制事实(git 官方文档):

- gitrepository-layout(https://git-scm.com/docs/gitrepository-layout,DESCRIPTION 节)明确定义仓库的第一种形态是 **"a `.git` directory at the root of the working tree"** —— `git init ~` 之后整个家目录就是这个仓库的 working tree,`.git` 就是家目录下的普通子目录,任何沿目录树向上找 `.git` 的工具都会在家目录"发现仓库"。
- 嵌套仓库(~/Repos 下的项目仓库、~/plans)在此形态下的表现:
  - gitsubmodules 指南(https://git-scm.com/docs/gitsubmodules,DESCRIPTION 节):**"A submodule is a repository embedded inside another repository"**,superproject 通过 tree 里的 `gitlink` 条目 + `.gitmodules` 条目跟踪它;`gitlink` 只记录 commit 的对象名,**`.gitmodules` 才提供 URL 等提示**。其 FORMS 节还列出 "Old-form submodule: A working directory with an embedded `.git` directory"(即子仓库自带 `.git` 目录的形态——正是 `~/Repos/*` 在家目录仓库眼里的样子)。
  - git-add 文档(https://git-scm.com/docs/git-add,`--no-warn-embedded-repo` 项):**"By default, `git add` will warn when adding an embedded repository to the index without using `git submodule add` to create an entry in `.gitmodules`"** —— 误把 `~/Repos/foo` add 进家目录仓库,得到的是一个**没有 URL 的裸 gitlink**,换机 clone 后无法还原。
- gitignore 的 allowlist 写法与其限制(https://git-scm.com/docs/gitignore):
  - 官方示例(PATTERN FORMAT/EXAMPLES 节)——排除一切、只放行 `foo/bar` 的唯一正确写法:

    ```gitignore
    # exclude everything except directory foo/bar
    /*
    !/foo
    /foo/*
    !/foo/bar
    ```

  - 关键限制原文(PATTERN FORMAT 节,`!` 前缀条目):**"It is not possible to re-include a file if a parent directory of that file is excluded. Git doesn't list excluded directories for performance reasons, so any patterns on contained files have no effect, no matter where they are defined."** —— 这就是为什么必须用上面的"逐层开门"写法,不能简单 `*` + `!dir/file`。
- 性能:git status 需要"确定 untracked 文件",在 `~` 仓库下意味着扫描整个家目录(含 23 G 的 `~/Repos`)。官方缓解手段是 untracked cache(见 §4 性能行),但它按目录 mtime 剪枝,**首次/结构变动后的全量扫描不可避免**。
- 工具干扰(一手证据,ripgrep 官方 GUIDE.md,https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md):
  - rg 默认尊重 `.gitignore`,且 **"This includes `.gitignore` files in parent directories that are part of the same `git` repository. (Unless the `--no-require-git` flag is given.)"** —— `~` 有 `.git` 后,`~/Repos/ups-hms-all-in-one` 等目录(若自身被 ignore 或在其外)的搜索会被家目录级 ignore 规则接管。
  - 更直接的坑(同页 Basics 节注):**"One likely cause of this is that you have a `*` rule in a `$HOME/.gitignore` file."** —— 家目录放 `*` allowlist 式 `.gitignore` 本身就会让 rg 在家目录下"搜不到任何文件"。**注意:这个坑与 `~` 是否有 `.git` 无关,`$HOME/.gitignore` 里的 `*` 规则就足以触发**(rg 还尊重 `core.excludesFile`,同页 Automatic filtering 节)。
- 其他干扰(zsh git 提示符每条命令跑 `git status`、IDE 打开 `~` 时把它识别为仓库根、`git clean -xdf` 误在家目录执行会清掉所有 untracked 文件含其他仓库):**本机推断**(基于 git clean/status 的已知语义;上述具体工具行为的官方原文未逐一核验,ripgrep 除外)。

### 2.2 bare repo + work-tree(Atlassian 方法)

来源:Atlassian 官方教程 "Dotfiles: Best way to store in a bare git repository"(https://www.atlassian.com/git/tutorials/dotfiles,已全文核验;作者 Nicola Paolucci,技术源自 Hacker News 上 StreakyCobra 的方案)。

- 核心原文:**"storing a Git bare repository in a '*side*' folder (like `$HOME/.cfg` or `$HOME/.myconfig`) using a specially crafted alias so that commands are run against that repository and not the usual `.git` local folder, which would interfere with any other Git repositories around."** —— 这就是"git dir 不叫 `.git` 就能规避工具发现"的出处:gitrepository-layout 定义的两种形态里,working tree 根下的 `.git` 目录才是"仓库标记";bare 目录(如 `~/.cfg`)不满足该形态,向上搜索 `.git` 的工具找不到它。
- 标准四步(教程原文):

  ```bash
  git init --bare $HOME/.cfg
  alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
  config config --local status.showUntrackedFiles no
  echo "alias config='...'" >> $HOME/.bashrc
  ```

- ignore 策略:教程**不依赖 `.gitignore`**,而是 (a) `status.showUntrackedFiles no`(原文解释:"files you are not interested in tracking will not show up as untracked"),(b) 只显式 `config add <file>`;(c) 迁移到新机器时把 `.cfg` 写进 `.gitignore` 防递归(`echo ".cfg" >> .gitignore`)。
- 适用场景(教程定位):**"No extra tooling, no symlinks, files are tracked on a version control system, you can use different branches for different computers, you can replicate you configuration easily on new installation."** —— 无新依赖、纯 git 心智,适合只想管 dotfiles、接受手动 add 的人。
- 它没解决的:机密文件裸奔依旧(chezmoi 对比表中 bare git 的 "Private files" / "Whole file encryption" / "Password manager integration" 全为 ❌);`config add -A` 仍会一把抓;误 add `~/Repos/foo` 同样产生裸 gitlink(§2.1 的 git-add 警告规则与仓库形态无关)。
- 本机组合要点(由上述文档推导):ignore 规则应放 **`$GIT_DIR/info/exclude`**(即 `~/.cfg/info/exclude`;gitignore 文档 SYNOPSIS/DESCRIPTION 节列明的标准 exclude 来源之一,且对外不可见、rg 不感知)而**不是** `~/.gitignore`(避 §2.1 的 rg 坑)。

### 2.3 chezmoi

来源:chezmoi 官方对比页 https://chezmoi.io/comparison-table/(已核验;**注意旧链 https://chezmoi.io/comparison/ 已 404**,任务书给的 URL 即此旧址)。生态佐证:dotfiles.github.io/utilities/(chezmoi 21,649 stars,列首位)。

官方对比表摘录(chezmoi vs bare git 等六方案,表头含 chezmoi/dotbot/rcm/vcsh/yadm/bare git):

| 维度 | chezmoi | yadm | bare git |
|---|---|---|---|
| Distribution | Single binary | Single script | – |
| Bootstrap requirements | **None** | git | git |
| dotfiles are... | Files | Files | Files |
| Private files | ✅ | ✅ | ❌ |
| Whole file encryption | ✅ | ✅ | ❌ |
| Password manager integration | ✅ | ❌ | ❌ |
| Machine-to-machine file differences | Templates | Alternative files, templates | ⁉️ |
| Run (once) scripts | ✅ | ✅ | ❌ |
| File removal / Externals | ✅ | ❌ / ✅ | ❌ |

- 定位:单一 Go 二进制、源状态(source state)独立目录、模板处理机器差异、整文件加密(age/gpg)、密码管理器集成、`diff` 预览后 apply。表尾注明图例(✅ 支持 / ⁉️ 需大量手工 / ❌ 不支持),并给出进一步比较的链接即 dotfiles.github.io/utilities。
- 取舍:功能最全,但引入新工具与新概念(模板、source/target 状态);对"只想要 git"的人是额外复杂度。

### 2.4 yadm

来源:yadm 官网首页 https://yadm.io/ 与 Overview 页 https://yadm.io/docs/overview(均已核验;**https://yadm.io/docs 裸路径 404**,docs 以 `/docs/<page>` 组织)。

- 官方定位(首页 Overview 卡片):**"yadm helps you maintain a single repository of dotfiles, while keeping them where they belong—in `$HOME`"**;**"If you know how to use Git, you already know how to use yadm."**
- Overview 页原文要点:它"像只作用于 dotfiles 的 git";**"It doesn't matter if your current directory is another Git-managed repository"**(不干扰 `~/Repos` 里的仓库——与 bare 方法同理,内部使用专用仓库而非 `~/.git`);"automatically inherits all of Git's features(branch/merge/rebase/submodules)"。
- 功能四件套(首页卡片):Alternate Files(按 OS/hostname 切换文件)、**Encryption**(官方原文点出 "passwords, encryption keys, or other sensitive information" 场景)、Bootstrap(clone 后自执行)、Hooks。
- 取舍(结合 chezmoi 对比表):单脚本、git 心智、有加密;但无密码管理器集成、模板能力弱于 chezmoi;本质是"官方维护的 bare repo + 别名 + 加密层"。

### 2.5 GNU stow

来源:GNU Stow 官方手册 https://www.gnu.org/software/stow/manual/stow.html(手动 webfetch 超时,改经 web-reader 核验成功;手册版本 2.4.1,2024-09-08)。

- 官方定义(Introduction 章):**"GNU Stow is a symlink farm manager which takes distinct sets of software and/or data located in separate directories on the filesystem, and makes them all appear to be installed in a single directory tree."** 且明说现代用途之一是 **"management of configuration files in the user's home directory…, especially when coupled with version control systems"**。
- Terminology 章官方点名 home 场景:**"Another common choice is `~` … in the case where Stow is being used to manage the user's configuration ('dotfiles')"**(target directory = `~`,package 目录放在 stow directory 下)。
- 安全性设计(Introduction 章):**"Stow stores no extra state between runs"**、**"Stow will never delete any files, directories, or links that appear in a Stow directory"**;有 Ignore Lists(第 4 章)、冲突处理(第 7 章)、tree folding/unfolding(第 5 章)。
- 取舍:仓库边界是 stow 目录(如 `~/dotfiles`,一个普通 git 仓库),`~` 本身永远没有 `.git`;代价是 symlink 心智、无加密/模板/机器差异能力(chezmoi 表中未列 stow,该表只比六方案)。生态位佐证:dotfiles.github.io/utilities/ 对 GNU Stow 的描述 "a symlink farm manager, useful for automatically (and safely) linking your dotfiles folder into your home directory"。

### 2.6 homeshick

来源:dotfiles.github.io/utilities/(GitHub 官方 dotfiles 站,已核验):**"Homeshick … is like Homesick but written in bash. Great to combine with myrepos."**(2,193 stars)。定位:castle(每仓库一个主题)+ symlink + bash 实现,无加密/模板。其 GitHub README 未单独核验,以上为二级引用(官方生态页转述)。

### 2.7 家目录下分仓库管理(现状延伸 / vcsh 路线)

来源:dotfiles.github.io/utilities/(已核验)对 vcsh 的描述:**"`vcsh` manages all your dotfiles in Git without the need for symlinks. Any number of Git repositories will co-exist in parallel in your `$HOME` without interfering with each other."**(2,276 stars)

- 即:`~` 不做仓库,按主题建多个仓库(plans 一个、docs 一个、dotfiles 一个……),vcsh 是这条路线的工具化版本(多仓库并行叠加在同一 `$HOME`,chezmoi 表中 vcsh "Source repos: Multiple")。
- 用户本机已经在用这条路线的朴素版:`~/plans` 独立仓库推 GitHub。`~/docs` 完全可以复刻同模式。零新依赖、仓库边界天然贴合 AGENTS.md 的分主题 plans/docs 约定。

## 3. 风险清单(针对直接 `git init ~`)

| # | 风险 | 机制与后果 | 出处 |
|---|---|---|---|
| 1 | **误 add 密钥** | `~/.gcp/*.json`(GCP SA 私钥×3)、`~/.azure*`(MSAL token cache)、`~/.azure-devops/credentials.jsonc`(ADO PAT)、`~/.ssh/` 全在工作 tree 内;`git add -A` 或 IDE 的"stage all"一步入库,推到 GitHub 即泄密(本机 `~/plans` 推的是远端仓库,事故面真实存在) | 机制:gitrepository-layout "`.git` at the root of the working tree";目录清单为本机实测 |
| 2 | **allowlist 维护成本与语义陷阱** | 安全写法必须 `/*`+`!/foo`+`/foo/*`+`!foo/bar` 逐层开门;"父目录被排除后其内文件无法 re-include"是官方明记的语义限制;66 个顶层条目新装一个工具就可能漏一条 | gitignore 文档 PATTERN FORMAT(`!` 条目)与 EXAMPLES(官方 allowlist 示例) |
| 3 | **rg / 工具沿目录树找 `.git` 被干扰** | `~` 有 `.git` 后整个家目录成为"同一个 git 仓库",rg 尊重父目录 `.gitignore`(可用 `--no-require-git` 关);即使不放 `.git`,家目录 `.gitignore` 里的 `*` 规则也会让 rg 搜不到文件;zsh git 提示符、IDE 仓库识别同理会"看见"家目录仓库 | ripgrep GUIDE.md(原文见 §2.1,已核验);提示符/IDE 部分**本机推断** |
| 4 | **嵌套仓库 = 裸 gitlink** | `~/Repos/*`(10 个)与 `~/plans` 在家目录仓库下是 embedded repo;`git add` 会警告并记成无 `.gitmodules` 的 gitlink,只存 commit SHA 不存 URL,换机不可还原;`git status` 把它们显示为 untracked 目录 | gitsubmodules(DESCRIPTION/FORMS)+ git-add(`--no-warn-embedded-repo`) |
| 5 | **status / add 性能随家目录增长** | untracked 探测需遍历 working tree(23 G `~/Repos`、6.2 G `~/.local`、415 M `~/.cache`);untracked cache 靠记录目录 mtime 剪枝(原文:"recording the mtime of the working tree directories and then omitting reading directories and stat calls…"),且要求 FS 对目录内增删改正确更新 `st_mtime`;首次扫描与 mtime 失真时仍全量 | git-update-index 文档 UNTRACKED CACHE 节 |
| 6 | **误操作放大**(`git clean -xdf`、`git stash -u`、`git checkout .`) | 在家目录任意子目录执行时作用于整个家目录仓库,untracked 的其他仓库/密钥/备份可能被清 | **本机推断**(git clean/stash 已知语义;官方原文未在本次核验范围) |
| 7 | WSL2 特有 | `~` 在 VM 内 ext4,目录 mtime 语义正常,untracked cache 可用;但若把这套仓库挪到 `/mnt/c`(DrvFs/9p)则 mtime 粒度/可靠性差,untracked cache 与 status 都会更慢 | ext4 为本机实测(`df -T ~` 未跑,由 WSL2 默认布局推断);`/mnt/c` 部分**本机推断**(未核验官方文档) |

## 4. 针对本机环境的推荐结论(按用户实际诉求排序)

**结论:不要 `git init ~`。按诉求拆成三件事处理。**

1. **今天的真实痛点是 `~/docs` 未版本化 → 立即给 `~/docs` 单独建仓库**(复刻 `~/plans` 模式:独立 repo + 推 GitHub 私有仓库)。这是 §2.7 路线,零新依赖、零风险、立刻止损,且和已有 AGENTS.md 工作流(plans/docs 分主题)完全一致。`~/plans` 保持独立仓库,**不要**并入任何家目录级仓库。
2. **若目标是 dotfiles 管理 → 采纳 Atlassian bare repo 方法**(§2.2),理由:无新依赖、`~` 下无 `.git`(不触发风险 #3/#4 的发现机制)、git 心智与用户习惯匹配。本机落地要点:
   - git dir 取名 `~/.dotfiles.git` 或 `~/.cfg`(**不叫 `.git`**);alias `dotfiles='git --git-dir=$HOME/.cfg --work-tree=$HOME'`;
   - `status.showUntrackedFiles no` + **只显式 add**;
   - ignore 规则放 `~/.cfg/info/exclude`,**不要**在家目录创建 `.gitignore`(ripgrep 官方 GUIDE 明示 `$HOME/.gitignore` 的 `*` 规则会废掉 rg;`info/exclude` 是 gitignore 文档列明的标准 exclude 来源,且 rg 不感知无 `.git` 目录的仓库);
   - **密钥永不 add**:`~/.gcp`、`~/.azure*`、`~/.azure-devops`、`~/.ssh` 不进任何远端仓库;若确有"版本化机密文件"需求,这是升级到 chezmoi/yadm(整文件加密 ✅)的触发条件,不是把它们塞进 bare repo 的理由(chezmoi 对比表:bare git 加密 ❌)。
3. **未来若出现多机同步/模板差异化/密码管理器联动 → 升级 chezmoi**(§2.3,官方对比表全面领先;yadm 为同类替代,更贴 git 心智)。届时 bare repo 的历史可直接迁移(chezmoi 提供 migrating-from-another-dotfile-manager 文档,见其站内导航,未逐页核验)。

**为什么不推荐直接 `git init ~`(一句话版)**:本机家目录的密钥密度(风险 #1)+ 23 G/≥11 个嵌套仓库(风险 #4/#5)+ allowlist 的语义陷阱与 rg 污染(风险 #2/#3)使"省一个 side 目录"的收益完全盖不过风险面;而 bare repo 方法用同一个 git、只多一个别名,就把 `.git` 从工具的发现路径里拿掉了(出处见 §2.1/§2.2)。

## 5. 决策记录(2026-09-21)

用户决策:**不做 home git 化,也不为 ~/docs 单独建仓** —— 备份职责由 restic 承担(快照式备份)。本调研的第 2 条(Atlassian bare repo 方法)留作未来真有 dotfiles 管理需求时的参考方案,第 3 条(chezmoi)同理。

## 6. 参考

已核验(2026-09-21,经 webfetch / web-reader 实际读到全文或所引章节):

| # | URL | 用到的部分 |
|---|---|---|
| 1 | https://www.atlassian.com/git/tutorials/dotfiles | 全文(bare 方法原始出处、四步 setup、showUntrackedFiles no) |
| 2 | https://git-scm.com/docs/gitignore | SYNOPSIS/DESCRIPTION/PATTERN FORMAT(`!` 限制)/EXAMPLES(allowlist 官方示例) |
| 3 | https://git-scm.com/docs/gitrepository-layout | DESCRIPTION(两种仓库形态、gitfile 机制)、`info/exclude` 条目 |
| 4 | https://git-scm.com/docs/gitsubmodules | DESCRIPTION(embedded repo/gitlink)、FORMS(old-form embedded `.git`) |
| 5 | https://git-scm.com/docs/git-add | `--no-warn-embedded-repo` 项原文 |
| 6 | https://git-scm.com/docs/git-update-index | UNTRACKED CACHE 节全文(speed up git status、mtime 机制、core.untrackedCache) |
| 7 | https://chezmoi.io/comparison-table/ | 全表(chezmoi/dotbot/rcm/vcsh/yadm/bare git 六方案对比) |
| 8 | https://yadm.io/ + https://yadm.io/docs/overview | 首页四特性卡 + Overview(single repo in $HOME、cwd 是别的仓库也不影响、inherits Git features) |
| 9 | https://www.gnu.org/software/stow/manual/stow.html | Introduction(symlink farm、no extra state、never deletes)、Terminology(target=`~`)、Invoking(`--ignore` 等) |
| 10 | https://dotfiles.github.io/utilities/ | 全页(chezmoi/yadm/vcsh/homeshick/GNU Stow 定位与 stars) |
| 11 | https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md(经 raw.githubusercontent.com 取得) | Basics 注(`$HOME/.gitignore` 的 `*` 规则)、Automatic filtering(父目录 .gitignore 需同仓库、`--no-require-git`、`core.excludesFile`) |

未能核验 / URL 变动:

- https://chezmoi.io/comparison/ —— **404**,官方页已迁移至 `https://chezmoi.io/comparison-table/`(由 dotfiles.github.io 的链接证实并已核验新址);
- https://yadm.io/docs —— **404**(裸路径无页面),docs 实际按 `/docs/<page>` 组织,已核验 `/docs/overview`;
- homeshick 官方 GitHub README —— 未核验,§2.6 仅引用 dotfiles.github.io(二级、但为 GitHub 官方站点);
- chezmoi "migrating from another dotfile manager" 子页 —— 仅见站内导航,未逐页核验(§4 结论 3 中已标注);
- oh-my-zsh / VS Code / nvim 对上层 `.git` 的具体行为 —— 未取官方文档,相关论断在 §2.1/§3 标注为"本机推断"。

本机实测命令(只读):`ls -A ~ | wc -l`、`find ~/Repos -maxdepth 3 -name .git -type d`、`du -sh ~/Repos ~/.cache ~/plans ~/docs ~/.local ~/Backups`、`ls ~/.gcp ~/.azure* ~/.ssh`(2026-09-21)。
