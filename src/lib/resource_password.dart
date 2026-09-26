import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'resource_password_key.dart';

/// Matches tools/encrypt_resource_password.py: nonce + ciphertext + GCM tag.
Future<String> restoreResourcePassword(String ciphertext) async {
  if (ciphertext.isEmpty) throw StateError('未配置资源包密码密文');
  try {
    final bytes = base64Decode(ciphertext);
    if (bytes.length <= 28) throw const FormatException();
    final box = SecretBox(
      bytes.sublist(12, bytes.length - 16),
      nonce: bytes.sublist(0, 12),
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    final clear = await AesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(resourcePasswordWrappingKey),
    );
    final password = utf8.decode(clear);
    if (password.isEmpty) throw const FormatException();
    return password;
  } catch (_) {
    // Never include decrypted bytes or library exception details in logs/UI.
    throw StateError('资源包密码密文配置无效，请重新生成并完整复制密文');
  }
}
