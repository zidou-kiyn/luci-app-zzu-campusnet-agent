#!/bin/sh
# 在 immortalwrt/sdk 容器内编译本包。
# 约定:仓库以只读方式挂载到 /src,产物输出目录挂载到 /out(需可写)。
#   docker run --rm -v "$PWD:/src:ro" -v "$PWD/out:/out" \
#     immortalwrt/sdk:<tag> /bin/sh /src/.github/sdk-build.sh
set -ex

PKG_NAME="${PKG_NAME:-luci-app-zzu-campusnet-agent}"

# 定位 SDK 根目录:immortalwrt/sdk 镜像的 WORKDIR 即 SDK(/home/build/immortalwrt),
# openwrt/sdk 镜像则在 /builder;也可用 SDK_DIR 显式指定
if [ -n "${SDK_DIR:-}" ]; then
	cd "$SDK_DIR"
elif [ -x ./scripts/feeds ]; then
	:
elif [ -x /builder/scripts/feeds ]; then
	cd /builder
else
	echo "ERROR: SDK directory not found" >&2
	exit 1
fi

# 拷入源码(只取打包所需文件,避免 .git 等无关内容)
rm -rf "package/$PKG_NAME"
mkdir -p "package/$PKG_NAME"
cp -r /src/Makefile /src/htdocs /src/root "package/$PKG_NAME/"

# 用 CI 传入的版本号(来自 git tag,如 v1.0.1 → 1.0.1)覆盖 Makefile 里写死的
# PKG_VERSION,使产物文件名跟随标签;workflow_dispatch 等无 tag 场景留空,沿用默认值。
# 改的是拷进 SDK 的副本(可写),/src 仍只读不动。
if [ -n "${PKG_VERSION:-}" ]; then
	sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=${PKG_VERSION}/" "package/$PKG_NAME/Makefile"
	grep '^PKG_VERSION:=' "package/$PKG_NAME/Makefile"
fi

# 强制给随包脚本加可执行位(双保险):rpcd 只加载带执行权限的插件,
# 否则前端 RPC 调用会报 -32000 Object not found;此处不依赖 git 是否保留 mode。
chmod 0755 "package/$PKG_NAME/root/usr/libexec/rpcd/luci.zzucampusnetagent" \
           "package/$PKG_NAME/root/usr/sbin/zzucampusnetagent" \
           "package/$PKG_NAME/root/etc/init.d/zzucampusnetagent"

# luci.mk 与 luci-base 依赖来自 luci feed
./scripts/feeds update luci
./scripts/feeds install -p luci luci-base

# 绕过 csstidy 源下载校验失败:构建任何 luci 包都会 host 编译 csstidy 工具,
# 它先从镜像源拉取 csstidy-1.1.0.tar.zst。25.12/snapshot 镜像尚未缓存该包(全部 404),
# 退回 git clone 本地重打包时,因 git archive / zstd 版本差异生成的字节与 feed 内置
# PKG_MIRROR_HASH 不符(构建日志提示 "probably caused by .gitattributes")而报错。
# 源码内容一致、仅压缩字节不同,故将其下载校验置为 skip 接受 git 回退产物。
# 对 24.10 镜像可正常下载的场景无副作用(skip 仅跳过校验)。本包无 CSS,不依赖 csstidy 产物。
CSSTIDY_MK="feeds/luci/contrib/package/csstidy/Makefile"
if [ -f "$CSSTIDY_MK" ]; then
	sed -i 's/^PKG_MIRROR_HASH[[:space:]]*:=.*/PKG_MIRROR_HASH:=skip/; s/^PKG_HASH[[:space:]]*:=.*/PKG_HASH:=skip/' "$CSSTIDY_MK"
	grep -E '^PKG_(MIRROR_)?HASH:=' "$CSSTIDY_MK" || true
fi

make defconfig
make "package/$PKG_NAME/compile" -j"$(nproc)" V=s

# 收集产物:24.10 及更早为 .ipk,25.12/snapshot 为 .apk
find bin -type f \( -name "${PKG_NAME}*.ipk" -o -name "${PKG_NAME}*.apk" \) -exec cp -v {} /out/ \;
ls -l /out
