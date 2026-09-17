# camtest — DESKMATE 자세 화면 (Pi 5 / ATLAS)

ESP32-CAM 이 보는 사람을 **지금 앉아 있는지 · 자세가 무너졌는지** 두 가지로 크게
보여주는 Atlas Flutter 앱이다. 앱 ID 는 `com.atlas.app.camtest` 로, 보드에 이미 깔린
다른 DESKMATE 앱들과 **나란히 설치**된다(기존 앱을 지우지 않는다).

내 노트북에서 보드로 SSH 가 닿지 않아(보드는 172.16.34.x 유선망, 노트북은 다른 Wi-Fi)
**설치만 대신 해 줄 사람에게 넘기려고 만든 임시 레포**다. 원본은 팀 모노레포의
`display/atlas/camtest` 다.

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

업로드 → 이전 버전 제거 → 설치 → 실행까지 한 번에 한다.

설치 후 확인:

```bash
ssh root@<보드IP> 'abusctl call com.atlas.AppManager1 ListRunningApps'
```

## 주소는 보드 화면에서 넣는다 (0.2.0)

헤더의 **톱니 버튼 → 숫자 키패드**로 Pi 4 자세 노드의 IP 를 찍고 `저장` 하면 즉시 그
주소를 보기 시작하고, 다음에 켤 때도 그 주소를 쓴다. `데모로` 를 누르면 지우고 화면
내장 데모로 돌아간다.

**키보드가 필요 없다.** 보드에 USB 키보드가 꽂혀 있으리라 가정할 수 없고 Flutter
eLinux 에는 화면 키보드가 없어서 `TextField` 대신 키패드를 직접 그렸다. 그래서 IPv4 만
받고 포트는 `8765` 고정이다.

이 화면이 생기기 전에는 주소를 빌드에 박아야 해서, Pi 4 의 DHCP 주소가 바뀔 때마다
다시 굽고 설치를 다시 부탁해야 했다. **이제 그 왕복이 없다.**

주소 우선순위는 **보드에 저장된 값 → 빌드에 박은 `DESKMATE_HUB_URL` → 데모** 순이다.

## 이 `.ipk` 를 그냥 깔면 데모로 뜬다

주소를 안 박고 구웠기 때문이다. 화면이 상태를 혼자 순환하고(바른 자세 → 엎드림 →
졸음 → 뒤로 젖힘 → 자리 비움 → 기준 측정 중) 헤더에 `DEMO · 실데이터 아님` 이 붙는다.

**실제 자세를 보려면** Pi 4 쪽이 먼저 떠 있어야 한다.

1. ESP32-CAM + RP2040 브리지를 Pi 4 에 USB 로 연결
2. Pi 4 에서 자세 노드 실행 — `python -m deskmate_posture`
3. 보드 화면 톱니 버튼 → Pi 4 의 IP 입력 → 저장

그러면 데모 배지가 사라지고 실제 판정이 올라온다. 캘리브레이션(자리 비켜 주기 8초 →
앉기 10초)은 노드가 알아서 진행하고, 남은 초가 화면 문구로 나온다.

## 직접 빌드하려면

Atlas 개발 컨테이너 안에서:

```bash
cd app
flutter pub get
flutter test
flutter-atlas build atlas --ipk --release
```

산출물은 `app/build/atlas/arm64/release/ipk/com.atlas.app.camtest.ipk` 다.
Flutter 3.27.4(Dart 3.6.2) 기준이고 의존성은 Flutter SDK 밖에 없다. 주소를 공장
기본값으로 박고 싶으면 `--dart-define=DESKMATE_HUB_URL=http://<Pi4-IP>:8765` 를 붙인다.

앱 이름·ID 는 세 곳이 서로 맞아야 한다 — `pubspec.yaml` 의 `name`,
`atlas/CMakeLists.txt` 의 `ATLAS_APP_ID`·`BINARY_NAME`, `atlas/meta/appinfo.json` 의
`id`·`name`·`entry`. `BINARY_NAME` 이 `entry` 첫 토큰과 다르면 **설치는 되는데 실행만
안 된다.**

## 검증 상태

Atlas 컨테이너(Flutter 3.27.4)에서 확인했다.

- `flutter analyze` — No issues found
- `flutter test` — **34개 통과**
- release `.ipk` 생성, 패키지 안의 실행 파일 이름이 `entry` 첫 토큰과 일치

**실기기에서 실제 센서로는 아직 안 돌려봤다.** Pi 4 자세 노드 자체가 보드를 꽂은
상태로 돌아간 적이 없다. 보드 화면이 뜨는 것까지는 확인됐다(0.1.1, 데모).

화면 구성과 데이터 계약은 [`app/README.md`](app/README.md) 에 있다.
