#!/bin/sh
#
# autobuild/build.sh - 在 FreeBSD VM 里构建 os-mosdns 完整包并生成 pkg repo
#
# 输入:  $WORKSPACE/dist/bin/{mosdns,pf-aliasd}  (ubuntu 上 GOOS=freebsd 交叉编译)
# 流程:
#   1. shallow clone opnsense/plugins (取 Mk/plugins.mk 基础设施)
#   2. 把 dns/os-mosdns 拷进去，二进制注入 src/usr/local/bin/
#   3. make package  -> os-mosdns-*.pkg (插件 UI + rc.d + template + 双二进制)
#   4. pkg repo .     -> 生成仓库元数据
#   5. 产物全部进 $PUBLISH_DIR, 由 workflow 发布到 gh-pages
#
set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-${WORKSPACE_DIR}/dist}"
PUBLISH_DIR="${PUBLISH_DIR:-${WORKSPACE_DIR}/public}"
PLUGINS_BRANCH="${PLUGINS_BRANCH:-master}"
PLUGINS_SRC="/tmp/opnsense-plugins"

echo "=========================================================="
echo " os-mosdns 完整包构建 (FreeBSD $(uname -r))"
echo " 工作目录: ${WORKSPACE_DIR}"
echo " 二进制目录: ${DIST_DIR}/bin"
echo " 发布目录: ${PUBLISH_DIR}"
echo "=========================================================="

for bin in mosdns pf-aliasd; do
    if [ ! -x "${DIST_DIR}/bin/${bin}" ]; then
        echo "缺二进制: ${DIST_DIR}/bin/${bin}" >&2
        exit 1
    fi
done

echo "==> [1/5] clone opnsense/plugins (${PLUGINS_BRANCH})"
rm -rf "${PLUGINS_SRC}"
git clone --depth 1 --branch "${PLUGINS_BRANCH}" \
    https://github.com/opnsense/plugins.git "${PLUGINS_SRC}"

echo "==> [2/5] 载入插件并注入二进制"
rm -rf "${PLUGINS_SRC}/dns/os-mosdns"
cp -R "${WORKSPACE_DIR}/dns/os-mosdns" "${PLUGINS_SRC}/dns/os-mosdns"
mkdir -p "${PLUGINS_SRC}/dns/os-mosdns/src/usr/local/bin"
cp "${DIST_DIR}/bin/mosdns" "${DIST_DIR}/bin/pf-aliasd" \
    "${PLUGINS_SRC}/dns/os-mosdns/src/usr/local/bin/"
chmod +x "${PLUGINS_SRC}/dns/os-mosdns/src/usr/local/bin/"*

echo "==> [3/5] make package"
cd "${PLUGINS_SRC}/dns/os-mosdns"
make package
ls -la ./*.pkg

echo "==> [4/5] pkg repo"
mkdir -p "${PUBLISH_DIR}"
cp ./*.pkg "${PUBLISH_DIR}/"
if [ -f "${WORKSPACE_DIR}/autobuild/index.html" ]; then
    cp "${WORKSPACE_DIR}/autobuild/index.html" "${PUBLISH_DIR}/"
fi
cd "${PUBLISH_DIR}"
pkg repo .
echo "==> [5/5] 仓库内容:"
ls -la "${PUBLISH_DIR}"
echo "构建完成"
