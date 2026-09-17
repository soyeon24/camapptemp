// DESKMATE — 자세 화면 (ATLAS Flutter)
//
// ESP32-CAM(마스크) → RP2040 브리지 → Pi 4 `deskmate_posture`(판정) → 이 화면.
//
// **이 앱은 판정하지 않는다.** Pi 4 가 1Hz 로 내는 `/api/state` 를 읽어
// "지금 앉아 있는지"와 "자세가 무너졌는지"만 크게 보여준다. 판정을 Pi 4 에 둔
// 이유는 ATLAS 에 Python 런타임이 없어서 numpy 판정부를 통째로 다시 써야 하기
// 때문이다(2026-09-17 결정).
//
// 옆 앱: `display/atlas/app`(허브 FSM 대시보드) · `display/atlas/keystroke`(국면).
// 앱 ID 가 서로 달라 Pi 5 에 셋을 나란히 설치해 비교할 수 있다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'posture_source.dart';
import 'posture_state.dart';

/// 배포 스크립트(`deploy/device.env` 의 `ATLAS_HUB_URL`)가 그대로 넘겨주는 값.
/// 여기서는 허브가 아니라 **Pi 4 자세 노드**의 주소다 — 두 API 모양이 같아서
/// 이름을 그대로 쓴다. 비어 있으면 화면 내장 데모가 돈다.
const _hubUrl = String.fromEnvironment('DESKMATE_HUB_URL');

void main() => runApp(const PostureApp());

const _bg = Color(0xFF0F1420);
const _surface = Color(0xFF171D2B);
const _line = Color(0xFF2A3348);
const _ink = Color(0xFFE8ECF4);
const _muted = Color(0xFF9AA6BD);
const _dim = Color(0xFF5A667E);

const _green = Color(0xFF37D0A0);
const _amber = Color(0xFFF5B455);
const _red = Color(0xFFFF7A7A);
const _blue = Color(0xFF5E9BFF);
const _violet = Color(0xFFB98BFF);
const _gray = Color(0xFF8A93A6);

class PostureLook {
  const PostureLook(this.ko, this.en, this.color, this.icon, this.desc);
  final String ko;
  final String en;
  final Color color;
  final IconData icon;
  final String desc;
}

/// 라벨별 화면 표현. 한국어 이름은 노드의 `LABEL_TEXT` 와 같은 말을 쓴다 —
/// 같은 상태를 Pi 4 로그와 Pi 5 화면이 다르게 부르면 시연 중에 못 맞춘다.
const kPostureLook = <PostureLabel, PostureLook>{
  PostureLabel.upright: PostureLook('바른 자세', 'UPRIGHT', _green,
      Icons.airline_seat_recline_normal, '좋아요. 지금 자세를 그대로 유지해 주세요'),
  PostureLabel.slump: PostureLook('엎드림', 'SLUMP', _red, Icons.airline_seat_flat,
      '머리가 기준보다 내려간 채로 이어지고 있어요'),
  PostureLabel.recline: PostureLook('뒤로 젖힘', 'RECLINE', _amber,
      Icons.airline_seat_recline_extra, '센서에서 멀어졌어요. 책상 쪽으로 다시 앉아 보세요'),
  PostureLabel.drowsy: PostureLook('졸음', 'DROWSY', _violet, Icons.bedtime_outlined,
      '머리가 반복해서 끄덕이고 있어요. 잠깐 쉬어 가는 건 어때요?'),
  PostureLabel.absent: PostureLook('자리 비움', 'ABSENT', _gray,
      Icons.person_off_outlined, '책상 앞에 사람이 없어요'),
  PostureLabel.baseline: PostureLook('기준 측정 중', 'BASELINE', _blue,
      Icons.straighten, '바른 자세 기준을 재고 있어요'),
  PostureLabel.unknown: PostureLook('기준 없음', 'UNKNOWN', _gray,
      Icons.help_outline, '아직 판정할 기준이 없어요'),
};

