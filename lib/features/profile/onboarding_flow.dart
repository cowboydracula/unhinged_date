// lib/features/profile/onboarding_flow.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/storage.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Step 0 (name/dob)
  final _name = TextEditingController();
  DateTime? _dob;

  // Step 2 (bio/program/streak)
  final _bio = TextEditingController();
  String _program = 'None';
  bool _showStreak = false;
  DateTime? _soberDate;

  // Step 3 (prefs)
  RangeValues _ageRange = const RangeValues(21, 60);
  double _distanceKm = 50;

  // Step 4 (pronouns / identity)
  String _pronouns = 'Prefer not to say';
  final _customPronouns = TextEditingController();
  String _genderIdentity = 'Prefer not to say';

  // Step 5 (location)
  bool? _locationConsent;
  Position? _pos;

  // Step 6 (notifications)
  bool? _notifChoice;
  String? _fcmToken;

  // Photos
  final _picker = ImagePicker();
  final _photos = <String>[];

  bool _busy = false;
  int _step = 0;

  String get _uid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _customPronouns.dispose();
    super.dispose();
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    try {
      final seconds = (v as dynamic).seconds as int?;
      final nanos = (v as dynamic).nanoseconds as int? ?? 0;
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + (nanos ~/ 1e6),
        );
      }
    } catch (_) {}
    try {
      final m = v as Map<String, dynamic>;
      final s = m['_seconds'] as int?;
      final n = m['_nanoseconds'] as int? ?? 0;
      if (s != null) {
        return DateTime.fromMillisecondsSinceEpoch(s * 1000 + (n ~/ 1e6));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _prefill() async {
    final doc = await _db.collection('profiles').doc(_uid).get();
    final data = doc.data() ?? {};
    _name.text = (data['displayName'] ?? '').toString();
    _bio.text = (data['bio'] ?? '').toString();
    _program = (data['program'] ?? 'None') as String;
    _showStreak = (data['showStreak'] ?? false) as bool;

    _dob = _parseDate(data['dob']);
    _soberDate = _parseDate(data['soberDate']);

    final ageMin = (data['minAge'] ?? 21) as int;
    final ageMax = (data['maxAge'] ?? 60) as int;
    _ageRange = RangeValues(ageMin.toDouble(), ageMax.toDouble());
    _distanceKm = ((data['maxDistanceKm'] ?? 50) as num).toDouble();

    _pronouns = (data['pronouns'] ?? 'Prefer not to say') as String;
    _genderIdentity = (data['genderIdentity'] ?? 'Prefer not to say') as String;
    _locationConsent = data['locationConsent'] as bool?;
    _notifChoice = data['notificationsEnabled'] as bool?;

    if (data['photos'] is List) {
      _photos
        ..clear()
        ..addAll(List<String>.from(data['photos']));
    }
    setState(() {});
  }

  Future<void> _saveBasics() async {
    await _db.collection('profiles').doc(_uid).set({
      'displayName': _name.text.trim(),
      'dob': _dob?.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveMore() async {
    await _db.collection('profiles').doc(_uid).set({
      'bio': _bio.text.trim(),
      'program': _program,
      'showStreak': _showStreak,
      'soberDate': _soberDate?.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _savePrefs() async {
    await _db.collection('profiles').doc(_uid).set({
      'minAge': _ageRange.start.round(),
      'maxAge': _ageRange.end.round(),
      'maxDistanceKm': _distanceKm.round(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveIdentity() async {
    final pronouns = _pronouns == 'Custom'
        ? _customPronouns.text.trim()
        : _pronouns;
    await _db.collection('profiles').doc(_uid).set({
      'pronouns': pronouns,
      'genderIdentity': _genderIdentity,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveLocationConsent() async {
    await _db.collection('profiles').doc(_uid).set({
      'locationConsent': _locationConsent ?? false,
      if (_pos != null)
        'location': {
          'geopoint': GeoPoint(_pos!.latitude, _pos!.longitude),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveNotifChoice() async {
    await _db.collection('profiles').doc(_uid).set({
      'notificationsEnabled': _notifChoice ?? false,
      'fcmToken': _fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (_fcmToken != null) {
      await _db
          .collection('profiles')
          .doc(_uid)
          .collection('tokens')
          .doc(_fcmToken)
          .set({
            'token': _fcmToken,
            'platform': Platform.isAndroid
                ? 'android'
                : Platform.isIOS
                ? 'ios'
                : 'other',
            'createdAt': FieldValue.serverTimestamp(),
          });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (x == null) return;
      setState(() => _busy = true);

      final url = await StorageService().uploadXFile(x);

      _photos.add(url);
      await _db.collection('profiles').doc(_uid).set({
        'photos': FieldValue.arrayUnion([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String url) async {
    setState(() => _busy = true);
    try {
      await _db.collection('profiles').doc(_uid).set({
        'photos': FieldValue.arrayRemove([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _photos.remove(url);
      await StorageService().deleteByUrl(url);
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Location helpers ----
  Future<void> _requestLocation() async {
    setState(() => _busy = true);
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) {
        throw 'Location services are disabled';
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _pos = pos;
      _locationConsent = true;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Location captured')));
      }
    } catch (e) {
      _locationConsent = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Location not available: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Notifications helpers ----
  Future<void> _requestNotifications() async {
    setState(() => _busy = true);
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      _notifChoice = granted;
      if (granted) {
        _fcmToken = await FirebaseMessaging.instance.getToken();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications enabled')),
          );
        }
      } else {
        _fcmToken = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications not enabled')),
          );
        }
      }
    } catch (e) {
      _notifChoice = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification setup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canNext {
    switch (_step) {
      case 0:
        return _name.text.trim().isNotEmpty && _dob != null;
      case 1:
        return _photos.isNotEmpty;
      case 2:
        return true;
      case 3:
        return true;
      case 4:
        if (_pronouns == 'Custom') {
          return _customPronouns.text.trim().isNotEmpty;
        }
        return true;
      case 5:
        return _locationConsent != null;
      case 6:
        return _notifChoice != null;
      default:
        return false;
    }
  }

  Future<void> _next() async {
    setState(() => _busy = true);
    try {
      if (_step == 0) {
        await _saveBasics();
      } else if (_step == 2) {
        await _saveMore();
      } else if (_step == 3) {
        await _savePrefs();
      } else if (_step == 4) {
        await _saveIdentity();
      } else if (_step == 5) {
        await _saveLocationConsent();
      } else if (_step == 6) {
        await _saveNotifChoice();
        await _db.collection('profiles').doc(_uid).set({
          'onboardingCompleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (_step < 6) {
        setState(() => _step += 1);
      } else {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _StepBasics(
        controllerName: _name,
        dob: _dob,
        onPickDob: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
            firstDate: DateTime(now.year - 100),
            lastDate: DateTime(now.year - 18),
            helpText: 'Select your date of birth',
          );
          if (picked != null) setState(() => _dob = picked);
        },
      ),
      _StepPhotos(
        photos: _photos,
        busy: _busy,
        onAdd: _pickPhoto,
        onRemove: _removePhoto,
      ),
      _StepBasics2(
        bioController: _bio,
        program: _program,
        showStreak: _showStreak,
        soberDate: _soberDate,
        onProgram: (v) => setState(() => _program = v),
        onStreak: (v) => setState(() => _showStreak = v),
        onPickSober: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _soberDate ?? DateTime(now.year - 1),
            firstDate: DateTime(now.year - 50),
            lastDate: now,
            helpText: 'Sober since',
          );
          if (picked != null) setState(() => _soberDate = picked);
        },
      ),
      _StepPrefs(
        range: _ageRange,
        distanceKm: _distanceKm,
        onRange: (v) => setState(() => _ageRange = v),
        onDistance: (v) => setState(() => _distanceKm = v),
      ),
      _StepPronouns(
        pronouns: _pronouns,
        customController: _customPronouns,
        genderIdentity: _genderIdentity,
        onPronouns: (v) => setState(() => _pronouns = v),
        onGender: (v) => setState(() => _genderIdentity = v),
      ),
      _StepLocation(
        consent: _locationConsent,
        busy: _busy,
        onEnable: _requestLocation,
        onSkip: () => setState(() => _locationConsent = false),
      ),
      _StepNotifications(
        choice: _notifChoice,
        busy: _busy,
        onEnable: _requestNotifications,
        onSkip: () => setState(() => _notifChoice = false),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              _StepperHeader(current: _step, total: pages.length),
              const SizedBox(height: 8),
              Expanded(child: pages[_step]),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _step -= 1),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_busy || !_canNext) ? null : _next,
                    child: Text(
                      _step == pages.length - 1 ? 'Finish' : 'Continue',
                    ),
                  ),
                ],
              ),
              if (_busy) const SizedBox(height: 8),
              if (_busy) const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- UI bits ----------

class _StepperHeader extends StatelessWidget {
  final int current;
  final int total;
  const _StepperHeader({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= current;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            height: 6,
            decoration: BoxDecoration(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }),
    );
  }
}

class _StepBasics extends StatelessWidget {
  final TextEditingController controllerName;
  final DateTime? dob;
  final VoidCallback onPickDob;

  const _StepBasics({
    required this.controllerName,
    required this.dob,
    required this.onPickDob,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          'Tell us about you',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controllerName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'e.g., Alex',
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Date of birth'),
          subtitle: Text(
            dob == null
                ? 'Select your birthday'
                : '${dob!.year}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.calendar_month),
          onTap: onPickDob,
        ),
        const SizedBox(height: 8),
        Text(
          'We ask for DOB to verify age (18+).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StepPhotos extends StatelessWidget {
  final List<String> photos;
  final bool busy;
  final Future<void> Function() onAdd;
  final Future<void> Function(String) onRemove;

  const _StepPhotos({
    required this.photos,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add at least one photo',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final url in photos)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(url, fit: BoxFit.cover),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                          ),
                          icon: const Icon(Icons.close),
                          onPressed: busy ? null : () => onRemove(url),
                        ),
                      ),
                    ],
                  ),
                ),
              InkWell(
                onTap: busy ? null : onAdd,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Icon(Icons.add_a_photo_outlined)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBasics2 extends StatelessWidget {
  final TextEditingController bioController;
  final String program;
  final bool showStreak;
  final DateTime? soberDate;
  final ValueChanged<String> onProgram;
  final ValueChanged<bool> onStreak;
  final VoidCallback onPickSober;

  const _StepBasics2({
    required this.bioController,
    required this.program,
    required this.showStreak,
    required this.soberDate,
    required this.onProgram,
    required this.onStreak,
    required this.onPickSober,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Basics', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: bioController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Bio',
            hintText: 'A few lines about you',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: program,
          items: const [
            DropdownMenuItem(value: 'None', child: Text('No program')),
            DropdownMenuItem(value: 'AA', child: Text('AA')),
            DropdownMenuItem(value: 'NA', child: Text('NA')),
            DropdownMenuItem(value: 'SMART', child: Text('SMART Recovery')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: (v) => v == null ? null : onProgram(v),
          decoration: const InputDecoration(labelText: 'Program'),
        ),
        SwitchListTile.adaptive(
          value: showStreak,
          onChanged: onStreak,
          title: const Text('Show sober streak'),
          subtitle: const Text('Display how long you’ve been sober'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sober since'),
          subtitle: Text(
            soberDate == null
                ? 'Optional'
                : '${soberDate!.year}-${soberDate!.month.toString().padLeft(2, '0')}-${soberDate!.day.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: onPickSober,
        ),
      ],
    );
  }
}

class _StepPrefs extends StatelessWidget {
  final RangeValues range;
  final double distanceKm;
  final ValueChanged<RangeValues> onRange;
  final ValueChanged<double> onDistance;

  const _StepPrefs({
    required this.range,
    required this.distanceKm,
    required this.onRange,
    required this.onDistance,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Preferences', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('Age range'),
        RangeSlider(
          values: range,
          min: 18,
          max: 80,
          divisions: 62,
          labels: RangeLabels(
            range.start.round().toString(),
            range.end.round().toString(),
          ),
          onChanged: onRange,
        ),
        const SizedBox(height: 12),
        Text('Max distance: ${distanceKm.round()} km'),
        Slider(
          value: distanceKm,
          min: 5,
          max: 200,
          divisions: 39,
          onChanged: onDistance,
        ),
        const SizedBox(height: 8),
        Text(
          'You can change these anytime in Edit profile.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StepPronouns extends StatelessWidget {
  final String pronouns;
  final TextEditingController customController;
  final String genderIdentity;
  final ValueChanged<String> onPronouns;
  final ValueChanged<String> onGender;

  const _StepPronouns({
    required this.pronouns,
    required this.customController,
    required this.genderIdentity,
    required this.onPronouns,
    required this.onGender,
  });

  @override
  Widget build(BuildContext context) {
    final options = const [
      'She/Her',
      'He/Him',
      'They/Them',
      'She/They',
      'He/They',
      'Custom',
      'Prefer not to say',
    ];
    final genders = const [
      'Woman',
      'Man',
      'Non-binary',
      'Trans woman',
      'Trans man',
      'Other',
      'Prefer not to say',
    ];

    return ListView(
      children: [
        Text(
          'How should people refer to you?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: pronouns,
          items: [
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => v == null ? null : onPronouns(v),
          decoration: const InputDecoration(labelText: 'Pronouns'),
        ),
        const SizedBox(height: 8),
        if (pronouns == 'Custom')
          TextField(
            controller: customController,
            decoration: const InputDecoration(
              labelText: 'Custom pronouns',
              hintText: 'e.g., Ze/Hir',
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: genderIdentity,
          items: [
            for (final g in genders) DropdownMenuItem(value: g, child: Text(g)),
          ],
          onChanged: (v) => v == null ? null : onGender(v),
          decoration: const InputDecoration(
            labelText: 'Gender identity (optional)',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We show pronouns on your profile to help others address you correctly.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StepLocation extends StatelessWidget {
  final bool? consent;
  final bool busy;
  final Future<void> Function() onEnable;
  final VoidCallback onSkip;

  const _StepLocation({
    required this.consent,
    required this.busy,
    required this.onEnable,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Share your location?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'We use your approximate location to show nearby profiles. '
          'You can change this later.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onEnable,
                icon: const Icon(Icons.my_location),
                label: const Text('Enable location'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onSkip,
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (consent != null)
          Text(
            consent! ? 'Location enabled' : 'Location skipped',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _StepNotifications extends StatelessWidget {
  final bool? choice;
  final bool busy;
  final Future<void> Function() onEnable;
  final VoidCallback onSkip;

  const _StepNotifications({
    required this.choice,
    required this.busy,
    required this.onEnable,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enable notifications?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'We’ll let you know about new matches and messages. '
          'You can turn this off anytime in Settings.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onEnable,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onSkip,
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (choice != null)
          Text(
            choice! ? 'Notifications enabled' : 'Notifications skipped',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
