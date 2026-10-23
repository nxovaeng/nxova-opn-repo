# nxova-opn-repo

OPNsense 自用插件仓库：一套基于域名的分流组件——mosdns 做 DNS 分流，
解析结果经 pf-aliasd 同步进 pf 表做策略路由，xray-core 提供代理出口，
hev-socks5-tunnel 把 LAN 流量透明送进 SOCKS5。各插件独立启停、弱依赖，
内核（xray-core / 未来的 sing-box）可平替。

## 目录结构

```
nxova-opn-repo/
├── dns/os-mosdns/        # mosdns DNS 分流引擎插件（配 pf-aliasd）
├── net/os-xray/          # xray-core 路由引擎插件
├── net/os-tun2socks/     # TUN 转 SOCKS5 透明桥接插件
├── daemon/pf-aliasd/     # Go 守护进程：DNS 解析结果 → pf 表（独立 go module）
├── autobuild/            # CI 构建脚本 + pkg 仓库配置（nxova-opn.conf）
└── scripts/
    └── build-daemon.sh   # 本地编译 pf-aliasd（FreeBSD amd64 静态二进制）
```

插件目录布局对齐官方 `opnsense/plugins`（`Makefile` + `pkg-descr` +
`src/opnsense/mvc/...` + `src/opnsense/service/...` + `src/etc/...`），
原生 MVC（PHP/Volt + configd），不依赖任何外部 controller 二进制。

## 插件一览

### dns/os-mosdns

本地 DNS 引擎（mosdns v5，`nxovaeng/mosdns-pf` 构建，含 pfalias 插件）：

- **分流模式**：白名单（默认走代理）/ 黑名单（默认直连）/ 自定义；
  阻止名单开启时在所有模式下最先拦截。
- **规则组**（规则页）：直连 / 代理 / 阻止三类，每类分自定义组（手写）
  与在线组（URL 拉取，预设 Loyalsoldier 清单双源）；编辑、拉取只写
  文件，点「合并并应用」才合并成六个文件（`custom_*` / `sync_*`）
  并重启 mosdns。在线清单拉取/合并时自动清洗不支持的行并计数上报，
  本地组逐条校验报错。
- **转发上游**：一行一个的多行编辑器，带常用 DNS 下拉预设与实时
  格式校验；代理上游可经 SOCKS5（如本机 xray 入站）出去。
- **pf 同步**：代理域名的 A/AAAA 经 pf-aliasd 写入 pf 表（默认表名
  `proxy_group`），按 DNS TTL 过期。点「应用」时若防火墙别名里没有
  同名的“外部（高级）”别名会自动创建，pf 表随之生成，无需手动建；
  PF 别名守护页带「清空别名表」按钮（连 TTL 记录一起清，立即生效）。
- 附规则模拟测试页（按当前名单与优先链推演一个域名会怎么走）与日志页。

### net/os-xray

xray-core 的配置与服务管理（只用官方内核二进制，配置与 rc.d 全部
独立命名 `/usr/local/etc/xray-os/`、`xray_os`，与官方包零冲突）：

- 节点：结构化凭据字段 + 分享链接导入（vless/vmess/trojan/ss 等），
  活动节点可切换，带延迟测试；订阅：多订阅管理、行内更新/全部更新。
- 入站与细粒度路由规则在插件内独立维护（不消费 mosdns 规则组）；
  固定内部入站 hev-socks-in `127.0.0.1:10808`（给 os-tun2socks）、
  dns-in `127.0.0.1:10853`。

### net/os-tun2socks

hev-socks5-tunnel（官方 release 二进制打包）：把 pf 策略路由送进
`tun_hev` 的 LAN 流量透明转发到本地 SOCKS5（典型接 os-xray 的
127.0.0.1:10808），实现全网透明代理。

### daemon/pf-aliasd

Go 守护进程：监听 Unix SOCK_SEQPACKET socket 接收 mosdns 发来的
解析结果，用内存 TTL 堆管理到期（续期、到期删除），经 /dev/pf
ioctl 维护 pf 表；启动时可按配置先清空受管表（内存记录不落盘，
避免残留条目永不过期）。协议与用法见 `daemon/pf-aliasd/README.md`。

## 数据流

```
客户端 DNS 查询
   ▼
mosdns（规则组分流：直连上游 / 代理上游经 SOCKS5）
   │  代理域名的 A/AAAA + TTL（SOCK_SEQPACKET 同步等 ACK）
   ▼
pf-aliasd ── /dev/pf ioctl ──► pf 表（External (advanced) 别名）
   │                             防火墙规则 destination = 该别名
   ▼                             → 策略路由到 tun_hev
os-tun2socks ──► SOCKS5（os-xray 127.0.0.1:10808）──► 代理节点
```

## 安装

在 OPNsense 上添加本仓库后从包管理安装（root shell，单行命令）：

```sh
fetch -o /usr/local/etc/pkg/repos/nxova-opn.conf https://raw.githubusercontent.com/nxovaeng/nxova-opn-repo/main/autobuild/nxova-opn.conf
pkg update -r nxova-opn && pkg install -r nxova-opn os-mosdns os-xray os-tun2socks
```

仓库地址 `https://opnrepo.zro.qzz.io`（GitHub Pages）。推送到 main
触发 CI：跨编 pf-aliasd → FreeBSD VM 打包三插件 → 发布到 gh-pages；
版本号自动为 `<日期>.<CI 轮次>`，`pkg upgrade` 可直接识别升级。

## 状态

已在 OPNsense 26.7（FreeBSD 15.1）测试机上装机验收：三插件的
设置/规则全链路（建组 → 编辑 → 拉取 → 合并 → 模拟测试）、pf 同步
与别名自动创建均通过 UI + API 双路验证。os-tun2socks 的透明代理
全链路流量验收尚待在真实 LAN 环境完成。

本地构建单个插件（需 OPNsense Mk 环境）：`cd dns/os-mosdns && make package`；
本地编译 pf-aliasd：`./scripts/build-daemon.sh`。

## 许可证

GPL-3.0。mosdns-pf fork 与 pf-aliasd 均衍生自 GPL-3.0 代码，
分发二进制时请保持仓库公开可获取。
