/// Fixed-capacity ring buffer of the last N formatted log lines, kept
/// entirely in memory. Backs the "warning+ tail attached to every Sentry
/// event" behavior in OBSERVABILITY_STRATEGY.md Phase 4.3 — it works at 0%
/// log-export sampling and fully offline, and costs nothing.
class LogRingBuffer {
  LogRingBuffer({this.capacity = 200}) : assert(capacity > 0);

  final int capacity;
  final _buffer = <String>[];

  void add(String line) {
    _buffer.add(line);
    if (_buffer.length > capacity) {
      _buffer.removeAt(0);
    }
  }

  List<String> get lines => List.unmodifiable(_buffer);

  void clear() => _buffer.clear();
}
