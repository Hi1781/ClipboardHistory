#!/bin/bash
# ============================================================
# ClipboardHistory - 一键构建 IPA 脚本
# 适用环境：macOS + Xcode 15+ + XcodeGen
# 用法：./build.sh [development|release]
# ============================================================
set -e

SCHEME="ClipboardHistory"
CONFIGURATION="${1:-Release}"
EXPORT_DIR="build/export"
ARCHIVE_PATH="build/ClipboardHistory.xcarchive"
IPA_NAME="ClipboardHistory.ipa"

echo "========================================"
echo "  ClipboardHistory IPA 构建脚本"
echo "  配置: ${CONFIGURATION}"
echo "========================================"

# ---- 1. 检查环境 ----
echo ""
echo "[1/5] 检查构建环境..."

if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 未找到 xcodebuild，请安装 Xcode"
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -1)
echo "  Xcode: ${XCODE_VERSION}"

# 检查 XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "  未找到 XcodeGen，尝试安装..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "❌ 未找到 Homebrew，请先安装: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
fi
echo "  XcodeGen: $(xcodegen --version)"

# ---- 2. 生成 Xcode 项目 ----
echo ""
echo "[2/5] 生成 Xcode 项目..."
xcodegen generate
echo "  ✓ 已生成 ClipboardHistory.xcodeproj"

# ---- 3. 清理旧构建 ----
echo ""
echo "[3/5] 清理旧构建产物..."
rm -rf build
echo "  ✓ 已清理"

# ---- 4. Archive ----
echo ""
echo "[4/5] 编译 Archive (这可能需要几分钟)..."
xcodebuild archive \
    -project "${SCHEME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | tee build/archive.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "❌ Archive 失败，请查看 build/archive.log"
    exit 1
fi
echo "  ✓ Archive 成功"

# ---- 5. 导出 IPA ----
echo ""
echo "[5/5] 导出 IPA..."

# 生成导出选项 plist（开发证书自动签名）
cat > build/exportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

mkdir -p "${EXPORT_DIR}"

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist build/exportOptions.plist \
    -allowProvisioningUpdates \
    2>&1 | tee build/export.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "❌ IPA 导出失败，请查看 build/export.log"
    echo ""
    echo "提示：如果是签名问题，请在 Xcode 中打开项目，设置你的 Apple ID 团队："
    echo "  open ${SCHEME}.xcodeproj"
    echo "  然后在 Signing & Capabilities 中选择你的团队"
    exit 1
fi

# 重命名 IPA
if [ -f "${EXPORT_DIR}/${SCHEME}.ipa" ]; then
    mv "${EXPORT_DIR}/${SCHEME}.ipa" "${EXPORT_DIR}/${IPA_NAME}"
fi

echo ""
echo "========================================"
echo "  ✅ 构建成功！"
echo "  IPA 路径: $(pwd)/${EXPORT_DIR}/${IPA_NAME}"
echo "  Archive:  $(pwd)/${ARCHIVE_PATH}"
echo "========================================"
echo ""
echo "安装方式："
echo "  1. 使用 AltStore/SideStore 侧载"
echo "  2. 或使用 Xcode: Window → Devices and Simulators → 选择设备 → + 添加 IPA"
echo "  3. 或使用命令: xcrun devicectl device install app --device <UDID> ${EXPORT_DIR}/${IPA_NAME}"
echo ""
