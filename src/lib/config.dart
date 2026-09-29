import 'resource_password.dart';

/// 内容专用配置；下载地址和 ZIP 密码密文必须对应同一批资源包。
class ResourceConfig {
//   static const baseUrl = 'https://yzc-1256369926.cos.ap-shanghai.myqcloud.com/yzc/textbook/';
  static const baseUrl = 'http://10.0.0.212:8080/textbook/';
  static const passwordCiphertext = 'zcm/AQ6GCXJ2qd1lBYh9eePWvTE0q3MY5TjoAd+DT7N7Wq260TSNgGILohCt00GocMeLIhfs';

  // 不接受外部密文，也不回退到其他模块的密码。
  static Future<String> restorePassword() async {
    try {
      return await restoreResourcePassword(passwordCiphertext);
    } catch (_) {
      throw StateError('内容资源包密码密文配置无效，请检查本模块配置');
    }
  }

  static Uri get base {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty || uri.hasQuery || uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw StateError('内容资源包下载地址无效');
    }
    return uri.replace(path: uri.path.endsWith('/') ? uri.path : uri.path + '/');
  }
}
