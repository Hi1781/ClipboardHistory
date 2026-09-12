#!/bin/bash
# ============================================================================
# ClipboardHistory —— Ubuntu/Linux 交叉编译，产出「未签名裸 raw.ipa」
# ----------------------------------------------------------------------------
# 流程：
#   swiftc/clang (host=linux, target=arm64-apple-ios16.0)
#     -> arm64 Mach-O 未签名二进制
#     -> 手动搭建 Payload/ClipboardHistory.app（Frameworks / PlugIns）
#     -> 放入二进制 + Info.plist + PkgInfo（不写 mobileprovision、不调用任何签名工具）
#     -> zip -r 得到 raw.ipa
#   设备端由 SideStore / AltStore 在本地完成全部签名与安装。
#
# 依赖：
#   1. Swift for Linux（含 clang、ld64.lld），建议 5.8.x（与 SDK 构建版本一致）
#        https://www.swift.org/download/
#   2. iPhoneOS SDK（从 Xcode 抽取，或 https://github.com/xybp888/iOS-SDKs）
#
# 用法：
#   SWIFT_TOOLCHAIN=/path/to/swift/usr IOS_SDK=/path/to/iPhoneOS.sdk ./build_linux.sh
# ============================================================================
set -euo pipefail

# ---------- 0. 参数 ----------
APP_NAME="ClipboardHistory"
DEPLOY="16.0"
TARGET="arm64-apple-ios${DEPLOY}"
BUILD_DIR="build-linux"
PAYLOAD="${BUILD_DIR}/Payload/${APP_NAME}.app"
OUT_IPA="build-linux/ClipboardHistory-raw-unsigned.ipa"

SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-${SWIFT_ROOT:-}}"
IOS_SDK="${IOS_SDK:-${SDK:-}}"

# 自动探测常见位置
if [[ -z "${SWIFT_TOOLCHAIN}" ]]; then
  for c in /tmp/swift-*/usr /usr/share/swift/usr /opt/swift/usr; do
    [[ -x "$c/bin/swiftc" ]] && SWIFT_TOOLCHAIN="$c" && break
  done
fi
if [[ -z "${IOS_SDK}" ]]; then
  for s in /tmp/ios-sdks/iPhoneOS*.sdk /opt/iPhoneOS*.sdk; do
    [[ -d "$s" ]] && IOS_SDK="$s" && break
  done
fi

SWIFTC="${SWIFT_TOOLCHAIN}/bin/swiftc"
CLANG="${SWIFT_TOOLCHAIN}/bin/clang"
LD64="${SWIFT_TOOLCHAIN}/bin/ld64.lld"

echo "================================================"
echo " ClipboardHistory Linux 交叉编译 (未签名裸 IPA)"
echo "  toolchain : ${SWIFT_TOOLCHAIN:-未找到}"
echo "  sdk       : ${IOS_SDK:-未找到}"
echo "  target    : ${TARGET}"
echo "================================================"

[[ -x "${SWIFTC}" ]] || { echo "❌ 未找到 swiftc，请设置 SWIFT_TOOLCHAIN"; exit 1; }
[[ -d "${IOS_SDK}" ]]  || { echo "❌ 未找到 iPhoneOS SDK，请设置 IOS_SDK"; exit 1; }

# 自定义 resource-dir（规避 Linux 平台模块与 iOS SDK 冲突）
RES_DIR="${BUILD_DIR}/resource-dir"
rm -rf "${BUILD_DIR}"; mkdir -p "${BUILD_DIR}/obj" "${PAYLOAD}/Frameworks" "${PAYLOAD}/PlugIns"
rm -rf "${RES_DIR}"; cp -r "${SWIFT_TOOLCHAIN}/lib/swift" "${RES_DIR}"
# 删除与 iOS SDK 冲突的 Linux 原生模块
rm -rf "${RES_DIR}/dispatch" "${RES_DIR}/os" "${RES_DIR}/CoreFoundation" \
       "${RES_DIR}/Block" "${RES_DIR}/linux" 2>/dev/null || true
# clang 内置头
CLANG_VER="$(ls "${SWIFT_TOOLCHAIN}/lib/clang" 2>/dev/null | head -1)"
[[ -n "${CLANG_VER}" && -d "${SWIFT_TOOLCHAIN}/lib/clang/${CLANG_VER}" ]] && \
  rm -rf "${RES_DIR}/clang" && cp -r "${SWIFT_TOOLCHAIN}/lib/clang/${CLANG_VER}" "${RES_DIR}/clang" || true

COMMON_FLAGS=(
  -target "${TARGET}"
  -sdk "${IOS_SDK}"
  -resource-dir "${RES_DIR}"
  -O
  -parse-as-library
)

# ============================================================================
# 1. 编译 ClipKit.framework
# ============================================================================
echo "[1/5] 编译 ClipKit.framework ..."
mapfile -t CLIPKIT_SRC < <(find ClipKit -name "*.swift" | sort)
mkdir -p "${PAYLOAD}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule"

"${SWIFTC}" "${COMMON_FLAGS[@]}" \
  -module-name ClipKit \
  -emit-module \
  -emit-library \
  -emit-module-path "${PAYLOAD}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule/arm64-apple-ios.swiftmodule" \
  -o "${PAYLOAD}/Frameworks/ClipKit.framework/ClipKit" \
  -Xlinker -install_name -Xlinker @rpath/ClipKit.framework/ClipKit \
  "${CLIPKIT_SRC[@]}" || {
    echo "⚠️  ClipKit 编译失败。已知问题：Linux swiftc 与抽取版 iOS SDK 的 Dispatch overlay"
    echo "    可能存在模块桥接差异。请使用与 SDK 同版本的 Swift，或改用 GitHub Actions(macOS) 构建。"
    exit 2
  }
