# AihuishouBatchFind

爱回收 App「严选二手」批量查找 iOS 越狱插件

[![Build rootless](https://github.com/qq1643240/AihuishouBatchFind/actions/workflows/build.yml/badge.svg)](https://github.com/qq1643240/AihuishouBatchFind/actions/workflows/build.yml)

## 两种编译路径

1. **GitHub Actions 自动构建**（推荐，无需 Mac）：push 触发 `Build` 工作流，同时产出 `rootless` 和 `roothide` 两份 deb，从 Actions → Artifacts 下载。打 tag 如 `v1.0.0` 会触发 `Release` 工作流，自动把两份 deb 挂到 GitHub Release。
2. **本地 Mac 编译**：执行 `./scripts/build.sh rootless` 或 `./scripts/build.sh roothide`。

## 功能一览

| 区块 | 行为 |
|------|------|
| 入口 | 在「严选二手」Tab 顶部注入导航栏「批量查找」按钮 |
| 筛选 | 机器型号、内存、电池健康度（支持 `>=90`）、系统版本、颜色 5 维组合 |
| 进度 | 自定义 HUD：开始时 show，进行中实时刷新「第 N/N 页 · 已采集 X 条」，结束 dismiss |
| 入库 | 每次采集写入本地 SQLite（Documents/ahbatchfind.sqlite） |
| 复制 | 单条复制（多行可读） / 全部复制（Tab 分隔，粘贴即可进 Excel） |
| 导出 | TXT 文本 / Excel 兼容 CSV（含 UTF-8 BOM，直接 Excel/WPS 打开） |
| 清空 | 「操作」区可一键清空库 |

## 运行环境

- 设备：iPhone 15 Pro Max 17.3.1（任意 iOS 15+ 设备均可）
- 越狱：RELAXIN（roothide）/ Dopamine（rootless）/ 老式 rootful

## 安装（从 GitHub Release / Actions Artifact）

1. 打开仓库 Releases 页面（打 tag 后会生成）或 Actions 页面找到最近一次 `Build` 工作流
2. 下载 `AihuishouBatchFind-rootless-deb.zip` 或 `AihuishouBatchFind-roothide-deb.zip`
3. 解压得到 `.deb`，用 Sileo / Filza / ssh 安装：
   ```bash
   dpkg -i com.example.aihuishou.batchfind_1.0.0_iphoneos-arm64.deb
   sileo install com.example.aihuishou.batchfind_1.0.0_iphoneos-arm64.deb
   ```
4. respring / 重启爱回收 App

## 本地编译

```bash
git clone https://github.com/qq1643240/AihuishouBatchFind.git
cd AihuishouBatchFind

# 安装 Theos
git clone --depth=1 https://github.com/theos/theos.git ~/theos
export THEOS=~/theos
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
ln -sf "$SDK_PATH" "$THEOS/sdks/iPhoneOS.sdk"

# 编译两个版本
chmod +x scripts/build.sh
./scripts/build.sh rootless     # Dopamine / 越狱 rootless
./scripts/build.sh roothide     # RELAXIN / roothide
```

产物：`packages/com.example.aihuishou.batchfind_1.0.0_iphoneos-arm64.deb`

## 项目结构

```
AihuishouBatchFind/
├── .github/workflows/
│   ├── build.yml                # push 自动构建 rootless + roothide
│   └── release.yml              # tag 自动发 Release
├── .gitignore
├── Makefile                     # Theos 构建（variant 由 THEOS_PACKAGE_SCHEME 控制）
├── control.rootless             # 包元数据（rootless / rootful）
├── control.roothide             # 包元数据（roothide，含 Package-Type）
├── AihuishouBatchFind.plist     # Substrate filter，限定 bundle id
├── Tweak.xm                     # Logos 主钩子：UIViewController 注入
├── AHBatchFindController.h/m    # 主筛选 / 结果 / 操作界面
├── AHBatchFindProxy.h/m         # 注入按钮的代理 target
├── AHRecordStore.h/m            # SQLite 记录仓库（系统 sqlite3，无依赖）
├── AHExporter.h/m               # TXT / Excel(CSV) / 剪贴板
├── AHProgressHUD.h/m            # 独立 UIWindow 浮层 HUD
├── AHAppProbe.h/m               # bundle id 探测
└── scripts/
    └── build.sh                 # 一键编译脚本（按 variant 切 control + 设 scheme）
```

## ⚠️ 重要：你必须替换的地方

`AHBatchFindController.m` 里的 `_runBatchSearchWithModel:...` **是占位实现**，演示完整流程（HUD 实时刷新、入库）。**投产前**请替换为真实实现：

1. **抓包真实接口**：Charles / mitmproxy 拦截爱回收 App，记录搜索 H5 的 HTTPS 接口；用 `NSURLSession` 调该 URL，把返回的 JSON 转 `AHRecord` 然后 `insertRecord:`。
2. **Hook 现有搜索控制器**：class-dump 出 `YanxuanSearchViewController` 等真实类名，往它的属性赋筛选条件，触发它的内部方法，再监听返回数据。
3. **WebView scheme**：爱回收部分流程走 H5，可以拦截 `WKWebView` 的 `decidePolicyForNavigationAction:` 在 URL 上注入参数。

无论哪种方式：
- 每页请求结束后调用一次 `[AHProgressHUD updateTitle:progress:]` —— UI 上就能看到「第 N/M 页 · 已采集 K 条」实时滚动。
- 每条命中记录 `[AHRecordStore insertRecord:]` 入库；UI 列表会自动刷新。
- 总进度 = `page / totalPages`。

## Bundle id 配置

爱回收 App 的 bundle id 历史上是 `com.aihuishou` 等。三种配置方式：

- 修改 `AihuishouBatchFind.plist` 里的 `Bundles` 数组（Substrate 层 filter）
- 修改 `AHAppProbe.m` 的 `isInsideAihuishou`（应用内运行时探测）

任选其一即可，建议同时改两边保持一致。

## 发新版本

```bash
# 修改完代码后
git add -A
git commit -m "release: v1.0.1"
git tag v1.0.1
git push origin main --tags
# → GitHub Actions 自动构建并把两份 deb 挂到 Release 页面
```

## 已知限制 / 扩展点

| 项目 | 说明 |
|------|------|
| 数据库位置 | Documents/ahbatchfind.sqlite，会被 iCloud 备份。需要持久化请改 App Group 或 `/var/mobile/...` |
| 真正的 .xlsx | 当前导出的是 CSV（含 UTF-8 BOM），Excel/WPS 可直接打开。如需保留公式/多 Sheet / 样式，请加入 ZipArchive 库并重写 `AHExporter` |
| 多选复制 | 通过点选记录切换 ✔️ / 无，再去「复制全部」 |
| 后台任务 | 当前是同步式 sleep 模拟；若改真实接口建议用 NSURLSession 并 `pause/resume` |

## 常见问题

1. **CI 报 "missing iOS SDK"** —— 已用 macos-14 runner 自带 Xcode 15；如失败可把 `macos-14` 改成 `macos-latest` 重试。
2. **本机 `make` 报 "缺少 iOS SDK"** —— macOS + Xcode 命令行工具装好，且 `xcrun --sdk iphoneos --show-sdk-path` 有输出；然后照上面步骤软链到 `$THEOS/sdks/iPhoneOS.sdk`。
3. **安装后爱回收 App 没看到按钮** —— 反复查看 `Tweak.xm` 里 `isTarget` 关键字，给 class-dump 出的真实类名加分支。
4. **HUD 出不来** —— 应用直接 kill 一次再开；HUD 用了独立 `UIWindowLevelAlert+1`，不应受任何容器影响。