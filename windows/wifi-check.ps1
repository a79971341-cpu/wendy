<#
  WiFi 진단 + 최적화 (Windows 10/11)
  진단만:   powershell -ExecutionPolicy Bypass -File .\wifi-check.ps1
  고치기:   (관리자 PowerShell) powershell -ExecutionPolicy Bypass -File .\wifi-check.ps1 -Fix
  DNS 변경: ... -Fix -SetDns   (Cloudflare 1.1.1.1 / Google 8.8.8.8 로 변경)
#>
param([switch]$Fix, [switch]$SetDns)

$ErrorActionPreference = 'SilentlyContinue'
$problems = @()
function Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Bad($t)  { Write-Host "  [문제] $t" -ForegroundColor Yellow; $script:problems += $t }
function Ok($t)   { Write-Host "  [정상] $t" -ForegroundColor Green }

# ---------- 1. 무선 연결 상태 ----------
Head "1. 무선 연결 상태"
$raw = netsh wlan show interfaces
function Field($name) { ($raw | Select-String "^\s*$name\s*:" | Select-Object -First 1) -replace '^[^:]+:\s*','' }
$ssid = Field 'SSID'; $signal = Field 'Signal'; $radio = Field 'Radio type'
$chan = Field 'Channel'; $rx = Field 'Receive rate \(Mbps\)'; $tx = Field 'Transmit rate \(Mbps\)'
$band = Field 'Band'
if (-not $ssid) { # 한국어 Windows
  $ssid = Field 'SSID'; $signal = Field '신호'; $radio = Field '라디오 유형'
  $chan = Field '채널'; $rx = Field '수신 속도\(Mbps\)'; $tx = Field '전송 속도 \(Mbps\)'; $band = Field '대역'
}
Write-Host "  SSID=$ssid  신호=$signal  규격=$radio  대역=$band  채널=$chan  수신=${rx}Mbps 송신=${tx}Mbps"
$sig = [int]($signal -replace '[^0-9]','')
if ($sig -gt 0 -and $sig -lt 60) { Bad "신호가 약함($sig%). 공유기 가까이 가거나 벽/전자레인지/어항 같은 장애물을 피하세요." }
elseif ($sig -ge 60) { Ok "신호 세기 $sig%" }
if ([int]$chan -ge 1 -and [int]$chan -le 14) { Bad "2.4GHz(채널 $chan) 사용 중. 공유기의 5GHz 와이파이(이름에 5G 붙은 것)로 바꾸면 보통 훨씬 빠름." }
if ($radio -match '802\.11[bgn]$') { Bad "구형 규격($radio). 공유기/랜카드가 오래됐을 수 있음." }

# ---------- 2. 주변 채널 혼잡도 ----------
Head "2. 주변 와이파이 채널 혼잡도"
$nets = netsh wlan show networks mode=bssid
$chs = $nets | Select-String '^\s*(Channel|채널)\s*:' | ForEach-Object { [int](($_ -replace '^[^:]+:\s*','').Trim()) }
$chs | Group-Object | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { Write-Host "  채널 $($_.Name): 공유기 $($_.Count)개" }
$same = ($chs | Where-Object { $_ -eq [int]$chan }).Count - 1
if ($same -ge 3) { Bad "내 채널($chan)에 다른 공유기 $same개가 겹침. 공유기 설정에서 채널을 '자동' 또는 덜 붐비는 채널(2.4GHz면 1/6/11 중 하나)로 바꾸세요." }
else { Ok "채널 혼잡 심하지 않음" }

# ---------- 3. 지연/손실 ----------
Head "3. 핑 (공유기 / 인터넷)"
$gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop
foreach ($t in @(@{n='공유기';h=$gw}, @{n='인터넷(1.1.1.1)';h='1.1.1.1'})) {
  if (-not $t.h) { continue }
  $r = Test-Connection -ComputerName $t.h -Count 10
  $loss = 10 - @($r).Count
  $avg = [math]::Round((@($r) | Measure-Object -Property ResponseTime -Average).Average, 1)
  Write-Host "  $($t.n) $($t.h): 평균 ${avg}ms, 손실 $loss/10"
  if ($t.n -eq '공유기' -and ($avg -gt 20 -or $loss -gt 0)) { Bad "공유기까지 지연 ${avg}ms/손실 $loss — 와이파이 구간 자체가 문제(신호/간섭/공유기)." }
  if ($t.n -ne '공유기' -and $avg -gt 80) { Bad "인터넷 지연 ${avg}ms — 회선/통신사 쪽 또는 누군가 대역폭을 많이 쓰는 중." }
}

