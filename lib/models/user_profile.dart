class UserProfile {
  final String name;
  final String email;
  final String planName;
  final int scansRemaining;
  final bool isPremium;

  final String? avatarPath;

  const UserProfile({
    required this.name,
    required this.email,
    required this.planName,
    required this.scansRemaining,
    required this.isPremium,
    this.avatarPath,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? planName,
    int? scansRemaining,
    bool? isPremium,
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      planName: planName ?? this.planName,
      scansRemaining: scansRemaining ?? this.scansRemaining,
      isPremium: isPremium ?? this.isPremium,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    );
  }
}

