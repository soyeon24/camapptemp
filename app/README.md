# camtest — Pi 5 자세 화면

`display/atlas/app`(`com.atlas.app.deskmate_display`) · `display/atlas/keystroke`
옆에 두는 세 번째 Atlas Flutter 앱이다. 앱 ID 가 `com.atlas.app.camtest` 로 달라
Pi 5 에 셋을 나란히 설치해 비교할 수 있다.

ESP32-CAM 이 보는 사람을 **지금 앉아 있는지 · 자세가 무너졌는지** 두 가지로만
크게 보여준다.

```text
ESP32-CAM ──UART──> RP2040 브리지 ──USB CDC──> Pi 4 (판정)
                                                 │
                                    HTTP :8765 /api/state ──1Hz──> Pi 5 (이 앱)
```

**판정은 이 앱이 하지 않는다.** 마스크에서 자세를 가르는 쪽은 Pi 4 에서 도는
[`espcam_with_decision`](https://github.com/soyeon24/espcam_with_decision) 의
`pi/deskmate_posture` 이고(로컬 작업 트리 `C:\school\26summer\swcontest\pico_esp32-cam_ftdi`),
이 앱은 그 노드가 1초에 한 번 내는 `/api/state` 를 읽어 그리기만 한다. 판정을
Pi 4 에 둔 이유는 ATLAS 에 Python 런타임이 없어 numpy 판정부(561줄)를 C++/Dart 로
다시 써야 하기 때문이다(2026-09-17 결정).

## 먼저 Pi 4 노드를 띄운다

```bash
# Pi 4
cd pi
python -m deskmate_posture --list             # 어느 포트인지 확인
python -m deskmate_posture                    # --broker 없이도 /api/state 는 나간다
curl http://localhost:8765/api/state          # 이 앱이 읽는 바로 그 응답
```

노드가 없으면 이 앱은 **화면 내장 데모**로 돈다(바른 자세 → 엎드림 → 졸음 →
뒤로 젖힘 → 자리 비움 → 기준 측정 중 순환, 헤더에 `DEMO · 실데이터 아님`).

## 빌드와 배포

절차와 스크립트는 [../deploy/README.md](../deploy/README.md) 를 따른다.
`deploy/device.env` 에서 두 줄만 이 앱으로 돌리면 된다.

```ini
ATLAS_APP_DIR=display/atlas/camtest
ATLAS_HUB_URL=http://<Pi4-IP>:8765
```

```powershell
.\display\atlas\scripts\pi-deploy.ps1                                  # device.env 기본 대상
.\display\atlas\scripts\pi-deploy.ps1 -AppDir display/atlas/camtest    # 한 번만 바꿔 쓸 때
```

컨테이너에서 직접 빌드할 때는 다음과 같다. `ATLAS_HUB_URL` 은 배포 스크립트가
`--dart-define=DESKMATE_HUB_URL` 로 넘기는 값이라 이름을 그대로 쓴다 — 여기서는
허브가 아니라 **자세 노드**의 주소지만, 두 API 모양이 같아 정의를 나누지 않았다.

```bash
source "$ATLAS_FLUTTER_NDK_ENV"
cd /workspace/display/atlas/camtest
flutter pub get
flutter test
flutter-atlas build atlas --ipk --release \
  --dart-define=DESKMATE_HUB_URL=http://<Pi4-IP>:8765
```

## 화면

| 자리 | 보여주는 것 |
|---|---|
| 착석 배지 | `착석 중` · `자리 비움` — 제일 먼저 답해야 하는 질문 |
| 가운데 원 | 바른 자세 · 엎드림 · 뒤로 젖힘 · 졸음 · 자리 비움 · 기준 측정 중 |
| 지표 넷 | 머리 거리(기준 대비, − 가까움) · 꾸벅임(회/분) · 움직임 · 화면 점유 |
| 막대 둘 | 집중 저하 · 피로 — 허브 `Signal(phi, delta)` 로 그대로 들어가는 값 |
| 근거 칩 | 판정이 실제로 본 축(`reasons`). 모르는 코드는 그대로 보여준다 |
| 상단 경고 | 연결 실패 · 센서 링크 끊김 · 갱신 정지 · 기준 측정 중 |
| `기준 다시 잡기` | `POST /api/calibrate`. Pi 4 에는 SPACE 를 눌러 줄 사람이 없다 |

경고 줄을 따로 둔 이유가 있다. **끊긴 링크는 살아 있는 링크와 똑같이 보인다** —
마지막 프레임이 계속 재발행되므로 `/api/state` 만 보면 화면이 멀쩡해 보인다.
그래서 `/health` 를 5초에 한 번 따로 읽어 `stale` · `link_error` 를 확인한다.

`valid` 가 내려간 동안(기준 측정 중이거나 프레임이 묵었을 때)에는 판정을 믿지
말라고 화면이 먼저 말한다. 이걸 안 보면 캘리브레이션 30초가 통째로 '바른 자세'로
읽힌다.

## 이름을 바꿀 때

앱 이름 · ID 는 세 곳에 있고 서로 맞아야 한다.

- `pubspec.yaml` 의 `name`
- `atlas/CMakeLists.txt` 의 `ATLAS_APP_ID` 와 `BINARY_NAME`
- `atlas/meta/appinfo.json` 의 `id` · `name` · `entry`

`BINARY_NAME` 이 `appinfo.json` 의 `entry` 첫 토큰과 다르면 설치는 되지만
실행되지 않는다.

## 나중에 MQTT 로 바꿀 때

자세 노드는 `deskmate/sensor/tof/<node>` 로도 같은 판정을 낸다(`--broker <허브-IP>`).
옮길 자리는 [`lib/posture_source.dart`](lib/posture_source.dart) 하나다 —
`PostureSource` 를 구현한 `MqttPostureSource` 를 더하고 `main.dart` 의 소스 선택만
바꾸면 화면 코드는 그대로다. 그때는 `mqtt_client` 의존이 생기므로 옆 앱
`display/atlas/app/pubspec.yaml` 과 같은 `10.5.1` 로 고정한다(Atlas 의 Dart 3.6.2
상한).

## 아직 확인 안 된 것

- **이 PC 에는 Flutter 가 없어 `flutter test` 를 못 돌렸다.** 컨테이너에서 한 번
  돌려야 한다.
- 실기기 확인 전이다. Pi 4 노드 자체도 아직 보드를 꽂은 상태로 돌린 적이 없다
  (`pi/README.md` "아직 확인 안 된 것").
- 카메라를 쓰는 경로다. 팀 `CLAUDE.md` 의 "카메라·마이크 미사용" 원칙과 어긋나므로
  대회 제출물에 넣을지는 팀 결정이 필요하다. 전송되는 것은 사진이 아니라 마스크지만,
  영상 센서인 것은 맞다.