# ---------- 4. DNS ----------
Head "4. DNS 응답 속도"
$dnsSrv = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | Select-Object -First 1).ServerAddresses -join ', '
$sw = [Diagnostics.Stopwatch]::StartNew(); Resolve-DnsName "example-$(Get-Random).com" -DnsOnly -QuickTimeout | Out-Null; $sw.Stop()
Write-Host "  현재 DNS: $dnsSrv   조회 시간: $($sw.ElapsedMilliseconds)ms"
if ($sw.ElapsedMilliseconds -gt 150) { Bad "DNS가 느림($($sw.ElapsedMilliseconds)ms). -Fix -SetDns 로 1.1.1.1 / 8.8.8.8 사용 권장." } else { Ok "DNS 빠름" }

# ---------- 5. 대역폭 잡아먹는 것들 ----------
Head "5. 네트워크 많이 쓰는 프로그램 (연결 수 기준)"
Get-NetTCPConnection -State Established | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object {
  $p = Get-Process -Id $_.Name; Write-Host ("  {0,-28} 연결 {1}" -f $p.ProcessName, $_.Count)
}
$hogs = 'OneDrive','Dropbox','GoogleDriveFS','steam','EpicGamesLauncher','qbittorrent','uTorrent','BitTorrent','Battle.net','iCloudDrive','MicrosoftEdgeUpdate'
$running = Get-Process | Where-Object { $hogs -contains $_.ProcessName } | Select-Object -ExpandProperty ProcessName -Unique
if ($running) { Bad "백그라운드 동기화/다운로드 프로그램 실행 중: $($running -join ', ') — 동기화 일시중지/다운로드 중지하면 빨라짐." }
if ((Get-Service wuauserv).Status -eq 'Running' -and (Get-Service DoSvc).Status -eq 'Running') { Write-Host "  (Windows 업데이트/전송 최적화 서비스 동작 중 — 업데이트 다운로드 중이면 느려질 수 있음)" }

# ---------- 6. VPN / 절전 ----------
Head "6. VPN · 절전 설정"
$vpn = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'VPN|TAP|WireGuard|Tunnel|Fortinet|Cisco AnyConnect' }
if ($vpn) { Bad "VPN 켜져 있음: $($vpn.Name -join ', ') — VPN은 속도를 크게 떨어뜨릴 수 있음." } else { Ok "VPN 없음" }
$wifi = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.Name -match 'Wi-?Fi|무선') } | Select-Object -First 1
if ($wifi) {
  $pm = Get-NetAdapterPowerManagement -Name $wifi.Name
  if ($pm.AllowComputerToTurnOffDevice -eq 'Enabled') { Bad "무선랜 어댑터 절전 켜짐 — 끊김/느려짐 원인. -Fix 로 끔." } else { Ok "어댑터 절전 꺼짐" }
}
$auto = (netsh int tcp show global) | Select-String 'Receive Window Auto-Tuning Level|수신 창 자동 조정 수준'
if ($auto -and $auto -notmatch 'normal') { Bad "TCP 자동 조정이 normal 아님: $auto" }

# ---------- 고치기 ----------
if ($Fix) {
  Head "자동 수정"
  if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Write-Host "  관리자 권한 PowerShell에서 다시 실행하세요." -ForegroundColor Red; exit 1 }
  ipconfig /flushdns | Out-Null; Write-Host "  DNS 캐시 비움"
  netsh int tcp set global autotuninglevel=normal | Out-Null; Write-Host "  TCP 자동 조정 = normal"
  if ($wifi) {
    Disable-NetAdapterPowerManagement -Name $wifi.Name -NoRestart | Out-Null; Write-Host "  무선랜 절전 끔"
    if ($SetDns) { Set-DnsClientServerAddress -InterfaceAlias $wifi.Name -ServerAddresses '1.1.1.1','8.8.8.8'; Write-Host "  DNS -> 1.1.1.1, 8.8.8.8 (되돌리기: Set-DnsClientServerAddress -InterfaceAlias '$($wifi.Name)' -ResetServerAddresses)" }
  }
  powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
  powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
  powercfg /setactive SCHEME_CURRENT; Write-Host "  전원 옵션: 무선 어댑터 '최대 성능'"
  # 업데이트를 다른 PC에 업로드하는 것 끄기 (LAN 내 공유만 허용)
  New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Force | Out-Null
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name DODownloadMode -Value 1 -Type DWord
  Write-Host "  Windows 업데이트 인터넷 P2P 업로드 끔"
  Write-Host "  와이파이 재연결 중..."; if ($wifi) { Restart-NetAdapter -Name $wifi.Name }
}

Head "요약"
if ($problems.Count -eq 0) { Write-Host "  PC 쪽 문제는 안 보임. 그래도 느리면 공유기 재부팅 / 통신사 회선 점검." -ForegroundColor Green }
else { $problems | ForEach-Object { Write-Host "  - $_" } ; if (-not $Fix) { Write-Host "`n  관리자 PowerShell에서 -Fix 붙여 실행하면 PC 쪽 설정은 자동으로 고칩니다." } }
