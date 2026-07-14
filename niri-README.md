# fedora-gpu2 桌面环境维护说明

这个目录是 `distrobox` 容器 `fedora-gpu2` 的 HOME：

```bash
/home/defaultuser/DIST-HOME-GPU2
```

当前重点目标是：在 Sailfish/Android 宿主上，通过 `distrobox` 跑 Fedora 图形桌面、软键盘、Chromium/Firefox、3D GPU、音频和基础输入。

重要边界：

- 目标容器是 `fedora-gpu2`，不是 droidspaces 的 Fedora rootfs。
- 进入容器时用：

  ```bash
  distrobox enter fedora-gpu2 -- bash -lc '...'
  ```

- 需要容器 root 时用 Docker：

  ```bash
  docker exec -u root fedora-gpu2 bash -lc '...'
  ```

- 下载慢时可以临时带代理：

  ```bash
  export http_proxy=http://192.168.2.209:7897
  export https_proxy=http://192.168.2.209:7897
  ```

- 不要把 `/home/defaultuser/Downloads/droidspaces-fedora44/rootfs` 当成这个容器的 rootfs 去修改。当前只借用了其中的 Sailfish 兼容 `Xwayland` 二进制作为嵌套显示后端。

## 当前状态

已完成：

- `fedora-gpu2` 容器能启动嵌套 niri 桌面。
- 软键盘 `wvkbd-mobintl` 会随桌面启动。
- 触屏点击和软键盘输入通过桥接脚本转发，当前可用。
- Chromium wrapper 已接入 KGSL/Turnip/ANGLE Vulkan，`chrome://gpu` 能看到 Adreno/Turnip 3D GPU。
- Chromium 和 ALSA/PulseAudio 音频已打通到 Droid 硬件输出。
- 容器网络当前可访问 `https://cn.bing.com` 和 `https://www.bilibili.com`。

未完成 / 当前限制：

- Chromium 的视频硬解码和硬编码还没有真正打通。
- 强行打开视频 flags 只能让 `chrome://gpu` 显示 `enabled`，但 `videoDecoding=[]`、`videoEncoding=[]`，没有实际 codec profile，所以不要把这些 flags 写进正式 wrapper。
- VAAPI 路径缺少 msm/kgsl/freedreno 视频驱动。
- V4L2 Venus 设备存在，但这个 msm_vidc 驱动只接受 `USERPTR`，常规 Chromium/FFmpeg V4L2 m2m 路径需要的 `MMAP/DMABUF` 不可用。

## 入口和常用命令

宿主桌面入口：

```text
/home/defaultuser/.local/share/applications/fedora-gpu2.desktop
```

其中实际执行：

```bash
/usr/bin/distrobox enter fedora-gpu2 -- bash /home/defaultuser/DIST-HOME-GPU2/start-niri.sh
```

`start-niri.sh` 只做一件事：

```bash
exec "$HOME/.local/bin/fedora-gpu2-niri-session" start
```

查看容器：

```bash
distrobox ls
```

进入容器：

```bash
distrobox enter fedora-gpu2
```

从宿主执行容器命令：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'id; echo "$HOME"'
```

容器 root：

```bash
docker exec -u root fedora-gpu2 bash -lc 'dnf -y install 包名'
```

## 目录结构

关键路径：

```text
DIST-HOME-GPU2/
├── README.md
├── start-niri.sh
├── .asoundrc
├── .config/
│   ├── niri/config.kdl
│   ├── pulse/client.conf
│   └── chromium-fedora-gpu2/
├── .local/
│   ├── bin/
│   │   ├── chromium-browser
│   │   ├── fedora-gpu2-chromium
│   │   ├── fedora-gpu2-chromium-gpu-launcher
│   │   ├── fedora-gpu2-niri-session
│   │   ├── fedora-gpu2-touch-click-bridge
│   │   ├── fedora-gpu2-wvkbd
│   │   └── wvkbd-mobintl
│   ├── lib/fedora-gpu2/
│   │   ├── libfedora_gpu2_legacy_ion_ioctl.so
│   │   └── libfedora_gpu2_v4l2_m2m_cap_shim.so
│   ├── src/
│   │   ├── fedora_gpu2_legacy_ion_ioctl.c
│   │   ├── fedora_gpu2_v4l2_m2m_cap_shim.c
│   │   ├── v4l2_venus_reqbufs_probe.c
│   │   └── ion_abi_probe.c
│   └── state/fedora-gpu2-niri/
│       ├── niri.log
│       ├── xwayland.log
│       ├── wvkbd.log
│       ├── touch-click-bridge.log
│       └── chromium-*.log
└── wvkbd/
```

## niri 桌面

主脚本：

```text
~/.local/bin/fedora-gpu2-niri-session
```

配置：

```text
~/.config/niri/config.kdl
```

状态和日志：

```text
~/.local/state/fedora-gpu2-niri/niri.log
~/.local/state/fedora-gpu2-niri/xwayland.log
```

运行状态：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-niri-session status'
```

