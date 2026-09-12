# sdkman 安装 + JDK 21(Temurin)设默认 设计规格

- 日期:2026-09-11 21:42
- 环境:WSL2 Ubuntu 26.04(宿主 Windows 11 物理机 DESKTOP-J7NBNU4,mirrored networking)
- 状态:完成并验证
- 目标机器:本 Linux 机(WSL,用户 desmond,zsh)

## 1. 背景与目标

本机无 JDK、无 sdkman。目标:用官方脚本装 sdkman,再装 JDK 21(Temurin)并设为所有 shell 的默认 java,`JAVA_HOME` 由 sdkman 托管。

## 2. 方案

1. 官方安装脚本 `curl -s "https://get.sdkman.io" | bash`,装到 `~/.sdkman`。
2. 前置依赖 `unzip`、`zip` 缺失(sudo 需交互认证,由用户手跑 `sudo apt-get install -y unzip` / `zip`;两次轮询等待)。
3. 安装脚本自动向 `~/.bashrc` 与 `~/.zshrc` 追加 init 片段(`SDKMAN_DIR` + `source sdkman-init.sh`),zsh 下直接可用,无需手工配置。
4. JDK 选 **Temurin**(Eclipse Adoptium,社区默认发行版):`sdk install java 21.0.12+1.1-tem`,装完自动设默认;再显式 `sdk default java 21.0.12+1.1-tem` 兜底。
5. 网络:get.sdkman.io 及 broker 直连可达(本 shell 代理环境),下载无需额外镜像。

## 3. 验证(2026-09-11,均通过)

```
$ sdk version
SDKMAN! script: 5.23.0 / native: 0.7.34 (linux x86_64)

$ sdk current java
Current default java version 21.0.12+1.1-tem

$ java -version
openjdk version "21.0.12.1" 2026-08-18 LTS
OpenJDK Runtime Environment Temurin-21.0.12.1+1 (build 21.0.12.1+1-LTS)
OpenJDK 64-Bit Server VM Temurin-21.0.12.1+1 (mixed mode, sharing)

$ echo $JAVA_HOME
/home/desmond/.sdkman/candidates/java/current
```

## 4. 已知残余

- 安装脚本对 `zip` 仅做存在性检查(第 221–227 行),安装过程只用 `unzip`;但缺 `zip` 会直接退出,故仍需装。
- `sdk default <candidate>` 必须带版本参数,不带会报 usage 错误。
- 新 shell 需重开或 `source ~/.zshrc` 后 `sdk`/`java` 才可用(zshrc 片段在文件末尾,与 sdkman 要求一致)。

## 5. 参考

- 安装脚本源码:`curl -s https://get.sdkman.io`(存 /tmp 备查,zip 检查位置 209–227,解包 421/439/464/482)
