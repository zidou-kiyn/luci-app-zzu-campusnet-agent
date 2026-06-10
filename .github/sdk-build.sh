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

# luci.mk 与 luci-base 依赖来自 luci feed
./scripts/feeds update luci
./scripts/feeds install -p luci luci-base

make defconfig
make "package/$PKG_NAME/compile" -j"$(nproc)" V=s

# 收集产物:24.10 及更早为 .ipk,25.12/snapshot 为 .apk
find bin -type f \( -name "${PKG_NAME}*.ipk" -o -name "${PKG_NAME}*.apk" \) -exec cp -v {} /out/ \;
ls -l /out