重启桌面：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-niri-session restart'
```

停止桌面：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-niri-session stop'
```

查看日志：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-niri-session logs'
```

### 显示架构

当前桌面是嵌套跑法：

```text
宿主 Wayland
  -> Sailfish 兼容 Xwayland，默认 display :9
    -> niri winit/X11 backend
      -> niri 内部 Wayland socket
        -> Chromium / foot / wvkbd 等 Wayland 应用
```

`fedora-gpu2-niri-session` 会：

1. 启动兼容 Xwayland。
2. 通过 X11/winit 启动 niri。
3. 把外层 niri 窗口 resize 到手机竖屏尺寸。
4. 启动软键盘。
5. 启动触屏/软键盘桥接脚本。

默认尺寸：

```bash
FEDORA_GPU2_NIRI_WIDTH=1080
FEDORA_GPU2_NIRI_HEIGHT=2340
FEDORA_GPU2_WVKBD_HEIGHT=480
```

### 可调环境变量

```bash
FEDORA_GPU2_NIRI_XDISPLAY=9
FEDORA_GPU2_PARENT_WAYLAND=../../display/wayland-0
FEDORA_GPU2_COMPAT_XWAYLAND=/home/defaultuser/Downloads/droidspaces-fedora44/rootfs/opt/bin/Xwayland.sfos
FEDORA_GPU2_NIRI_EGL_DIR=$HOME/.local/lib/niri-mesa-egl
FEDORA_GPU2_NIRI_WIDTH=1080
FEDORA_GPU2_NIRI_HEIGHT=2340
```

## 输入、触屏和软键盘

当前软键盘是：

```text
~/.local/bin/wvkbd-mobintl
```

启动器：

```text
~/.local/bin/fedora-gpu2-wvkbd
```

日志：

```text
~/.local/state/fedora-gpu2-niri/wvkbd.log
```

手动重启软键盘：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-wvkbd restart'
```

查看软键盘状态：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-wvkbd status'
```

### 为什么有 touch-click bridge

之前的现象是：

- `xeyes` 能跟随触屏移动，说明 pointer motion 有了。
- 但触屏点击 Firefox/Chromium/软键盘没有反应。
- `xvkbd` 的输入只进自己的面板，Firefox/Chromium 收不到。
- 复合键如 Ctrl+T、Alt+T 对普通软键盘也不可靠。

当前解决办法：

```text
~/.local/bin/fedora-gpu2-touch-click-bridge
```

它在外层 Xwayland display 上跑：

```bash
xinput test-xi2 --root
```

然后根据触屏坐标做两类转发：

- 非键盘区域：用 `xdotool mousemove ... click 1` 转成真实鼠标点击。
- 底部键盘区域：按坐标映射成按键，再用 `wtype` 发到 niri 内部 Wayland。

日志：

```text
~/.local/state/fedora-gpu2-niri/touch-click-bridge.log
```

手动重启：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-touch-click-bridge restart'
```

