import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/services.dart';

class Ios {
  static Ios? _instance;
  late MethodChannel methodChannel;
  Completer<String>? _homeDirCompleter;

  Ios._internal() {
    methodChannel = const MethodChannel('$packageName/ios');
  }

  factory Ios() {
    _instance ??= Ios._internal();
    return _instance!;
  }

  Future<String> getHomeDir() {
    final completer = _homeDirCompleter;
    if (completer != null) {
      return completer.future;
    }
    final next = Completer<String>();
    _homeDirCompleter = next;
    methodChannel
        .invokeMethod<String>('getHomeDir')
        .then((value) => next.complete(value ?? ''))
        .catchError((Object error) {
          _homeDirCompleter = null;
          next.completeError(error);
        });
    return next.future;
  }

  Future<bool> openAppSettings() async {
    return await methodChannel.invokeMethod<bool>('openAppSettings') ?? false;
  }
}

final ios = system.isIOS ? Ios() : null;
