#!/bin/sh
#
# autobuild/build.sh - 在 FreeBSD VM 里构建插件包并生成 pkg repo
#
# 二进制来源:
#   pf-aliasd        : $DIST_DIR/bin/pf-aliasd (ubuntu 上 Go 交叉编译, 自有代码常变)
#   mosdns            : 从 nxovaeng/mosdns-pf release 下载 (调通后很少更新)
#   hev-socks5-tunnel : 从 heiher/hev-socks5-tunnel 官方 release 下载
# 插件:
#   dns/os-mosdns     : mosdns + pf-aliasd (src/bin/)
#   net/os-xray       : 无捆绑二进制 (PLUGIN_DEPENDS=xray-core 官方包)
#   net/os-tun2socks  : hev-socks5-tunnel (src/bin/)
#
# plugins.mk 规则: src/<path> -> /usr/local/<path>, 所以 /usr/local/bin 的
# 目标源路径是 src/bin (不是 src/usr/local/bin).
#
set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-${WORKSPACE_DIR}/dist}"
PUBLISH_DIR="${PUBLISH_DIR:-${WORKSPACE_DIR}/public}"
PLUGINS_BRANCH="${PLUGINS_BRANCH:-master}"
PLUGINS_SRC="/tmp/opnsense-plugins"
MOSDNS_RELEASE="${MOSDNS_RELEASE:-v5.3.4-pf1}"
HEV_VERSION="${HEV_VERSION:-2.19.0}"

echo "=========================================================="
echo " nxova-opn-repo 插件构建 (FreeBSD $(uname -r))"
echo "=========================================================="

# --- 1. 准备二进制 -------------------------------------------------------
mkdir -p "${DIST_DIR}/bin"
if [ ! -x "${DIST_DIR}/bin/pf-aliasd" ]; then
    echo "缺二进制: ${DIST_DIR}/bin/pf-aliasd (ubuntu job 应已交叉编译)" >&2
    exit 1
fi

if [ ! -x "${DIST_DIR}/bin/mosdns" ]; then
    echo "==> 下载 mosdns (${MOSDNS_RELEASE})"
    fetch -o "${DIST_DIR}/bin/mosdns" \
        "https://github.com/nxovaeng/mosdns-pf/releases/download/${MOSDNS_RELEASE}/mosdns-freebsd-amd64"
    chmod +x "${DIST_DIR}/bin/mosdns"
fi

if [ ! -x "${DIST_DIR}/bin/hev-socks5-tunnel" ]; then
    echo "==> 下载 hev-socks5-tunnel (${HEV_VERSION})"
    fetch -o "${DIST_DIR}/bin/hev-socks5-tunnel" \
        "https://github.com/heiher/hev-socks5-tunnel/releases/download/${HEV_VERSION}/hev-socks5-tunnel-freebsd-x86_64"
    chmod +x "${DIST_DIR}/bin/hev-socks5-tunnel"
fi
ls -la "${DIST_DIR}/bin"

# --- 2. clone opnsense/plugins -------------------------------------------
echo "==> clone opnsense/plugins (${PLUGINS_BRANCH})"
rm -rf "${PLUGINS_SRC}"
git clone --depth 1 --branch "${PLUGINS_BRANCH}" \
    https://github.com/opnsense/plugins.git "${PLUGINS_SRC}"

# --- 3. 逐个构建插件 ------------------------------------------------------
mkdir -p "${PUBLISH_DIR}"
build_plugin() {
    _src="$1"   # 仓库内插件目录, 如 dns/os-mosdns
    _bins="$2"  # 注入 src/bin 的二进制, 空格分隔, 如 "mosdns pf-aliasd"
    echo "==> 构建 ${_src}"
    rm -rf "${PLUGINS_SRC}/${_src}"
    cp -R "${WORKSPACE_DIR}/${_src}" "${PLUGINS_SRC}/${_src}"
    if [ -n "${_bins}" ]; then
        mkdir -p "${PLUGINS_SRC}/${_src}/src/bin"
        for _b in ${_bins}; do
            cp "${DIST_DIR}/bin/${_b}" "${PLUGINS_SRC}/${_src}/src/bin/"
        done
        chmod +x "${PLUGINS_SRC}/${_src}/src/bin/"*
    fi
    cd "${PLUGINS_SRC}/${_src}"
    # CI 自动版本: PLUGIN_VERSION=<构建日期>.<run_number>, 如 2026.10.23.42
    # 日期取构建当天（不读仓库 Makefile 里写死的日期，免得长期不更新）;
    # run_number 单调递增, 保证 pkg upgrade 能认出新包
    if [ -n "${PLUGIN_BUILD}" ]; then
        _newver="$(date +%Y.%m.%d).${PLUGIN_BUILD}"
        sed -i '' "s/^PLUGIN_VERSION.*/PLUGIN_VERSION=     ${_newver}/" Makefile
        echo "Version set: ${_newver}"
    fi
    make package PLUGIN_DEVEL=
    cp ./work/pkg/*.pkg "${PUBLISH_DIR}/"
    cd "${WORKSPACE_DIR}"
}

build_plugin "dns/os-mosdns" "mosdns pf-aliasd"
build_plugin "net/os-xray" ""
build_plugin "net/os-tun2socks" "hev-socks5-tunnel"

# --- 4. pkg repo ----------------------------------------------------------
if [ -f "${WORKSPACE_DIR}/autobuild/index.html" ]; then
    cp "${WORKSPACE_DIR}/autobuild/index.html" "${PUBLISH_DIR}/"
fi
# 仓库自带 pkg 源配置: 新机器一条 fetch 就能自举本仓库
#   fetch -o /usr/local/etc/pkg/repos/nxova-opn.conf https://opnrepo.zro.qzz.io/nxova-opn.conf
if [ -f "${WORKSPACE_DIR}/autobuild/nxova-opn.conf" ]; then
    cp "${WORKSPACE_DIR}/autobuild/nxova-opn.conf" "${PUBLISH_DIR}/"
fi
cd "${PUBLISH_DIR}"
pkg repo .
echo "==> 仓库内容:"
ls -la "${PUBLISH_DIR}"
echo "构建完成"