/// 노드가 보내는 근거 코드 → 사람이 읽는 한국어.
///
/// 코드는 `envelope.py` 의 `reasons_for()` 와 `posture.py` 의 `note` 에서 온다.
/// 숫자가 붙어 오는 것들은 접두사로 잘라 읽고, 모르는 코드는 **그대로 보여준다** —
/// 안 보여주면 판정이 왜 그렇게 나왔는지 화면에서 확인할 길이 없어진다.
const kReasonLabel = <String, String>{
  'posture_only': '자세 신호만 사용',
  'head_dropped_and_held': '머리가 내려간 채 유지',
  'moved_away_from_sensor': '센서에서 멀어짐',
  'desk_empty': '책상이 비어 있음',
  'low occupancy': '사람이 거의 안 잡힘',
  'no baseline': '기준 없음',
  'baseline clipped - press b': '기준 프레임이 잘렸어요 · 기준 다시 잡기',
};

String reasonLabel(String raw) {
  final known = kReasonLabel[raw];
  if (known != null) return known;
  if (raw.startsWith('nods_per_min_')) {
    return '꾸벅임 ${raw.substring('nods_per_min_'.length)}회/분';
  }
  if (raw.startsWith('head_width_ratio_')) {
    return '머리 크기 비 ${raw.substring('head_width_ratio_'.length)}';
  }
  if (raw.startsWith('background ')) {
    return '배경 측정 ${raw.substring('background '.length)}';
  }
  if (raw.startsWith('posture ')) {
    return '자세 기준 ${raw.substring('posture '.length)}';
  }
  return raw;
}

class PostureApp extends StatelessWidget {
  const PostureApp({super.key, this.source});

  /// 테스트에서 가짜 소스를 꽂는 자리. 비우면 빌드 시 준 주소를 따른다.
  final PostureSource? source;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DESKMATE 자세',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: _bg,
        ),
        home: PostureScreen(source: source),
      );
}

class PostureScreen extends StatefulWidget {
  const PostureScreen({super.key, this.source});
  final PostureSource? source;

  @override
  State<PostureScreen> createState() => _PostureScreenState();
}

