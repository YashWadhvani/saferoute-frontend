class ContactModel {
  final String? id;
  final String name;
  final String phone;

  ContactModel({this.id, required this.name, required this.phone});

  factory ContactModel.fromMap(Map<String, dynamic> m) => ContactModel(
        id: m['_id']?.toString() ?? m['id']?.toString(),
        name: m['name']?.toString() ?? '',
        phone: m['phone']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}
