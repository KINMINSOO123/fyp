import '../../../core/network/api_client.dart';
import '../domain/leftover_models.dart';

abstract interface class LeftoverGateway {
  Future<LeftoverDay> list({String? date});
  Future<List<CharityPartner>> activeCharities();
  Future<List<DonationRow>> donations(String date);
  Future<void> donate(
    String resultId,
    int quantity,
    String charityId,
    String? notes,
  );
  Future<void> recordWaste(String resultId, int quantity, String reason);
  Future<void> advanceDonation(String donationId, String status);
}

class LeftoverService implements LeftoverGateway {
  LeftoverService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  dynamic _data(Map<String, dynamic> response) {
    if (!response.containsKey('data')) {
      throw const FormatException('Invalid leftover response.');
    }
    return response['data'];
  }

  @override
  Future<LeftoverDay> list({String? date}) async {
    final path = date == null
        ? '/api/leftovers'
        : Uri(
            path: '/api/leftovers',
            queryParameters: {'date': date},
          ).toString();
    final data = _data(await _apiClient.getJson(path));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid leftover list.');
    }
    return LeftoverDay.fromJson(data);
  }

  @override
  Future<List<CharityPartner>> activeCharities() async {
    final data = _data(await _apiClient.getJson('/api/leftovers/charities'));
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid charity list.');
    }
    return data
        .map((item) => CharityPartner.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<DonationRow>> donations(String date) async {
    final uri = Uri(
      path: '/api/donations',
      queryParameters: {'date': date, 'page': '1'},
    );
    final data = _data(await _apiClient.getJson(uri.toString()));
    if (data is! Map<String, dynamic> || data['items'] is! List) {
      throw const FormatException('Invalid donation list.');
    }
    final rows = data['items'] as List;
    if (rows.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid donation record.');
    }
    return rows
        .map((item) => DonationRow.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> donate(
    String resultId,
    int quantity,
    String charityId,
    String? notes,
  ) async {
    await _apiClient.postJson('/api/donations', {
      'dailyResultId': resultId,
      'quantity': quantity,
      'charityPartnerId': charityId,
      'notes': notes,
      'confirm': true,
    });
  }

  @override
  Future<void> recordWaste(String resultId, int quantity, String reason) async {
    await _apiClient.postJson('/api/waste-records', {
      'dailyResultId': resultId,
      'quantity': quantity,
      'disposalReason': reason,
      'confirm': true,
    });
  }

  @override
  Future<void> advanceDonation(String donationId, String status) async {
    await _apiClient.patchJson(
      '/api/donations/${Uri.encodeComponent(donationId)}/status',
      {'status': status, 'confirm': true},
    );
  }

  void close() => _apiClient.close();
}

abstract interface class CharityAdminGateway {
  Future<List<CharityPartner>> list();
  Future<void> save({
    String? id,
    required String name,
    required String? contactInfo,
    required bool isActive,
  });
}

class CharityAdminService implements CharityAdminGateway {
  CharityAdminService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();
  final ApiClient _apiClient;

  @override
  Future<List<CharityPartner>> list() async {
    final response = await _apiClient.getJson('/api/admin/charity-partners');
    final data = response['data'];
    if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid charity list.');
    }
    return data
        .map((item) => CharityPartner.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> save({
    String? id,
    required String name,
    required String? contactInfo,
    required bool isActive,
  }) async {
    final body = {
      'name': name,
      'contactInfo': contactInfo,
      'isActive': isActive,
    };
    if (id == null) {
      await _apiClient.postJson('/api/admin/charity-partners', body);
    } else {
      await _apiClient.patchJson(
        '/api/admin/charity-partners/${Uri.encodeComponent(id)}',
        body,
      );
    }
  }

  void close() => _apiClient.close();
}
