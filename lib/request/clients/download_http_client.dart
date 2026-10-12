import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';

class DownloadHttpClient {
  DownloadHttpClient._();

  static final DownloadHttpClient instance = DownloadHttpClient._();

  Future<Response<ResponseBody>> getStream(
    String url, {
    Map<String, dynamic> headers = const {},
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async {
    try {
      return await DioFactory.downloadDio.get<ResponseBody>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          receiveTimeout: receiveTimeout,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<String> getPlain(
    String url, {
    Map<String, dynamic> headers = const {},
    Duration? receiveTimeout,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await DioFactory.downloadDio.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          receiveTimeout: receiveTimeout,
        ),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      return response.data ?? '';
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  /// Reads a byte range of a URL, returning the bytes and the total file size
  /// parsed from `Content-Range`. Returns null when the server ignores the
  /// Range header (it replies with the whole body or a 200).
  Future<({Uint8List bytes, int? totalSize})?> getRangeBytes(
    String url, {
    int start = 0,
    int end = 256 * 1024 - 1,
    Duration receiveTimeout = const Duration(seconds: 15),
    Map<String, dynamic> headers = const {},
  }) async {
    try {
      final response = await DioFactory.downloadDio.get<ResponseBody>(
        url,
        options: Options(
          headers: {...headers, 'Range': 'bytes=$start-$end'},
          responseType: ResponseType.stream,
          receiveTimeout: receiveTimeout,
        ),
      );
      if (response.statusCode != 206) {
        // The server ignored the Range header; drain the body so the
        // underlying connection is released instead of hanging on a socket.
        await response.data!.stream.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.data!.stream) {
        builder.add(chunk);
      }
      final contentRange = response.headers.value('content-range');
      final totalSize = contentRange == null
          ? null
          : int.tryParse(contentRange.split('/').last.trim());
      return (bytes: builder.takeBytes(), totalSize: totalSize);
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<void> download(
    String url,
    String savePath, {
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      await DioFactory.downloadDio.download(
        url,
        savePath,
        options: Options(headers: headers),
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