class _PostureScreenState extends State<PostureScreen> {
  late final PostureSource _source;
  Timer? _timer;
  PostureState? _state;
  LinkHealth? _health;
  String? _error;
  bool _busy = false;
  bool _calibrating = false;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _source = widget.source ??
        (_hubUrl.trim().isEmpty
            ? DemoPostureSource()
            : HttpPostureSource(_hubUrl.trim()));
    _refresh();
    // 노드도 1Hz 로 내보낸다. 더 자주 긁어도 새 값이 없다.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _source.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    // 응답이 느려지면 폴링이 서로를 밀어낸다. 한 번에 하나만 보낸다.
    if (_busy) return;
    _busy = true;
    try {
      final state = await _source.fetch();
      if (mounted) {
        setState(() {
          _state = state;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _busy = false;
    }
    // 링크 상태는 5초에 한 번이면 충분하다. 판정과 같은 주기로 긁으면 요청만
    // 두 배가 되고, 이 값은 그렇게 빨리 바뀌지 않는다.
    if (_ticks++ % 5 != 0) return;
    final health = await _source.health();
    if (mounted) setState(() => _health = health);
  }

  String _message(Object error) {
    if (error is SocketException) return '자세 노드에 연결하지 못했습니다';
    if (error is TimeoutException) return '자세 노드가 응답하지 않습니다';
    if (error is FormatException) return '알 수 없는 형식의 응답입니다';
    if (error is HttpException) return error.message;
    return error.toString();
  }

  Future<void> _calibrate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('기준을 다시 잡을까요?'),
        content: const Text('먼저 자리에서 비켜 주세요. 빈 책상을 재고 나면 화면이 '
            '"바른 자세로 앉아 주세요" 로 바뀝니다. 전부 20초쯤 걸립니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              key: const ValueKey('calibrate-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('다시 잡기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _calibrating = true);
    try {
      await _source.calibrate();
      _notify('기준을 다시 잡습니다 — 화면 안내를 따라 주세요');
    } catch (error) {
      _notify('기준 다시 잡기에 실패했습니다: ${_message(error)}');
    } finally {
      if (mounted) setState(() => _calibrating = false);
    }
  }

  void _notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final look = kPostureLook[state?.label ?? PostureLabel.unknown]!;
    final now = DateTime.now();
    final note = _note(state, now);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.45),
            radius: 1.2,
            colors: [look.color.withValues(alpha: .16), _bg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(state),
                if (note != null) ...[
                  const SizedBox(height: 12),
                  _noteBar(note),
                ],
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: state == null ? _loading() : _body(state, look),
                    ),
                  ),
                ),
                _footer(state, now),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(PostureState? state) => Row(children: [
        const Icon(Icons.chair_alt, color: _green, size: 22),
        const SizedBox(width: 8),
        const Text('DESKMATE · 자세',
            style: TextStyle(
                fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 18)),
        const Spacer(),
        if (!_source.canCalibrate)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: _surface, borderRadius: BorderRadius.circular(20)),
            child: const Text('DEMO · 실데이터 아님',
                style: TextStyle(fontSize: 11, color: _muted)),
          ),
        if (_source.canCalibrate)
          TextButton.icon(
            key: const ValueKey('calibrate'),
            onPressed: _calibrating ? null : _calibrate,
            style: TextButton.styleFrom(
              foregroundColor: _ink,
              backgroundColor: _surface,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            icon: _calibrating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.restart_alt, size: 18),
            label: const Text('기준 다시 잡기'),
          ),
        const SizedBox(width: 10),
        _link(state),
      ]);

  /// 연결 상태 점. 판정이 멀쩡해 보여도 링크가 죽어 있을 수 있어서 색을 따로 낸다.
  Widget _link(PostureState? state) {
    final health = _health;
    final color = _error != null
        ? _red
        : (health != null && !health.healthy)
            ? _amber
            : _green;
    return Tooltip(
      message: _source.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text('#${state?.sequence ?? 0}',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      ),
    );
  }

  /// 지금 화면에서 제일 급한 한 줄. 없으면 null.
  ({IconData icon, Color color, String text})? _note(
      PostureState? state, DateTime now) {
    if (_error != null) {
      return (
        icon: Icons.link_off,
        color: _red,
        text: '$_error · ${_source.label}'
      );
    }
    final health = _health;
    if (health?.error != null) {
      return (
        icon: Icons.usb_off,
        color: _red,
        text: '센서 링크가 끊겼습니다 — ${health!.error}'
      );
    }
    if (health != null && health.stale) {
      return (
        icon: Icons.sensors_off,
        color: _amber,
        text: '센서 프레임이 멈췄습니다 — 보드 USB 와 전원을 확인하세요'
      );
    }
    if (state == null) return null;
    final age = state.ageFrom(now);
    // 노드는 프레임이 멈춰도 1초에 한 번은 내보낸다. 그것마저 멈췄다는 뜻이다.
    if (age.inSeconds >= 5) {
      return (
        icon: Icons.update_disabled,
        color: _amber,
        text: '판정이 ${age.inSeconds}초째 갱신되지 않았습니다'
      );
    }
    if (!state.valid) {
      return (
        icon: Icons.straighten,
        color: _blue,
        text: state.scenario ?? '기준을 잡는 중입니다 — 판정은 아직 신뢰할 수 없어요'
      );
    }
    return null;
  }

  Widget _noteBar(({IconData icon, Color color, String text}) note) =>
      Container(
        key: const ValueKey('note'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: note.color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: note.color.withValues(alpha: .45)),
        ),
        child: Row(children: [
          Icon(note.icon, size: 18, color: note.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(note.text,
                style: TextStyle(fontSize: 14, color: note.color)),
          ),
        ]),
      );

  Widget _loading() => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(height: 16),
        Text(_error == null ? '자세 노드를 기다리는 중입니다' : '자세 노드를 다시 부르는 중입니다',
            style: const TextStyle(color: _muted)),
      ]);

  Widget _body(PostureState state, PostureLook look) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _presence(state),
          const SizedBox(height: 16),
          _hero(state, look),
          if (state.valid && state.scenario != null) ...[
            const SizedBox(height: 8),
            Text(state.scenario!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: _dim)),
          ],
          const SizedBox(height: 20),
          _metrics(state),
          const SizedBox(height: 14),
          _bars(state),
          const SizedBox(height: 14),
          _reasons(state),
        ],
      );

  /// 화면이 제일 먼저 답해야 하는 질문 — 지금 앉아 있는가.
  Widget _presence(PostureState state) {
    final seated = state.present;
    final color = seated ? _green : _gray;
    return Container(
      key: const ValueKey('presence'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(seated ? Icons.event_seat : Icons.person_off_outlined,
            size: 18, color: color),
        const SizedBox(width: 8),
        Text(seated ? '착석 중' : '자리 비움',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ]),
    );
  }

  Widget _hero(PostureState state, PostureLook look) => Column(children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: look.color.withValues(alpha: .12),
            border: Border.all(color: look.color, width: 3),
            boxShadow: [
              BoxShadow(
                  color: look.color.withValues(alpha: .3),
                  blurRadius: 40,
                  spreadRadius: 4)
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(look.icon, color: look.color, size: 52),
            const SizedBox(height: 6),
            SizedBox(
              width: 164,
              // 라벨 길이가 제각각이라('바른 자세' vs '기준 측정 중') 고정 글자
              // 크기로 두면 원 밖으로 넘친다.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(look.ko,
                    key: const ValueKey('posture-label'),
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: look.color)),
              ),
            ),
            Text(look.en,
                style: const TextStyle(
                    fontSize: 11, letterSpacing: 3, color: _muted)),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 520,
          child: Text(look.desc,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 16, color: _ink)),
        ),
      ]);

  Widget _metrics(PostureState state) {
    final nod = state.nodPerMin;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        _tile('머리 거리', _headText(state.headDeltaMm), '기준 대비 · − 가까움 + 멀어짐'),
        _tile('꾸벅임', nod == null ? '—' : '${nod.toStringAsFixed(1)}회/분',
            '분당 끄덕임 횟수'),
        _tile('움직임', state.motion.toStringAsFixed(2), '직전 프레임 대비 변화'),
        _tile('화면 점유', '${(state.coverage * 100).round()}%', '센서에 잡힌 사람 크기'),
      ],
    );
  }

  static String _headText(double? mm) {
    if (mm == null) return '—';
    return '${mm < 0 ? '−' : '+'}${mm.abs().round()}mm';
  }

  Widget _tile(String label, String value, String hint) => Container(
        width: 190,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(fontSize: 10, color: _dim)),
        ]),
      );

  /// 허브 `Signal(phi, delta)` 로 그대로 들어가는 값. 옆 앱과 같은 이름으로 부른다.
  Widget _bars(PostureState state) => SizedBox(
        width: 520,
        child: Row(children: [
          Expanded(child: _bar('집중 저하', state.focusDrop, _blue)),
          const SizedBox(width: 20),
          Expanded(child: _bar('피로', state.fatigue, _amber)),
        ]),
      );

  Widget _bar(String label, double value, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          Text('${(value * 100).round()}%',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: _surface,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]);

  Widget _reasons(PostureState state) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final reason in state.reasons)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _line),
              ),
              child: Text(reasonLabel(reason),
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFFC7D4EE))),
            ),
        ],
      );

  Widget _footer(PostureState? state, DateTime now) {
    final health = _health;
    final bits = <String>[
      if (state?.node != null) 'node ${state!.node}',
      if (health != null)
        'stage ${health.stage} · ${health.fps.toStringAsFixed(1)}fps',
      if (state != null) '갱신 ${state.ageFrom(now).inSeconds}초 전',
      _source.label,
    ];
    return Text(bits.join('   ·   '),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: _dim));
  }
}
