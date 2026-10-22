import '../core/rtc_stats.dart';

/// Reconnect backoff policy for the media/control link.
/// 媒体 / 控制链路的重连退避策略。
///
/// Overseas links cross many hops, so the first retries must be fast enough to
/// hide a transient ISP blip but the tail must be long enough to survive a
/// multi-minute backbone outage without hammering the server.
/// 海外链路跨越多跳：前几次重试要快到能掩盖瞬断，尾部又要长到能扛住数分钟的
/// 骨干故障，同时不把服务端打爆。
class ReconnectPolicy {
  const ReconnectPolicy({
    this.maxAttempts = 8,
    this.baseDelay = const Duration(milliseconds: 600),
    this.maxDelay = const Duration(seconds: 15),
    this.jitterRatio = 0.25,
    this.relayAfterAttempts = 2,
    this.stableWindow = const Duration(seconds: 20),
  });

  /// Maximum attempts before the link is declared failed. / 判定链路失败前的最大尝试次数。
  final int maxAttempts;

  /// Delay of the first retry. / 首次重试的延迟。
  final Duration baseDelay;

  /// Upper bound of the backoff. / 退避上限。
  final Duration maxDelay;

  /// Jitter ratio (0–1) applied to every delay to avoid thundering herds.
  /// 施加到每次延迟上的抖动比例（0–1），避免重连风暴。
  final double jitterRatio;

  /// Attempt (1-based) from which TURN relay is forced. Direct paths almost
  /// never survive symmetric NAT + CGNAT across continents.
  /// 从哪一次尝试（从 1 开始）起强制 TURN 中继。跨洲对称 NAT + CGNAT 下
  /// 直连几乎不可能成功。
  final int relayAfterAttempts;

  /// How long the link must stay up before the attempt counter resets.
  /// 链路需稳定保持多久才重置尝试计数。
  final Duration stableWindow;

  /// Backoff delay for [attempt] (1-based), before jitter. / 第 [attempt] 次（从 1 开始）的退避延迟（未加抖动）。
  Duration delayForAttempt(int attempt) {
    final normalized = attempt < 1 ? 1 : attempt;
    final exponent = normalized - 1 > 24 ? 24 : normalized - 1;
    final raw = baseDelay.inMicroseconds * (1 << exponent);
    final capped = raw > maxDelay.inMicroseconds
        ? maxDelay.inMicroseconds
        : raw;
    return Duration(microseconds: capped);
  }

  /// Whether another attempt is allowed. / 是否还允许继续尝试。
  bool allowsAttempt(int attempt) => attempt <= maxAttempts;

  /// Copies with the given fields replaced. / 复制并替换给定字段。
  ReconnectPolicy copyWith({
    int? maxAttempts,
    Duration? baseDelay,
    Duration? maxDelay,
    double? jitterRatio,
    int? relayAfterAttempts,
    Duration? stableWindow,
  }) {
    return ReconnectPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      baseDelay: baseDelay ?? this.baseDelay,
      maxDelay: maxDelay ?? this.maxDelay,
      jitterRatio: jitterRatio ?? this.jitterRatio,
      relayAfterAttempts: relayAfterAttempts ?? this.relayAfterAttempts,
      stableWindow: stableWindow ?? this.stableWindow,
    );
  }
}

/// Thresholds that classify a weak (congested / frozen) downlink.
/// 判定弱网（拥塞 / 画面冻结）下行链路的阈值。
class WeakNetworkPolicy {
  const WeakNetworkPolicy({
    this.frozenFps = 2,
    this.frozenSamples = 2,
    this.keyframeAfter = const Duration(seconds: 4),
    this.resubscribeAfter = const Duration(seconds: 12),
    this.stutterLossPercent = 6,
    this.stutterJitterMs = 120,
    this.congestedRttMs = 400,
    this.congestedLossPercent = 12,
    this.recoverySamples = 3,
    this.degradeAfter = const Duration(seconds: 6),
    this.minClarity = ClarityLevel.p360,
  });

  /// FPS at or below which a video track counts as frozen. / 视频轨道判定为冻结的帧率上限。
  final double frozenFps;

  /// Consecutive bad samples required before an issue is reported (debounce).
  /// 上报问题所需的连续坏样本数（去抖）。
  final int frozenSamples;

  /// How long a freeze lasts before a keyframe (PLI/FIR) is requested.
  /// 冻结持续多久后请求关键帧（PLI / FIR）。
  final Duration keyframeAfter;

  /// How long a freeze lasts before the subscription is rebuilt.
  /// 冻结持续多久后重建订阅。
  final Duration resubscribeAfter;

  /// Packet loss (%) above which playback counts as stuttering. / 判定为卡顿的丢包率（%）阈值。
  final double stutterLossPercent;

  /// Jitter (ms) above which playback counts as stuttering. / 判定为卡顿的抖动（ms）阈值。
  final double stutterJitterMs;

  /// RTT (ms) above which the link counts as congested. / 判定为拥塞的 RTT（ms）阈值。
  final double congestedRttMs;

  /// Packet loss (%) above which the link counts as congested. / 判定为拥塞的丢包率（%）阈值。
  final double congestedLossPercent;

  /// Consecutive good samples required before recovery is reported.
  /// 上报恢复所需的连续好样本数。
  final int recoverySamples;

  /// How long congestion must last before clarity is downgraded.
  /// 拥塞持续多久后降低清晰度。
  final Duration degradeAfter;

  /// Lowest clarity the auto-degrader may select. / 自动降级允许选到的最低清晰度。
  final ClarityLevel minClarity;
}

