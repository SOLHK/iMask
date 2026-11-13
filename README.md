# iMask

iMask 2.0 是使用 SwiftUI 与 AVKit 的 iPhone 高刷新率辅助工具。首页重新设计为单页控制台，提供开启/停止、PiP 窗口模式、屏幕上限、本页帧率与诊断日志。最低支持 iOS 17。

## 运行方式

点击“开启高刷”会创建 VideoCall 画中画并启动内容更新。实际运行状态由 AVKit 的启动、停止和失败回调确认。选择“最小化”时请求 300 × 0.1 pt 的内容尺寸，选择“显示”时请求 300 × 44 pt。停止会释放 PiP、更新驱动和帧率采样。

App 前台请求最高 120Hz，并从 CADisplayLink 的实际回调间隔计算“本页帧率”。PiP 内容按参考项目的 60fps 内容更新配置运行。屏幕上限从设备读取。其他 App 的屏幕刷新率无法由本 App 直接测量，诊断中记为 `globalDisplayRefreshRate=unavailable`。

此方案的跨 App 效果和 0.1 pt 最小化表现取决于系统，需在真机确认。Apple 的帧率接口向系统提交偏好，系统会结合硬件、电量、温度与前台 App 调度。因此，120Hz 是请求目标，无法保证所有 App 固定在该值。[Apple ProMotion 文档](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)

## 参考来源与参数

技术来源为 CaiWanFeng 的 PiP 示例与 Yoroin 的 GlobalRefresh-PiP。参考提交为 `1b62341c1d62308962fb3656192d6783631aa00c`，署名保存在 `NOTICE`，并随 App 打包，也可在诊断页访问项目链接。[CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP) · [Yoroin/GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP)

| 参数 | 数值或机制 |
| --- | --- |
| PiP 内容来源 | AVPictureInPictureVideoCallViewController / ContentSource |
| 内容宽度 | 300 pt |
| 最小化高度 | 0.1 pt |
| 可见高度 | 44 pt |
| PiP 内容更新 | 60fps CADisplayLink |
| 内容动画周期 | 2.4 秒 |
| App 前台刷新偏好 | 最高 120Hz，按屏幕上限截断 |

此版本采用公开 VideoCall 路径及上述参考参数，SwiftUI 界面和内容绘制单独实现。参考项目的完整方案还包含内部 PiP 控件与多 PiP 共存适配，相关系统依赖见其项目文档。后台模式使用 Xcode 的 Audio / AirPlay / Picture in Picture 能力对应配置，内容由 PiP 托管。

## 升级与日志

2.0 从 1.x 升级时会结束旧的 iMask 实时活动，防止旧通知卡片继续显示。保留旧 `MaskAttributes` 类型用于读取、结束历史会话，主 App 的 `NSSupportsLiveActivities` 配置用于该迁移。

诊断页可导出 `iMask-diagnostics.txt`，包含设备和系统版本、画中画状态、请求与实际内容尺寸、内容回调次数、前台帧率采样、启动错误及最近 256 条事件。日志保存在本机，导出由用户通过分享菜单完成。

## 构建与签名

在 Mac 的 Xcode 中打开 `iMask.xcodeproj`，选择 `iMask` scheme。将项目级 `IMASK_BUNDLE_IDENTIFIER` 改成你的团队可用 ID，在主 App 的 Signing & Capabilities 中选择 Team 并启用自动签名，即可运行或 Archive。

```sh
bash scripts/build-unsigned-ipa.sh
```

该命令输出 `build/artifacts/iMask-unsigned.ipa` 及 SHA-256 校验文件。2.0 只包含主 App，签名工具应对这个主 App 使用有效的证书和匹配的描述文件。GitHub Actions 的 IPA 明确为未签名，需用 ESign 或 Xcode 等工具签名后安装。

签名归档与导出示例，替换 Team ID 和 Bundle ID 后执行。

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

日常 `main` 更新只编译打包，安装包交由用户真机测试。只有用户明确要求推送到 `test` 才执行该推送，`test` 的 push 触发已维护的 UI/数据测试。`workflow_dispatch` 与 pull request 默认只构建。本次 2.0 交付只进行编译和打包校验，PiP 启动、隐藏、跨 App 高刷效果及新版 UI 均待真机验证。
