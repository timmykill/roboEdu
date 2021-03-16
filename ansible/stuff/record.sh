#!/bin/sh

TEST=$1
tmux new -s "pulseaudio" -d; 
tmux send-keys 'touch /root/started; su -c "pulseaudio -v" yolo -' C-m ;
tmux new -s "xvfb" -d; 
tmux send-keys "xvfb-run --listen-tcp -s \"-ac -screen 0 1920x1080x24\" su -c \"node /home/yolo/pup/${TEST}.js\" yolo -" C-m;
tmux new -s "ffmpeg" -d; 
tmux send-keys 'su -c "ffmpeg -y -f pulse -ac 2 -i "auto_null.monitor" -framerate 15 -f x11grab -draw_mouse 0 -s 1920x1080 -i :99 -c:v libx265 -crf 35 -preset fast /home/yolo/reg.mkv" yolo -' C-m;
