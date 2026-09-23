import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { UdpChannel } from '../plugins/UdpChannel';
import { SensorChannel } from '../plugins/SensorChannel';

export default class EntryAbility extends FlutterAbility {
  private udpChannel: UdpChannel = new UdpChannel();
  private sensorChannel: SensorChannel = new SensorChannel();

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    const messenger = flutterEngine.dartExecutor.getBinaryMessenger();
    this.udpChannel.attach(messenger);
    this.sensorChannel.attach(messenger);
  }

  onDestroy() {
    this.udpChannel.detach();
    this.sensorChannel.detach();
    super.onDestroy();
  }
}
