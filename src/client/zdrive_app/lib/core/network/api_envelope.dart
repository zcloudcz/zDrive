import 'package:dio/dio.dart';

/// Thrown when the backend envelope reports `success: false`.
///
/// The backend wraps every JSON response in `{ success, data, error }`
/// (see `ZDrive.Shared.DTOs.ApiResponse<T>`). A logical failure still arrives
/// as HTTP 200 with `success: false`, so it would otherwise slip past Dio's
/// status-code error handling unnoticed.
class ApiException implements Exception {
  final String code;
  final String message;

  const ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException($code): $message';
}

/// Returns the inner `data` of the backend envelope, or throws [ApiException]
/// when the envelope reports failure.
///
/// Defensive: if the body is not an envelope (no `success` key) it is returned
/// as-is, so non-enveloped responses (should not happen against our backend)
/// do not blow up.
dynamic unwrapData(Response response) {
  final body = response.data;
  if (body is Map && body.containsKey('success')) {
    if (body['success'] == true) {
      return body['data'];
    }
    final error = body['error'] as Map?;
    throw ApiException(
      error?['code'] as String? ?? 'unknown',
      error?['message'] as String? ?? 'Request failed',
    );
  }
  return body;
}

/// Unwraps an envelope whose `data` is a JSON object.
Map<String, dynamic> unwrapMap(Response response) {
  return (unwrapData(response) as Map).cast<String, dynamic>();
}

/// Unwraps an envelope whose `data` is a JSON array of objects.
List<Map<String, dynamic>> unwrapMapList(Response response) {
  return (unwrapData(response) as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
}

/// Verifies the envelope reports success; ignores the payload.
/// For endpoints that return `ApiResponse<bool>` / `<int>` and similar.
void ensureSuccess(Response response) => unwrapData(response);
