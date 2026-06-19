#!/usr/bin/env bash
export USER="${USER:-ubuntu}"
export HOME="${HOME:-/home/ubuntu}"

VNC_GEOMETRY=${VNC_RESOLUTION:-1280x720}
VNC_DEPTH=${VNC_COL_DEPTH:-24}
VNC_PORT=${VNC_PORT:-5901}
NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_PASSWORD=${VNC_PASSWORD:-novnc}

# Kill any leftover VNC lock from a previous run
vncserver -kill :1 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

mkdir -p "$HOME/.vnc" /tmp/runtime-ubuntu
chmod 700 /tmp/runtime-ubuntu
touch "$HOME/.Xresources"

printf '%s' "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

cat > "$HOME/.vnc/xstartup" <<'EOF'
#!/usr/bin/env bash
export XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources" 2>/dev/null
exec dbus-launch --exit-with-session startxfce4
EOF
chmod +x "$HOME/.vnc/xstartup"

# Start VNC
vncserver :1 -geometry "$VNC_GEOMETRY" -depth "$VNC_DEPTH" -rfbport "$VNC_PORT"

# Wait for VNC to be ready
for i in $(seq 1 15); do
    ss -tlnp 2>/dev/null | grep -q "$VNC_PORT" && break
    sleep 1
done

# Find websockify
WS=""
for candidate in /usr/bin/websockify /usr/local/bin/websockify; do
    [[ -x "$candidate" ]] && WS="$candidate" && break
done
[[ -z "$WS" ]] && WS="python3 -m websockify"

# Start websockify in background
nohup $WS --web=/usr/share/novnc/ "$NOVNC_PORT" localhost:"$VNC_PORT" >> /tmp/novnc.log 2>&1 &

echo "Lab desktop ready on port $NOVNC_PORT"

# Fetch key from API, decrypt .v.enc → tmpfs (/home/ubuntu/labs), re-encrypt on save.
# Logs go to /tmp/lab-crypto.log — visible to root, not ubuntu, for debugging.
nohup /usr/local/bin/decrypt_watch.sh >> /tmp/lab-crypto.log 2>&1 &

# Keep container alive
exec tail -f /dev/null
