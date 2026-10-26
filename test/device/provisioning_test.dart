import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake BLE channel. / 假 BLE 通道。
class FakeBleChannel implements BleProvisioningChannel {
  bool scanCalled = false;
  bool provisionCalled = false;
  bool provisionResult = true;
  WifiCredential? lastWifi;

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
    lastWifi = wifi;
    return provisionResult;
  }
}

/// Fake DPP channel. / 假 DPP 通道。
class FakeDppChannel implements DppProvisioningChannel {
  bool called = false;
  String? lastQrContent;

  @override
  Future<bool> provision({required String qrContent}) async {
    called = true;
    lastQrContent = qrContent;
    return true;
  }
}

/// Fake NFC channel. / 假 NFC 通道。
class FakeNfcChannel implements NfcProvisioningChannel {
  WifiCredential? tagCredential = _wifi;

  @override
  Future<WifiCredential?> readCredentialTag() async => tagCredential;

  @override
  Future<bool> writeCredentialTag(WifiCredential wifi) async => true;
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
        const ProvisionDevice(id: 'dev', name: 'dev', dppUri: 'DPP:C:1/2'),
        wifi: _wifi,
        method: ProvisionMethod.dpp,
      );
      expect(ok, isTrue);
      expect(dpp.called, isTrue);
      expect(dpp.lastQrContent, 'DPP:C:1/2');
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

    test('DPP rejects a device id that is not a bootstrap URI', () async {
      final dpp = FakeDppChannel();
      final provisioning = DeviceProvisioning(dpp: dpp);
      final statuses = <ProvisioningStatus>[];
      provisioning.status.listen(statuses.add);
      final ok = await provisioning.provisionViaDpp(qrContent: 'aa:bb:cc');
      await _flushEvents();
      expect(ok, isFalse);
      expect(dpp.called, isFalse);
      expect(statuses.last.reason, ProvisionFailureReason.protocolMismatch);
      await provisioning.dispose();
    });

    test('the chain hands the device dppUri to DPP, not its id', () async {
      final dpp = FakeDppChannel();
      final provisioning = DeviceProvisioning(dpp: dpp);
      final ok = await provisioning.provision(
        const ProvisionDevice(
          id: 'aa:bb:cc',
          name: 'dev',
          capabilities: <ProvisionMethod>{ProvisionMethod.dpp},
          dppUri: 'DPP:V:2;M:11aa;;',
        ),
        wifi: _wifi,
      );
      expect(ok, isTrue);
      expect(dpp.lastQrContent, 'DPP:V:2;M:11aa;;');
      await provisioning.dispose();
    });

    test(
      'readNfcCredential returns the tag without claiming success',
      () async {
        final nfc = FakeNfcChannel();
        final provisioning = DeviceProvisioning(nfc: nfc);
        final statuses = <ProvisioningStatus>[];
        provisioning.status.listen(statuses.add);
        final credential = await provisioning.readNfcCredential();
        await _flushEvents();
        expect(credential?.ssid, 'plant-5g');
        expect(
          statuses.any((s) => s.state == ProvisioningState.success),
          isFalse,
        );
        await provisioning.dispose();
      },
    );

    test('NFC without a device fails instead of reporting success', () async {
      final nfc = FakeNfcChannel();
      final ble = FakeBleChannel();
      final provisioning = DeviceProvisioning(nfc: nfc, ble: ble);
      final statuses = <ProvisioningStatus>[];
      provisioning.status.listen(statuses.add);
      final ok = await provisioning.provisionViaNfc();
      await _flushEvents();
      expect(ok, isFalse);
      expect(statuses.last.state, ProvisioningState.failed);
      expect(ble.provisionCalled, isFalse);
      await provisioning.dispose();
    });

    test('provisionViaNfc delivers the tag credentials over BLE', () async {
      final nfc = FakeNfcChannel();
      final ble = FakeBleChannel();
      final provisioning = DeviceProvisioning(nfc: nfc, ble: ble);
      final ok = await provisioning.provisionViaNfc(
        device: const ProvisionDevice(
          id: 'aa:bb',
          name: 'dev',
          capabilities: <ProvisionMethod>{ProvisionMethod.ble},
        ),
      );
      expect(ok, isTrue);
      expect(ble.provisionCalled, isTrue);
      expect(ble.lastWifi?.ssid, 'plant-5g');
      await provisioning.dispose();
    });
  });
}
