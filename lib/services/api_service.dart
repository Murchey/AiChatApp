import 'package:dio/dio.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://your-api-base-url.com/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
  }

  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<Response> getCharacters() {
    return _dio.get('/characters');
  }

  Future<Response> getCharacter(String id) {
    return _dio.get('/characters/$id');
  }

  Future<Response> getConversations() {
    return _dio.get('/conversations');
  }

  Future<Response> getMessages(String conversationId) {
    return _dio.get('/conversations/$conversationId/messages');
  }

  Future<Response> sendMessage(String conversationId, String content) {
    return _dio.post('/conversations/$conversationId/messages', data: {
      'content': content,
    });
  }

  Future<Response> createConversation(String characterId) {
    return _dio.post('/conversations', data: {
      'character_id': characterId,
    });
  }
}
