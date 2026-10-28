/// MQTT credentials (JWT is fetched dynamically — never hardcoded).
/// MQTT 凭证（JWT 动态获取——严禁硬编码）。
///
/// This lives in `core/` on purpose: both the device module (log upload) and the
/// robot module (teleoperation) connect to MQTT, and putting the type here keeps
/// those two modules from depending on each other.
/// 有意放在 `core/`：设备模块（日志上传）与机器人模块（遥控）都要连 MQTT，
/// 把类型放在此处可避免这两个模块互相依赖。
class MqttCredentials {
  const MqttCredentials({this.username, this.password});

  /// MQTT username. / MQTT 用户名。
  final String? username;

  /// MQTT password (or a freshly minted JWT). / MQTT 密码（或新签发的 JWT）。
  final String? password;
}
