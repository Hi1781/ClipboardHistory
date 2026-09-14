# 预编译裸 IPA（未签名）

- 文件：ClipboardHistory-2.4.0-raw-unsigned.ipa
- 大小： 547K
- SHA-256：`4b1f72adb4dd890fae53c2e9e87ca04c5a712d2ca64a39322f188861bb2f8d02`
- 架构：arm64（iPhone / iPad，最低 iOS 16）
- 状态：**未签名、无 embedded.mobileprovision、无 _CodeSignature**，为 raw 裸包；
  但 4 个可执行文件已用 ldid 把 App Group entitlements 嵌入 ad-hoc 签名，
  SideStore/AltStore 重签后会保留，主 App 与键盘扩展共享同一数据容器。
- 若安装器报 `Could not find EOCD`，说明下载不完整，请重新下载并核对上面的 SHA-256。

## 安装方式（SideStore / AltStore 设备端自签）
1. 把本 ipa 通过「文件」或 SideStore 的「安装 IPA」导入手机；
2. SideStore 在设备本地用你的 Apple ID 完成签名并安装（无需越狱）；
3. 首次运行前到「设置 - 通用 - VPN与设备管理」信任开发者证书；
4. 键盘扩展：设置 - 通用 - 键盘 - 添加「剪贴板」，并开启「允许完全访问」
   （读写共享容器中的历史记录所必需）。

## 为什么不直接签名
本仓库与该产物刻意不内置任何签名/描述文件；签名证书与设备绑定，
交由 SideStore/AltStore 在你的设备上本地完成，可随时用自己的 Apple ID 重签。

## 自行从源码构建（Ubuntu）
见仓库根目录 `build_linux.sh`：Linux 上用 Swift 5.8 + iPhoneOS16.4 SDK
交叉编译 arm64 Mach-O，手动搭建 Payload 后 zip 出同样的裸包。
