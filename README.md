# nxova-opn-repo

OPNsense 自用插件与配套守护进程仓库：基于域名的分流（mosdns → pf 表 → 策略路由）。

## 目录结构

```
nxova-opn-repo/
├── README.md
├── dns/os-mosdns/        # mosdns DNS 引擎插件（配 pf-aliasd）
├── net/os-netbox/        # 策略路由总控插件（meta，聚合 mosdns/tun2socks/xray）
├── net/os-tun2socks/     # TUN 转 SOCKS5 桥接插件
├── net/os-xray/          # xray-core 路由引擎插件（镜像，见下）
├── daemon/pf-aliasd/     # Go 守护进程：DNS 解析结果 → pf 表（独立 go module）
└── scripts/
    └── build-daemon.sh   # 编译 pf-aliasd（FreeBSD amd64 静态二进制）
```

插件目录布局对齐官方 `opnsense/plugins`（`Makefile` + `pkg-descr` +
`src/opnsense/mvc/...` + `src/opnsense/service/...` + `src/etc/...`）。
`+MANIFEST` 不手写，由 `make metadata` 在构建时自动生成。

## 插件状态（诚实标注）

四个插件均沿用 `nxovaeng/opn-box` 的实现，目前状态：**界面简陋、
未做端到端联调**（dig → 入表 → 策略路由命中的完整链路还没跑通过）。
MVC 骨架（Model/Controller/View/ACL/Menu）、configd action、
`plugins.inc.d` 钩子已就位；缺：rc.d 服务脚本、配置模板、脚本、
表单持久化修复。

**os-xray 特别说明**：该插件的 canonical 位置是
`nxovazro/opn-repo`（已在用、有自动构建）。本仓库的
`net/os-xray/` 仅为**镜像**，保持同步即可，**不要**独立分叉改，
否则两边会越差越远。

## pf-aliasd 与 mosdns-pf 的配套关系

```
nxovaeng/mosdns-pf  (plugin/executable/pfalias)
        │  Unix SOCK_SEQPACKET, 二进制帧协议，同步等 ACK
        ▼
nxova-opn-repo/daemon/pf-aliasd
        │  /dev/pf ioctl (DIOCRADDADDRS/DELADDRS/GETADDRS)
        ▼
OPNsense pf 表 (External (advanced) 别名, table <name> persist)
        │  防火墙规则 destination = 别名
        ▼
策略路由 / 分流
```

- mosdns 侧用 `nxovaeng/mosdns-pf` 仓库构建（含 `pfalias` 插件），
  sequence 里 `exec: pf_alias <表名>` 即可把解析出的 A/AAAA 推送过来。
- pf-aliasd 侧见 `daemon/pf-aliasd/README.md`（含 `-tables` 启动清空说明）。
- OPNsense 侧先建 `External (advanced)` 别名并 Apply 一次，让表定义生效。

## 构建

```sh
# pf-aliasd（FreeBSD amd64 静态二进制）
./scripts/build-daemon.sh        # 产物：dist/pf-aliasd-freebsd-amd64

# 插件本身按 OPNsense 官方流程构建（需 Mk/plugins.mk 环境）
# cd dns/os-mosdns && make package
```

## 许可证

GPL-3.0。mosdns-pf fork 与 pf-aliasd 均衍生自 GPL-3.0 代码，
分发二进制时请保持仓库公开可获取。
