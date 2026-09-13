#!/bin/bash
# ============================================================================
# ClipboardHistory v2.0 —— Ubuntu/Linux 交叉编译，产出「未签名裸 raw.ipa」
# ----------------------------------------------------------------------------
# host=linux  target=arm64-apple-ios16.0
#   swiftc/clang 交叉编译 + ld64.lld 链接 -> arm64 Mach-O（不运行任何签名工具）
#   手动搭建 Payload/ClipboardHistory.app（Frameworks / PlugIns / 图标 / plist）
#   zip 得到 raw ipa；设备端由 SideStore / AltStore 本地完成签名安装。
#
# 已验证的关键修复（缺一不可）：
#   1) resource-dir 必须用【绝对路径】，并删除其中与 iOS SDK 冲突的 Linux 模块
#   2) 补 Dispatch.apinotes / os.apinotes（把 OS_dispatch_queue 映射为 DispatchQueue）
#   3) SDK 内 .swiftinterface 的编译器版本行需改写为与本工具链一致
#   4) SDK 内 dispatch/os module.modulemap 去掉 [extern_c]（让 ObjC 类可见）
#   5) 用名为 ld 的包装脚本转调 ld64.lld（GNU ld 不认 -dynamic）
#   6) 链接显式传 -platform_version ios 16.0.0 16.4
#   7) -Xcc -fmodules-cache-path=PATH 必须是单参数（= 形式）
#
# 用法：
#   SWIFT_TOOLCHAIN=/path/to/swift/usr IOS_SDK=/path/to/iPhoneOS.sdk ./build_linux.sh
# ============================================================================
set -euo pipefail

APP_NAME="ClipboardHistory"
DEPLOY="16.0"; SDK_VER="16.4"
TARGET="arm64-apple-ios${DEPLOY}"
MARK_VER="2.1.1"; CUR_VER="4"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${ROOT}/build-linux"
APP="${BUILD}/Payload/${APP_NAME}.app"
OUT_IPA="${BUILD}/ClipboardHistory-${MARK_VER}-raw-unsigned.ipa"

SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-}"
IOS_SDK="${IOS_SDK:-}"
# 默认探测持久工具链目录
for c in "$SWIFT_TOOLCHAIN" \
         "${ROOT}/../toolchain/swift-5.8-RELEASE-ubuntu22.04/usr" \
         /home/user/.doubao/agent_mode/workspace/toolchain/swift-5.8-RELEASE-ubuntu22.04/usr; do
    [[ -z "$c" ]] && continue
    if [[ -x "$c/bin/swiftc" ]]; then SWIFT_TOOLCHAIN="$c"; break; fi
done
for s in "$IOS_SDK" "${ROOT}/../toolchain/iPhoneOS16.4.sdk" \
         /home/user/.doubao/agent_mode/workspace/toolchain/iPhoneOS16.4.sdk; do
    [[ -z "$s" ]] && continue
    if [[ -d "$s/usr/include" ]]; then IOS_SDK="$s"; break; fi
done
[[ -x "${SWIFT_TOOLCHAIN}/bin/swiftc" ]] || { echo "❌ 未找到 swiftc，请设置 SWIFT_TOOLCHAIN"; exit 1; }
[[ -d "${IOS_SDK}" ]] || { echo "❌ 未找到 iOS SDK，请设置 IOS_SDK"; exit 1; }
SWIFTC="${SWIFT_TOOLCHAIN}/bin/swiftc"

# ---- ld 包装：swiftc 链接时默认调 /usr/bin/ld(GNU)，需转 ld64.lld ----
LINKBIN="${BUILD}/linkbin"; mkdir -p "$LINKBIN"
cat > "$LINKBIN/ld" <<EOF
#!/bin/bash
exec "${SWIFT_TOOLCHAIN}/bin/ld64.lld" "\$@"
EOF
chmod +x "$LINKBIN/ld"
export PATH="${LINKBIN}:${SWIFT_TOOLCHAIN}/bin:$PATH"

