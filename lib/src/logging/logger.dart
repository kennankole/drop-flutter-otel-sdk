import 'ring_buffer.dart';

enum DropLogLevel { debug, info, warning, error }

/// Package-owned logging facade. At L1, output goes only to the in-memory
/// ring buffer — OTEL log export (gated, L4) and release-build severity
/// filtering land in later phases; this is the shape those phases wire
/// into, not a placeholder that gets replaced wholesale.
abstract class DropLogger {
  void log(DropLogLevel level, String message, {Map<String, Object?>? fields});

  void d(String message, {Map<String, Object?>? fields}) =>
      log(DropLogLevel.debug, message, fields: fields);

  void i(String message, {Map<String, Object?>? fields}) =>
      log(DropLogLevel.info, message, fields: fields);

  void w(String message, {Map<String, Object?>? fields}) =>
      log(DropLogLevel.warning, message, fields: fields);

  void e(String message, {Map<String, Object?>? fields}) =>
      log(DropLogLevel.error, message, fields: fields);
}

/// L1's [DropLogger]: writes every record at or above [minLevel] into
/// [ringBuffer] and nowhere else. `fields` are folded into the formatted
/// line body — never treated as labels (design principle 4 / strategy
/// Phase 4.2's "fields → body, never labels").
class RingBufferLogger extends DropLogger {
  RingBufferLogger({
    LogRingBuffer? ringBuffer,
    DropLogLevel minLevel = DropLogLevel.warning,
  }) : ringBuffer = ringBuffer ?? LogRingBuffer(),
       _minLevel = minLevel;

  final LogRingBuffer ringBuffer;
  final DropLogLevel _minLevel;

  @override
  void log(DropLogLevel level, String message, {Map<String, Object?>? fields}) {
    if (level.index < _minLevel.index) return;
    final fieldsSuffix = (fields == null || fields.isEmpty) ? '' : ' $fields';
    ringBuffer.add('[${level.name}] $message$fieldsSuffix');
  }
}
