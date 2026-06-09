# Changelog

## v8.3 - 2026-06-10

- 增加 `flock` 防重入。
- 日志写入 `/var/log/auto-clean.log`，并保留最近 300 行。
- 支持 apt、dnf、yum 缓存清理。
- Debian/Ubuntu 上清理 apt cache、stale apt lists 和 auto-removable packages，并避开正在运行的 apt/dpkg。
- 将 systemd journal 限制到 30M，并写入持久 journald drop-in 配置。
- 清理 7 天以上 `/tmp`、`/var/tmp` 临时文件，避开 systemd 私有目录和 Unix socket 临时目录。
- 清理旧 web 轮转日志。
- 截断过大的 Docker JSON 日志和 `/var/log/btmp`。
- 清理 NodeQuality、LemonBench、UnixBench、Geekbench、YABS、Superbench 等常见 VPS 跑分工具残留。
- 对 `bench.sh`、`benchtest.sh`、`ecs.sh` 等泛名脚本增加内容特征检查，避免只凭文件名删除。
