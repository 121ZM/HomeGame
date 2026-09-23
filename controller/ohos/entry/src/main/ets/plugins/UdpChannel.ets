import {
  BinaryMessenger,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { BusinessError } from '@ohos.base';
import socket from '@ohos.net.socket';

const CHANNEL_NAME: string = 'cn.zm.homegame/udp';

/**
 * UDP 发送通道（鸿蒙原生侧）。
 *
 * 对应 lib/net/udp_transport.dart 的 UdpTransport：
 * - open({port})             → 绑定本地 UDP 端口，0 表示系统分配
 * - send({host,port,bytes})  → 发一包；失败只回 {ok:false,...}，绝不抛异常
 * - close()                  → 释放 socket
 *
 * 字节序：Dart 侧已按小端编好协议字节，原生只透传，不再处理字节序。
 */
export class UdpChannel implements MethodCallHandler {
  private channel: MethodChannel | null = null;
  private udp: socket.UDPSocket | null = null;

  attach(messenger: BinaryMessenger): void {
    this.channel = new MethodChannel(messenger, CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  detach(): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.closeSocket();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'open':
        this.handleOpen(call, result);
        break;
      case 'send':
        this.handleSend(call, result);
        break;
      case 'close':
        this.handleClose(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private handleOpen(call: MethodCall, result: MethodResult): void {
    const portValue = call.argument('port');
    const port: number = (typeof portValue === 'number') ? portValue : 0;
    const udp: socket.UDPSocket = socket.constructUDPSocketInstance();
    udp.bind({ address: '0.0.0.0', port: port })
      .then((): void => {
        this.udp = udp;
        result.success({ ok: true, error: null });
      })
      .catch((err: BusinessError): void => {
        this.udp = null;
        result.success({ ok: false, error: this.describeError(err) });
      });
  }

  private handleSend(call: MethodCall, result: MethodResult): void {
    const host = call.argument('host');
    const portValue = call.argument('port');
    const bytesValue = call.argument('bytes');
    const udp: socket.UDPSocket | null = this.udp;

    if (udp === null) {
      result.success({ ok: false, error: 'UDP 未打开（请先调用 open）' });
      return;
    }
    if (typeof host !== 'string' || typeof portValue !== 'number' || !(bytesValue instanceof Uint8Array)) {
      result.success({ ok: false, error: 'send 参数缺失或类型错误' });
      return;
    }

    const buffer: ArrayBuffer = this.toArrayBuffer(bytesValue as Uint8Array);
    udp.send({ data: buffer, address: { address: host, port: portValue } })
      .then((): void => {
        result.success({ ok: true, error: null });
      })
      .catch((err: BusinessError): void => {
        result.success({ ok: false, error: this.describeError(err) });
      });
  }

  private handleClose(result: MethodResult): void {
    this.closeSocket();
    result.success(null);
  }

  private closeSocket(): void {
    const udp: socket.UDPSocket | null = this.udp;
    if (udp !== null) {
      this.udp = null;
      udp.close().catch((err: BusinessError): void => {
        // 关不掉吞掉：下次 open 会覆盖，不影响主流程。
        console.error(`UdpChannel.close failed: ${this.describeError(err)}`);
      });
    }
  }

  private toArrayBuffer(src: Uint8Array): ArrayBuffer {
    const copy: Uint8Array = new Uint8Array(src.byteLength);
    copy.set(src);
    return copy.buffer;
  }

  private describeError(err: Object): string {
    if (err instanceof BusinessError) {
      return `${err.code}: ${err.message}`;
    }
    if (err instanceof Error) {
      return err.message;
    }
    return String(err);
  }
}
