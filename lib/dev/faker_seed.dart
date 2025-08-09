// lib/dev/faker_seed.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faker/faker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Generate fake profiles into Firestore for local/dev testing.
/// Everything is tagged with isFake=true so you can clean it up.
class FakerSeed {
  FakerSeed(this._db);

  final FirebaseFirestore _db;
  final _faker = Faker();
  final _uuid = const Uuid();
  final _rand = Random();

  /// Creates [count] fake profiles. Returns the created doc IDs.
  ///
  /// Guarded to run in debug/profile only.
  Future<List<String>> seedProfiles(int count) async {
    assert(() {
      // Prevent accidental prod seeding in release.
      if (kReleaseMode) {
        throw StateError('Refusing to seed in release mode.');
      }
      return true;
    }());

    final createdIds = <String>[];
    final programs = ['AA', 'NA', 'SMART', 'None', 'Other'];
    final interestPool = [
      'hiking',
      'sci-fi',
      'yoga',
      'board games',
      'running',
      'coffee',
      'coding',
      'dogs',
      'cats',
      'music',
      'thrifting',
      'cooking',
      'photography',
      'climbing',
      'beach',
      'reading',
      'movies',
      'gym',
      'travel',
      'baking',
    ];

    // Firestore batches max out at 500 writes. We’ll chunk safely.
    const maxBatch = 450;
    var remaining = count;

    while (remaining > 0) {
      final n = remaining > maxBatch ? maxBatch : remaining;
      final batch = _db.batch();

      for (var i = 0; i < n; i++) {
        final id = _uuid.v4();
        createdIds.add(id);

        final name = _faker.person.name();
        final bio = _faker.lorem.sentences(_rand.nextInt(2) + 1).join(' ');
        final showStreak = _rand.nextBool();
        final program = programs[_rand.nextInt(programs.length)];

        // Age 21–60
        final age = 21 + _rand.nextInt(40);
        final now = DateTime.now();
        final dob = DateTime(
          now.year - age,
          _rand.nextInt(12) + 1,
          _rand.nextInt(28) + 1,
        );

        // Sober 30 days to 5 years ago
        final soberDays = 30 + _rand.nextInt(5 * 365);
        final soberDate = now.subtract(Duration(days: soberDays));

        // 3–5 random interests
        final interests = interestPool.toList()..shuffle(_rand);
        final pickedInterests = interests.take(3 + _rand.nextInt(3)).toList();

        // Picsum seeded images = stable URLs without uploading anything.
        final seed = id.substring(0, 8);
        final photos = List.generate(
          1 + _rand.nextInt(3),
          (i) => 'https://picsum.photos/seed/${seed}_$i/900/1200',
        );

        // Discovery prefs
        final minAge = 18;
        final maxAge = 60;
        final maxDistanceKm = [5, 10, 25, 50, 100].elementAt(_rand.nextInt(4));

        final doc = _db.collection('profiles').doc(id);
        batch.set(doc, {
          'displayName': name,
          'bio': bio,
          'program': program,
          'showStreak': showStreak,
          'hideMode': false,
          'interests': pickedInterests,
          'minAge': minAge,
          'maxAge': maxAge,
          'maxDistanceKm': maxDistanceKm,
          'dob': dob.toIso8601String(),
          'soberDate': soberDate.toIso8601String(),
          'photos': photos,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          // handy flag for cleanup
          'isFake': true,
        });
      }

      await batch.commit();
      remaining -= n;
    }

    return createdIds;
  }

  /// Deletes every document in `profiles` where `isFake == true`.
  Future<int> deleteFakes() async {
    assert(!kReleaseMode, 'Refusing to delete in release mode.');
    final qs = await _db
        .collection('profiles')
        .where('isFake', isEqualTo: true)
        .get();

    const maxBatch = 450;
    var deleted = 0;

    for (var i = 0; i < qs.docs.length; i += maxBatch) {
      final chunk = qs.docs.skip(i).take(maxBatch);
      final batch = _db.batch();
      for (final d in chunk) {
        batch.delete(d.reference);
        deleted++;
      }
      await batch.commit();
    }
    return deleted;
  }
}
