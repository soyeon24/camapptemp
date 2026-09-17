# camtest — DESKMATE 자세 화면 (Pi 5 / ATLAS)

ESP32-CAM 이 보는 사람을 **지금 앉아 있는지 · 자세가 무너졌는지** 두 가지로 크게
보여주는 Atlas Flutter 앱이다. 앱 ID 는 `com.atlas.app.camtest` 로, 보드에 이미 깔린
다른 DESKMATE 앱들과 **나란히 설치**된다(기존 앱을 지우지 않는다).

내 노트북에서 보드로 SSH 가 닿지 않아(공유기 격리로 보임) **설치만 대신 해 줄 사람에게
넘기려고 만든 임시 레포**다. 원본은 팀 모노레포의 `display/atlas/camtest` 다.

```text
ESP32-CAM ──UART──> RP2040 브리지 ──USB CDC──> Pi 4 (판정) ──HTTP :8765──> Pi 5 (이 앱)
```

## 설치 — 개발 환경 필요 없음

`ssh` 와 `scp` 만 있으면 된다. 이 레포를 통째로 받아서(Code → Download ZIP) 풀고,
`.ipk` 와 스크립트가 있는 폴더에서 보드 IP 만 주면 끝이다.

macOS · Linux · WSL · Git Bash:

```bash
bash install-to-pi.sh <보드IP>
```

Windows PowerShell:

```powershell
.\install-to-pi.ps1 -Ip <보드IP>
```

업로드 → 이전 버전 제거 → 설치 → 실행까지 한 번에 한다. 보드 IP 는 공유기 DHCP
목록이나 보드 콘솔의 `ip -br addr` 로 확인한다.

| 자주 쓰는 옵션 | bash | PowerShell |
|---|---|---|
| 설치만 하고 실행 안 함 | `NO_START=1` | `-NoStart` |
| SSH 키 지정 | `SSH_KEY=<경로>` | `-SshKey <경로>` |
| 계정 · 포트 | `BOARD_USER=` · `BOARD_PORT=` | `-BoardUser` · `-Port` |

설치 후 확인:

```bash
ssh root@<보드IP> 'abusctl call com.atlas.AppManager1 ListRunningApps'
```

## 이 `.ipk` 는 데모 빌드다

Pi 4 주소(`DESKMATE_HUB_URL`)를 넣지 않고 구웠다. 보드에 올리면 화면 내장 데모가
순환하고(바른 자세 → 엎드림 → 졸음 → 뒤로 젖힘 → 자리 비움 → 기준 측정 중) 헤더에
`DEMO · 실데이터 아님` 이 붙는다. **먼저 화면이 뜨는지만 보려는 목적이다.**

Pi 4 자세 노드에 실제로 붙이려면 그 주소를 박아서 다시 구워야 한다.

## 직접 빌드하려면

Atlas 개발 컨테이너 안에서:

```bash
cd app
flutter pub get
flutter test
flutter-atlas build atlas --ipk --release --dart-define=DESKMATE_HUB_URL=http://<Pi4-IP>:8765
```

산출물은 `app/build/atlas/arm64/release/ipk/com.atlas.app.camtest.ipk` 다.
Flutter 3.27.4(Dart 3.6.2) 기준이고, 의존성은 Flutter SDK 밖에 없다.

앱 이름·ID 는 세 곳이 서로 맞아야 한다 — `pubspec.yaml` 의 `name`,
`atlas/CMakeLists.txt` 의 `ATLAS_APP_ID`·`BINARY_NAME`, `atlas/meta/appinfo.json` 의
`id`·`name`·`entry`. `BINARY_NAME` 이 `entry` 첫 토큰과 다르면 **설치는 되는데 실행만
안 된다.**

## 검증 상태

Atlas 컨테이너(Flutter 3.27.4)에서 확인했다.

- `flutter analyze` — No issues found
- `flutter test` — 20개 통과
- release `.ipk` 생성, 패키지 안의 실행 파일 이름이 `entry` 첫 토큰과 일치

**실기기에서는 아직 안 돌려봤다.** 보드에 올려 본 것은 이번이 처음이다.

화면 구성과 데이터 계약은 [`app/README.md`](app/README.md) 에 있다.
