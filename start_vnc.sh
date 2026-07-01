#!/bin/bash
set -e

DISPLAY_NUM=1

# 已运行则退出
if pgrep -x Xvnc >/dev/null; then
    echo "TurboVNC is already running."
    exit 0
fi

# 清理残留
rm -f /tmp/.X${DISPLAY_NUM}-lock
rm -f ~/.vnc/*.pid
rm -f ~/.vnc/*.log

# 启动 TurboVNC
/opt/TurboVNC/bin/vncserver :${DISPLAY_NUM} \
    -geometry 1920x1080 \
    -depth 24 \
    -rfbport 5901 \
    -xstartup ~/.vnc/xstartup

echo
echo "TurboVNC Started."
echo "Port: 5901"
