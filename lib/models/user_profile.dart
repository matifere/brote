class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? email;

  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.bannerUrl,
    this.email,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json, {String? email}) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['display_name'] as String? ?? json['username'] as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String? ?? json['avatar_url'] as String?,
      bannerUrl: json['bannerUrl'] as String? ?? json['banner_url'] as String? ?? json['header_url'] as String?,
      email: email,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'bannerUrl': bannerUrl,
      'email': email,
    };
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? bannerUrl,
    String? email,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      email: email ?? this.email,
    );
  }
}

class AuthResponse {
  final bool success;
  final String? token;
  final UserProfile? profile;
  final String? error;

  const AuthResponse({
    required this.success,
    this.token,
    this.profile,
    this.error,
  });

  factory AuthResponse.success({
    required String token,
    required UserProfile profile,
  }) {
    return AuthResponse(
      success: true,
      token: token,
      profile: profile,
    );
  }

  factory AuthResponse.failure(String errorMessage) {
    return AuthResponse(
      success: false,
      error: errorMessage,
    );
  }
}
