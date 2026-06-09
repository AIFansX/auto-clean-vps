# auto-clean-vps

`auto-clean-vps` 是一个面向小型 Linux VPS 的定时清理脚本。当前发布版本为 `auto-clean v8.3`，用于定期清理包管理器缓存、systemd journal、临时目录、旧日志、Docker JSON 日志、用户缓存，以及常见 VPS 跑分工具残留。

脚本适合放在 `/usr/local/bin/auto-clean.sh`，配合 cron 每月运行一次。

## 功能

- 使用 `flock` 防止重复运行。
- 日志写入 `/var/log/auto-clean.log`，每次结束后只保留最近 300 行。
- 支持 `apt`、`dnf`、`yum` 缓存清理。
- Debian/Ubuntu 环境会执行 `apt-get clean`、`autoclean`、`autoremove -y`，并清理过期 apt lists。
- 检测 `apt`、`apt-get`、`dpkg`、`unattended-upgr` 进程，避免包管理器正在运行时强行清理。
- 将 systemd journal vacuum 到 30M。
- 写入 `/etc/systemd/journald.conf.d/99-auto-clean.conf`：
  - `SystemMaxUse=30M`
  - `RuntimeMaxUse=30M`
  - `MaxRetentionSec=14day`
- journald 配置只有发生变化时才重启 `systemd-journald`。
- 清理 `/tmp`、`/var/tmp` 中超过 7 天的临时文件和空目录。
- 避开 `systemd-private-*`、`.*-unix` 等敏感临时目录。
- 清理 `/var/log/nginx`、`/var/log/apache2`、`/var/log/httpd` 中超过 30 天的压缩或轮转日志。
- 截断超过 50M 的 Docker `*-json.log`。
- 截断超过 10M 的 `/var/log/btmp`。
- 清理 `/root` 和 `/home/*` 下超过 14 天的用户缓存文件。
- 删除常见跑分工具残留和脚本，包括 NodeQuality、LemonBench、UnixBench、Geekbench、YABS、Superbench、nench、vpsbench、serverreview 等。
- 对 `bench.sh`、`benchtest.sh`、`ecs.sh` 这类泛名脚本，会先检查内容是否包含跑分特征，再决定是否删除。

## 安装

```bash
sudo install -m 0755 auto-clean.sh /usr/local/bin/auto-clean.sh
sudo bash -n /usr/local/bin/auto-clean.sh
```

手动运行一次：

```bash
sudo /usr/local/bin/auto-clean.sh
sudo tail -n 80 /var/log/auto-clean.log
```

## Cron 示例

每月 1 日 05:00 自动运行：

```cron
0 5 1 * * /usr/local/bin/auto-clean.sh >/dev/null 2>&1
```

可以用下面的命令安装到 root 用户 crontab：

```bash
(sudo crontab -l 2>/dev/null; echo '0 5 1 * * /usr/local/bin/auto-clean.sh >/dev/null 2>&1') | sudo crontab -
```

如果已经存在同一条任务，请先手动去重。

## 校验

当前 v8.3 脚本的 SHA-256：

```text
8b1cc78eaec61ba40ed5a8ccb86a4993a871bdc55095e3a5f3cb44c4b453cd4a
```

校验命令：

```bash
sha256sum auto-clean.sh
bash -n auto-clean.sh
```

## 注意事项

- 请用 root 或具备 sudo 权限的用户运行，否则无法清理系统日志、包缓存和系统目录。
- 脚本会删除匹配条件的旧临时文件、轮转日志、用户缓存和跑分工具残留，请先阅读脚本后再部署到生产服务器。
- 脚本会写入 journald drop-in 配置，并在配置变化时重启 `systemd-journald`。
- Docker JSON 日志超过 50M 时会被直接截断为 0。
- `/var/log/btmp` 超过 10M 时会被直接截断为 0。
- 该脚本偏向 VPS 日常维护，不替代完整的日志保留、备份、监控或合规策略。

## 文件

- `auto-clean.sh`：主清理脚本。
- `CHANGELOG.md`：版本变更记录。
- `LICENSE`：MIT License。
