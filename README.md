# nxova-opn-repo

OPNsense 自用插件仓库：基于域名的分流套件，各插件独立启停、弱依赖，
布局对齐官方 `opnsense/plugins`，原生 MVC 实现。

- **os-mosdns**：mosdns DNS 分流（规则组：直连/代理/阻止 × 自定义/在线，
  合并生效）+ pf-aliasd 把代理域名的解析结果同步进 pf 表（默认表名
  `proxy_group`，按 DNS TTL 过期；同名“外部（高级）”别名缺失时，
  点应用自动创建）。
- **os-xray**：xray-core 管理（结构化节点、订阅、入站、细粒度路由），
  配置与服务独立命名（`/usr/local/etc/xray-os/`、`xray_os`），与官方包零冲突。
- **os-tun2socks**：hev-socks5-tunnel 透明桥，把 pf 策略路由的流量
  送进本地 SOCKS5。
- **pf-aliasd**（`daemon/`）：Go 守护进程，接收 mosdns 的解析结果
  维护 pf 表（内存 TTL 堆，启动可清空受管表）。

数据流：DNS 查询 → mosdns 分流 → 代理域名 A/AAAA 经 pf-aliasd 入 pf 表
→ 防火墙策略路由 → tun_hev → os-xray 的 SOCKS5（127.0.0.1:10808）→ 节点。

## 安装

```sh
fetch -o /usr/local/etc/pkg/repos/nxova-opn.conf https://raw.githubusercontent.com/nxovaeng/nxova-opn-repo/main/autobuild/nxova-opn.conf
pkg update -r nxova-opn && pkg install -r nxova-opn os-mosdns os-xray os-tun2socks
```

推送 main 触发 CI 自动打包并发布到 https://opnrepo.zro.qzz.io ，
版本号为 `<日期>.<CI 轮次>`，`pkg upgrade` 可直接升级。

## 状态

已在 OPNsense 26.7 测试机装机验收（UI + API 全链路）；
os-tun2socks 全链路流量验收待真实 LAN 环境。

## 许可证

GPL-3.0（mosdns-pf fork 与 pf-aliasd 均衍生自 GPL-3.0 代码）。
