# GitHub 上传方案（不推送任何密钥）

## 1) 初始化仓库

在本机：

```bash
cd /home/aroen/projects/derp-relay-bootstrap
git init
git add .
git commit -m "init: derp relay bootstrap"
```

## 2) 创建远端仓库并推送

二选一：

### A) 使用 GitHub CLI（推荐）

```bash
gh repo create <你的账号>/derp-relay-bootstrap --public
git remote add origin git@github.com:<你的账号>/derp-relay-bootstrap.git
git push -u origin main
```

### B) 手动在网页创建仓库

创建后：

```bash
git remote add origin git@github.com:<你的账号>/derp-relay-bootstrap.git
git push -u origin main
```

## 3) 密钥与配置的处理原则

- 严禁把任何真实的 Tailscale API Key、服务器私钥、证书私钥提交到 GitHub
- 建议让部署脚本从如下来源读取：
  - `/etc/derp/derp.env`（权限 `600`）
  - `/etc/derp/tskey.txt`（权限 `600`）

## 4) 其它服务器“一键部署”的推荐交付方式

建议在仓库后续补齐两类交付物：

1) **Release 附带 `derper` 二进制**
   - GitHub Actions 构建并发布 `derper-linux-amd64`
   - 目标机安装脚本直接下载 release artifact 到 `/usr/local/bin/derper`

2) **提供 `install.sh`**
   - 安装/更新 systemd unit、脚本、env 文件模板
   - 默认不覆盖已有配置，除非 `--force`
