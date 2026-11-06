import 'package:http/http.dart' as http;

/// Política global de rede: com o modo offline forçado, nenhuma requisição
/// HTTP sai do app (todos os clientes passam por [GuardedClient]).
class NetPolicy {
  static bool offline = false;
}

class GuardedClient extends http.BaseClient {
  GuardedClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (NetPolicy.offline) {
      return Future.error(http.ClientException('modo offline', request.url));
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
