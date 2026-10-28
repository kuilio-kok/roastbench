<div align="center">

# 烤机台 RoastBench

**一个双击就能用的 Mac 烤机（压力测试）工具。**

不装 Homebrew，不敲一行命令，下载 → 打开 → 开始烤。

[下载最新版](https://github.com/kuilio-kok/roastbench/releases/latest) · [使用方法](#-使用方法) · [从源码构建](#-从源码构建)

![烤机台界面预览](docs/preview.png)

</div>

---

## 为什么做它

买了新 Mac，总会想问几个问题：这机器满载到底多烫？风扇会不会起飞？标称的功耗墙能顶多久？

要回答这些问题，通常得开终端跑 `yes > /dev/null`，或者装一套 Homebrew + Python 监控工具。对很多人来说门槛太高了。**烤机台把这些全装进了一个 1.3 MB 的 App 里**——双击打开，点一个按钮，剩下的交给它。

> 「烤机」是硬件圈的叫法：让电脑长时间满载运行，测试散热、功耗和稳定性，就像把机器放进烤箱里烤一遍。

## 它能做什么

- **自动认识你的 Mac** — 打开就知道你的机型、芯片、P/E 核数量、内存、有没有风扇、插没插电，并据此推荐合适的烤机模式
- **六种烤法**，想怎么烤就怎么烤（见下表）
- **实时曲线图** — 温度、功耗、风扇转速、P 核频率三条曲线 60 fps 平滑滚动，压力测试第一次可以「看得见」
- **温度保险丝** — 默认 108 °C 自动断电保护（可关）。烤机是测极限，不是烧机器
- **成绩单** — 烤完给你一个 S / A / B / C 评级和徽章，一键拷贝，可以直接发朋友圈晒机
- **拔电秒感知** — 烤到一半拔掉电源？立刻弹提示，功耗墙状态即时更新
- **菜单栏常驻** — 收进菜单栏也能看温度、控制烤机

| 模式 | 适合场景 |
|---|---|
| 🔥 极限双烤 | CPU + GPU + 内存一起满载，模拟最恶劣工况 |
| 🧠 CPU 单烤 | 满载 CPU，测处理器散热与降频表现 |
| 🎮 GPU 单烤 | 满载 GPU，测图形负载下的表现 |
| 🌡️ 温度探底 | 烤 45 秒、歇 15 秒，自动找出这台机器的**温度墙** |
| 🥶 凉拌模式 | 专为准无风扇机器（MacBook Air）设计的轻负载方案 |
| 🔋 电池降频 | 用电池烤，看拔电后功耗墙掉了多少 |

## 使用方法

1. 到 [Releases](https://github.com/kuilio-kok/roastbench/releases/latest) 下载 `烤机台 v2.7.zip`，解压
2. 把 `烤机台.app` 拖进「应用程序」文件夹（可选）
3. 第一次打开，macOS 会提示「无法验证开发者」——**右键点击 烤机台.app → 打开 → 打开**，只需要做一次

   或者终端执行：`xattr -dr com.apple.quarantine 烤机台.app`
4. 选一个模式，点「开始烤机」⏱

### 系统要求

- macOS 14 (Sonoma) 或更高
- 实时图表功能需要 **Apple Silicon（M 系列）**；Intel Mac 仍可以烤 CPU / GPU，但图表没有数据
- 烤机时机身会发烫、风扇会转——这是正常的。摸着烫手就让机器歇会儿 ☕

## 从源码构建

```bash
git clone https://github.com/kuilio-kok/roastbench.git
cd roastbench
./build.sh
```

构建脚本会编译 arm64 + x86_64 双架构通用二进制、生成图标，并输出 `烤机台.app`。需要 Xcode 命令行工具（`xcode-select --install`）。

## 技术实现

- **原生外壳，Web 内芯**：Swift + WKWebView，界面用 HTML / CSS / JS 画，通过自定义 URL Scheme 与原生层通信，无需任何框架依赖
- **数据源**：内嵌 [macmon](https://github.com/vladkens/macmon)（Apple Silicon 专属），免密码读取传感器数据，省掉了 Homebrew
- **隐私**：所有数据只在本机流转，**App 完全不联网**，没有任何统计、上报或遥测

## 已知限制

- 没有做公证（没有 Apple 开发者账号），所以第一次打开需要右键 → 打开
- Intel Mac 不支持实时图表
- 温度探底等长时间满载模式会让机身很烫，请把电脑放在硬质平面上使用

## 许可证

[MIT](LICENSE) · 感谢 [macmon](https://github.com/vladkens/macmon) 提供传感器数据支持

---

<div align="center">

如果烤机台帮你看清了你的 Mac，欢迎点个 ⭐ 支持一下

</div>