# ---- resource-dir（绝对路径）----
RES="$(mkdir -p "${BUILD}/resource-dir" && cd "${BUILD}/resource-dir" && pwd)"
if [[ ! -f "${RES}/.prepared" ]]; then
  rm -rf "${RES:?}"/*
  cp -R "${SWIFT_TOOLCHAIN}/lib/swift/"*.swift "${RES}/" 2>/dev/null || true
  cp -R "${SWIFT_TOOLCHAIN}/lib/swift/linux" "${RES}/" 2>/dev/null || true
  # 删除与 iOS SDK 冲突的 Linux/重复模块
  rm -rf "${RES}/dispatch" "${RES}/os" "${RES}/CoreFoundation" "${RES}/Block" "${RES}/linux" 2>/dev/null || true
  CLANG_VER="$(ls "${SWIFT_TOOLCHAIN}/lib/clang" | head -1)"
  mkdir -p "${RES}/clang"
  cp -R "${SWIFT_TOOLCHAIN}/lib/clang/${CLANG_VER}/include" "${RES}/clang/" 2>/dev/null || true
  # apinotes（OS_dispatch_* -> Dispatch* 改名映射）
  mkdir -p "${RES}/apinotes"
  for ap in Dispatch.apinotes os.apinotes; do
    for cand in "${ROOT}/../toolchain/swift-apinotes/apinotes/$ap" \
                "/home/user/.doubao/agent_mode/workspace/toolchain/swift-apinotes/apinotes/$ap"; do
      [[ -f "$cand" ]] && cp "$cand" "${RES}/apinotes/" && break
    done
  done
  touch "${RES}/.prepared"
fi

COMMON=(-target "$TARGET" -sdk "$IOS_SDK" -resource-dir "$RES" -O -parse-as-library
        -Xcc -fmodules-cache-path="${BUILD}/mcapp")
# 显式写入 ad-hoc 代码签名槽（LC_CODE_SIGNATURE + CodeDirectory），
# 否则 Swift 驱动默认关闭，SideStore/ldid 重签时会因缺少签名头而安装失败。
LINKV=(-Xlinker -adhoc_codesign \
       -Xlinker -platform_version -Xlinker ios -Xlinker "${DEPLOY}.0" -Xlinker "$SDK_VER")

mkdir -p "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule"
mkdir -p "${APP}/PlugIns/ClipboardKeyboard.appex" "${APP}/PlugIns/ClipboardWidget.appex"

subst(){ # $1=exec/module  $2=bundleid  $3=src
  sed -e "s/\\\$(EXECUTABLE_NAME)/$1/g" -e "s/\\\$(PRODUCT_MODULE_NAME)/$1/g" \
      -e "s/\\\$(PRODUCT_NAME)/$1/g" -e "s/\\\$(PRODUCT_BUNDLE_IDENTIFIER)/$2/g" \
      -e "s/\\\$(MARKETING_VERSION)/${MARK_VER}/g" -e "s/\\\$(CURRENT_PROJECT_VERSION)/${CUR_VER}/g" "$3"
}

echo "==> [1/4] ClipKit.framework"
mapfile -t KITSRC < <(find "${ROOT}/ClipKit" -name '*.swift' | sort)
"$SWIFTC" "${COMMON[@]}" -module-name ClipKit -emit-module -emit-library \
  -emit-module-path "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule/arm64-apple-ios.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/ClipKit.framework/ClipKit "${LINKV[@]}" \
  -o "${APP}/Frameworks/ClipKit.framework/ClipKit" "${KITSRC[@]}"

echo "==> [2/4] 主 App"
mapfile -t APPSRC < <(find "${ROOT}/ClipboardHistory" -name '*.swift' | sort)
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardHistory -emit-executable \
  -F "${APP}/Frameworks" -I "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule" \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks "${LINKV[@]}" \
  -o "${APP}/ClipboardHistory" "${APPSRC[@]}"

echo "==> [3/4] 键盘扩展"
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardKeyboard -emit-library \
  -F "${APP}/Frameworks" -I "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/ClipboardKeyboard.appex/ClipboardKeyboard \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -Xlinker -rpath -Xlinker @executable_path/../../Frameworks "${LINKV[@]}" \
  -o "${APP}/PlugIns/ClipboardKeyboard.appex/ClipboardKeyboard" "${ROOT}"/ClipboardKeyboard/*.swift

echo "==> [4/4] Widget 扩展"
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardWidget -emit-library \
  -Xlinker -install_name -Xlinker @rpath/ClipboardWidget.appex/ClipboardWidget "${LINKV[@]}" \
  -o "${APP}/PlugIns/ClipboardWidget.appex/ClipboardWidget" "${ROOT}"/ClipboardWidget/*.swift

# ---- 组装 Bundle ----
echo "==> 组装 Info.plist / PkgInfo / 图标"
subst ClipboardHistory com.clipboard.history "${ROOT}/ClipboardHistory/Resources/Info.plist" > "${APP}/Info.plist"
subst ClipKit com.clipboard.kit "${ROOT}/ClipKit/Info.plist" > "${APP}/Frameworks/ClipKit.framework/Info.plist"
subst ClipboardKeyboard com.clipboard.history.keyboard "${ROOT}/ClipboardKeyboard/Resources/Info.plist" > "${APP}/PlugIns/ClipboardKeyboard.appex/Info.plist"
subst ClipboardWidget com.clipboard.history.widget "${ROOT}/ClipboardWidget/Info.plist" > "${APP}/PlugIns/ClipboardWidget.appex/Info.plist"
printf 'APPL????' > "${APP}/PkgInfo"
printf 'XPC!????' > "${APP}/PlugIns/ClipboardKeyboard.appex/PkgInfo"
printf 'XPC!????' > "${APP}/PlugIns/ClipboardWidget.appex/PkgInfo"

# 补齐 installd 校验所需、手写 plist 缺失的标准键（Xcode 构建时会自动生成）
python3 - "${DEPLOY}" "${SDK_VER}" \
  "${APP}/Info.plist" \
  "${APP}/PlugIns/ClipboardKeyboard.appex/Info.plist" \
  "${APP}/PlugIns/ClipboardWidget.appex/Info.plist" <<'PY'
import sys, plistlib
minos, sdkver = sys.argv[1], sys.argv[2]
std = {
    "MinimumOSVersion": minos,
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "DTPlatformName": "iphoneos",
    "DTPlatformVersion": sdkver,
    "DTSDKName": f"iphoneos{sdkver}",
    "DTCompiler": "com.apple.compilers.llvm.clang.1_0",
}
for path in sys.argv[3:]:
    with open(path, "rb") as f:
        pl = plistlib.load(f)
    for k, v in std.items():
        pl.setdefault(k, v)
    with open(path, "wb") as f:
        plistlib.dump(pl, f, fmt=plistlib.FMT_XML)
PY

# 生成散件图标（无 actool）
python3 - "${APP}" "${ROOT}/ClipboardHistory/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" <<'PY'
import sys
from PIL import Image
app,src=sys.argv[1],sys.argv[2]
im=Image.open(src).convert("RGB")
specs=[("Icon-20","@2x",40),("Icon-20","@3x",60),("Icon-20~ipad","",20),("Icon-20@2x~ipad","",40),
("Icon-29","@2x",58),("Icon-29","@3x",87),("Icon-29~ipad","",29),("Icon-29@2x~ipad","",58),
("Icon-40","@2x",80),("Icon-40","@3x",120),("Icon-40~ipad","",40),("Icon-40@2x~ipad","",80),
("Icon-60","@2x",120),("Icon-60","@3x",180),("Icon-76~ipad","",76),("Icon-76@2x~ipad","",152),
("Icon-83.5@2x~ipad","",167),("Icon-1024","",1024)]
for base,suf,size in specs:
    im.resize((size,size),Image.LANCZOS).save(f"{app}/{base}{suf}.png","PNG",optimize=True)
PY

# ---- Mach-O 校验 ----
echo "==> Mach-O 校验"
python3 - "${APP}" <<'PY'
import struct,sys,glob,os
app=sys.argv[1]
bins=["ClipboardHistory","Frameworks/ClipKit.framework/ClipKit",
"PlugIns/ClipboardKeyboard.appex/ClipboardKeyboard","PlugIns/ClipboardWidget.appex/ClipboardWidget"]
ok=True
for b in bins:
    d=open(os.path.join(app,b),'rb').read()
    magic,cput=struct.unpack('<Ii',d[:8]);n=struct.unpack('<I',d[16:20])[0]
    assert magic==0xfeedfacf and cput==0x0100000c, b+" 非 arm64 Mach-O64"
    off=32;plat=None;sig=None
    for _ in range(n):
        cmd,cs=struct.unpack('<II',d[off:off+8])
        if cmd==0x32: plat=struct.unpack('<I',d[off+8:off+12])[0]
        if cmd==0x1d: sig=struct.unpack('<II',d[off+8:off+16])  # dataoff,datasize
        off+=cs
    assert plat==2, b+" 平台非 iOS"
    assert sig and sig[1]>0, b+" 缺少 LC_CODE_SIGNATURE 签名槽，SideStore 无法重签"
    so,ss=sig
    magic=struct.unpack('>I',d[so:so+4])[0]
    assert magic==0xfade0cc0, b+" 签名 SuperBlob magic 异常"
    print(f"  ✓ {b} arm64/iOS + ad-hoc签名槽({ss}B)")
print("Mach-O 全部通过")
PY

# ---- 打包裸 IPA（不签名、无 mobileprovision、无 _CodeSignature）----
echo "==> 打包 IPA"
rm -f "$OUT_IPA"
( cd "$BUILD" && zip -qr -X "ClipboardHistory-${MARK_VER}-raw-unsigned.ipa" Payload )
echo "✅ 完成: ${OUT_IPA}"
ls -lh "$OUT_IPA"
