/// Hybrid logical clock (Kulkarni et al.). Every synced row carries the HLC of
/// its last write; merges keep the row with the greater HLC. Stamps are fixed
/// width so plain string comparison orders them, and the device id at the end
/// breaks ties, so every device resolves the same conflict the same way.
class HlcClock {
  HlcClock(this.node, {int Function()? now}) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (node.contains('-')) throw ArgumentError('node must not contain "-"');
  }

  /// Stamp for rows that ship with the app (default categories). Lower than
  /// any real write, so a user's edit always wins over the seed.
  static const seed = '000000000000000-000000-seed';

  final String node;
  final int Function() _now;
  int _millis = 0;
  int _counter = 0;

  /// A new stamp for a local write; strictly greater than any stamp seen.
  String tick() {
    final wall = _now();
    if (wall > _millis) {
      _millis = wall;
      _counter = 0;
    } else {
      _counter++;
    }
    return _format(_millis, _counter, node);
  }

  /// Folds a stamp from another device into this clock.
  void receive(String stamp) {
    final parts = stamp.split('-');
    if (parts.length != 3) return;
    final rMillis = int.tryParse(parts[0]);
    final rCounter = int.tryParse(parts[1]);
    if (rMillis == null || rCounter == null) return;
    final wall = _now();
    final m = [wall, _millis, rMillis].reduce((a, b) => a > b ? a : b);
    if (m == _millis && m == rMillis) {
      _counter = (_counter > rCounter ? _counter : rCounter) + 1;
    } else if (m == _millis) {
      _counter++;
    } else if (m == rMillis) {
      _counter = rCounter + 1;
    } else {
      _counter = 0;
    }
    _millis = m;
  }

  static String _format(int millis, int counter, String node) =>
      '${millis.toString().padLeft(15, '0')}-'
      '${counter.toString().padLeft(6, '0')}-$node';
}
