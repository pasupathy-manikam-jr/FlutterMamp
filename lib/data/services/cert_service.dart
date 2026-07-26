import 'dart:io';

/// Generates self-signed TLS certificates using MAMP's `openssl`.
///
/// Certs are cached per common-name under the app-support `certs/` directory so
/// we only shell out to openssl the first time a host enables SSL.
class CertService {
  const CertService();

  /// Ensure a cert/key pair exists for [commonName], generating one if needed.
  /// Returns their absolute paths.
  Future<({String certPath, String keyPath})> ensureCert({
    required String commonName,
    required String opensslPath,
    required String outDir,
  }) async {
    final dir = '$outDir/$commonName';
    await Directory(dir).create(recursive: true);
    final certPath = '$dir/cert.pem';
    final keyPath = '$dir/key.pem';

    if (File(certPath).existsSync() && File(keyPath).existsSync()) {
      return (certPath: certPath, keyPath: keyPath);
    }

    // A proper server *leaf* certificate: browsers reject a cert used for TLS
    // that is marked as a CA (BasicConstraints CA:TRUE) or lacks a SAN /
    // serverAuth EKU. These extensions produce a cert modern browsers accept
    // once it is trusted in the keychain.
    final result = await Process.run(opensslPath, [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256',
      '-keyout', keyPath,
      '-out', certPath,
      '-days', '825',
      '-subj', '/CN=$commonName',
      '-addext', 'subjectAltName=DNS:$commonName,DNS:localhost,IP:127.0.0.1',
      '-addext', 'basicConstraints=critical,CA:FALSE',
      '-addext', 'keyUsage=critical,digitalSignature,keyEncipherment',
      '-addext', 'extendedKeyUsage=serverAuth',
    ]);
    if (result.exitCode != 0) {
      throw StateError('openssl failed to create a certificate: ${result.stderr}');
    }
    return (certPath: certPath, keyPath: keyPath);
  }
}
