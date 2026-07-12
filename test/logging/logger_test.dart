import 'package:drop_observability/drop_observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RingBufferLogger', () {
    test('writes at-or-above minLevel to the ring buffer', () {
      final logger = RingBufferLogger(minLevel: DropLogLevel.warning);
      logger
        ..d('debug noise')
        ..i('info noise')
        ..w('degraded')
        ..e('boom');

      expect(logger.ringBuffer.lines, ['[warning] degraded', '[error] boom']);
    });

    test('release-filtered default: warning is the minimum level', () {
      final logger = RingBufferLogger();
      logger.i('should not appear');
      expect(logger.ringBuffer.lines, isEmpty);
    });

    test('fields are folded into the line body, never treated as labels', () {
      final logger = RingBufferLogger(minLevel: DropLogLevel.debug);
      logger.w('poll degraded', fields: {'storeId': 'abc123'});

      expect(logger.ringBuffer.lines.single, contains('storeId'));
      expect(logger.ringBuffer.lines.single, contains('abc123'));
    });

    test(
      'a custom ring buffer instance can be shared with other consumers',
      () {
        final sharedBuffer = LogRingBuffer(capacity: 5);
        final logger = RingBufferLogger(
          ringBuffer: sharedBuffer,
          minLevel: DropLogLevel.debug,
        );

        logger.e('boom');

        expect(sharedBuffer.lines, ['[error] boom']);
      },
    );
  });
}
