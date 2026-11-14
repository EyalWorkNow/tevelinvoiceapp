import 'client.dart';
import '../state/session.dart';

class CrmRemoteRecord {
  const CrmRemoteRecord({
    required this.customerId,
    required this.revision,
    required this.record,
  });
  final String customerId;
  final int revision;
  final Map<String, dynamic> record;
  factory CrmRemoteRecord.fromJson(Map<String, dynamic> value) =>
      CrmRemoteRecord(
        customerId: value['customerId'] as String,
        revision: value['revision'] as int,
        record: Map<String, dynamic>.from(value['record'] as Map),
      );
}

abstract interface class CustomerCrmRemote {
  bool get enabled;
  String? get userId;
  Future<List<CrmRemoteRecord>> load(String businessId);
  Future<CrmRemoteRecord> write(
    String businessId,
    String customerId,
    Map<String, Object?> record,
    int expectedRevision,
    String mutationId, {
    bool importLocal = false,
  });
}

class CustomerCrmApi implements CustomerCrmRemote {
  final _api = ApiClient.instance;
  @override
  bool get enabled => _api.hasDeviceToken;
  @override
  String? get userId => session.account?.userId;
  @override
  Future<List<CrmRemoteRecord>> load(String businessId) async {
    final records = <CrmRemoteRecord>[];
    for (var offset = 0; ; offset += 100) {
      final json = await _api.getForBusiness(
        businessId,
        '/crm/customers',
        query: {'offset': '$offset', 'limit': '100'},
      );
      final page = (json['records'] as List)
          .map(
            (item) => CrmRemoteRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      records.addAll(page);
      if (records.length >= (json['total'] as num).toInt()) return records;
      if (page.isEmpty || offset >= 1000000) {
        throw const FormatException('Invalid CRM pagination');
      }
    }
  }

  @override
  Future<CrmRemoteRecord> write(
    String businessId,
    String customerId,
    Map<String, Object?> record,
    int expectedRevision,
    String mutationId, {
    bool importLocal = false,
  }) async => CrmRemoteRecord.fromJson(
    await _api.putForBusiness(businessId, '/crm/customers/$customerId', {
      'record': _wireRecord(record),
      'expectedRevision': expectedRevision,
      'mutationId': mutationId,
      if (importLocal) 'importLocal': true,
    }),
  );

  Map<String, Object?> _wireRecord(Map<String, Object?> record) {
    Map<String, Object?> instantFields(Map value, List<String> fields) {
      final result = Map<String, Object?>.from(value);
      for (final key in fields) {
        final text = result[key];
        if (text is String) {
          result[key] = DateTime.parse(text).toUtc().toIso8601String();
        }
      }
      return result;
    }

    return {
      ...record,
      'notes': [
        for (final value in record['notes'] as List? ?? const [])
          instantFields(value as Map, ['createdAt', 'updatedAt']),
      ],
      'reminders': [
        for (final value in record['reminders'] as List? ?? const [])
          instantFields(value as Map, ['dueAt']),
      ],
      'jobs': [
        for (final value in record['jobs'] as List? ?? const [])
          instantFields(value as Map, ['scheduledAt', 'createdAt']),
      ],
    };
  }
}
