# Sailfish OS 完整环境迁移手册

**适用机型**: OnePlus 6T (kepler)
**系统版本**: Sailfish OS 5.1.0.11
**迁移方式**: Docker 容器 + rsync
**最后更新**: 2026-08-21

---

## 目录

1. [环境概述](#1-环境概述)
2. [迁移前准备](#2-迁移前准备)
3. [目标机初始化](#3-目标机初始化)
4. [Docker 容器迁移](#4-docker-容器迁移)
5. [Docker 服务部署](#5-docker-服务部署)
6. [用户环境迁移](#6-用户环境迁移)
7. [桌面图标同步](#7-桌面图标同步)
8. [验证与测试](#8-验证与测试)
9. [故障排查](#9-故障排查)
10. [关键文件清单](#10-关键文件清单)

---

## 1. 环境概述

### 1.1 本机环境架构

```
┌─────────────────────────────────────────────┐
│  Sailfish OS (Lipstick 桌面)                 │
│  用户: defaultuser (uid 100000)              │
├─────────────────────────────────────────────┤
│  系统 Docker (root)                          │
│  └─ fedora44 容器                            │
│     ├─ niri (Wayland compositor)            │
│     ├─ Xwayland (X11 兼容层)                │
│     ├─ fcitx5 (中文输入法)                   │
│     ├─ SPlayer (MPV 播放器)                 │
│     ├─ QQ (Linux QQ)                        │
│     ├─ Chromium (浏览器)                     │
│     └─ wvkbd (虚拟键盘)                      │
└─────────────────────────────────────────────┘
```

### 1.2 关键用户与权限

| 项目 | 值 |
|------|-----|
| 用户名 | defaultuser |
| UID | 100000 |
| GID | 100000 |
| docker 组 GID | 100001 |
| subuid/subgid | defaultuser:100000:65536 |
| sudo | NOPASSWD |

### 1.3 迁移数据量

| 数据 | 大小 | 位置 |
|------|------|------|
| Docker 二进制 + 配置 | ~200MB | /usr/bin/, /etc/docker/ |
| Docker 数据 | ~8.8GB | /var/lib/docker/ |
| HOME_Fedora | ~2GB | /home/defaultuser/HOME_Fedora/ |
| rootitanium | ~311MB | /home/rootitanium/ |
| 应用数据 | ~500MB | /home/defaultuser/ 其他 |
| **合计** | **~12GB** | |

---

## 2. 迁移前准备

### 2.1 确认本机环境状态

```bash
# 检查 docker 容器状态
docker ps -a

# 检查本机用户名（确认不是 nemo）
id defaultuser

# 检查 docker 数据目录大小
du -sh /var/lib/docker/

# 检查 HOME_Fedora 大小
du -sh /home/defaultuser/HOME_Fedora/

# 检查本机自定义桌面文件
ls /usr/share/applications/SPlayer* /usr/share/applications/qq*

# 检查本机自定义图标
ls /usr/share/icons/hicolor/86x86/apps/silisili*
ls /usr/share/icons/hicolor/86x86/apps/harbour-rootitanium*
```

### 2.2 确认本机自定义内容清单

需要迁移的自定义内容：

- [ ] Docker 二进制: dockerd, containerd, runc, containerd-shim-runc-v2
- [ ] Docker 配置: daemon.json, docker.service
- [ ] Docker 数据: /var/lib/docker/ (容器层、镜像、卷)
- [ ] HOME_Fedora: ~/.config/niri/, ~/.config/fcitx5/, ~/.config/SPlayer/, start-niri-stack.sh
- [ ] 应用目录: /home/rootitanium/, /opt/SPlayer/, /opt/QQ/
- [ ] 桌面文件: cn.silisili.native.desktop, harbour-rootitanium.desktop, harbour-storeman.desktop
- [ ] 图标文件: silisili-native-devel.png, harbour-rootitanium.png, harbour-storeman.png
- [ ] 用户桌面文件: ~/.local/share/applications/niri.desktop
- [ ] 用户图标: ~/.local/share/icons/distrobox/fedora-distrobox.png
- [ ] RPM 包: fastfetch, harbour-rootitanium, libvncserver, lipstick2vnc, silisili-native-devel, wget, zip
- [ ] distrobox 工具链: /usr/local/bin/distrobox*

### 2.3 准备本机 SSH 服务

```bash
# 确保本机 sshd 运行（用于 rsync 传输）
systemctl status sshd

# 确保 defaultuser 可以 ssh 登录
grep defaultuser /etc/ssh/sshd_config
# 应有: AllowUsers defaultuser 或类似配置
```

---

## 3. 目标机初始化

### 3.1 基础网络与用户配置

```bash
# 确认目标机 IP（假设为 192.168.2.165）
# 在目标机上执行

# 安装 sudo
zypper install sudo

# 配置 NOPASSWD
echo "defaultuser ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/defaultuser
sudo chmod 440 /etc/sudoers.d/defaultuser

# 验证 sudo
sudo echo "sudo-ok"
```

### 3.2 安装基础软件包

```bash
# 在目标机上执行
sudo zypper install zip rsync wget
```

### 3.3 安装 fastfetch

```bash
# 从本机拷贝 rpm 到目标机
scp /path/to/fastfetch-linux-aarch64.rpm defaultuser@192.168.2.165:/tmp/
ssh defaultuser@192.168.2.165 "sudo rpm -ivh /tmp/fastfetch-linux-aarch64.rpm"
```

### 3.4 验证目标机状态

```bash
# 确认目标机环境
ssh defaultuser@192.168.2.165 "
  cat /etc/os-release | head -1
  id
  cat /etc/subuid
  cat /etc/subgid
  uname -r
"
```

---

## 4. Docker 容器迁移

### 4.1 方案选择

**推荐方案: rsync (通过容器内 SSH 中转)**

原因:
- Docker 数据量大 (8.8GB)，dd 方式备份恢复太慢
- rsync 支持增量传输和断点续传
- 容器内有 Fedora 工具链，SSH 操作方便
- TWRP zip 方式失败（21GB zip 超出 TWRP /tmp tmpfs 限制）

### 4.2 启动 SSH 中转

```bash
# 在容器内启动 SSH 服务（用于 rsync 中转）
docker exec fedora44 bash -c '
  mkdir -p /run/sshd
  /usr/sbin/sshd
'
```

### 4.3 rsync 传输 Docker 数据

```bash
# 通过容器 rsync 传输（压缩模式，提速 5-7 倍）
docker exec fedora44 bash -c '
  setsid bash -c "
    rsync -az --info=progress2 \
      -e \"sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no\" \
      --rsync-path=\"sudo rsync\" \
      /run/host/var/lib/docker/ \
      defaultuser@TARGET_IP:/var/lib/docker/ \
      > /tmp/docker-rsync-z.log 2>&1
  " < /dev/null &
  echo "rsync started"
'
```

**关键参数说明**:
- `-a`: 归档模式，保留权限、时间戳、符号链接
- `-z`: 压缩传输，WiFi 下提速 5-7 倍（约 5-8MB/s vs 1MB/s）
- `--info=progress2`: 显示总体进度
- `--rsync-path="sudo rsync"`: 目标端用 sudo 执行 rsync（需要 root 权限写 /var/lib/docker）
- `/run/host/`: 容器内访问宿主机文件系统的路径

**监控传输进度**:
```bash
# 查看进度
docker exec fedora44 tail -c 300 /tmp/docker-rsync-z.log | tr "\r" "\n" | tail -3

# 查看传输速度
docker exec fedora44 tail -c 300 /tmp/docker-rsync-z.log | grep -o '[0-9.]*MB/s'
```

### 4.4 rsync 完成后处理

```bash
# 确认传输完整性
ssh defaultuser@192.168.2.165 "sudo du -sh /var/lib/docker"
# 应显示约 8.8GB

ssh defaultuser@192.168.2.165 "sudo ls /var/lib/docker/"
# 应有: buildkit containerd containers engine-id image network plugins rootfs runtimes swarm tmp volumes
```

### 4.5 注意事项

- rsync 可能卡在 `/sys/power/wake_unlock` 等系统文件（No data available 错误），属正常现象
- 如果卡住太久，可直接杀掉 rsync 进程（数据已到位）
- 增量检查（ir-chk）阶段可能很慢（1.2M 个小文件/symlink）
- 传输中断后可重新运行，rsync 会断点续传

---

## 5. Docker 服务部署

### 5.1 传输 Docker 二进制

```bash
# 通过容器 scp 传输
docker exec fedora44 bash -c '
SSH="sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no"
SSHCP="sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no"
HOST=/run/host/usr/bin

# 传输二进制文件
for bin in dockerd containerd runc containerd-shim-runc-v2; do
  $SSHCP $HOST/$bin defaultuser@TARGET_IP:/tmp/
  $SSH "echo YOUR_PASSWORD | sudo -S cp /tmp/$bin /usr/bin/ && echo $bin-ok"
done
'

# 在另一台也拷贝一份到 /home/defaultuser/bin/
ssh defaultuser@192.168.2.165 "
  mkdir -p /home/defaultuser/bin
  sudo cp /usr/bin/docker* /home/defaultuser/bin/
  sudo cp /usr/bin/containerd* /home/defaultuser/bin/
  sudo cp /usr/bin/runc /home/defaultuser/bin/
  sudo chown -R defaultuser:defaultuser /home/defaultuser/bin/
"
```

### 5.2 部署 Docker 配置

```bash
# 传输 docker.service
docker exec fedora44 bash -c '
  sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
    /run/host/etc/systemd/system/docker.service \
    defaultuser@TARGET_IP:/tmp/docker.service
  sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
    defaultuser@TARGET_IP \
    "echo YOUR_PASSWORD | sudo -S cp /tmp/docker.service /etc/systemd/system/ && echo service-ok"
'

# 创建 daemon.json（注意：Sailfish 需要 "userland-proxy": false）
docker exec fedora44 bash -c '
  echo "{\"registry-mirrors\":[\"https://docker.1ms.run\",\"https://docker.1panel.live\"],\"userland-proxy\":false}" \
    | base64 > /tmp/daemon.json.b64
  sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
    /tmp/daemon.json.b64 defaultuser@TARGET_IP:/tmp/
  sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
    defaultuser@TARGET_IP \
    "echo YOUR_PASSWORD | sudo -S bash -c \"base64 -d /tmp/daemon.json.b64 > /etc/docker/daemon.json\" && echo daemon-ok"
'
```

### 5.3 创建 Docker 组并添加用户

```bash
ssh defaultuser@192.168.2.165 "
  echo YOUR_PASSWORD | sudo -S groupadd -g 100001 docker 2>/dev/null
  echo YOUR_PASSWORD | sudo -S usermod -aG docker defaultuser
  echo docker-group-ok
"
```

### 5.4 启动 Docker 服务

```bash
ssh defaultuser@192.168.2.165 "
  echo YOUR_PASSWORD | sudo -S systemctl daemon-reload
  echo YOUR_PASSWORD | sudo -S systemctl enable docker
  echo YOUR_PASSWORD | sudo -S systemctl start docker
  sleep 2
  echo YOUR_PASSWORD | sudo -S systemctl is-active docker
  docker info | head -10
"
# 应显示: active, Client/Server 都正常
```

### 5.5 重建缺失的 Docker 卷

```bash
# rsync 未完成时可能缺失 volume，手动创建
ssh defaultuser@192.168.2.165 "
  echo YOUR_PASSWORD | sudo -S docker volume create 8241c741230aa7525bb3902f1def2c6d007947fdf1b4cd6e794065ea2fa69b2e
  echo YOUR_PASSWORD | sudo -S docker volume create 99ea8a7735a43c684740b880d98990ad1bd4c3044794084700ab79965be92589
  echo YOUR_PASSWORD | sudo -S docker volume ls
"
```

### 5.6 启动 fedora44 容器

```bash
ssh defaultuser@192.168.2.165 "
  docker start fedora44
  sleep 3
  docker ps -a --filter name=fedora44
  # 应显示 STATUS: Up
"
```

---

## 6. 用户环境迁移

### 6.1 传输 HOME_Fedora

```bash
docker exec fedora44 bash -c '
  rsync -a -e "sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no" \
    --rsync-path="sudo rsync" \
    /run/host/home/defaultuser/HOME_Fedora/ \
    defaultuser@TARGET_IP:/home/defaultuser/HOME_Fedora/
'
```

### 6.2 传输 rootitanium

```bash
docker exec fedora44 bash -c '
  rsync -a -e "sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no" \
    --rsync-path="sudo rsync" \
    /run/host/home/rootitanium/ \
    defaultuser@TARGET_IP:/home/rootitanium/
'
```

### 6.3 传输其他用户文件

```bash
# 传输 .bashrc 等隐藏文件
docker exec fedora44 bash -c '
  rsync -a -e "sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no" \
    --rsync-path="sudo rsync" \
    /run/host/home/defaultuser/.bashrc \
    defaultuser@TARGET_IP:/home/defaultuser/
'
```

### 6.4 传输 distrobox 工具链

```bash
docker exec fedora44 bash -c '
  # 传输二进制
  for f in distrobox distrobox-export distrobox-host-exec distrobox-init; do
    sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
      /run/host/usr/local/bin/$f defaultuser@TARGET_IP:/tmp/
    sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
      defaultuser@TARGET_IP "echo YOUR_PASSWORD | sudo -S cp /tmp/$f /usr/local/bin/ && echo $f-ok"
  done

  # 创建符号链接
  sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
    defaultuser@TARGET_IP "
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-create
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-enter
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-ephemeral
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-generate-entry
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-list
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-ls
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-rm
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-stop
      echo YOUR_PASSWORD | sudo -S ln -sf /usr/local/bin/distrobox /usr/local/bin/distrobox-upgrade
      echo symlinks-ok
    "
'
```

### 6.5 传输 bin 目录

```bash
docker exec fedora44 bash -c '
  rsync -a -e "sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no" \
    --rsync-path="sudo rsync" \
    /run/host/home/defaultuser/bin/ \
    defaultuser@TARGET_IP:/home/defaultuser/bin/
'
```

### 6.6 安装缺失的 RPM 包

```bash
ssh defaultuser@192.168.2.165 "
  # 可通过 zypper 安装的
  echo YOUR_PASSWORD | sudo -S zypper --non-interactive install wget libvncserver lipstick2vnc zip rsync

  # harbour-rootitanium 只有数据目录（/home/rootitanium），已通过 rsync 传输
"
```

### 6.7 传输 silisili

```bash
# silisili-native-devel 包含运行时库，手动拷贝
docker exec fedora44 bash -c '
  SSH="sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no"
  SSHCP="sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no"

  $SSHCP /run/host/usr/bin/silisili-native defaultuser@TARGET_IP:/tmp/
  $SSH "echo YOUR_PASSWORD | sudo -S cp /tmp/silisili-native /usr/bin/"

  $SSHCP -r /run/host/usr/lib64/silisili-native/ defaultuser@TARGET_IP:/tmp/silisili-native/
  $SSH "echo YOUR_PASSWORD | sudo -S cp -r /tmp/silisili-native /usr/lib64/"

  $SSHCP /run/host/usr/lib/systemd/system/silisili-native-minimedia.service defaultuser@TARGET_IP:/tmp/
  $SSH "echo YOUR_PASSWORD | sudo -S cp /tmp/silisili-native-minimedia.service /usr/lib/systemd/system/"
  echo silisili-ok
'
```

---

## 7. 桌面图标同步

### 7.1 传输桌面文件

```bash
docker exec fedora44 bash -c '
  for f in cn.silisili.native.desktop harbour-rootitanium.desktop harbour-storeman.desktop; do
    sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
      /run/host/usr/share/applications/$f defaultuser@TARGET_IP:/tmp/
    sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
      defaultuser@TARGET_IP "echo YOUR_PASSWORD | sudo -S cp /tmp/$f /usr/share/applications/"
  done
  echo desktop-files-ok
'
```

### 7.2 传输 niri 桌面文件

```bash
docker exec fedora44 bash -c '
  sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
    /home/defaultuser/.local/share/applications/niri.desktop \
    defaultuser@TARGET_IP:/tmp/
  sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
    defaultuser@TARGET_IP "
      mkdir -p /home/defaultuser/.local/share/applications
      cp /tmp/niri.desktop /home/defaultuser/.local/share/applications/
      echo niri-desktop-ok
    "
'
```

### 7.3 传输图标文件

```bash
docker exec fedora44 bash -c '
  # silisili 图标
  sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
    /run/host/usr/share/icons/hicolor/86x86/apps/silisili-native-devel.png \
    defaultuser@TARGET_IP:/tmp/
  sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
    defaultuser@TARGET_IP "echo YOUR_PASSWORD | sudo -S cp /tmp/silisili-native-devel.png /usr/share/icons/hicolor/86x86/apps/"

  # rootitanium 图标（多尺寸）
  for size in 86x86 108x108 128x128 172x172; do
    sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
      /run/host/usr/share/icons/hicolor/$size/apps/harbour-rootitanium.png \
      defaultuser@TARGET_IP:/tmp/
    sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
      defaultuser@TARGET_IP "echo YOUR_PASSWORD | sudo -S mkdir -p /usr/share/icons/hicolor/$size/apps && echo YOUR_PASSWORD | sudo -S cp /tmp/harbour-rootitanium.png /usr/share/icons/hicolor/$size/apps/"
  done

  # niri 图标（多尺寸）
  for size in 86x86 108x108 128x128 172x172; do
    sshpass -p YOUR_PASSWORD scp -o StrictHostKeyChecking=no \
      /home/defaultuser/.local/share/icons/distrobox/fedora-distrobox.png \
      defaultuser@TARGET_IP:/tmp/niri.png
    sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
      defaultuser@TARGET_IP "echo YOUR_PASSWORD | sudo -S mkdir -p /usr/share/icons/hicolor/$size/apps && echo YOUR_PASSWORD | sudo -S cp /tmp/niri.png /usr/share/icons/hicolor/$size/apps/niri.png && echo YOUR_PASSWORD | sudo -S chmod 644 /usr/share/icons/hicolor/$size/apps/niri.png"
  done

  # 确保 distrobox 图标目录存在且权限正确
  sshpass -p YOUR_PASSWORD ssh -o StrictHostKeyChecking=no \
    defaultuser@TARGET_IP "
      mkdir -p /home/defaultuser/.local/share/icons/distrobox
      cp /tmp/niri.png /home/defaultuser/.local/share/icons/distrobox/fedora-distrobox.png
      chmod 644 /home/defaultuser/.local/share/icons/distrobox/fedora-distrobox.png
      chmod 755 /home/defaultuser/.local/share/icons/distrobox
      chmod 644 /home/defaultuser/.local/share/applications/niri.desktop
    "
  echo icons-ok
'
```

### 7.4 刷新桌面

```bash
# 重启 Lipstick 刷新桌面（无需注销）
ssh defaultuser@192.168.2.165 "systemctl --user restart lipstick"
```

---

## 8. 验证与测试

### 8.1 Docker 服务验证

```bash
# 检查 docker 服务状态
ssh defaultuser@192.168.2.165 "docker info | head -15"
# 应显示: Client + Server 正常, overlayfs 驱动

# 检查容器状态
ssh defaultuser@192.168.2.165 "docker ps -a --filter name=fedora44"
# 应显示: STATUS: Up

# 检查 defaultuser 权限
ssh defaultuser@192.168.2.165 "docker info 2>&1 | head -3"
# 应显示: Client Version (无 sudo 错误)
```

### 8.2 容器内环境验证

```bash
ssh defaultuser@192.168.2.165 "
  docker exec fedora44 bash -c '
    echo OS: \$(cat /etc/os-release | head -1)
    echo FCITX: \$(fcitx5 --version 2>/dev/null)
    echo NIRI: \$(which niri)
    echo SPLAYER: \$(ls /opt/SPlayer/SPlayer 2>/dev/null)
    echo DBUS: \$(ls /run/user/100000/dbus/user_bus_socket 2>/dev/null)
  '
"
```

### 8.3 桌面图标验证

```bash
# 检查桌面文件
ssh defaultuser@192.168.2.165 "
  ls /usr/share/applications/cn.silisili.native.desktop
  ls /usr/share/applications/harbour-rootitanium.desktop
  ls /usr/share/applications/harbour-storeman.desktop
  ls /home/defaultuser/.local/share/applications/niri.desktop
"

# 检查图标文件
ssh defaultuser@192.168.2.165 "
  ls /usr/share/icons/hicolor/86x86/apps/silisili-native-devel.png
  ls /usr/share/icons/hicolor/86x86/apps/harbour-rootitanium.png
  ls /usr/share/icons/hicolor/86x86/apps/niri.png
"
```

### 8.4 niri 桌面启动验证

```bash
# 在 Sailfish 桌面上点击 niri 图标
# 或手动测试启动
ssh defaultuser@192.168.2.165 "
  docker exec fedora44 sh /home/defaultuser/HOME_Fedora/start-niri-stack.sh
"
```

---

## 9. 故障排查

### 9.1 Docker 服务启动失败

**错误**: `unable to configure the Docker daemon: invalid userland-proxy-path`

**原因**: Sailfish OS 需要禁用 userland-proxy

**解决**:
```bash
# 检查 daemon.json
cat /etc/docker/daemon.json

# 确保包含 "userland-proxy": false
echo '{"registry-mirrors":["https://docker.1ms.run","https://docker.1panel.live"],"userland-proxy":false}' | sudo tee /etc/docker/daemon.json

# 重启 docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 9.2 容器启动失败 (exit code 255)

**错误**: `no such volume`

**原因**: Docker 卷未完整传输

**解决**:
```bash
# 查看缺失的卷
docker inspect fedora44 | grep -A 50 "Mounts"

# 手动创建缺失的卷
docker volume create <volume-id>
docker start fedora44
```

### 9.3 docker info 权限拒绝

**错误**: `Cannot connect to the Docker daemon`

**原因**: 用户不在 docker 组

**解决**:
```bash
sudo groupadd -g 100001 docker 2>/dev/null
sudo usermod -aG docker defaultuser
# 重新登录生效
```

### 9.4 桌面图标不显示

**原因**: 图标文件权限或路径问题

**解决**:
```bash
# 检查图标文件权限（应为 644）
ls -la /usr/share/icons/hicolor/86x86/apps/niri.png
chmod 644 /usr/share/icons/hicolor/86x86/apps/niri.png

# 确保桌面文件权限正确
chmod 644 ~/.local/share/applications/niri.desktop

# 重启 lipstick
systemctl --user restart lipstick
```

### 9.5 rsync 传输卡住

**现象**: rsync 进度不变，日志显示 ir-chk

**原因**: 正在扫描大量小文件（1.2M+），属正常现象

**解决**:
- 等待完成（可能需要 30-60 分钟）
- 如果卡住超过 1 小时，可杀掉 rsync（数据已基本到位）:
```bash
docker exec fedora44 pkill -9 -f "rsync -az"
```

### 9.6 niri 桌面无法启动

**检查步骤**:
```bash
# 检查 niri 日志
docker exec fedora44 cat /tmp/niri.log

# 检查 X 显示号
docker exec fedora44 cat /run/user/100000/xdisplay

# 检查 Wayland socket
docker exec fedora44 ls -la /run/user/100000/wayland-*

# 检查 fcitx5
docker exec fedora44 pgrep -a fcitx5
```

---

## 10. 关键文件清单

### 10.1 Docker 相关

| 文件 | 说明 |
|------|------|
| `/usr/bin/dockerd` | Docker 守护进程 |
| `/usr/bin/docker` | Docker CLI |
| `/usr/bin/containerd` | Containerd |
| `/usr/bin/runc` | OCI 运行时 |
| `/usr/bin/containerd-shim-runc-v2` | 容器 shim |
| `/etc/systemd/system/docker.service` | Systemd 服务文件 |
| `/etc/docker/daemon.json` | Docker 配置 |
| `/var/lib/docker/` | Docker 数据目录 |

### 10.2 用户环境

| 文件 | 说明 |
|------|------|
| `/home/defaultuser/HOME_Fedora/` | Fedora 容器用户目录 |
| `/home/defaultuser/HOME_Fedora/start-niri-stack.sh` | Niri 启动脚本 |
| `/home/defaultuser/HOME_Fedora/.config/niri/config.kdl` | Niri 配置 |
| `/home/defaultuser/HOME_Fedora/.config/fcitx5/` | Fcitx5 配置 |
| `/home/defaultuser/HOME_Fedora/.config/SPlayer/` | SPlayer 配置 |
| `/home/defaultuser/.config/` | 用户全局配置 |
| `/home/defaultuser/bin/` | 用户二进制目录 |

### 10.3 应用

| 文件 | 说明 |
|------|------|
| `/opt/SPlayer/SPlayer` | SPlayer 播放器 |
| `/opt/QQ/qq` | Linux QQ |
| `/home/rootitanium/` | RootTitanium 数据 |

### 10.4 桌面与图标

| 文件 | 说明 |
|------|------|
| `/usr/share/applications/cn.silisili.native.desktop` | Silisili 桌面文件 |
| `/usr/share/applications/harbour-rootitanium.desktop` | RootTitanium 桌面文件 |
| `/usr/share/applications/harbour-storeman.desktop` | Storeman 桌面文件 |
| `/home/defaultuser/.local/share/applications/niri.desktop` | Niri 桌面文件 |
| `/usr/share/icons/hicolor/86x86/apps/silisili-native-devel.png` | Silisili 图标 |
| `/usr/share/icons/hicolor/86x86/apps/harbour-rootitanium.png` | RootTitanium 图标 |
| `/usr/share/icons/hicolor/86x86/apps/niri.png` | Niri 图标 |

### 10.5 系统配置

| 文件 | 说明 |
|------|------|
| `/etc/subuid` | 用户命名空间映射 |
| `/etc/subgid` | 组命名空间映射 |
| `/etc/sudoers.d/defaultuser` | Sudo 配置 |

---

## 附录: 快速迁移脚本

```bash
#!/bin/bash
# 快速迁移脚本（在容器内执行）
# 用法: docker exec fedora44 bash quick-migrate.sh

TARGET_IP="192.168.2.165"
PASSWORD="YOUR_PASSWORD"
SSH="sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no"
SCP="sshpass -p $PASSWORD scp -o StrictHostKeyChecking=no"

echo "=== 1. 传输 Docker 二进制 ==="
for bin in dockerd containerd runc containerd-shim-runc-v2; do
  $SCP /run/host/usr/bin/$bin defaultuser@$TARGET_IP:/tmp/
  $SSH "echo $PASSWORD | sudo -S cp /tmp/$bin /usr/bin/"
done

echo "=== 2. 传输 Docker 配置 ==="
$SCP /run/host/etc/systemd/system/docker.service defaultuser@$TARGET_IP:/tmp/
$SSH "echo $PASSWORD | sudo -S cp /tmp/docker.service /etc/systemd/system/"

echo '{"registry-mirrors":["https://docker.1ms.run","https://docker.1panel.live"],"userland-proxy":false}' | base64 > /tmp/daemon.json.b64
$SCP /tmp/daemon.json.b64 defaultuser@$TARGET_IP:/tmp/
$SSH "echo $PASSWORD | sudo -S bash -c 'base64 -d /tmp/daemon.json.b64 > /etc/docker/daemon.json'"

echo "=== 3. 创建 Docker 组 ==="
$SSH "echo $PASSWORD | sudo -S groupadd -g 100001 docker 2>/dev/null; echo $PASSWORD | sudo -S usermod -aG docker defaultuser"

echo "=== 4. 启动 Docker ==="
$SSH "echo $PASSWORD | sudo -S systemctl daemon-reload && echo $PASSWORD | sudo -S systemctl enable docker && echo $PASSWORD | sudo -S systemctl start docker"

echo "=== 5. rsync Docker 数据 ==="
setsid bash -c "
  rsync -az --info=progress2 \
    -e 'sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no' \
    --rsync-path='sudo rsync' \
    /run/host/var/lib/docker/ \
    defaultuser@$TARGET_IP:/var/lib/docker/
" < /dev/null &

echo "=== 6. 传输用户环境 ==="
$SSH "mkdir -p /home/defaultuser/bin"
rsync -a --rsync-path="sudo rsync" -e "$SSH" /run/host/home/defaultuser/HOME_Fedora/ defaultuser@$TARGET_IP:/home/defaultuser/HOME_Fedora/
rsync -a --rsync-path="sudo rsync" -e "$SSH" /run/host/home/rootitanium/ defaultuser@$TARGET_IP:/home/rootitanium/

echo "=== 7. 传输 distrobox ==="
for f in distrobox distrobox-export distrobox-host-exec distrobox-init; do
  $SCP /run/host/usr/local/bin/$f defaultuser@$TARGET_IP:/tmp/
  $SSH "echo $PASSWORD | sudo -S cp /tmp/$f /usr/local/bin/"
done

echo "=== 完成 ==="
echo "请在目标机执行: docker start fedora44"
```

---

**手册版本**: 1.0
**适用环境**: Sailfish OS 5.1.0.11 (OnePlus 6T)
**最后验证**: 2026-08-21
