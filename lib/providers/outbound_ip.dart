import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

/// Keyed by the outbound a lookup pins: a node name, `DIRECT`, or
/// [routedOutbound] for whatever the rules pick right now.
@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  static const _retryBudget = Duration(seconds: 15);
  static const _retryGap = Duration(seconds: 2);

  @override
  RoutedProbeState<String, IpInfo> build() => buildProbe();

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    final deadline = DateTime.now().add(_retryBudget);
    OutboundIpResult? result;
    IpInfo? value;
    while (true) {
      result = await lookupOutboundIp(ref.read(coreHandlerProvider), proxyName);
      value = parseOutboundIp(result);
      if (value != null || !DateTime.now().isBefore(deadline)) {
        break;
      }
      await Future<void>.delayed(_retryGap);
    }
    final hits = result?.hits ?? const <RouteHit>[];
    final exit = result?.chains.firstOrNull;
    return {
      target: ProbeAnswer(
        value: value,
        coreEpoch: result?.coreEpoch,
        routeVersion: result?.routeVersion,
        hits: hits,
      ),
      // A node leaves through the same address whatever it is asked for.
      if (value != null && exit != null && exit != target)
        exit: ProbeAnswer(
          value: value,
          coreEpoch: result?.coreEpoch,
          routeVersion: result?.routeVersion,
          hits: result?.nodeHits ?? const [],
        ),
    };
  }
}
