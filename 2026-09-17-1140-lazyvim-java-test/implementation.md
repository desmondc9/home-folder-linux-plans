# 实施记录

## 变更清单

1. `~/.config/nvim/lazyvim.json`:extras 追加 `lazyvim.plugins.extras.test.core`
2. `~/.config/nvim/lua/plugins/java-neotest.lua`(新增,见 spec.md 表格)
3. `~/.local/share/nvim/neotest-java/`:junit-platform-console-standalone-{6.0.3,1.10.1}.jar
   (repo1.maven.org 手动下载,sha256 校验通过)
4. `:MasonUpdate` + java-debug-adapter → 0.59.0(扩展版本;plugin jar 仍 0.53.2=最新)
5. `~/plans/2026-09-17-1140-lazyvim-java-test/`:本档案

## 验证过程(均为 headless 真机,XDG_CACHE_HOME 隔离避免抢用户 nvim 的 jdtls 工作区锁)

- [x] 根因复现:repro2(repro.lua)/repro5/6/7 —— findTestTypesAndMethods 恒 `[]`,
      findTestPackagesAndTypes 188 类(项目级正常,文件级坏)
- [x] 对照实验:mini-mvn 最小项目同版本组合全链路 OK → 排除版本组合、定位到"backend 项目 +
      文件级 AST 路径"
- [x] cwd 根因:umbrella 根启动 → is_test_file=false(原生 adapter);包装后 true
- [x] E2E:backend + umbrella 两种 cwd 均跑通 nearest test,passed=1 failed=0
- [x] 配置冒烟 CONFIG_OK;`Lazy sync` 装齐 neotest/neotest-java

## 遗留 / 跟进

- [ ] 上游:#844(jdt.ls 文件级 discovery)、mason#16867(asm jar)修复后,可考虑移除包装、
      恢复 nvim-jdtls 原生 runner(其优势:DAP 调试单测更顺);neotest-java 的 `<leader>td`
      Debug Nearest 亦可用(依赖 nvim-dap + jdtls)
- [ ] 若日后需要 go/python 的 neotest,在 java-neotest.lua 里去掉对应 `= false` 并解决
      neotest-golang 的 root 误判($HOME 当 root)问题
- [ ] `:NeotestJava setup` 的交互式下载在 headless 不可用 —— 若 junit jar 丢失,手动下载
      (spec.md 有 URL/版本)
