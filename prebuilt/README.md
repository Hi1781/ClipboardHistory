# 预编译裸 IPA（未签名）

- 文件：ClipboardHistory-2.1.0-raw-unsigned.ipa
- 大小： 472K
- SHA-256：`e773a9d4ad93dffc837136e40714585d052c2e528f4f85dbffcbf07ff8bb0736`
- 架构：arm64（iPhone / iPad，最低 iOS 16）
- 状态：**未签名、无 embedded.mobileprovision、无 _CodeSignature**，为 raw 裸包。

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
