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
MARK_VER="2.6.0"; CUR_VER="9"
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

# ---- ldid：把 App Group 等 entitlements 嵌入 ad-hoc 签名，
#      SideStore/AltStore 设备端重签时会保留，主 App 与键盘才能共享数据容器 ----
LDID="${LDID:-}"
for c in "$LDID" "${ROOT}/../toolchain/bin/ldid" \
         /home/user/.doubao/agent_mode/workspace/toolchain/bin/ldid "$(command -v ldid)"; do
    [[ -z "$c" ]] && continue
    if [[ -x "$c" ]]; then LDID="$c"; break; fi
done
[[ -n "$LDID" && -x "$LDID" ]] || { echo "❌ 未找到 ldid（用于嵌入 entitlements），请先编译 toolchain/bin/ldid"; exit 1; }
echo "使用 ldid: $LDID"

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
mkdir -p "${APP}/PlugIns/ClipboardKeyboard.appex" \
         "${APP}/PlugIns/ClipboardWidget.appex" \
         "${APP}/PlugIns/ClipboardNotify.appex"

subst(){ # $1=exec/module  $2=bundleid  $3=src
  sed -e "s/\\\$(EXECUTABLE_NAME)/$1/g" -e "s/\\\$(PRODUCT_MODULE_NAME)/$1/g" \
      -e "s/\\\$(PRODUCT_NAME)/$1/g" -e "s/\\\$(PRODUCT_BUNDLE_IDENTIFIER)/$2/g" \
      -e "s/\\\$(MARKETING_VERSION)/${MARK_VER}/g" -e "s/\\\$(CURRENT_PROJECT_VERSION)/${CUR_VER}/g" "$3"
}

echo "==> [1/5] ClipKit.framework"
mapfile -t KITSRC < <(find "${ROOT}/ClipKit" -name '*.swift' | sort)
"$SWIFTC" "${COMMON[@]}" -module-name ClipKit -emit-module -emit-library \
  -emit-module-path "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule/arm64-apple-ios.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/ClipKit.framework/ClipKit "${LINKV[@]}" \
  -o "${APP}/Frameworks/ClipKit.framework/ClipKit" "${KITSRC[@]}"

echo "==> [2/5] 主 App"
mapfile -t APPSRC < <(find "${ROOT}/ClipboardHistory" -name '*.swift' | sort)
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardHistory -emit-executable \
  -F "${APP}/Frameworks" -I "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule" \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks "${LINKV[@]}" \
  -o "${APP}/ClipboardHistory" "${APPSRC[@]}"

echo "==> [3/5] 键盘扩展（MH_EXECUTE + NSExtensionMain）"
# appex 主程序必须是可执行文件 MH_EXECUTE（非 dylib），否则 installd 拒绝安装
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardKeyboard -emit-executable \
  -F "${APP}/Frameworks" -I "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -Xlinker -rpath -Xlinker @executable_path/../../Frameworks "${LINKV[@]}" \
  -o "${APP}/PlugIns/ClipboardKeyboard.appex/ClipboardKeyboard" "${ROOT}"/ClipboardKeyboard/*.swift

