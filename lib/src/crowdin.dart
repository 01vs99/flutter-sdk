import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crowdin_sdk/src/crowdin_api.dart';
import 'package:crowdin_sdk/src/crowdin_storage.dart';
import 'package:crowdin_sdk/src/crowdin_extractor.dart';
import 'package:crowdin_sdk/src/crowdin_mapper.dart';
import 'package:crowdin_sdk/src/real_time_preview/crowdin_preview_manager.dart';
import 'package:flutter/widgets.dart';

import 'common/gen_l10n_types.dart';
import 'crowdin_logger.dart';
import 'real_time_preview/crowdin_auth_config.dart';

enum InternetConnectionType { wifi, mobileData, ethernet, any }

class Crowdin {
  static String _distributionHash = '';
  static Duration? _updatesInterval;

  /// connection type logic will be implemented soon
  static InternetConnectionType _connectionType = InternetConnectionType.any;

  /// keeps app resource bundle for the last received distribution
  static AppResourceBundle? _arb;

  static Map<String, Object>? _arbTemplateAttributes;

  @visibleForTesting
  static set arb(AppResourceBundle? value) {
    _arb = value;
  }

  static AppResourceBundle? get currentArb => _arb;

  static DateTime? _translationTimeToUpdate;

  /// contains certain distribution file paths for locales
  static Map<String, dynamic> _distributionsMap = {};

  /// contains certain distribution file paths for locales
  static int? _timestamp;

  static List<String> _mappingFilePaths = [];

  static final CrowdinStorage _storage = CrowdinStorage();

  static late int? _timestampCached;

  static final _api = CrowdinApi();

  /// if _withRealTimeUpdates = true, real-time preview is enabled and authentication is required
  static bool _withRealTimeUpdates = false;

  static bool get withRealTimeUpdates => _withRealTimeUpdates;

  @visibleForTesting
  static set withRealTimeUpdates(bool value) {
    _withRealTimeUpdates = value;
  }

  /// contains configuration for real-time preview functionality
  static late CrowdinPreviewManager crowdinPreviewManager;

  /// contains all parameters needed for OAuth authentication
  static late CrowdinAuthConfig? _authConfig;

