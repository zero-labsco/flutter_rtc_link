import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake BLE channel. / 假 BLE 通道。
class FakeBleChannel implements BleProvisioningChannel {
  bool scanCalled = false;
  bool provisionCalled = false;
  bool provisionResult = true;

  @override
  Future<List<ProvisionDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    scanCalled = true;
    return <ProvisionDevice>[
      ProvisionDevice(
        id: 'aa:bb:cc:dd:ee:ff',
        name: 'ESP32-Prov',
        capabilities: const <ProvisionMethod>{ProvisionMethod.ble},
      ),
    ];
  }

  @override
  Future<bool> provision(ProvisionDevice device, WifiCredential wifi) async {
    provisionCalled = true;
    return provisionResult;
  }
}

/// Fake DPP channel. / 假 DPP 通道。
class FakeDppChannel implements DppProvisioningChannel {
  bool called = false;

  @override
  Future<bool> provision({required String qrContent}) async {
    called = true;
    return true;
  }
}

/// Fake SmartConfig channel. / 假 SmartConfig 通道。
class FakeSmartConfigChannel implements SmartConfigChannel {
  bool called = false;

  @override
  Future<bool> provision(WifiCredential wifi) async {
    called = true;
    return true;
  }
}

const WifiCredential _wifi = WifiCredential(
  ssid: 'plant-5g',
  password: 'secret',
);

/// Broadcast stream controllers deliver events asynchronously, so tests must
/// let the event queue drain before asserting on captured states.
/// 广播流控制器异步投递事件，因此测试断言前需让事件队列排空。
Future<void> _flushEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 1));

void main() {
  group('DeviceProvisioning', () {
    test('scanBle reports scanning state then returns devices', () async {
      final ble = FakeBleChannel();
      final provisioning = DeviceProvisioning(ble: ble);
      final states = <ProvisioningState>[];
      provisioning.status.listen((s) => states.add(s.state));
      final devices = await provisioning.scanBle();
      expect(ble.scanCalled, isTrue);
      expect(devices.single.id, 'aa:bb:cc:dd:ee:ff');
      expect(states.first, ProvisioningState.scanning);
      await provisioning.dispose();
    });

    test('auto chain picks BLE first when the device supports it', () async {
      final ble = FakeBleChannel();
      final smart = FakeSmartConfigChannel();
      final provisioning = DeviceProvisioning(ble: ble, smartConfig: smart);
      final ok = await provisioning.provision(
        const ProvisionDevice(
          id: 'aa:bb',
          name: 'dev',
          capabilities: <ProvisionMethod>{
            ProvisionMethod.ble,
            ProvisionMethod.smartConfig,
          },
        ),
        wifi: _wifi,
      );
      expect(ok, isTrue);
      expect(ble.provisionCalled, isTrue);
      expect(smart.called, isFalse);
      await provisioning.dispose();
    });

    test('auto chain degrades to the next method on failure', () async {
      final ble = FakeBleChannel()..provisionResult = false;
      final smart = FakeSmartConfigChannel();
      final provisioning = DeviceProvisioning(ble: ble, smartConfig: smart);
      final statuses = <ProvisioningStatus>[];
      provisioning.status.listen(statuses.add);
      final ok = await provisioning.provision(
        const ProvisionDevice(
          id: 'aa:bb',
          name: 'dev',
          capabilities: <ProvisionMethod>{
            ProvisionMethod.ble,
            ProvisionMethod.smartConfig,
          },
        ),
        wifi: _wifi,
      );
      await _flushEvents();
      expect(ok, isTrue);
      expect(ble.provisionCalled, isTrue);
      expect(smart.called, isTrue);
      expect(
        statuses.last,
        isA<ProvisioningStatus>()
            .having((s) => s.state, 'state', ProvisioningState.success)
            .having((s) => s.method, 'method', ProvisionMethod.smartConfig),
      );
      await provisioning.dispose();
    });

    test('explicit method bypasses the chain', () async {
      final ble = FakeBleChannel();
      final dpp = FakeDppChannel();
      final provisioning = DeviceProvisioning(ble: ble, dpp: dpp);
      final ok = await provisioning.provision(
        const ProvisionDevice(id: 'dev', name: 'dev'),
        wifi: _wifi,
        method: ProvisionMethod.dpp,
      );
      expect(ok, isTrue);
      expect(dpp.called, isTrue);
      expect(ble.provisionCalled, isFalse);
      await provisioning.dispose();
    });

    test('unsupported method reports a classified failure', () async {
      final provisioning = DeviceProvisioning();
      final statuses = <ProvisioningStatus>[];
      provisioning.status.listen(statuses.add);
      final ok = await provisioning.provision(
        const ProvisionDevice(
          id: 'dev',
          name: 'dev',
          capabilities: <ProvisionMethod>{ProvisionMethod.dpp},
        ),
        wifi: _wifi,
      );
      await _flushEvents();
      expect(ok, isFalse);
      expect(statuses.last.state, ProvisioningState.failed);
      expect(statuses.last.reason, ProvisionFailureReason.unsupportedPlatform);
      await provisioning.dispose();
    });

    test('DPP without a channel fails as unsupported', () async {
      final provisioning = DeviceProvisioning();
      final ok = await provisioning.provisionViaDpp(qrContent: 'DPP:C:1/2');
      expect(ok, isFalse);
      await provisioning.dispose();
    });
  });
}
