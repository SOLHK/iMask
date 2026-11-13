# iMask

iMask 2.3 在重新设计的 SwiftUI 界面中集成 GlobalRefresh-PiP 高刷运行核心，并恢复标准长度的纯黑灵动岛。首页可选择悬浮窗或灵动岛模式。灵动岛模式会同时使用最小化 PiP 作为高刷驱动。最低支持 iOS 17。

## 功能

- 高刷核心直接使用 Yoroin/GlobalRefresh-PiP 提交 `1b62341c1d62308962fb3656192d6783631aa00c` 的原控制器。
- 保留 VideoCall 默认方案与 PlayerLayer 兼容方案，以及原有生成视频、播放循环、超时处理、音频中断恢复和后台状态管理。
- 保留三种保活策略：仅 PiP（默认）、锁屏音频增强、音频强保活。音频策略使用上游自带的 `slience.mp3`，具体行为在设置页显示，需用户自行选择。
- 保留一键开启并隐藏、窗口高度调整及记忆、文字滚动、时钟内容、关闭确认、被挤出通知、极限静默和快捷指令功能。
- 保留原项目的 VideoCall 隐藏与画中画共存适配代码及运行时方法签名检查。
- 黑色灵动岛使用 ActivityKit + WidgetKit，固定为 1.1–1.3 的“标准”尺寸参数，compact 左右内容各 15 pt、高 16 pt；不提供长度档位。
- 导出同一份 `iMask-diagnostics.txt`，包含高刷底层、保活、音频、窗口、ActivityKit 状态和原项目运行日志。

## 使用

1. 开启高刷，或使用“一键开启并隐藏悬浮窗”。
2. 在“运行方案与保活”里选择底层和保活模式、调整窗口与内容选项。切换底层时沿用原项目的停止与重建流程。
3. 首页选择“灵动岛”，固定使用标准长度。运行中切换模式会协调停止与重新启动。灵动岛模式先启动 VideoCall / 仅 PiP / 0.1 pt 驱动，再开启标准长度实时活动；选择悬浮窗时恢复之前的底层、保活、内容与高度选项。返回桌面查看系统灵动岛。驱动失败时会明确提示，并允许单独保留黑色实时活动。
4. 快捷指令开关开启后，可使用 iMask 的原生“打开并一键 0.1pt”动作，也支持 `imask://startandhide`。
5. 出现问题时，在诊断页开启日志、复现问题，再关闭日志并导出。默认关闭。每次开启开始新一轮刷新和电量统计，关闭后停止采样、计时、写盘，保留本轮结果。

## 实际行为与来源

高刷运行机制、后台策略与内置隐藏/共存适配来自原项目，首页及设置入口由 iMask 实现。`Vendor/GlobalRefresh` 中保留上游源码；`ViewController.swift` 增加 iMask 界面桥接、模式协调和可关闭的诊断采样。未创建上游的首页、设置、版本或教程页面。依赖的 SnapKit 以源码编入，保留 MIT 许可证，无付费 SDK。

原项目的隐藏/共存包含系统内部适配，例如 `_proxyControlsStyle` 和 PiP 内容类型切换，并非 Apple 公开保证的能力。相关检查与失败处理保留在 `PiPCoexistenceExperiment.swift`。普通 IPA 无法保证所有 App 和系统版本全局固定 120Hz，实际高刷、共存、熄屏与保活效果需真机确认。“本页帧率”只表示本 App 的前台回调采样。

黑色灵动岛仍是系统实时活动，系统可以显示其锁屏/通知容器；空内容不等于移除系统卡片。每次活动最长 8 小时，系统可能提前结束或改变显示，App 会在收到事件或返回前台时刷新状态。模式切换会结束上一模式的会话，诊断记录停止确认与切换完成。系统活动为 active 并不证明当前屏幕一定显示了灵动岛。

来源：[CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP)、[Yoroin/GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP)。署名及 SnapKit 许可证随 App 打包。

## 构建与签名

在 Xcode 27 中打开 `iMask.xcodeproj`，选择 `iMask` scheme。原项目使用 iOS 27 MetricKit 接口，因此编译需要 Xcode 27 SDK，部署最低版本仍为 iOS 17。项目级 `IMASK_BUNDLE_IDENTIFIER` 可改为你的团队 ID，主 App 和 iMaskWidget 都需要设置同一 Team。

```sh
bash scripts/build-unsigned-ipa.sh
```

输出 `build/artifacts/iMask-unsigned.ipa` 和 SHA-256 文件。此 IPA 未签名，需要 ESign 等工具使用有效证书及匹配描述文件重新签名。必须同时签主 App 和 `PlugIns/iMaskWidget.appex`，不能删除扩展。Widget ID 为主 App ID 加 `.widget`。

签名导出可使用 `Config/ExportOptions-Debugging.plist`：

```sh
xcodebuild archive -project iMask.xcodeproj -scheme iMask -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/iMask.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YOURTEAMID \
  IMASK_BUNDLE_IDENTIFIER=com.yourname.imask
xcodebuild -exportArchive -archivePath build/iMask.xcarchive \
  -exportOptionsPlist Config/ExportOptions-Debugging.plist \
  -exportPath build/signed -allowProvisioningUpdates
```

## 构建约定

main 日常更新只编译打包。只有用户明确要求推送 test 后，test 的 push 才运行 UI/数据测试。本次只编译及校验安装包，真机效果交由用户确认；构建通过不代表已验证系统刷新率或后台存活。

## 2.3 预览交付状态

本次修改仅发布到 `preview/imask-2.3`，通过 GitHub Actions 手动编译预览 IPA，自动化测试不运行。用户真机确认前不更新 main 或 test。编译结果见对应 Actions 记录，构建通过不代表已通过真机验收。

## 刷新诊断与电量统计

- 使用现有的前台和 PiP CADisplayLink 回调采样，不额外创建用于测量的 DisplayLink。按来源区分前台、PiP 内容、滚动、时钟和 PlayerLayer 驱动。
- 导出请求帧率、平均回调频率、最短/最长间隔、较长回调间隔及暂停间隔、屏幕上限、低电量模式、温度、充电情况与运行时长。
- 只有开启日志时才监测电量。报告记录起止电量、未充电观察区间的掉电百分点及每小时估算；不足 5 分钟不外推每小时速率。整机电量受其他 App、屏幕与网络影响，不能视为 iMask 独占耗电。
- 日志关闭时停止统计定时器与电量通知订阅，不再积累诊断数据。高刷必需的渲染回调仍用于功能运行，不进行诊断采样。模式偏好与必要的运行状态仍正常保存。
- PiP 高刷驱动与 Live Activity 同时运行的外观仍需真机确认，系统可能不展示实时活动。软件无法保证全局固定 120Hz，也不能直接读取其他 App 或屏幕硬件的当前刷新率；不可获取的数据明确标为 unavailable。

参考：[Apple ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)、[UIDevice 电量读数](https://developer.apple.com/documentation/uikit/uidevice/batterylevel)。
