import 'dart:io';

import 'package:pocketbase/pocketbase.dart';

import 'sync_engine.dart';

/// Plain HTTP is accepted only where traffic stays on this machine or a
/// private network; anything else needs HTTPS. Changes are end-to-end
/// encrypted either way, but the login secret should not cross the internet
/// in clear.
Uri validateServerUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw SyncException('Enter a server address like https://sync.example.com');
  }
  if (uri.scheme == 'https') return uri;
  if (uri.scheme == 'http' && _isLocalHost(uri.host)) return uri;
  throw SyncException('Use https:// for servers outside your own network');
}

/// Loopback, link-local, RFC 1918, CGNAT/Tailscale (100.64/10), IPv6 ULA,
/// `localhost` and mDNS `.local` names. Only literal addresses count, so
/// `192.168.1.5.example.com` is not local.
bool _isLocalHost(String host) {
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
  }
  return (b[0] & 0xfe) == 0xfc;
}

/// Runs a PocketBase call, turning its errors into readable [SyncException]s.
Future<T> pbCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ClientException catch (e) {
    if (e.statusCode == 0) throw SyncException('Sync server unreachable');
    final msg = e.response['message'];
    final data = e.response['data'];
    final field = data is Map && data.isNotEmpty ? data.values.first : null;
    final detail = field is Map ? field['message'] : null;
    final text = [if (msg is String) msg, if (detail is String) detail].join(' ').trim();
    throw SyncException(text.isEmpty ? 'Sync server error ${e.statusCode}' : text);
  }
}

/// Whether the server refused a create because a unique index already holds it.
bool isNotUnique(ClientException e) {
  final data = e.response['data'];
  return e.statusCode == 400 &&
      data is Map &&
      data.values.any((v) => v is Map && v['code'] == 'validation_not_unique');
}

/// [SyncRemote] over the PocketBase collections in server/pb_migrations.
class PocketBaseRemote implements SyncRemote {
  PocketBaseRemote(this.pb, this.ownerId);
  final PocketBase pb;
  final String ownerId;

  RecordService get _changes => pb.collection('changes');

  @override
  Future<bool> push(String device, int seq, String payload) async {
    try {
      await _changes.create(body: {'owner': ownerId, 'device': device, 'seq': seq, 'payload': payload});
      return true;
    } on ClientException catch (e) {
      if (isNotUnique(e)) return false;
      return pbCall(() => Future.error(e));
    }
  }

  @override
  Future<String?> fetch(String device, int seq) => pbCall(() async {
    final r = await _changes.getList(
      perPage: 1,
      skipTotal: true,
      filter: pb.filter('device = {:d} && seq = {:s}', {'d': device, 's': seq}),
    );
    return r.items.isEmpty ? null : r.items.single.getStringValue('payload');
  });

  @override
  Future<int> lastSeq(String device) => pbCall(() async {
    final r = await _changes.getList(
      perPage: 1,
      skipTotal: true,
      sort: '-seq',
      fields: 'seq',
      filter: pb.filter('device = {:d}', {'d': device}),
    );
    return r.items.isEmpty ? 0 : r.items.single.getIntValue('seq');
  });

  @override
  Future<List<String>> devices() => pbCall(() async {
    final r = await pb.collection('devices').getFullList(fields: 'device');
    return [for (final d in r) d.getStringValue('device')];
  });

  @override
  Future<List<RemoteChange>> pull(String device, int afterSeq, {int limit = 50}) => pbCall(() async {
    final r = await _changes.getList(
      perPage: limit,
      skipTotal: true,
      sort: 'seq',
      fields: 'seq,payload',
      filter: pb.filter('device = {:d} && seq > {:s}', {'d': device, 's': afterSeq}),
    );
    return [for (final x in r.items) RemoteChange(x.getIntValue('seq'), x.getStringValue('payload'))];
  });
}
