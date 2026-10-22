/// Room roles for an RTC session. / RTC 会话的房间角色。
///
/// Roles drive what a participant may do:
/// - [RtcRole.anchor] — the lead operator, publishes camera/mic/screen.
/// - [RtcRole.coHost] — promoted viewer, may publish (talk show / takeover).
/// - [RtcRole.viewer] — audience, subscribe-only.
/// - [RtcRole.iotViewer] — IoT camera viewer, one-way pull (WHEP), power-friendly.
/// - [RtcRole.robotOperator] — robot teleoperator, publish + subscribe + control.
///
/// 角色决定参与者的能力边界：
/// - [RtcRole.anchor] —— 牵头操作者，发布摄像头 / 麦克风 / 屏幕；
/// - [RtcRole.coHost] —— 由观众提升而来，可发布（连麦 / 接管）；
/// - [RtcRole.viewer] —— 围观观众，只订阅；
/// - [RtcRole.iotViewer] —— IoT 摄像头查看器，单向拉流（WHEP），省电省带宽；
/// - [RtcRole.robotOperator] —— 机器人遥控端，可发布 + 订阅 + 控制。
enum RtcRole {
  /// Lead operator: publishes camera, microphone and screen. / 牵头操作者：发布摄像头、麦克风与屏幕。
  anchor(
    label: 'anchor',
    canPublish: true,
    canSubscribe: true,
    canControl: true,
  ),

  /// Co-host: promoted from viewer, may publish. / 连麦嘉宾：由观众提升而来，可发布。
  coHost(
    label: 'coHost',
    canPublish: true,
    canSubscribe: true,
    canControl: false,
  ),

  /// Viewer: subscribe-only audience. / 围观观众：仅订阅。
  viewer(
    label: 'viewer',
    canPublish: false,
    canSubscribe: true,
    canControl: false,
  ),

  /// IoT viewer: one-way stream pull for cameras/robots. / IoT 查看器：摄像头 / 机器人的单向拉流角色。
  iotViewer(
    label: 'iotViewer',
    canPublish: false,
    canSubscribe: true,
    canControl: true,
  ),

  /// Robot operator: teleoperation with control channel. / 机器人遥控端：带控制通道的远控角色。
  robotOperator(
    label: 'robotOperator',
    canPublish: true,
    canSubscribe: true,
    canControl: true,
  );

  const RtcRole({
    required this.label,
    required this.canPublish,
    required this.canSubscribe,
    required this.canControl,
  });

  /// Stable wire name used by signaling layers. / 信令层使用的稳定名称。
  final String label;

  /// Whether this role may publish tracks. / 该角色是否可以发布轨道。
  final bool canPublish;

  /// Whether this role may subscribe to remote tracks. / 该角色是否可以订阅远端轨道。
  final bool canSubscribe;

  /// Whether this role may send control commands (PTZ/robot). / 该角色是否可以发送控制指令（云台 / 机器人）。
  final bool canControl;

  /// Parses a role from its [label]; returns `null` for unknown names. / 从 [label] 解析角色；未知名称返回 `null`。
  static RtcRole? fromName(String? name) {
    if (name == null) return null;
    for (final role in RtcRole.values) {
      if (role.label == name) return role;
    }
    return null;
  }
}
