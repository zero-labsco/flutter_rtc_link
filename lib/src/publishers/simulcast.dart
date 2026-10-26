import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/rtc_stats.dart';

/// Simulcast layer rid: full resolution. / simulcast 层 rid：全分辨率。
const String kRidFull = 'f';

/// Simulcast layer rid: half resolution. / simulcast 层 rid：一半分辨率。
const String kRidHalf = 'h';

/// Simulcast layer rid: quarter resolution. / simulcast 层 rid：四分之一分辨率。
const String kRidQuarter = 'q';

/// Nominal bitrate (bps) of the full layer for each clarity level.
/// 各清晰度层级对应的满层标称码率（bps）。
const Map<ClarityLevel, int> kFullLayerBitrate = <ClarityLevel, int>{
  ClarityLevel.p360: 450 * 1000,
  ClarityLevel.p540: 800 * 1000,
  ClarityLevel.p720: 1700 * 1000,
  ClarityLevel.p1080: 3000 * 1000,
  ClarityLevel.p2160: 8000 * 1000,
};

/// Whether a simulcast layer is active for the given publish cap.
/// 给定发布上限下某 simulcast 层是否激活。
///
/// `auto` keeps every layer active (subscribers pick); fixed levels deactivate
/// layers above the cap so the encoder never wastes bits on them.
/// `auto` 保留全部层（由订阅端选择）；固定层级则停用高于上限的层，
/// 避免编码器把码率浪费在高层上。
bool isSimulcastLayerActive(String rid, ClarityLevel maxLevel) {
  switch (maxLevel) {
    case ClarityLevel.auto:
      return true;
    case ClarityLevel.p360:
      return rid == kRidQuarter;
    case ClarityLevel.p540:
      return rid == kRidQuarter || rid == kRidHalf;
    case ClarityLevel.p720:
    case ClarityLevel.p1080:
    case ClarityLevel.p2160:
      return true;
  }
}

/// Builds simulcast send encodings capped at [maxLevel].
/// 构建以 [maxLevel] 为上限的 simulcast 发送编码。
///
/// Attach the result to the video sender (via transceiver init before the
/// first offer, or via `setParameters` afterwards) so the SDP carries `rid`
/// lines — without rid lines there is no simulcast at all.
/// 将结果挂到视频 sender（首次 offer 前经 transceiver init，或之后经
/// `setParameters`），SDP 才会携带 `rid` 行——没有 rid 就没有 simulcast。
List<RTCRtpEncoding> buildSimulcastEncodings(ClarityLevel maxLevel) {
  final fullBitrate =
      kFullLayerBitrate[maxLevel] ?? kFullLayerBitrate[ClarityLevel.p720]!;
  return <RTCRtpEncoding>[
    RTCRtpEncoding(
      rid: kRidFull,
      active: isSimulcastLayerActive(kRidFull, maxLevel),
      scaleResolutionDownBy: 1.0,
      maxBitrate: fullBitrate,
      maxFramerate: 30,
      priority: RTCPriorityType.high,
    ),
    RTCRtpEncoding(
      rid: kRidHalf,
      active: isSimulcastLayerActive(kRidHalf, maxLevel),
      scaleResolutionDownBy: 2.0,
      maxBitrate: fullBitrate ~/ 2,
      maxFramerate: 30,
    ),
    RTCRtpEncoding(
      rid: kRidQuarter,
      active: isSimulcastLayerActive(kRidQuarter, maxLevel),
      scaleResolutionDownBy: 4.0,
      maxBitrate: fullBitrate ~/ 4,
      maxFramerate: 15,
    ),
  ];
}

/// Recomputes `active` flags and bitrate caps on existing encodings.
/// 在既有 encodings 上重算 `active` 标志与码率上限。
///
/// Mutating the existing list keeps each layer's native-assigned `ssrc`
/// (which must not change between get/set parameters).
/// 原地修改既有列表可保留各层由原生分配的 `ssrc`（get/set parameters 之间不可变）。
void applyClarityToEncodings(
  List<RTCRtpEncoding>? encodings,
  ClarityLevel maxLevel,
) {
  if (encodings == null || encodings.isEmpty) return;
  final fullBitrate =
      kFullLayerBitrate[maxLevel] ?? kFullLayerBitrate[ClarityLevel.p720]!;
  for (final encoding in encodings) {
    final rid = encoding.rid;
    if (rid == null) continue;
    encoding.active = isSimulcastLayerActive(rid, maxLevel);
    switch (rid) {
      case kRidFull:
        // Every branch must break: falling through would let the later cases
        // overwrite maxBitrate, so every layer ended up at full ~/ 4. /
        // 每个分支都必须 break：直通会让后续 case 覆盖 maxBitrate，导致每一层
        // 最终都变成 full ~/ 4。
        encoding.maxBitrate = fullBitrate;
        break;
      case kRidHalf:
        encoding.maxBitrate = fullBitrate ~/ 2;
        break;
      case kRidQuarter:
        encoding.maxBitrate = fullBitrate ~/ 4;
        break;
    }
  }
}
