
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { HomeGameChannel } from '../plugins/HomeGameChannel';

export default class EntryAbility extends FlutterAbility {
  private homeGameChannel: HomeGameChannel | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)

    // HomeGame 自己的两个通道（UDP + 传感器）。
    // 注册点与安卓侧 MainActivity.configureFlutterEngine 对应。
    this.homeGameChannel = new HomeGameChannel();
    this.homeGameChannel.registerWith(flutterEngine);
  }

  onDestroy(): void {
    // 释放 socket 与传感器监听。
    this.homeGameChannel?.dispose();
    this.homeGameChannel = null;
    super.onDestroy();
  }
}