查看状态：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-touch-click-bridge status'
```

### 软键盘修饰键行为

当前桥接脚本里 Shift / Ctrl / Alt 是“一次性 armed modifier”：

- 点 Ctrl 后，下一次按键带 Ctrl。
- 点 Alt 后，下一次按键带 Alt。
- 点 Shift 后，下一次按键带 Shift。

桥接脚本里专门处理了一批 niri 全局快捷键，因为普通虚拟键盘事件不一定能可靠触发 compositor-level shortcut。

当前重点快捷键：

```text
Ctrl+T      打开 foot 终端
Alt+T       打开 foot 终端
Alt+D       打开 fuzzel
Alt+O       niri overview
Alt+Q       关闭窗口
Alt+Left    聚焦左侧 column
Alt+Right   聚焦右侧 column
Alt+Up      聚焦上方窗口
Alt+Down    聚焦下方窗口
Alt+H/J/K/L 同方向聚焦
Alt+U/I     工作区上下切换
Alt+1..9    切换工作区
Alt+F       maximize-column
Alt+M       maximize-window-to-edges
Alt+V       toggle-window-floating
Alt+W       toggle-column-tabbed-display
Alt+R       switch-preset-column-width
Alt+Shift+/ 显示 niri hotkey overlay
```

niri 配置里也保留了直接快捷键：

```text
Mod+T  打开 foot
Ctrl+T 打开 foot
F12    打开 foot
```

但对触屏软键盘来说，实际更可靠的是桥接脚本里的 Ctrl/Alt 逻辑。

## 浏览器

### Chromium

入口：

```text
~/.local/bin/chromium-browser
```

它会转到：

```text
~/.local/bin/fedora-gpu2-chromium
```

默认打开：

```text
https://www.bilibili.com
```

手动打开：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-chromium https://www.bilibili.com'
```

Chromium profile：

```text
~/.config/chromium-fedora-gpu2
```

可用环境变量：

```bash
FEDORA_GPU2_CHROMIUM_PROFILE=$HOME/.config/chromium-fedora-gpu2
FEDORA_GPU2_CHROMIUM_BIN=/bin/chromium-browser
```

### Chromium GPU 参数

当前有效的 3D 组合是：

```text
--use-gl=angle
--use-angle=vulkan
```

不要改成：

```text
--use-gl=egl-angle
```

Fedora Chromium 当前不接受这个值。

wrapper 还设置：

```bash
MESA_LOADER_DRIVER_OVERRIDE=kgsl
FD_FORCE_KGSL=1
LIBGL_DRIVERS_PATH=/usr/lib64/dri
GBM_BACKENDS_PATH=/usr/lib64/gbm
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
EGL_PLATFORM=surfaceless
```

GPU process 通过 launcher 继承同样环境：

```text
~/.local/bin/fedora-gpu2-chromium-gpu-launcher
```

### ION shim

OnePlus 6T / hybris 4.9 kernel 暴露的是 legacy ION。当前 Chromium/GBM 路径需要 shim：

```text
~/.local/lib/fedora-gpu2/libfedora_gpu2_legacy_ion_ioctl.so
~/.local/src/fedora_gpu2_legacy_ion_ioctl.c
```

Chromium wrapper 会自动把它加入 `LD_PRELOAD`。

### GPU 当前验证结果

`chrome://gpu` 可看到类似：

```text
ANGLE (Qualcomm, Vulkan ... Turnip Adreno (TM) 630 ...)
```

已验证 3D GPU 状态：

```text
gpu_compositing = enabled
opengl = enabled_on
rasterization = enabled_force
vulkan = enabled_on
webgl = enabled
webgpu = enabled
```

注意：日志里可能仍出现：

```text
'--ozone-platform=wayland' is not compatible with Vulkan.
```

但当前 3D 仍然可用。

### Firefox

Firefox 已安装：

```bash
firefox --version
```

但当前 GPU/桌面调试主要围绕 Chromium wrapper 做。Firefox 若要继承同样音频环境，可以从 niri session 内启动，或显式带：

```bash
PULSE_SERVER=/run/user/100000/pulse/native PULSE_SINK=sink.deep_buffer firefox
```

## 网络

当前容器用户：

```text
uid=100000(defaultuser)
groups includes: video, audio, input, render, input_dev, netdev, inet
```

