class Profile {
  final String uid;
  final String displayName;
  final String bio;
  final List<String> photos;
  final DateTime? dob, soberDate;
  final String program; // "AA","NA","SMART","None","Other"
  final bool showStreak, hideMode;
  final List<String> interests;
  final int minAge, maxAge, maxDistanceKm;
  final String? geohash;
  final double? latApprox, lonApprox;

  const Profile({
    required this.uid,
    required this.displayName,
    this.bio = '',
    this.photos = const [],
    this.dob,
    this.soberDate,
    this.program = 'None',
    this.showStreak = false,
    this.hideMode = false,
    this.interests = const [],
    this.minAge = 21,
    this.maxAge = 60,
    this.maxDistanceKm = 100,
    this.geohash,
    this.latApprox,
    this.lonApprox,
  });

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'bio': bio,
    'photos': photos,
    'dob': dob?.toIso8601String(),
    'soberDate': soberDate?.toIso8601String(),
    'program': program,
    'showStreak': showStreak,
    'hideMode': hideMode,
    'interests': interests,
    'minAge': minAge,
    'maxAge': maxAge,
    'maxDistanceKm': maxDistanceKm,
    'geohash': geohash,
    'latApprox': latApprox,
    'lonApprox': lonApprox,
  };

  static Profile fromDoc(String uid, Map<String, dynamic> d) => Profile(
    uid: uid,
    displayName: (d['displayName'] ?? '') as String,
    bio: (d['bio'] ?? '') as String,
    photos: List<String>.from(d['photos'] ?? const []),
    dob: d['dob'] != null ? DateTime.parse(d['dob']) : null,
    soberDate: d['soberDate'] != null ? DateTime.parse(d['soberDate']) : null,
    program: (d['program'] ?? 'None') as String,
    showStreak: (d['showStreak'] ?? false) as bool,
    hideMode: (d['hideMode'] ?? false) as bool,
    interests: List<String>.from(d['interests'] ?? const []),
    minAge: (d['minAge'] ?? 21) as int,
    maxAge: (d['maxAge'] ?? 60) as int,
    maxDistanceKm: (d['maxDistanceKm'] ?? 100) as int,
    geohash: d['geohash'] as String?,
    latApprox: (d['latApprox'] as num?)?.toDouble(),
    lonApprox: (d['lonApprox'] as num?)?.toDouble(),
  );
}
