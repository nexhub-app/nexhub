/// 加解密工具：md5 / base64 / rc4 / aes / sha / hmac / hex（供 js_context 与源内嵌脚本复用）。
/// 纯逻辑、无 UI 依赖，可直接单测。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class CryptoUtils {
  CryptoUtils._();

  /// MD5 十六进制串。
  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static String base64EncodeString(String input) =>
      base64Encode(utf8.encode(input));

  static String base64DecodeString(String input) =>
      utf8.decode(base64Decode(input));

  /// base64 解码为原始字节列表。
  static List<int> base64DecodeBytes(String input) =>
      base64Decode(input).toList();

  /// 字节列表编码为 base64 字符串。
  static String base64EncodeBytes(List<int> bytes) =>
      base64Encode(bytes);

  /// SHA-1 / SHA-256 / SHA-512 十六进制串。
  static String sha1Hex(String input) =>
      sha1.convert(utf8.encode(input)).toString();

  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static String sha512Hex(String input) =>
      sha512.convert(utf8.encode(input)).toString();

  /// HMAC 十六进制串。[algorithm] 支持 'sha1' / 'sha256' / 'sha512'，缺省 sha256。
  static String hmacHex(String key, String data,
      {String algorithm = 'sha256'}) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);
    final Hmac hmac;
    switch (algorithm) {
      case 'sha1':
        hmac = Hmac(sha1, keyBytes);
        break;
      case 'sha512':
        hmac = Hmac(sha512, keyBytes);
        break;
      default:
        hmac = Hmac(sha256, keyBytes);
    }
    return hmac.convert(dataBytes).toString();
  }

  /// 字节数组转十六进制小写字符串。
  static String hexEncode(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// 十六进制字符串转字节数组。非法字符抛 [FormatException]。
  static List<int> hexDecode(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    if (clean.length % 2 != 0) {
      throw FormatException('hex string must have even length: $hex');
    }
    final out = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// RC4 流密码（咕咕番等源使用）。结果以字符串返回（spec 约定）。
  static String rc4(String data, String key) {
    final S = List<int>.generate(256, (i) => i);
    final keyBytes = utf8.encode(key);
    if (keyBytes.isEmpty) return data;
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + S[i] + keyBytes[i % keyBytes.length]) & 0xff;
      final t = S[i];
      S[i] = S[j];
      S[j] = t;
    }
    final dataBytes = utf8.encode(data);
    final out = Uint8List(dataBytes.length);
    int a = 0;
    int b = 0;
    for (int i = 0; i < dataBytes.length; i++) {
      a = (a + 1) & 0xff;
      b = (b + S[a]) & 0xff;
      final t = S[a];
      S[a] = S[b];
      S[b] = t;
      out[i] = dataBytes[i] ^ S[(S[a] + S[b]) & 0xff];
    }
    return String.fromCharCodes(out);
  }

  /// AES-CBC + PKCS7 解密。
  static String aesCbcDecrypt(
    List<int> cipher, {
    required List<int> key,
    required List<int> iv,
  }) {
    final cipherImpl =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipherImpl.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(
          KeyParameter(Uint8List.fromList(key)),
          Uint8List.fromList(iv),
        ),
        null,
      ),
    );
    final out = cipherImpl.process(Uint8List.fromList(cipher));
    return utf8.decode(out);
  }

  /// AES-CBC + PKCS7 加密，返回密文字节。
  static List<int> aesCbcEncrypt(
    List<int> plain, {
    required List<int> key,
    required List<int> iv,
  }) {
    _validateAesKey(key);
    final cipherImpl =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipherImpl.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(
          KeyParameter(Uint8List.fromList(key)),
          Uint8List.fromList(iv),
        ),
        null,
      ),
    );
    return cipherImpl.process(Uint8List.fromList(plain)).toList();
  }

  /// AES-ECB + PKCS7 加密，返回密文字节。
  static List<int> aesEcbEncrypt(
    List<int> plain, {
    required List<int> key,
  }) {
    _validateAesKey(key);
    final cipherImpl =
        PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
    cipherImpl.init(
      true,
      PaddedBlockCipherParameters(
        KeyParameter(Uint8List.fromList(key)),
        null,
      ),
    );
    return cipherImpl.process(Uint8List.fromList(plain)).toList();
  }

  /// AES-ECB + PKCS7 解密，返回明文字节。
  static List<int> aesEcbDecrypt(
    List<int> cipher, {
    required List<int> key,
  }) {
    _validateAesKey(key);
    final cipherImpl =
        PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
    cipherImpl.init(
      false,
      PaddedBlockCipherParameters(
        KeyParameter(Uint8List.fromList(key)),
        null,
      ),
    );
    return cipherImpl.process(Uint8List.fromList(cipher)).toList();
  }

  /// AES-CFB 流模式加密（反馈为密文，支持任意长度）。返回密文字节。
  static List<int> aesCfbEncrypt(
    List<int> plain, {
    required List<int> key,
    required List<int> iv,
  }) {
    _validateAesKey(key);
    final out = <int>[];
    var feedback = List<int>.from(iv);
    for (var i = 0; i < plain.length; i += 16) {
      final keystream = _aesEncryptBlock(feedback, key);
      final end = i + 16 > plain.length ? plain.length : i + 16;
      final cipherBlock = <int>[];
      for (var j = i; j < end; j++) {
        cipherBlock.add(plain[j] ^ keystream[j - i]);
      }
      out.addAll(cipherBlock);
      feedback = cipherBlock.length == 16
          ? cipherBlock
          : [...cipherBlock, ...List<int>.filled(16 - cipherBlock.length, 0)];
    }
    return out;
  }

  /// AES-CFB 流模式解密。返回明文字节。
  static List<int> aesCfbDecrypt(
    List<int> cipher, {
    required List<int> key,
    required List<int> iv,
  }) {
    _validateAesKey(key);
    final out = <int>[];
    var feedback = List<int>.from(iv);
    for (var i = 0; i < cipher.length; i += 16) {
      final keystream = _aesEncryptBlock(feedback, key);
      final end = i + 16 > cipher.length ? cipher.length : i + 16;
      for (var j = i; j < end; j++) {
        out.add(cipher[j] ^ keystream[j - i]);
      }
      final cipherBlock = cipher.sublist(i, end);
      feedback = cipherBlock.length == 16
          ? cipherBlock
          : [...cipherBlock, ...List<int>.filled(16 - cipherBlock.length, 0)];
    }
    return out;
  }

  /// AES-OFB 流模式（加密解密同一操作，反馈为密钥流输出）。返回结果字节。
  static List<int> aesOfbProcess(
    List<int> data, {
    required List<int> key,
    required List<int> iv,
  }) {
    _validateAesKey(key);
    final out = <int>[];
    var feedback = List<int>.from(iv);
    for (var i = 0; i < data.length; i += 16) {
      feedback = _aesEncryptBlock(feedback, key);
      final end = i + 16 > data.length ? data.length : i + 16;
      for (var j = i; j < end; j++) {
        out.add(data[j] ^ feedback[j - i]);
      }
    }
    return out;
  }

  // ---- AES internals ----

  /// 校验 AES key 长度（16 / 24 / 32 字节）。
  static void _validateAesKey(List<int> key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError(
          'AES key must be 16/24/32 bytes, got ${key.length}');
    }
  }

  /// 单块 AES 加密（16 字节输入 → 16 字节输出）。
  static List<int> _aesEncryptBlock(List<int> block, List<int> key) {
    final engine = AESEngine()
      ..init(true, KeyParameter(Uint8List.fromList(key)));
    final out = Uint8List(16);
    engine.processBlock(
      Uint8List.fromList(block.sublist(0, 16)),
      0,
      out,
      0,
    );
    return out.toList();
  }
}
