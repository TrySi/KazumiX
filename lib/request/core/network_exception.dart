enum NetworkExceptionType {
  badCertificate,
  badResponse,
  cancel,
  connectionError,
  connectionTimeout,
  receiveTimeout,
  sendTimeout,
  parseError,
  unknown,
}

class NetworkException implements Exception {
  final NetworkExceptionType type;
  final String message;
  final int? statusCode;
  final Object? rawError;
  final StackTrace? stackTrace;

  const NetworkException({
    required this.type,
    required this.message,
    this.statusCode,
    this.rawError,
    this.stackTrace,
  });

  /// Whether the request never reached the server (or never got a response) due
  /// to connectivity, DNS, or a timeout. These can be treated as a circuit
  /// break signal instead of retrying endlessly.
  bool get isConnectivityFailure =>
      type == NetworkExceptionType.connectionError ||
      type == NetworkExceptionType.connectionTimeout ||
      type == NetworkExceptionType.receiveTimeout ||
      type == NetworkExceptionType.sendTimeout;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'NetworkException.$type$status: $message';
  }
}
