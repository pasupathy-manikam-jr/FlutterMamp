import 'package:flutter_mamp/domain/models/php_version.dart';
import 'package:flutter_mamp/domain/models/server_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhpVersion', () {
    PhpVersion v(String version) => PhpVersion(
          version: version,
          binaryPath: '/bin/php$version',
          cgiPath: null,
        );

    test('shortLabel returns major.minor', () {
      expect(v('8.3.30').shortLabel, '8.3');
      expect(v('7.4.33').shortLabel, '7.4');
    });

    test('sorts newest-first when reversed', () {
      final list = [v('7.4.33'), v('8.5.2'), v('8.3.30')]
        ..sort((a, b) => b.compareTo(a));
      expect(list.map((e) => e.version).toList(),
          ['8.5.2', '8.3.30', '7.4.33']);
    });

    test('equality is by binary path', () {
      expect(v('8.3.30'), equals(v('8.3.30')));
      expect(v('8.3.30'), isNot(equals(v('8.4.0'))));
    });
  });

  group('ServerStatus', () {
    test('transition and active flags', () {
      expect(ServerStatus.starting.isTransitioning, isTrue);
      expect(ServerStatus.stopping.isTransitioning, isTrue);
      expect(ServerStatus.running.isActive, isTrue);
      expect(ServerStatus.stopped.isActive, isFalse);
    });
  });
}
