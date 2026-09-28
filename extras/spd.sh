#!/bin/sh
# spd.sh - 多流并发下载测速（绑定源IP），measured ON router.
#   spd.sh one  <ip> <streams> <secs> <tag>
#   spd.sh pair <ipA> <ipB> <streams_each> <secs>   # 同时压两条线，分别汇总
URL="http://dldir1.qq.com/weixin/Windows/WeChatSetup.exe"
UA="Mozilla/5.0"

burst(){ ip=$1; n=$2; t=$3; tag=$4
  rm -f /tmp/sp-$tag-* 2>/dev/null
  i=0
  while [ "$i" -lt "$n" ]; do
    curl -o /dev/null -sL --interface "$ip" --max-time "$t" -A "$UA" -w '%{speed_download}\n' "$URL" > /tmp/sp-$tag-$i 2>&1 &
    i=$((i+1))
  done
}
sumtag(){ tag=$1; label=$2
  cat /tmp/sp-$tag-* 2>/dev/null | awk -v L="$label" '{s+=$1;c++} END{printf "%-10s %8.1f Mbps  (%.1f MB/s, %d streams)\n", L, s*8/1e6, s/1e6, c}'
}

case "$1" in
  one)
    burst "$2" "$3" "$4" a; wait
    sumtag a "$5"
    ;;
  pair)
    burst "$2" "$4" "$5" A
    burst "$3" "$4" "$5" B
    wait
    sumtag A "lineA"
    sumtag B "lineB"
    cat /tmp/sp-A-* /tmp/sp-B-* 2>/dev/null | awk '{s+=$1} END{printf "%-10s %8.1f Mbps  (%.1f MB/s)\n","TOTAL",s*8/1e6,s/1e6}'
    ;;
esac
