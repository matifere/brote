class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? email;
  final bool isPrivate;
  final int followersCount;
  final int followingCount;
  final String followStatus; // 'none', 'pending', 'accepted'
  final bool isFollowedBy;
  final bool canViewContent;

  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.bannerUrl,
    this.email,
    this.isPrivate = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.followStatus = 'none',
    this.isFollowedBy = false,
    this.canViewContent = true,
  });

  bool get isFollowing => followStatus == 'accepted';
  bool get isPending => followStatus == 'pending';

  factory UserProfile.fromJson(Map<String, dynamic> json, {String? email}) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['display_name'] as String? ?? json['username'] as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String? ?? json['avatar_url'] as String?,
      bannerUrl: json['bannerUrl'] as String? ?? json['banner_url'] as String? ?? json['header_url'] as String?,
      email: email,
      isPrivate: json['isPrivate'] as bool? ?? json['is_private'] as bool? ?? false,
      followersCount: (json['followersCount'] as num? ?? json['followers_count'] as num? ?? 0).toInt(),
      followingCount: (json['followingCount'] as num? ?? json['following_count'] as num? ?? 0).toInt(),
      followStatus: json['followStatus'] as String? ?? json['follow_status'] as String? ?? 'none',
      isFollowedBy: json['isFollowedBy'] as bool? ?? json['is_followed_by'] as bool? ?? false,
      canViewContent: json['canViewContent'] as bool? ?? json['can_view_content'] as bool? ?? true,
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
      'isPrivate': isPrivate,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'followStatus': followStatus,
      'isFollowedBy': isFollowedBy,
      'canViewContent': canViewContent,
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
    bool? isPrivate,
    int? followersCount,
    int? followingCount,
    String? followStatus,
    bool? isFollowedBy,
    bool? canViewContent,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      email: email ?? this.email,
      isPrivate: isPrivate ?? this.isPrivate,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      followStatus: followStatus ?? this.followStatus,
      isFollowedBy: isFollowedBy ?? this.isFollowedBy,
      canViewContent: canViewContent ?? this.canViewContent,
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
