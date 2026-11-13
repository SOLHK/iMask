# iMask

iMask 在 iPhone 的系统灵动岛上请求一个纯黑、无可见文字和图标的实时活动。用途是在系统允许的范围内，让新款 iPhone 的黑色区域接近旧款灵动岛的视觉效果。首页的预览是示意图，实际效果可以在开启后返回桌面查看。

## 实际效果

| 项目 | iOS 的行为 |
| --- | --- |
| 外观 | Widget Extension 为紧凑左右两侧、最小化和展开状态提供不透明黑色内容。iOS 绘制黑色底及外轮廓。`keylineTint(.black)` 请求黑色边线，系统仍可能在特定背景和模式下绘制边线或指示。 |
| 尺寸 | 公开 API 允许调整活动内容和内容边距。首页提供较窄、标准、加宽三档，调整左右黑色内容区。系统根据机型、其他活动和显示环境决定外部宽高及圆角。 |
| 桌面和其他 App | 活动由 iOS 托管，退回桌面、切换 App 或重新打开 iMask 后仍可存续。系统可以缩窄、最小化、隐藏或暂时替换活动。iPhone 18 Pro 系列可同时显示多项活动，iMask 没有固定位置或优先权。 |
| 时长 | 每次最长 8 小时，系统或用户可以提前结束。到达上限后活动立即离开灵动岛。系统可能在锁屏保留卡片最多 4 小时。iMask 内手动关闭使用立即移除。 |
| 锁屏和解锁 | 1.3 版使用完全空的 `EmptyView` 锁屏布局，交由真机验证。1.2 的透明布局在 iOS 27.3 beta 1 上仍有系统透明框。公开 API 没有单独关闭锁屏容器的开关，1.3 能否消除容器尚未验证。解锁返回 iMask 时会重新读取活动状态。 |
| 触摸和系统功能 | iOS 保留活动的原生手势。轻点可打开 iMask，长按可展开。iMask 不拦截屏幕触摸，不获取 Face ID 或通知权限。 |
| 后台与耗电 | 内容是静态视图，宿主没有定时更新、推送、后台音频、后台定位或网络保活。活动结束后由用户手动开启下一次。 |