echo "==> [4/5] Widget 扩展（MH_EXECUTE，@main 入口）"
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardWidget -emit-executable "${LINKV[@]}" \
  -o "${APP}/PlugIns/ClipboardWidget.appex/ClipboardWidget" "${ROOT}"/ClipboardWidget/*.swift

echo "==> [5/5] 通知内容扩展（MH_EXECUTE + NSExtensionMain）"
"$SWIFTC" "${COMMON[@]}" -module-name ClipboardNotify -emit-executable \
  -F "${APP}/Frameworks" -I "${APP}/Frameworks/ClipKit.framework/Modules/ClipKit.swiftmodule" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -Xlinker -rpath -Xlinker @executable_path/../../Frameworks "${LINKV[@]}" \
  -o "${APP}/PlugIns/ClipboardNotify.appex/ClipboardNotify" "${ROOT}"/ClipboardNotify/*.swift

# ---- 用 ldid 把 entitlements 嵌入 ad-hoc 签名（App Group 共享的关键）----
# 主 App 与三个扩展都声明同一 App Group；框架 ClipKit 由宿主进程继承授权无需单独签。
echo "==> ldid 嵌入 entitlements（App Group 共享）"
"$LDID" -S"${ROOT}/ClipboardHistory/ClipboardHistory.entitlements"   "${APP}/ClipboardHistory"
"$LDID" -S"${ROOT}/ClipboardKeyboard/ClipboardKeyboard.entitlements" "${APP}/PlugIns/ClipboardKeyboard.appex/ClipboardKeyboard"
"$LDID" -S"${ROOT}/ClipboardWidget/ClipboardWidget.entitlements"     "${APP}/PlugIns/ClipboardWidget.appex/ClipboardWidget"
"$LDID" -S"${ROOT}/ClipboardNotify/ClipboardNotify.entitlements"     "${APP}/PlugIns/ClipboardNotify.appex/ClipboardNotify"
echo "  ✓ 4 个可执行文件已写入 application-groups 授权"

# ---- 组装 Bundle ----
echo "==> 组装 Info.plist / PkgInfo / 图标"
subst ClipboardHistory com.clipboard.history "${ROOT}/ClipboardHistory/Resources/Info.plist" > "${APP}/Info.plist"
subst ClipKit com.clipboard.kit "${ROOT}/ClipKit/Info.plist" > "${APP}/Frameworks/ClipKit.framework/Info.plist"
subst ClipboardKeyboard com.clipboard.history.keyboard "${ROOT}/ClipboardKeyboard/Resources/Info.plist" > "${APP}/PlugIns/ClipboardKeyboard.appex/Info.plist"
subst ClipboardWidget com.clipboard.history.widget "${ROOT}/ClipboardWidget/Info.plist" > "${APP}/PlugIns/ClipboardWidget.appex/Info.plist"
subst ClipboardNotify com.clipboard.history.notify "${ROOT}/ClipboardNotify/Info.plist" > "${APP}/PlugIns/ClipboardNotify.appex/Info.plist"
printf 'APPL????' > "${APP}/PkgInfo"
printf 'XPC!????' > "${APP}/PlugIns/ClipboardKeyboard.appex/PkgInfo"
printf 'XPC!????' > "${APP}/PlugIns/ClipboardWidget.appex/PkgInfo"
printf 'XPC!????' > "${APP}/PlugIns/ClipboardNotify.appex/PkgInfo"

# PiP / 静音音频保活所需资源
cp -f "${ROOT}/ClipboardHistory/Resources/blank_pip.mp4" "${APP}/blank_pip.mp4"
cp -f "${ROOT}/ClipboardHistory/Resources/silence.wav" "${APP}/silence.wav"

# 补齐 installd 校验所需、手写 plist 缺失的标准键（Xcode 构建时会自动生成）
python3 - "${DEPLOY}" "${SDK_VER}" \
  "${APP}/Info.plist" \
  "${APP}/PlugIns/ClipboardKeyboard.appex/Info.plist" \
  "${APP}/PlugIns/ClipboardWidget.appex/Info.plist" \
  "${APP}/PlugIns/ClipboardNotify.appex/Info.plist" <<'PY'
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
# (相对路径, 期望 filetype) 主程序与 appex=MH_EXECUTE(2)，framework=MH_DYLIB(6)
bins=[("ClipboardHistory",2),
("Frameworks/ClipKit.framework/ClipKit",6),
("PlugIns/ClipboardKeyboard.appex/ClipboardKeyboard",2),
("PlugIns/ClipboardWidget.appex/ClipboardWidget",2),
("PlugIns/ClipboardNotify.appex/ClipboardNotify",2)]
for b,wantFT in bins:
    d=open(os.path.join(app,b),'rb').read()
    magic,cput,sub,ft,n=struct.unpack('<IiiII',d[:20])
    assert magic==0xfeedfacf and cput==0x0100000c, b+" 非 arm64 Mach-O64"
    assert ft==wantFT, f"{b} filetype={ft}，期望 {wantFT}（appex 必须 MH_EXECUTE）"
    off=32;plat=None;sig=None
    for _ in range(n):
        cmd,cs=struct.unpack('<II',d[off:off+8])
        if cmd==0x32: plat=struct.unpack('<I',d[off+8:off+12])[0]
        if cmd==0x1d: sig=struct.unpack('<II',d[off+8:off+16])  # dataoff,datasize
        off+=cs
    assert plat==2, b+" 平台非 iOS"
    assert sig and sig[1]>0, b+" 缺少 LC_CODE_SIGNATURE 签名槽，SideStore 无法重签"
    so,ss=sig
    sm=struct.unpack('>I',d[so:so+4])[0]
    assert sm==0xfade0cc0, b+" 签名 SuperBlob magic 异常"
    ftName={2:"MH_EXECUTE",6:"MH_DYLIB"}.get(ft,ft)
    print(f"  ✓ {b} arm64/iOS/{ftName} + ad-hoc签名槽({ss}B)")
print("Mach-O 全部通过")
PY

# ---- entitlements 校验：4 个可执行文件必须含 App Group，键盘才能读到主 App 数据 ----
echo "==> entitlements 校验"
for b in "ClipboardHistory" \
         "PlugIns/ClipboardKeyboard.appex/ClipboardKeyboard" \
         "PlugIns/ClipboardWidget.appex/ClipboardWidget" \
         "PlugIns/ClipboardNotify.appex/ClipboardNotify"; do
  "$LDID" -e "${APP}/$b" | grep -q "group.com.clipboard.history" \
    && echo "  ✓ $b 含 App Group" \
    || { echo "  ❌ $b 缺少 App Group entitlements"; exit 1; }
done

# ---- 规范化打包裸 IPA（不签名、无 mobileprovision、无 _CodeSignature）----
# 用 python zipfile 显式写标准结构：固定时间戳、标准 EOCD、无 zip64、
# 显式 unix 权限位（可执行文件 755），最大化兼容 SideStore/iLoader(isideload)/LiveContainer。
echo "==> 规范化打包 IPA"
rm -f "$OUT_IPA"
python3 - "$BUILD" "$OUT_IPA" <<'PY'
import sys, os, zipfile, datetime
build, out = sys.argv[1], sys.argv[2]
root = os.path.join(build, "Payload")
# Mach-O 可执行文件集合（需 0755）
exec_names = {"ClipboardHistory", "ClipKit", "ClipboardKeyboard", "ClipboardWidget", "ClipboardNotify"}
fixed = (2024, 1, 1, 0, 0, 0)

def add_dir(zf, arc):
    zi = zipfile.ZipInfo(arc + "/", fixed)
    zi.create_system = 3            # Unix
    zi.external_attr = (0o40755 << 16) | 0o040000  # drwxr-xr-x
    zi.compress_type = zipfile.ZIP_STORED
    zf.writestr(zi, b"")

entries = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort(); filenames.sort()
    rel_dir = os.path.relpath(dirpath, build)
    if rel_dir != ".":
        entries.append(("dir", rel_dir, None))
    for fn in filenames:
        full = os.path.join(dirpath, fn)
        arc = os.path.relpath(full, build)
        entries.append(("file", arc, full))

# 目录优先、同级按路径排序，保证 Payload/ 在最前
entries.sort(key=lambda e: (e[1].count("/"), e[1]))
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9, allowZip64=False) as zf:
    seen_dirs = set()
    for kind, arc, full in entries:
        # 确保父目录都已写入
        parts = arc.split("/")[:-1]
        for i in range(len(parts)):
            d = "/".join(parts[:i+1])
            if d not in seen_dirs:
                add_dir(zf, d); seen_dirs.add(d)
        if kind == "dir":
            if arc not in seen_dirs: add_dir(zf, arc); seen_dirs.add(arc)
            continue
        zi = zipfile.ZipInfo(arc, fixed)
        zi.create_system = 3
        base = os.path.basename(arc)
        mode = 0o755 if base in exec_names else 0o644
        zi.external_attr = (mode << 16) | (0o100000 if mode == 0o644 else 0o100000)
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(full, "rb") as f:
            zf.writestr(zi, f.read(), compress_type=zipfile.ZIP_DEFLATED)

# 独立回读校验
with zipfile.ZipFile(out) as z:
    bad = z.testzip()
    assert bad is None, f"坏条目 {bad}"
    n = len(z.namelist())
raw = open(out, "rb").read()
assert raw.rfind(b"PK\x05\x06") == len(raw) - 22, "EOCD 不在文件末尾"
assert b"PK\x06\x06" not in raw, "不应包含 zip64 EOCD"
print(f"  规范化 zip 完成：{n} 条目，EOCD 位于末尾，无 zip64")
PY
echo "✅ 完成: ${OUT_IPA}"
ls -lh "$OUT_IPA"
shasum -a 256 "$OUT_IPA" | awk '{print "SHA256:",$1}'
