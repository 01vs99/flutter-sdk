import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crowdin_logger.dart';

class CrowdinApi {
  static String baseUrl = "https://distributions.crowdin.net";

  Future<Map<String, dynamic>?> loadTranslations({
    required String distributionHash,
    required String timeStamp,
    String? path,
  }) async {
    try {
      var response = await http.get(Uri.parse(
          '${CrowdinApi.baseUrl}/$distributionHash$path?timestamp=$timeStamp'));
      Map<String, dynamic> responseDecoded =
      jsonDecode(utf8.decode(response.bodyBytes));
      return responseDecoded;
    } catch (ex) {
      CrowdinLogger.printLog(
          "something went wrong. Crowdin couldn't download mapping file. Next exception occurred: $ex");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getManifest({
    required String distributionHash,
  }) async {
    try {
      var response = await http.get(
        Uri.parse('${CrowdinApi.baseUrl}/$distributionHash/manifest.json'),
      );
      Map<String, dynamic> responseDecoded =
      jsonDecode(utf8.decode(response.bodyBytes));
      return responseDecoded;
    } catch (ex) {
      CrowdinLogger.printLog(
          "something went wrong. Crowdin couldn't download manifest file. Next exception occurred: $ex");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getMapping({
    required String distributionHash,
    required String mappingFilePath,
  }) async {
    try {
      var response = await http.get(
          Uri.parse('${CrowdinApi.baseUrl}/$distributionHash$mappingFilePath'));
      Map<String, dynamic> responseDecoded =
      jsonDecode(utf8.decode(response.bodyBytes));
      return responseDecoded;
    } catch (ex) {
      CrowdinLogger.printLog(
          "something went wrong. Crowdin couldn't download mapping file. Next exception occurred: $ex");
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMetadata({
    required String accessToken,
    required String distributionHash,
    String? organizationName,
  }) async {
    try {
      String organizationDomain =
      organizationName != null ? '$organizationName.' : '';
      var response = await http.get(
          Uri.parse(
              'https://${organizationDomain}api.crowdin.com/api/v2/distributions/metadata?hash=$distributionHash'),
          headers: {'Authorization': 'Bearer $accessToken'});
      Map<String, dynamic> responseDecoded =
      jsonDecode(utf8.decode(response.bodyBytes));
      return responseDecoded;
    } catch (ex) {
      CrowdinLogger.printLog(
          "something went wrong. Crowdin couldn't download metadata file. Next exception occurred: $ex");
      return null;
    }
  }

  Future<String?> getWebsocketTicket({
    required String accessToken,
    required String event,
    String? organizationName,
  }) async {
    try {
      String organizationDomain =
      organizationName != null ? '$organizationName.' : '';
      var response = await http.post(
          Uri.parse(
              'https://${organizationDomain}api.crowdin.com/api/v2/user/websocket-ticket'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            "event": event,
            "context": {"mode": "translate"}
          }));
      Map<String, dynamic> responseDecoded =
      jsonDecode(utf8.decode(response.bodyBytes));
      return responseDecoded['data']['ticket'];
    } catch (e) {
      CrowdinLogger.printLog(
          "Something went wrong. Crowdin couldn't get the WebSocket ticket. The following exception was thrown:: $e");
      return null;
    }
  }
}