/// What happens when the app moves to the background (or the OS suspends it).
/// 应用进入后台（或被系统挂起）时的行为。
class BackgroundPolicy {
  const BackgroundPolicy({
    this.pauseVideo = true,
    this.keepAudio = true,
    this.gracePeriod = const Duration(seconds: 3),
    this.stopRobot = true,
    this.requireResumeConfirmation = true,
    this.confirmationTimeout = const Duration(seconds: 30),
    this.reconnectOnForeground = true,
  });

  /// Disable the outgoing video track while backgrounded (saves battery and
  /// avoids the "camera in use" indicator). / 后台时关闭出向视频轨道（省电，
  /// 并避免系统相机占用提示）。
  final bool pauseVideo;

  /// Keep the audio path alive (intercom keeps working). / 保持音频通路存活（对讲继续可用）。
  final bool keepAudio;

  /// Grace period before the background actions are applied (a quick
  /// notification shade pull-down must not tear the link down).
  /// 应用后台动作前的宽限期（快速下拉通知栏不应立即拆链）。
  final Duration gracePeriod;

  /// Stop the robot immediately when the operator loses the foreground.
  /// 操作者离开前台时立即停车。
  final bool stopRobot;

  /// Whether resuming requires an explicit user confirmation.
  /// 恢复是否需要用户显式确认。
  final bool requireResumeConfirmation;

  /// How long a resume ticket stays valid. / 恢复票据的有效期。
  final Duration confirmationTimeout;

  /// Re-establish the link when the app returns to the foreground.
  /// 应用回到前台时重建链路。
  final bool reconnectOnForeground;
}

/// Budget for the low-latency control link (robot teleoperation).
/// 低时延控制链路（机器人遥控）的预算。
class ControlLinkPolicy {
  const ControlLinkPolicy({
    this.commandInterval = const Duration(milliseconds: 100),
    this.maxPendingCommands = 1,
    this.staleAfter = const Duration(milliseconds: 300),
    this.preferDataChannel = true,
    this.rttBudgetMs = 200,
  });

  /// Keepalive interval while a velocity command is active. / 有活跃速度指令时的保活间隔。
  final Duration commandInterval;

  /// Maximum buffered commands; teleoperation is latest-wins, never a queue.
  /// 最大缓存指令数；遥控是"最新者胜"，绝不做排队。
  final int maxPendingCommands;

  /// A command older than this is expired and dropped, never replayed.
  /// 超过该时长的指令视为过期并丢弃，绝不补发。
  final Duration staleAfter;

  /// Prefer the WebRTC data channel (LAN) over MQTT (WAN) when both are up.
  /// 两条都可用时优先 WebRTC 数据通道（局域网）而非 MQTT（广域网）。
  final bool preferDataChannel;

  /// End-to-end command budget in milliseconds (overseas WAN target).
  /// 指令端到端预算（毫秒，海外广域网目标）。
  final int rttBudgetMs;
}

/// Aggregated policy for the resilient link. / 韧性链路的聚合策略。
class LinkPolicy {
  const LinkPolicy({
    this.reconnect = const ReconnectPolicy(),
    this.weakNetwork = const WeakNetworkPolicy(),
    this.background = const BackgroundPolicy(),
    this.control = const ControlLinkPolicy(),
    this.connectTimeout = const Duration(seconds: 12),
    this.iceGatheringTimeout = const Duration(seconds: 8),
    this.statsInterval = const Duration(seconds: 2),
    this.restartIceOnHandover = true,
    this.restartIceOnSameKindHandover = false,
  });

  /// Reconnect backoff. / 重连退避。
  final ReconnectPolicy reconnect;

  /// Weak-network classification. / 弱网判定。
  final WeakNetworkPolicy weakNetwork;

  /// App background behaviour. / 应用后台行为。
  final BackgroundPolicy background;

  /// Control link budget. / 控制链路预算。
  final ControlLinkPolicy control;

  /// Timeout for the initial signaling + ICE establishment. / 初始信令 + ICE 建立的超时。
  final Duration connectTimeout;

  /// Timeout for ICE gathering before the link is declared unusable.
  /// ICE 收集超时，超时即判定链路不可用。
  final Duration iceGatheringTimeout;

  /// Stats sampling interval. / stats 采样间隔。
  final Duration statsInterval;

  /// Restart ICE when the network path changes (WiFi ↔ cellular).
  /// 网络路径变化（WiFi ↔ 蜂窝）时重启 ICE。
  final bool restartIceOnHandover;

  /// Also restart ICE when the path stays on the same kind but the link
  /// changes (AP roaming, new SSID). Noisy by default — opt in.
  /// 同类型网络内链路变化（AP 漫游、换 SSID）时也重启 ICE。默认较敏感，需显式开启。
  final bool restartIceOnSameKindHandover;

  /// Copies with the given fields replaced. / 复制并替换给定字段。
  LinkPolicy copyWith({
    ReconnectPolicy? reconnect,
    WeakNetworkPolicy? weakNetwork,
    BackgroundPolicy? background,
    ControlLinkPolicy? control,
    Duration? connectTimeout,
    Duration? iceGatheringTimeout,
    Duration? statsInterval,
    bool? restartIceOnHandover,
    bool? restartIceOnSameKindHandover,
  }) {
    return LinkPolicy(
      reconnect: reconnect ?? this.reconnect,
      weakNetwork: weakNetwork ?? this.weakNetwork,
      background: background ?? this.background,
      control: control ?? this.control,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      iceGatheringTimeout: iceGatheringTimeout ?? this.iceGatheringTimeout,
      statsInterval: statsInterval ?? this.statsInterval,
      restartIceOnHandover: restartIceOnHandover ?? this.restartIceOnHandover,
      restartIceOnSameKindHandover:
          restartIceOnSameKindHandover ?? this.restartIceOnSameKindHandover,
    );
  }
}
