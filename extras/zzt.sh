#!/bin/sh
# zzt.sh - 郑大校园网多线路【临时测试】工具（ip/udhcpc，不写 UCI，易清理）
# 用独立 MAC 建 macvlan -> DHCP 拿新校园网 IP（= 新"设备/会话"），
# 每条线各用独立路由表 + `from <ip>` 策略路由，绝不改动主表（电信线不受影响）。
#
#   zzt.sh up   <name> <table>            建接口并拿 IP（如 up wt1 211）
#   zzt.sh down <name> <table>            拆除
#   zzt.sh login  <ip> <account> <isp> <password>
#   zzt.sh logout <ip>
#   zzt.sh status <ip>                    查在线状态（原始 JSON）
#   zzt.sh ip <name>                      打印该接口当前 IP
GW=10.172.255.254
PAR=wan
BASE=172.16.4.14
CIDR=10.172.0.0/16

b64(){ S="$1" awk 'BEGIN{
  s=ENVIRON["S"]; for(i=0;i<256;i++)O[sprintf("%c",i)]=i
  b="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  n=length(s); o=""
  for(i=1;i<=n;i+=3){c1=O[substr(s,i,1)];c2=(i+1<=n)?O[substr(s,i+1,1)]:0;c3=(i+2<=n)?O[substr(s,i+2,1)]:0
    o=o substr(b,int(c1/4)+1,1) substr(b,(int(c1%4)*16+int(c2/16))+1,1)
    o=o ((i+1<=n)?substr(b,(int(c2%16)*4+int(c3/64))+1,1):"=")
    o=o ((i+2<=n)?substr(b,(c3%64)+1,1):"=")}
  printf "%s",o }'; }
urlenc(){ S="$1" awk 'BEGIN{
  s=ENVIRON["S"]; for(i=0;i<256;i++)O[sprintf("%c",i)]=i
  h="0123456789ABCDEF"; n=length(s); o=""
  for(i=1;i<=n;i++){c=substr(s,i,1)
    if(c ~ /[A-Za-z0-9._~-]/){o=o c}
    else{v=O[c];o=o "%" substr(h,int(v/16)+1,1) substr(h,(v%16)+1,1)}}
  printf "%s",o }'; }
suffix(){ case "$1" in cmcc)echo @cmcc;; unicom)echo @unicom;; telecom)echo @telecom;; zzuplan)echo @zzuplan;; *)echo "";; esac; }
ifip(){ ip -4 -br addr show dev "$1" 2>/dev/null | awk '{print $3}' | cut -d/ -f1; }

up(){
  name=$1; tbl=$2
  mac=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-10 | sed 's/\(..\)/\1:/g; s/:$//')
  mac="02:$mac"
  ip link del "$name" 2>/dev/null
  ip link add "$name" link "$PAR" type macvlan mode bridge || return 1
  ip link set "$name" address "$mac"
  ip link set "$name" up
  for k in arp_ignore arp_announce rp_filter; do :; done
  sysctl -qw net.ipv4.conf.$name.arp_ignore=1 2>/dev/null
  sysctl -qw net.ipv4.conf.$name.arp_announce=2 2>/dev/null
  sysctl -qw net.ipv4.conf.$name.rp_filter=2 2>/dev/null
  cat > /tmp/zzt-dhcp.sh <<'EOS'
#!/bin/sh
[ "$1" = bound ] || [ "$1" = renew ] || exit 0
ip addr flush dev "$interface" 2>/dev/null
ip addr add "$ip/16" dev "$interface"
echo "$ip" > /tmp/zzt-ip-$interface
EOS
  chmod +x /tmp/zzt-dhcp.sh
  # -n 尝试一次失败即退出；-q 拿到即退出；自定义脚本只配 IP 不动路由
  udhcpc -i "$name" -n -q -f -t 8 -T 2 -s /tmp/zzt-dhcp.sh >/tmp/zzt-$name.log 2>&1
  myip=$(ifip "$name")
  [ -z "$myip" ] && { echo "FAIL: no IP for $name"; cat /tmp/zzt-$name.log; return 1; }
  ip route replace default via "$GW" dev "$name" table "$tbl"
  ip route replace "$CIDR" dev "$name" scope link src "$myip" table "$tbl"
  ip rule del from "$myip" 2>/dev/null
  ip rule add from "$myip" lookup "$tbl" priority $((11000+tbl))
  echo "UP $name ip=$myip mac=$mac table=$tbl"
}

down(){
  name=$1; tbl=$2; myip=$(ifip "$name")
  [ -n "$myip" ] && ip rule del from "$myip" 2>/dev/null
  ip route flush table "$tbl" 2>/dev/null
  ip link del "$name" 2>/dev/null
  rm -f /tmp/zzt-ip-$name
  echo "DOWN $name"
}

login(){
  ip=$1; acc=$2; isp=$3; pw=$4
  a=$(urlenc ",0,${acc}$(suffix "$isp")")
  p=$(urlenc "$(b64 "$pw")")
  curl -s --max-time 8 --interface "$ip" -e "http://$BASE/" \
    "http://$BASE:801/eportal/portal/login?user_account=${a}&user_password=${p}"
  echo
}
logout(){ curl -s --max-time 8 --interface "$1" -e "http://$BASE/" "http://$BASE:801/eportal/portal/logout"; echo; }
status(){ curl -s --max-time 8 --interface "$1" -e "http://$BASE/" "http://$BASE:801/eportal/portal/custom"; echo; }

cmd=$1; shift 2>/dev/null
case "$cmd" in
  up) up "$@";; down) down "$@";;
  login) login "$@";; logout) logout "$@";; status) status "$@";;
  ip) ifip "$@";;
  *) echo "usage: zzt.sh {up|down|login|logout|status|ip} ...";;
esac