cp ClipKit/Info.plist "${PAYLOAD}/Frameworks/ClipKit.framework/Info.plist"

# ============================================================================
# 2. 编译主 App
# ============================================================================
echo "[2/5] 编译主 App ..."
mapfile -t APP_SRC < <(find ClipboardHistory -name "*.swift" | sort)
"${SWIFTC}" "${COMMON_FLAGS[@]}" \
  -module-name ClipboardHistory \
  -F "${PAYLOAD}/Frameworks" \
  -I "${PAYLOAD}/Frameworks/ClipKit.framework/Modules" \
  -emit-executable \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -o "${PAYLOAD}/${APP_NAME}" \
  "${APP_SRC[@]}"

# ============================================================================
# 3. 编译键盘扩展
# ============================================================================
echo "[3/5] 编译键盘扩展 ..."
KB_DIR="${PAYLOAD}/PlugIns/ClipboardKeyboard.appex"
mkdir -p "${KB_DIR}"
"${SWIFTC}" "${COMMON_FLAGS[@]}" \
  -module-name ClipboardKeyboard \
  -F "${PAYLOAD}/Frameworks" \
  -I "${PAYLOAD}/Frameworks/ClipKit.framework/Modules" \
  -emit-library \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -Xlinker -rpath -Xlinker @executable_path/../../Frameworks \
  -o "${KB_DIR}/ClipboardKeyboard" \
  ClipboardKeyboard/*.swift
cp ClipboardKeyboard/Resources/Info.plist "${KB_DIR}/Info.plist"

# ============================================================================
# 4. 编译 Widget 扩展
# ============================================================================
echo "[4/5] 编译 Widget 扩展 ..."
WG_DIR="${PAYLOAD}/PlugIns/ClipboardWidget.appex"
mkdir -p "${WG_DIR}"
"${SWIFTC}" "${COMMON_FLAGS[@]}" \
  -module-name ClipboardWidget \
  -emit-library \
  -o "${WG_DIR}/ClipboardWidget" \
  ClipboardWidget/*.swift
cp ClipboardWidget/Info.plist "${WG_DIR}/Info.plist"

# ============================================================================
# 5. 组装 Bundle 资源 + 打包
# ============================================================================
echo "[5/5] 组装 Payload 并压缩 ..."
# 主 Info.plist（替换构建变量）
sed -e 's/\$(EXECUTABLE_NAME)/ClipboardHistory/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.clipboard.history/g' \
    -e 's/\$(PRODUCT_NAME)/ClipboardHistory/g' \
    -e 's/\$(MARKETING_VERSION)/2.0.0/g' \
    -e 's/\$(CURRENT_PROJECT_VERSION)/2/g' \
    -e 's/\$(PRODUCT_MODULE_NAME)/ClipboardHistory/g' \
    ClipboardHistory/Resources/Info.plist > "${PAYLOAD}/Info.plist"

# PkgInfo
printf 'APPL????' > "${PAYLOAD}/PkgInfo"

# 资源（Assets 编译后的 car 在无 actool 时以目录形式保留，SideStore 不强制）
mkdir -p "${PAYLOAD}/Assets.car.placeholder"

# 扩展 Info.plist 变量替换
sed -e 's/\$(EXECUTABLE_NAME)/ClipboardKeyboard/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.clipboard.history.keyboard/g' \
    -e 's/\$(PRODUCT_NAME)/ClipboardKeyboard/g' \
    -e 's/\$(MARKETING_VERSION)/2.0.0/g' \
    -e 's/\$(CURRENT_PROJECT_VERSION)/2/g' \
    -e 's/\$(PRODUCT_MODULE_NAME)/ClipboardKeyboard/g' \
    ClipboardKeyboard/Resources/Info.plist > "${KB_DIR}/Info.plist"
printf 'XPC!????' > "${KB_DIR}/PkgInfo"

sed -e 's/\$(EXECUTABLE_NAME)/ClipboardWidget/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.clipboard.history.widget/g' \
    -e 's/\$(PRODUCT_NAME)/ClipboardWidget/g' \
    -e 's/\$(MARKETING_VERSION)/2.0.0/g' \
    -e 's/\$(CURRENT_PROJECT_VERSION)/2/g' \
    ClipboardWidget/Info.plist > "${WG_DIR}/Info.plist"
printf 'XPC!????' > "${WG_DIR}/PkgInfo"

# 校验 Mach-O
echo "--------------------------------"
for bin in "${PAYLOAD}/${APP_NAME}" "${PAYLOAD}/Frameworks/ClipKit.framework/ClipKit" \
           "${KB_DIR}/ClipboardKeyboard" "${WG_DIR}/ClipboardWidget"; do
  if [[ -f "$bin" ]]; then
    file "$bin" | sed 's/^/  /'
  fi
done
echo "--------------------------------"

# zip 打包（裸 IPA，不签名）
cd "${BUILD_DIR}"
rm -f "$(basename "${OUT_IPA}")"
zip -qr -X "$(basename "${OUT_IPA}")" Payload
cd - >/dev/null

echo ""
echo "✅ 未签名裸 IPA 已生成：${OUT_IPA}"
echo "   传到 iPhone 后由 SideStore/AltStore 在设备端签名安装。"