已验证容器内可以访问：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'curl -I -L https://cn.bing.com'
distrobox enter fedora-gpu2 -- bash -lc 'curl -I -L https://www.bilibili.com'
```

两者当前都返回 HTTP 200。

如果以后网页无法访问，先查：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
id
cat /etc/resolv.conf
curl -I -L https://cn.bing.com
curl -I -L https://www.bilibili.com
'
```

如果只是下载慢，临时用代理：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
export http_proxy=http://192.168.2.209:7897
export https_proxy=http://192.168.2.209:7897
dnf -y install 包名
'
```

需要 `dnf` 安装包时通常要 root：

```bash
docker exec -u root fedora-gpu2 bash -lc '
export http_proxy=http://192.168.2.209:7897
export https_proxy=http://192.168.2.209:7897
dnf -y install 包名
'
```

## 音频

当前宿主有 PulseAudio：

```text
/run/user/100000/pulse/native
```

容器已 bind mount 到同一路径。

问题点：

- 宿主 PulseAudio 的全局 default sink 是 `sink.null`。
- 所以容器应用如果不指定输出，声音可能被打到空设备。
- Fedora 容器里原本 ALSA default 指向 PipeWire，但容器内没有 PipeWire server，`aplay` 会报 `Host is down`。

已做配置：

```text
~/.config/pulse/client.conf
~/.asoundrc
```

PulseAudio client 默认：

```text
default-server = unix:/run/user/100000/pulse/native
default-sink = sink.deep_buffer
default-source = source.droid
autospawn = no
```

ALSA default：

```text
pcm.!default { type pulse }
ctl.!default { type pulse }
```

已安装包：

```text
pulseaudio-utils
alsa-plugins-pulseaudio
alsa-utils
```

桌面 session 和 Chromium wrapper 也显式设置：

```bash
PULSE_SERVER=/run/user/100000/pulse/native
PULSE_SINK=sink.deep_buffer
PULSE_SOURCE=source.droid
```

可调环境变量：

```bash
FEDORA_GPU2_PULSE_SERVER=/run/user/100000/pulse/native
FEDORA_GPU2_PULSE_SINK=sink.deep_buffer
FEDORA_GPU2_PULSE_SOURCE=source.droid
```

### 音频测试

PulseAudio 播放：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'paplay /usr/share/sounds/alsa/Front_Center.wav'
```

ALSA 播放：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'aplay /usr/share/sounds/alsa/Front_Center.wav'
```

录音连通性，不保存内容：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'timeout 3 parec --channels=1 --rate=48000 --format=s16le >/dev/null'
```

播放时查看 sink：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
pactl list short sink-inputs
pactl list short sinks
'
```

预期播放时：

```text
sink.deep_buffer    RUNNING
```

录音时查看 source：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
pactl list short source-outputs
pactl list short sources
'
```

预期录音时：

```text
source.droid    RUNNING
```

## 视频硬解码 / 硬编码状态

当前结论：没有真正打通，不要把视频 flags 写入正式 Chromium wrapper。

### VAAPI

`vainfo` 失败原因：

```text
Trying to open /usr/lib64/dri/msm_drm_drv_video.so
va_openDriver() returns -1
```

Fedora/Mesa 当前没有 msm/kgsl/freedreno 的 VAAPI video driver。`mesa-dri-drivers` 里有：

```text
radeonsi_drv_video.so
r600_drv_video.so
nouveau_drv_video.so
d3d12_drv_video.so
virtio_gpu_drv_video.so
```

但没有：

```text
msm_drm_drv_video.so
kgsl_drv_video.so
freedreno_drv_video.so
```

试过 `libva-v4l2-request`，它是 V4L2 request API 方向，不适合当前 msm_vidc stateful Venus 设备；测试后已移除。

### V4L2 Venus 设备

设备存在：

```text
/dev/video/venus_dec -> ../video32
/dev/video/venus_enc -> ../video33
/dev/media0
/dev/media1
```

decoder：

```text
/dev/video32
driver: msm_vidc_driver
card:   msm_vidc_vdec
OUTPUT compressed: MPG2, H264, HEVC, VP80, VP90
CAPTURE raw:       NV12, QP10, Q128, Q12A
```

encoder：