Apple 资料：[ActivityKit 生命周期与布局](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) · [自定义颜色与边线](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities) · [WidgetKit DynamicIsland](https://developer.apple.com/documentation/widgetkit/dynamicisland) · [iPhone 18 Pro 系统灵动岛](https://www.apple.com/newsroom/2026/09/apple-debuts-iphone-18-pro-and-iphone-18-pro-max/) · [Live Activities 设计指南](https://developer.apple.com/design/human-interface-guidelines/live-activities)

项目最低部署版本为 iOS 17.0。灵动岛效果需要配备灵动岛的 iPhone。ActivityKit 的「运行中」表示实时活动仍有效，iOS 没有提供查询当前灵动岛可见像素或尺寸的 API。活动结束或被移除后，首页会显示「活动已结束」。ActivityKit 没有提供可区分系统超时和用户移除的结束原因。

纯黑内容使用公开 API。iPhone 18 系列实机的像素尺寸、边线、和 iPhone 17 默认轮廓的接近程度需要真机测量。Apple 的设计指南以可扫视的实时信息为目标，个人开发签名安装和 App Store 审核是不同流程，本项目未提交 App Store 审核。 [Apple 实时活动设计指南](https://developer.apple.com/design/human-interface-guidelines/live-activities)

## 构建与安装

### 使用 Xcode 和开发者证书

1. 在 Mac 上打开 `iMask.xcodeproj`。推荐用与设备系统相匹配的 Xcode，例如对 iOS 27 设备使用 Xcode 27。
2. 在项目级 Build Settings 中，将 `IMASK_BUNDLE_IDENTIFIER` 改为你的开发团队可用的唯一 ID，例如 `com.yourname.imask`。扩展自动使用该 ID 加 `.widget`。仓库默认值为 `com.imaskapp.iMask`。
3. 为 `iMask` 和 `iMaskWidget` 两个目标启用自动签名并选择同一个 Team。选择连接的 iPhone，运行 `iMask` scheme。按系统提示启用开发者模式。
4. 需要导出 IPA 时，在 Xcode 选择 `Any iOS Device`，执行 **Product → Archive**，再在 Organizer 选择 **Distribute App → Debugging**。设备需要符合所用描述文件的安装要求。仓库也附有命令行的调试导出配置。

[Apple 注册设备分发](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices) · [启用开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

使用已配置 Apple 开发账号的 Xcode，也可以在终端归档并导出。请替换下面的 Team ID 和 Bundle ID。

```sh
xcodebuild archive -project iMask.xcodeproj -scheme iMask -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/iMask.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YOURTEAMID \
  IMASK_BUNDLE_IDENTIFIER=com.yourname.imask
xcodebuild -exportArchive -archivePath build/iMask.xcarchive \
  -exportOptionsPlist Config/ExportOptions-Debugging.plist \
  -exportPath build/signed -allowProvisioningUpdates
```

### 使用 GitHub Actions 的未签名 IPA

在仓库 **Actions** 中打开通过的构建，下载含有 `iMask-unsigned.ipa` 和 SHA-256 校验文件的 Artifact。该 IPA 由 `iphoneos` 的 Release 构建打包，包含主程序与 `PlugIns/iMaskWidget.appex`。它需要用有效的签名和描述文件重新签名才能在真机安装。

使用 ESign 等签名工具时，选择能**保留并签署嵌入式 Widget Extension** 的签名方式。主 App 和 `.widget` 扩展须使用同一签名团队，Bundle ID 要与各自适用的描述文件匹配。如果需要更换 Bundle ID，扩展 ID 也要随之改为主 App ID 加 `.widget`。若工具只能签主程序或会移除扩展，请使用 Xcode 流程。仓库没有内置证书，也未验证特定 ESign 版本的操作界面或真机安装结果。

本地构建相同的未签名包：

```sh
bash scripts/build-unsigned-ipa.sh
```

产物默认位于 `build/artifacts/`。脚本使用 Xcode 的 iPhoneOS SDK，需要 macOS。

Artifact 解压后可在 Mac 上执行 `shasum -a 256 -c iMask-unsigned.ipa.sha256` 验证 IPA。

## 使用和验证

1.3 是空锁屏布局验证版。它将锁屏闭包中的透明视图替换为 `EmptyView()`，去掉该内容视图的尺寸和无障碍标签，并使用 `activityBackgroundTint(.clear)`。验收目标为通知中心完全没有 iMask 条目、边框和占位。当前仅完成编译打包，这个目标尚待用户真机确认。Apple 的公开 API 要求提供锁屏布局，由系统选择展示位置，代码无法保证系统会完全移除容器。用户在锁屏移除整项实时活动时，系统也可能结束灵动岛会话。

1.1 版将默认左右内容宽度从 9 pt 增至 15 pt。较窄、标准、加宽分别使用每侧 9、15、21 pt，内容高度为 16 pt。实际胶囊尺寸还包括系统中间区域及边距。切换档位会更新当前实时活动，开始时间和 8 小时上限继续沿用。iOS 在多活动、横屏等情况下可能限制可用宽度。

首页打开 **诊断与日志**，点击 **检查当前状态** 可以读取 ActivityKit 会话及授权状态。点击 **导出诊断日志** 后，通过系统分享菜单发送 `iMask-diagnostics.txt`，也可存入“文件”。报告包含 App/Widget 版本、设备型号、系统版本、屏幕点数与像素数、显示比例、安全区域、宽度参数、现有会话、最近启动和终止事件、失败的系统错误代码。所有日志保存在本机，最多保留 256 条，重启后可读。导出文件使用 UTF-8 文本。

诊断中的 `actualIslandGeometry=unavailable` 和 `actualIslandVisibility=unavailable` 表示系统没有开放相应查询 API。日志能确认会话及宽度请求，真机当前的外观需要配合包含状态栏的截图或另一台设备拍照判断。

当前反馈机型为 iPhone 18 Pro Max、iOS 27.3 beta 1。CI 优先使用 iPhone 18 Pro Max；现有 GitHub Xcode 27 镜像提供到 iOS 27.2，27.3 beta 1 的外观和签名安装需要真机复核。请在出现偏短、被挤压或活动消失后，回到 App 导出日志，便于核对当时的系统版本与会话记录。

1. 在 iMask 点「开启黑色模式」，确认首页显示「运行中」，再返回桌面并打开另一个 App。
2. 查看灵动岛有无文字、图标和边线。分别在浅色背景、深色背景及锁屏后解锁的场景对比。启动另一项实时活动，观察 iOS 如何摆放两项活动。
3. 重新打开 iMask，确认状态与现有活动一致。长按活动观察展开外观。在 App 内点「关闭黑色模式」，确认活动和锁屏卡片移除。
4. 再开启一次，从锁屏移除活动或等待系统超时。回到 iMask，确认首页提示活动已结束。要比较 iPhone 17 和 iPhone 18 的默认轮廓，请在相同显示缩放和方向下对照真机。

自动化 UI 测试通过按钮开启真实 ActivityKit 会话，在桌面与系统设置页检测黑色像素，并在同一会话中比较三档宽度。随后验证重启恢复、关闭、诊断导出与分享界面。数据测试覆盖旧版空状态解码、日志容量限制、重启加载及保存失败。模拟器的合成结果不等同于真机的物理开孔和显示效果。

按当前开发约定，日常 `main` 更新只编译打包，安装包由用户真机测试。只有用户明确要求推送到 `test` 分支时才执行该推送，`test` 的 push 会触发自动化测试。`workflow_dispatch` 和 pull request 默认仅构建。
