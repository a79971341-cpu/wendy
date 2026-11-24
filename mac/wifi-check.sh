#!/bin/bash
# WiFi 진단 + 최적화 (macOS)
#   진단만:   bash wifi-check.sh
#   고치기:   bash wifi-check.sh --fix          (sudo 비밀번호 물어봄)
#   DNS 변경: bash wifi-check.sh --fix --dns    (1.1.1.1 / 8.8.8.8)
FIX=0; DNS=0
for a in "$@"; do [ "$a" = "--fix" ] && FIX=1; [ "$a" = "--dns" ] && DNS=1; done
P=()
head(){ printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }
bad(){ printf "  \033[33m[문제]\033[0m %s\n" "$1"; P+=("$1"); }
ok(){ printf "  \033[32m[정상]\033[0m %s\n" "$1"; }

IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
SVC=$(networksetup -listallhardwareports | awk -F': ' '/Hardware Port: Wi-Fi/{print $2}')

head "1. 무선 연결 상태"
INFO=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{f=1;next} f&&/Other Local Wi-Fi Networks:/{exit} f')
CH=$(echo "$INFO" | awk -F': ' '/Channel:/{print $2; exit}')
SN=$(echo "$INFO" | awk -F': ' '/Signal \/ Noise:/{print $2; exit}')
PHY=$(echo "$INFO" | awk -F': ' '/PHY Mode:/{print $2; exit}')
RATE=$(echo "$INFO" | awk -F': ' '/Transmit Rate:/{print $2; exit}')
echo "  채널=$CH  신호/잡음=$SN  규격=$PHY  전송속도=${RATE}Mbps"
RSSI=$(echo "$SN" | grep -oE '^-?[0-9]+'); NOISE=$(echo "$SN" | grep -oE '/ -?[0-9]+' | grep -oE '-?[0-9]+')
if [ -n "$RSSI" ]; then
  if [ "$RSSI" -lt -70 ]; then bad "신호 약함(${RSSI}dBm). 공유기 가까이 / 장애물 제거."; else ok "신호 ${RSSI}dBm"; fi
  [ -n "$NOISE" ] && [ $((RSSI - NOISE)) -lt 25 ] && bad "신호 대비 잡음이 큼(SNR $((RSSI-NOISE))dB) — 간섭 심함."
fi
echo "$CH" | grep -q '2GHz' && bad "2.4GHz 사용 중. 5GHz 와이파이로 바꾸면 보통 훨씬 빠름."

head "2. 주변 채널 혼잡도"
OTHERS=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Other Local Wi-Fi Networks:/{f=1} f&&/Channel:/{print $2}')
echo "$OTHERS" | sort | uniq -c | sort -rn | head -6 | awk '{print "  채널 "$2": 공유기 "$1"개"}'
MYCH=$(echo "$CH" | awk '{print $1}')
SAME=$(echo "$OTHERS" | grep -cx "$MYCH")
[ "$SAME" -ge 3 ] && bad "내 채널($MYCH)에 공유기 ${SAME}개 겹침 — 공유기 채널을 자동/덜 붐비는 채널로." || ok "채널 혼잡 심하지 않음"

head "3. 핑 (공유기 / 인터넷)"
GW=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')
for h in "$GW" 1.1.1.1; do
  [ -z "$h" ] && continue
  R=$(ping -c 10 -q "$h" 2>/dev/null)
  LOSS=$(echo "$R" | grep -oE '[0-9.]+% packet loss' | cut -d% -f1)
  AVG=$(echo "$R" | awk -F'/' '/round-trip/{print $5}')
  echo "  $h: 평균 ${AVG}ms, 손실 ${LOSS}%"
  if [ "$h" = "$GW" ]; then awk "BEGIN{exit !($AVG>20 || $LOSS>0)}" && bad "공유기까지 지연/손실 — 와이파이 구간 문제."
  else awk "BEGIN{exit !($AVG>80)}" && bad "인터넷 지연 ${AVG}ms — 회선 또는 대역폭 점유."; fi
done

head "4. DNS 응답 속도"
echo "  현재 DNS: $(scutil --dns | awk '/nameserver\[0\]/{print $3}' | sort -u | tr '\n' ' ')"
T0=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000'); dscacheutil -q host -a name "test-$RANDOM.example.com" >/dev/null; T1=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
echo "  조회 시간: $((T1-T0))ms"
[ $((T1-T0)) -gt 150 ] && bad "DNS 느림 — --fix --dns 로 1.1.1.1/8.8.8.8 권장." || ok "DNS 빠름"

head "5. 네트워크 많이 쓰는 프로그램"
nettop -P -L 1 -J bytes_in,bytes_out -x 2>/dev/null | tail -n +2 | awk -F, '{t=$2+$3; if(t>0) printf "%d,%s\n", t, $1}' | sort -t, -k1 -rn | head -8 | awk -F, '{printf "  %-35s %.1f MB\n", $2, $1/1048576}'
for p in Dropbox OneDrive "Google Drive" Steam "Epic Games" qbittorrent Transmission bird cloudd softwareupdated; do
  pgrep -qf "$p" && RUN="$RUN $p"
done
[ -n "$RUN" ] && echo "  (동작 중인 동기화/다운로드 계열:$RUN — 큰 동기화/업데이트 중이면 느려짐)"

head "6. VPN"
if scutil --nc list 2>/dev/null | grep -q Connected || ifconfig | grep -qE '^utun[4-9]'; then bad "VPN/터널 켜져 있을 수 있음 — 끄고 비교해 보세요."; else ok "VPN 없음"; fi

if command -v networkQuality >/dev/null; then head "7. 실제 속도 측정"; networkQuality -s 2>/dev/null | grep -E 'Uplink|Downlink|Responsiveness'; fi

if [ $FIX -eq 1 ]; then
  head "자동 수정"
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; echo "  DNS 캐시 비움"
  if [ $DNS -eq 1 ]; then sudo networksetup -setdnsservers "$SVC" 1.1.1.1 8.8.8.8; echo "  DNS -> 1.1.1.1, 8.8.8.8 (되돌리기: sudo networksetup -setdnsservers \"$SVC\" Empty)"; fi
  echo "  와이파이 껐다 켜는 중..."; networksetup -setairportpower "$IF" off; sleep 2; networksetup -setairportpower "$IF" on
fi

head "요약"
if [ ${#P[@]} -eq 0 ]; then echo "  Mac 쪽 문제는 안 보임. 그래도 느리면 공유기 재부팅 / 통신사 회선 점검."
else for x in "${P[@]}"; do echo "  - $x"; done; [ $FIX -eq 0 ] && echo -e "\n  --fix 붙여 실행하면 Mac 쪽 설정은 자동으로 고칩니다."; fi
