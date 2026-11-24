# 와이파이 느린 원인 찾기 + 빠르게 하기

## Windows
1. 시작 메뉴에서 **PowerShell** 우클릭 → **관리자 권한으로 실행**
2. 이 폴더로 이동한 뒤:
   ```powershell
   # 1) 진단만 (아무것도 안 바꿈)
   powershell -ExecutionPolicy Bypass -File .\windows\wifi-check.ps1
   # 2) PC 설정 자동 수정
   powershell -ExecutionPolicy Bypass -File .\windows\wifi-check.ps1 -Fix
   # 3) DNS도 빠른 걸로 변경
   powershell -ExecutionPolicy Bypass -File .\windows\wifi-check.ps1 -Fix -SetDns
   ```

## Mac
```bash
bash mac/wifi-check.sh              # 진단만
bash mac/wifi-check.sh --fix        # 자동 수정
bash mac/wifi-check.sh --fix --dns  # + DNS 변경
```

## 무엇을 확인하나
| 항목 | 느려지는 이유 |
|---|---|
| 신호 세기 | 멀거나 벽·전자레인지 때문에 약함 |
| 2.4GHz / 5GHz | 2.4GHz는 느리고 간섭이 많음 |
| 채널 혼잡 | 이웃 공유기와 같은 채널을 쓰면 서로 방해 |
| 공유기까지 핑 | 와이파이 구간 문제인지, 통신사 회선 문제인지 구분 |
| DNS | 사이트가 뜨기 전에 오래 멈칫하는 원인 |
| 대역폭 많이 쓰는 앱 | OneDrive·Dropbox·Steam·토렌트·업데이트 |
| VPN | 모든 트래픽이 돌아가서 느려짐 |
| 어댑터 절전 (Windows) | 끊김과 속도 저하 |

## 자동 수정 (`-Fix` / `--fix`)
- DNS 캐시 비우기
- (Windows) 무선랜 절전 끄기, 전원 옵션 최대 성능, TCP 자동 조정 normal, 업데이트를 인터넷 P2P로 업로드하는 기능 끄기
- (선택) DNS를 1.1.1.1 / 8.8.8.8로 변경 (되돌리는 명령도 출력함)
- 와이파이 재연결

## 스크립트로 못 하는 것 (직접 해야 함)
- **공유기 재부팅**: 전원을 뽑고 30초 기다린 뒤 다시 꽂기
- **5GHz로 연결**: 이름에 `5G`가 붙은 와이파이 선택
- **공유기 채널 변경**: 공유기 관리 페이지(보통 192.168.0.1 또는 192.168.1.1)에서 채널을 자동이나 덜 붐비는 채널로
- **공유기 위치**: 집 가운데, 높은 곳, 바닥이나 장 속은 피하기
- **공유기 펌웨어 업데이트**, 너무 오래된 공유기(802.11n 이하)는 교체 고려
