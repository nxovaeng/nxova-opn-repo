# pf-aliasd

守护进程：接收 mosdns `pfalias` 插件通过 Unix SOCK_SEQPACKET socket 发来的
域名解析结果（A/AAAA），经 `/dev/pf` ioctl 实时写入 FreeBSD pf 表，
并按 DNS TTL 做 GC。OPNsense 侧用 `External (advanced)` 类型别名建出
`table <name> persist`，防火墙规则以该别名为目标做策略路由/分流。

配套：mosdns 需使用本组织 `nxovaeng/mosdns-pf` 仓库构建
（内置 `plugin/executable/pfalias` 插件）。

## 为什么启动时要 flush 表

pf 表是 `persist` 的：filter reload 不会清空它，机器重启也不会。
而表项的 TTL 只保存在 pf-aliasd **内存**里的最小堆中。
daemon 或机器重启后，内存堆丢失，表里残留的 IP 就再也没人 GC，
变成永久条目泄漏——重启越多次，表越脏，分流规则越不准。

因此启动时用 `-tables` 指定管理的表，逐个清空后再开始服务：

```sh
pf-aliasd -tables proxy_group,DIRECT
```

- 表不存在（还没在 OPNsense 里建别名/Apply）只记 warning，不退出。
- flush 失败（非"表不存在"）同样记 warning 继续跑，并在日志中标明，
  避免一次启动问题导致整个 DNS 分流停摆；请检查日志确认。

## 构建（FreeBSD amd64 静态二进制）

```sh
./scripts/build-daemon.sh
# 产物：dist/pf-aliasd-freebsd-amd64
```

纯 Go（CGO_ENABLED=0），无 libc 依赖，可直接放到 OPNsense 上运行。

## 命令行参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-socket` | `/var/run/pf-aliasd.sock` | Unix SOCK_SEQPACKET socket 路径 |
| `-dev` | `/dev/pf` | PF 字符设备路径 |
| `-tables` | 空 | 启动时清空的表名，逗号分隔，如 `proxy_group,DIRECT` |
| `-gc` | `2s` | TTL 过期 GC 扫描间隔 |
| `-batch` | `256` | 单次 GC 最多驱逐的过期 IP 数 |
| `-mode` | `0660` | socket 文件权限 |

## 协议

见 `pkg/protocol/`：二进制帧，`CmdAdd`（带 TTL）/`CmdDel`/`CmdFlush` +
ACK。mosdns 侧的 `pfalias` 插件默认同步等待 ACK（"同步屏障"），
消除"客户端先拿到 IP 发 SYN、表还没写入"的首包竞态。

## 许可证

GPL-3.0（随 opn-box 上游）。
