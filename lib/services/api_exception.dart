import 'package:dio/dio.dart';

/// A friendly error extracted from a ProblemDetails / validation response.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;

  /// Build a user-facing message from a Dio response or a thrown DioException.
  static ApiException from(Object error) {
    if (error is DioException) {
      final res = error.response;
      if (res != null) return _fromResponse(res);
      return ApiException('Network error. Please check your connection.');
    }
    if (error is Response) return _fromResponse(error);
    return ApiException(error.toString());
  }

  static ApiException _fromResponse(Response res) {
    final data = res.data;
    String msg = 'Something went wrong.';
    if (data is Map) {
      // Validation problem: { errors: { Field: [messages] } }
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        msg = first is List && first.isNotEmpty ? first.first.toString() : errors.values.first.toString();
      } else if (data['detail'] is String) {
        msg = data['detail'] as String;
      } else if (data['title'] is String) {
        msg = data['title'] as String;
      } else if (data['message'] is String) {
        msg = data['message'] as String;
      }
    }
    return ApiException(msg, statusCode: res.statusCode);
  }
}

/// True for a 2xx response.
bool isOk(Response r) => r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 300;