```text
/dev/video33
driver: msm_vidc_driver
card:   msm_vidc_venc
OUTPUT raw:        NV12, Q128, RGB4, NV21, Q12A, QP10
CAPTURE compressed:H264, VP80, HEVC, TME0
```

V4L2 shim：

```text
~/.local/lib/fedora-gpu2/libfedora_gpu2_v4l2_m2m_cap_shim.so
~/.local/src/fedora_gpu2_v4l2_m2m_cap_shim.c
```

它做了两件事：

- 对 `msm_vidc_driver` 的 `VIDIOC_QUERYCAP` 补 `V4L2_CAP_VIDEO_M2M_MPLANE`。
- 对 `VIDIOC_TRY_FMT` 返回 `ENOTTY` 的情况，如果格式确实在对应 queue 的 `VIDIOC_ENUM_FMT` 里存在，就返回成功。

这能让 FFmpeg/Chromium 多走几步，但不能解决 buffer memory type 不兼容。

### FFmpeg 当前问题

VP8 decode 能找到 `/dev/video32`，但失败在：

```text
output VIDIOC_REQBUFS failed: Invalid argument
no v4l2 output context's buffers
```

H264 encode 能找到 `/dev/video33`，但失败在：

```text
can't set v4l2 output format
```

`v4l2_venus_reqbufs_probe` 结论：

```text
V4L2_MEMORY_MMAP   -> EINVAL
V4L2_MEMORY_DMABUF -> EINVAL
V4L2_MEMORY_USERPTR -> OK
```

也就是说，当前 Venus 驱动只接受 `USERPTR`。标准 FFmpeg V4L2 m2m 路径固定走 `MMAP`，所以不能直接用。

Probe：

```text
~/.local/src/v4l2_venus_reqbufs_probe
~/.local/src/v4l2_venus_reqbufs_probe.c
```

运行：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/src/v4l2_venus_reqbufs_probe'
```

### Chromium 当前问题

正常 wrapper 的 `SystemInfo.getInfo`：

```text
video_decode = disabled_software
video_encode = disabled_software
videoDecoding = []
videoEncoding = []
```

强行加 V4L2/VAAPI flags + V4L2 shim + `--no-sandbox`：

```text
video_decode = enabled
video_encode = enabled
videoDecoding = []
videoEncoding = []
```

也就是 UI 状态会变成 enabled，但没有任何实际 profile。

Chromium 日志能看到 V4L2 枚举，例如：

```text
EnumerateSupportedProfilesForV4L2Codec(): Unsupported codec: MPG2
EnumerateSupportedProfilesForV4L2Codec(): Unsupported codec: HEVC
...
```

但最后没有形成可用 `videoDecoding` / `videoEncoding`。

保留日志：

```text
~/.local/state/fedora-gpu2-niri/chromium-sysinfo-baseline.log
~/.local/state/fedora-gpu2-niri/chromium-sysinfo-forced.log
~/.local/state/fedora-gpu2-niri/video-tests/
```

### 后续真正可行方向

优先级建议：

1. 先 patch FFmpeg 或 GStreamer，让 V4L2 m2m 对 msm_vidc 使用 `USERPTR`，确认 Venus 硬解/硬编能在命令行或播放器里跑通。
2. 再考虑 Chromium。Chromium 可能需要 patch V4L2 后端，或者实现/移植适配 msm_vidc 的 VAAPI/V4L2 bridge。

不要做：

- 不要只为了 `chrome://gpu` 好看，把强行视频 flags 写进正式 wrapper。
- 不要把 `video_decode=enabled` 但 `videoDecoding=[]` 当成硬解成功。

## 已安装/用到的关键包

容器里当前关键包包括：

```text
niri
chromium
firefox
foot
fuzzel
xrandr
xinput
xdotool
wtype
pulseaudio-utils
alsa-utils
alsa-plugins-pulseaudio
mesa-dri-drivers
mesa-vulkan-drivers
vulkan-tools
libva-utils
ffmpeg-free
v4l-utils
```