  /// Crowdin SDK initialization
  static Future<void> init({
    required String distributionHash,
    Duration? updatesInterval,
    InternetConnectionType? connectionType,
    bool withRealTimeUpdates = false,
    CrowdinAuthConfig? authConfigurations,
    Map<String, Object>? arbTemplateAttributes,
  }) async {
    await _storage.init();

    _arbTemplateAttributes = arbTemplateAttributes;

    _timestampCached = _storage.getTranslationTimestampFromStorage();
    _distributionHash = distributionHash;
    CrowdinLogger.printLog('distributionHash $_distributionHash');

    if (updatesInterval != null) {
      _updatesInterval = setUpdateInterval(updatesInterval);

      ///set initial value for _translationTimeToUpdate
      _translationTimeToUpdate = DateTime.now();
      CrowdinLogger.printLog('updatesInterval $_updatesInterval');
    }

    if (connectionType != null) {
      _connectionType = connectionType;
      CrowdinLogger.printLog('connectionType $_connectionType');
    }

    /// fetch manifest file to get certain paths for each locale distribution
    var manifest = await _api.getManifest(distributionHash: _distributionHash);

    if (manifest != null) {
      _distributionsMap = manifest['content'];

      /// fetch manifest file to check if new updates available
      _timestamp = manifest['timestamp'];

      _mappingFilePaths = (manifest['mapping'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }

    _withRealTimeUpdates = withRealTimeUpdates;

    _authConfig = authConfigurations;

    if (withRealTimeUpdates && _authConfig != null) {
      setUpRealTimePreviewManager(_authConfig!);
    }
  }

  /// Load translations from Crowdin for a specific locale
  static Future<void> loadTranslations(Locale locale) async {
    Map<String, dynamic>? distribution;
    //change first
    _arb = null;
    try {
      distribution = _storage.getTranslationFromStorage(locale);
      if (distribution != null) {
        _arb = AppResourceBundle(distribution);
        if (_withRealTimeUpdates) {
          crowdinPreviewManager.setPreviewArb(
              _arb!); // set default translations for real-time preview
        }
      }
    } catch (_) {}

    if (!await _isConnectionTypeAllowed(_connectionType)) {
      return; // return from function if connection type is forbidden for downloading translations
    }

    bool canUpdate = !canUseCachedTranslation(
      distributionTimeToUpdate: _translationTimeToUpdate,
      translationTimestamp: _timestamp,
      cachedTranslationTimestamp: _timestampCached,
    );

    if (!canUpdate) {
      return;
    }

    try {
      // map locales to avoid problems with different language codes on Crowdin side and supported
      // by GlobalMaterialLocalizations class for some countries
      Locale mappedLocale =
      _distributionsMap.keys.contains(locale.toLanguageTag())
          ? locale
          : CrowdinMapper.mapLocale(locale);

      distribution = await _api.loadTranslations(
          path: _distributionsMap[mappedLocale.toLanguageTag()][0] as String,
          distributionHash: _distributionHash,
          timeStamp: _timestamp.toString());
      if (distribution != null) {
        /// todo remove when distribution file locale will be fixed
        distribution['@@locale'] = locale.toString();
        if (_arbTemplateAttributes != null) {
          distribution.addAll(_arbTemplateAttributes!);
        }
        _storage.setDistributionToStorage(
          jsonEncode(distribution),
        );
        _arb = AppResourceBundle(distribution);

        // set initial value for _translationTimeToUpdate
        if (_updatesInterval != null) {
          _translationTimeToUpdate = DateTime.now().add(_updatesInterval!);
        }

        if (_timestamp != null && _timestamp != _timestampCached) {
          _storage.setTranslationTimeStampStorage(_timestamp!);
          _timestampCached = _timestamp;
        }
      }
    } catch (ex) {
      CrowdinLogger.printLog(
          "something went wrong. Crowdin couldn't download translation for '$locale' locale. Next exception occurred: $ex");
      _arb = null;
      return;
    }
    if (_withRealTimeUpdates) {
      crowdinPreviewManager.setPreviewArb(_arb!);
    }
  }

  @visibleForTesting
  static void setUpRealTimePreviewManager(CrowdinAuthConfig authConfig) {
    crowdinPreviewManager = CrowdinPreviewManager(
      config: authConfig,
      distributionHash: _distributionHash,
      mappingFilePaths: _mappingFilePaths,
    );
  }

  static final Extractor _extractor = Extractor();

  /// Returns translation for a given key and locale
  static String? getText(
      String locale,
      String key, [
        Map<String, dynamic> args = const {},
      ]) {
    if (_arb != null) {
      try {
        return _extractor.getText(
          locale,
          _withRealTimeUpdates ? crowdinPreviewManager.previewArb : _arb!,
          key,
          args,
        );
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}

@visibleForTesting
bool canUseCachedTranslation({
  DateTime? distributionTimeToUpdate,
  int? translationTimestamp,
  int? cachedTranslationTimestamp,
}) {
  if (distributionTimeToUpdate != null) {
    return distributionTimeToUpdate.isAfter(DateTime.now());
  } else {
    return translationTimestamp == cachedTranslationTimestamp;
  }
}

Future<bool> _isConnectionTypeAllowed(
    InternetConnectionType connectionType) async {
  var connectionResult = await Connectivity().checkConnectivity();
  //ignore: unnecessary_type_check
  final List<ConnectivityResult> connectionStatus = connectionResult is Iterable
      ? [...connectionResult as Iterable]
  //ignore: unnecessary_cast
      : [connectionResult as ConnectivityResult];

  switch (connectionType) {
    case InternetConnectionType.any:
      return !connectionStatus.contains(ConnectivityResult.none);
    case InternetConnectionType.wifi:
      return connectionStatus.contains(ConnectivityResult.wifi);
    case InternetConnectionType.mobileData:
      return connectionStatus.contains(ConnectivityResult.mobile);
    case InternetConnectionType.ethernet:
      return connectionStatus.contains(ConnectivityResult.ethernet);
  }
}

@visibleForTesting
Duration setUpdateInterval(Duration updatesInterval) {
  ///minimum updates interval is 15 minutes
  Duration updInterval;
  if (updatesInterval.inMinutes < 15) {
    updInterval = const Duration(minutes: 15);
    CrowdinLogger.printLog(
        'updates interval was settled to the default minimum value 15 minutes');
  } else {
    updInterval = updatesInterval;
  }
  return updInterval;
}
