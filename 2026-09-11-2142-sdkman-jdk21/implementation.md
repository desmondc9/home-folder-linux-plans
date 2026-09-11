# sdkman + JDK 21 实施记录

- [x] 检查现状:无 `~/.sdkman`、无 `sdk`、zshrc 无 sdkman 片段;get.sdkman.io 直连可达
- [x] 首次安装:失败——缺 `unzip`(sudo 需交互认证 → 用户自跑 `sudo apt-get install -y unzip`,轮询等待就绪)
- [x] 二次安装:失败——缺 `zip`(同上,用户自跑 `sudo apt-get install -y zip`,轮询等待就绪)
- [x] 确认安装脚本对 `zip` 仅存在性检查、安装只用 `unzip`(拉脚本源码核对 209–227/421–482 行)
- [x] 三次安装成功:sdkman script 5.23.0 / native 0.7.34,自动追加 `~/.bashrc` 与 `~/.zshrc` init 片段
- [x] `sdk list java` 查 21.x 可用版本 → 选 `21.0.12+1.1-tem`(Temurin)
- [x] `sdk install java 21.0.12+1.1-tem` → 自动设默认;显式 `sdk default java 21.0.12+1.1-tem` 兜底
- [x] 验证:`sdk version` / `sdk current java` / `java -version`(21.0.12.1 LTS)/ `JAVA_HOME=~/.sdkman/candidates/java/current`
- [x] 归档:spec.md + 本记录 + README 索引行;gitleaks 扫描后 commit & push
