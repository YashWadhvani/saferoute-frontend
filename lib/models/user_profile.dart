class UserProfile {
  final String id;
  final String name;
  final String? email;
  final String? phone;

  UserProfile({required this.id, required this.name, this.email, this.phone});

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        email: m['email']?.toString(),
        phone: m['phone']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
      };
}
