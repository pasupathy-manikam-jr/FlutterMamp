import 'dart:io';

/// Generates TLS certificates using a local root CA (the "mkcert" model).
///
/// A single self-signed **root CA** is created once and trusted in the keychain
/// (via the Trust Certificate action). Each site gets a **leaf** certificate
/// signed by that CA. Browsers then accept every site's cert — you only trust
/// the CA once. This avoids the "can't trust a leaf cert as a root" problem.
class CertService {
  const CertService();

  /// Path to the local root CA certificate — this is the file to trust.
  String caCertPath(String outDir) => '$outDir/_ca/ca.pem';

  /// Ensure a leaf cert/key exists for [commonName], signed by the local CA
  /// (creating the CA first if needed). Returns the leaf paths (used by the
  /// web servers).
  Future<({String certPath, String keyPath})> ensureCert({
    required String commonName,
    required String opensslPath,
    required String outDir,
  }) async {
    final ca = await _ensureCa(opensslPath, outDir);

    final dir = '$outDir/$commonName';
    await Directory(dir).create(recursive: true);
    final certPath = '$dir/cert.pem';
    final keyPath = '$dir/key.pem';
    if (File(certPath).existsSync() && File(keyPath).existsSync()) {
      return (certPath: certPath, keyPath: keyPath);
    }

    final csrPath = '$dir/req.csr';
    final extPath = '$dir/ext.cnf';

    // 1) leaf key + CSR
    final csr = await Process.run(opensslPath, [
      'req', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', keyPath, '-out', csrPath,
      '-subj', '/CN=$commonName',
    ]);
    if (csr.exitCode != 0) {
      throw StateError('openssl failed to create a CSR: ${csr.stderr}');
    }

    // 2) leaf extensions (SAN, not-a-CA, serverAuth)
    await File(extPath).writeAsString(
      'subjectAltName=DNS:$commonName,DNS:localhost,IP:127.0.0.1\n'
      'basicConstraints=critical,CA:FALSE\n'
      'keyUsage=critical,digitalSignature,keyEncipherment\n'
      'extendedKeyUsage=serverAuth\n',
    );

    // 3) sign the leaf with the local CA
    final sign = await Process.run(opensslPath, [
      'x509', '-req', '-in', csrPath,
      '-CA', ca.cert, '-CAkey', ca.key, '-CAcreateserial',
      '-out', certPath, '-days', '825', '-sha256',
      '-extfile', extPath,
    ]);
    if (sign.exitCode != 0) {
      throw StateError('openssl failed to sign the certificate: ${sign.stderr}');
    }

    return (certPath: certPath, keyPath: keyPath);
  }

  /// Create the local root CA once (idempotent).
  Future<({String cert, String key})> _ensureCa(
      String opensslPath, String outDir) async {
    final caDir = '$outDir/_ca';
    await Directory(caDir).create(recursive: true);
    final caCert = '$caDir/ca.pem';
    final caKey = '$caDir/ca-key.pem';
    if (File(caCert).existsSync() && File(caKey).existsSync()) {
      return (cert: caCert, key: caKey);
    }
    final result = await Process.run(opensslPath, [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256',
      '-days', '3650',
      '-keyout', caKey, '-out', caCert,
      '-subj', '/CN=OricDevServer Local CA',
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
    ]);
    if (result.exitCode != 0) {
      throw StateError('openssl failed to create the local CA: ${result.stderr}');
    }
    return (cert: caCert, key: caKey);
  }
}