检查：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
rpm -qa | sort | grep -Ei "niri|chromium|firefox|foot|fuzzel|xrandr|xinput|xdotool|wtype|pulseaudio|alsa|mesa|vulkan|libva|ffmpeg|v4l2"
'
```

## 常用排障

### 桌面没起来

```bash
distrobox enter fedora-gpu2 -- bash -lc '
$HOME/.local/bin/fedora-gpu2-niri-session status
$HOME/.local/bin/fedora-gpu2-niri-session logs
'
```

关键日志：

```text
~/.local/state/fedora-gpu2-niri/xwayland.log
~/.local/state/fedora-gpu2-niri/niri.log
```

### 触屏不能点击

先看 bridge：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
$HOME/.local/bin/fedora-gpu2-touch-click-bridge status
tail -120 $HOME/.local/state/fedora-gpu2-niri/touch-click-bridge.log
'
```

确认依赖：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
command -v xinput
command -v xdotool
command -v wtype
'
```

外层 X display 默认：

```text
:9
```

检查：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'DISPLAY=:9 xinput list'
```

### 软键盘不见了

```bash
distrobox enter fedora-gpu2 -- bash -lc '
$HOME/.local/bin/fedora-gpu2-wvkbd restart
$HOME/.local/bin/fedora-gpu2-wvkbd status
tail -120 $HOME/.local/state/fedora-gpu2-niri/wvkbd.log
'
```

如果键位和竖屏坐标不准，先检查尺寸：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'DISPLAY=:9 xrandr --query'
```

当前 bridge 默认按 `1080x2340` 和键盘高度 `480` 做坐标分区。

### Chromium 没打开页面

从容器里手动启动：

```bash
distrobox enter fedora-gpu2 -- bash -lc '$HOME/.local/bin/fedora-gpu2-chromium https://www.bilibili.com'
```

如果页面网络失败：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
curl -I -L https://cn.bing.com
curl -I -L https://www.bilibili.com
'
```

### Chromium 没声音

先确认网页正在播放，再查 sink-input：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
pactl list short sink-inputs
pactl list short sinks
pactl info
'
```

预期：

```text
sink.deep_buffer RUNNING
```

如果只看到 `sink.null`，说明应用没有继承当前 Pulse 配置或环境变量。重启 Chromium：

```bash
distrobox enter fedora-gpu2 -- bash -lc 'pkill -u "$(id -u)" -x chromium-browser 2>/dev/null || true'
```

然后从 wrapper 再打开。

### `aplay` 报 Host is down

说明 ALSA 还在走 PipeWire。检查：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
rpm -q alsa-plugins-pulseaudio
cat ~/.asoundrc
aplay -L | sed -n "1,80p"
'
```

应有：

```text
pcm.!default { type pulse }
ctl.!default { type pulse }
```

### GPU 变成软件渲染

检查 Chromium wrapper 是否仍有这些环境变量：

```bash
distrobox enter fedora-gpu2 -- bash -lc '
grep -nE "MESA_LOADER_DRIVER_OVERRIDE|FD_FORCE_KGSL|VK_ICD_FILENAMES|use-angle|gpu-launcher|legacy_ion" \
  $HOME/.local/bin/fedora-gpu2-chromium
'
```

检查 `chrome://gpu`：

```text
GL_RENDERER 应该包含 ANGLE / Qualcomm / Turnip / Adreno 630
```

### 视频硬解不要误判

正确判断必须同时看：

```text
featureStatus.video_decode
featureStatus.video_encode
videoDecoding
videoEncoding
```

如果只是：

```text
video_decode = enabled
video_encode = enabled
videoDecoding = []
videoEncoding = []
```

那仍然没有硬解/硬编 profile。

## 修改原则

1. 改 `fedora-gpu2` 时优先改：

   ```text
   /home/defaultuser/DIST-HOME-GPU2
   ```

2. 不要误改 droidspaces rootfs。
3. 不要全局改宿主 PulseAudio default sink，当前只在容器 client 侧指定 `sink.deep_buffer`。
4. Chromium 视频 flags 不要为了显示 enabled 而持久化。
5. 已有 shim 和 probe 源码都放在 `~/.local/src`，二进制/so 放在 `~/.local/lib/fedora-gpu2`。
6. 如果要调包，用 `docker exec -u root fedora-gpu2 ...`，因为 host 没有 sudo，`distrobox enter --root` 不可用。

