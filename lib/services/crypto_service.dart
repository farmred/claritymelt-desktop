import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;

/// Encryption utility for provider credentials.
/// Uses AES-256 for desktop credential storage.
class CryptoService {
  /// Generate a new random encryption key (base64 encoded).
  static String generateKey() {
    final key = enc.Key.fromSecureRandom(32);
    return key.base64;
  }

  /// Encrypt a plaintext string using AES-256.
  /// Returns `iv:ciphertext` (base64 encoded).
  static String encrypt(String plaintext, String base64Key) {
    final key = _getKey(base64Key);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypt a string produced by `encrypt()`.
  static String decrypt(String ciphertext, String base64Key) {
    final key = _getKey(base64Key);
    final parts = ciphertext.split(':');
    if (parts.length != 2) {
      throw const FormatException('Invalid ciphertext format — expected iv:ciphertext');
    }
    final iv = enc.IV.fromBase64(parts[0]);
    final encrypted = enc.Encrypted.fromBase64(parts[1]);
    final encrypter = enc.Encrypter(enc.AES(key));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// Mask a secret string, showing only first 4 and last 4 chars.
  static String maskSecret(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 8) {
      return '${value.substring(0, value.length > 2 ? 2 : 1)}***${value.substring(value.length - (value.length > 2 ? 2 : 1))}';
    }
    return '${value.substring(0, 4)}\u2022\u2022\u2022\u2022\u2022\u2022${value.substring(value.length - 4)}';
  }

  /// Encrypt credential JSON — convenience method.
  static String encryptCredentials(Map<String, String> credentials, String base64Key) {
    return encrypt(jsonEncode(credentials), base64Key);
  }

  /// Decrypt credential JSON — convenience method.
  static Map<String, String> decryptCredentials(String encrypted, String base64Key) {
    final json = decrypt(encrypted, base64Key);
    return Map<String, String>.from(jsonDecode(json));
  }

  /// Derive a Key from the stored base64 key material.
  static enc.Key _getKey(String base64Key) {
    try {
      return enc.Key.fromBase64(base64Key);
    } catch (_) {
      // If the key isn't valid base64 or wrong length, pad/truncate to 32 bytes
      final keyBytes = base64Decode(base64Key);
      final padded = List<int>.filled(32, 0);
      for (int i = 0; i < keyBytes.length && i < 32; i++) {
        padded[i] = keyBytes[i];
      }
      return enc.Key(Uint8List.fromList(padded));
    }
  }
}