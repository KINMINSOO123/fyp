class LeftoverRow {
  const LeftoverRow({
    required this.dailyResultId,
    required this.breadCategoryName,
    required this.leftover,
    required this.donated,
    required this.wasted,
    required this.remainingUnallocated,
  });
  final String dailyResultId;
  final String breadCategoryName;
  final int leftover;
  final int donated;
  final int wasted;
  final int remainingUnallocated;

  factory LeftoverRow.fromJson(Map<String, dynamic> json) {
    if (json['dailyResultId'] is! String ||
        json['breadCategoryName'] is! String ||
        json['dataOrigin'] != 'SIMULATION_GENERATED' ||
        json['leftover'] is! int ||
        json['donated'] is! int ||
        json['wasted'] is! int ||
        json['remainingUnallocated'] is! int) {
      throw const FormatException('Invalid leftover result.');
    }
    final leftover = json['leftover'] as int;
    final donated = json['donated'] as int;
    final wasted = json['wasted'] as int;
    final remaining = json['remainingUnallocated'] as int;
    if (leftover < 0 ||
        donated < 0 ||
        wasted < 0 ||
        remaining < 0 ||
        leftover != donated + wasted + remaining) {
      throw const FormatException('Leftover quantities do not reconcile.');
    }
    return LeftoverRow(
      dailyResultId: json['dailyResultId'] as String,
      breadCategoryName: json['breadCategoryName'] as String,
      leftover: leftover,
      donated: donated,
      wasted: wasted,
      remainingUnallocated: remaining,
    );
  }
}

class LeftoverDay {
  const LeftoverDay({required this.date, required this.items});
  final String date;
  final List<LeftoverRow> items;
  factory LeftoverDay.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (json['date'] is! String ||
        items is! List ||
        items.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid leftover list.');
    }
    return LeftoverDay(
      date: json['date'] as String,
      items: items
          .map((item) => LeftoverRow.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CharityPartner {
  const CharityPartner({
    required this.id,
    required this.name,
    required this.contactInfo,
    required this.isActive,
  });
  final String id;
  final String name;
  final String? contactInfo;
  final bool isActive;
  factory CharityPartner.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['isActive'] is! bool ||
        (json['contactInfo'] != null && json['contactInfo'] is! String)) {
      throw const FormatException('Invalid charity partner.');
    }
    return CharityPartner(
      id: json['id'] as String,
      name: json['name'] as String,
      contactInfo: json['contactInfo'] as String?,
      isActive: json['isActive'] as bool,
    );
  }
}

class DonationRow {
  const DonationRow({
    required this.id,
    required this.charityPartnerName,
    required this.quantity,
    required this.status,
  });
  final String id;
  final String charityPartnerName;
  final int quantity;
  final String status;
  factory DonationRow.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['quantity'] is! int ||
        json['quantity'] <= 0 ||
        json['status'] is! String ||
        json['charityPartnerName'] is! String) {
      throw const FormatException('Invalid donation record.');
    }
    return DonationRow(
      id: json['id'] as String,
      charityPartnerName: json['charityPartnerName'] as String,
      quantity: json['quantity'] as int,
      status: json['status'] as String,
    );
  }
}
