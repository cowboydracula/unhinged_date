// lib/features/profile/edit_profile_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

enum DistanceUnit { km, mi }

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Keep scroll position stable across rebuilds
  final _scrollController = ScrollController();
  static const _scrollStorageKey = PageStorageKey('edit_profile_scroll');

  // One-time hydration guard
  bool _hydrated = false;
  late NavigatorState _navigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffold ??= ScaffoldMessenger.maybeOf(context);
    _nav ??= Navigator.maybeOf(context);
  }

  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final Set<String> _selectedInterests = <String>{};

  static const List<String> kInterestOptions = [
    '🎸 Live music',
    '🥾 Hiking',
    '📚 Reading',
    '🎮 Gaming',
    '🍳 Cooking',
    '🎬 Movies',
    '🏋️ Gym',
    '🧘 Yoga',
    '✈️ Travel',
    '🎨 Art',
    '📷 Photography',
    '🎤 Karaoke',
    '🏄 Surfing',
    '🏀 Basketball',
    '⚽ Soccer',
    '🍿 Binge shows',
    '🧩 Puzzles',
    '☕ Coffee',
    '🐶 Dogs',
    '🐱 Cats',
  ];

  DateTime? _dob;
  DateTime? _soberDate;
  String _program = 'None';
  bool _showStreak = false;
  bool _hideMode = false;
  bool _disposed = false;
  bool _leaving = false; // set true when we decide to pop
  ScaffoldMessengerState?
  _scaffold; // cached — don’t look it up while tearing down
  NavigatorState? _nav; // cached

  // Age (we’ll show a RangeSlider)
  int _minAge = 21;
  int _maxAge = 60;

  // Always store distance in KM; convert only for UI
  double _maxDistanceKm = 100;
  bool _useMiles = false;

  double _kmToMiles(double km) => km * 0.621371;
  double _milesToKm(double miles) => miles / 0.621371;

  List<String> _photos = [];
  bool _busy = false;

  // ---------- Prompts state ----------
  final Map<String, TextEditingController> _promptCtrls = {};
  final Map<String, TextEditingController> _answerCtrls = {};
  final Map<String, FocusNode> _promptFocus = {};
  final Map<String, FocusNode> _answerFocus = {};
  bool _promptsBusy = false;
  static const int _maxPrompts = 3;
  static const List<String> _promptSuggestions = [
    "Two truths and a lie",
    "My perfect Saturday is",
    "I’m known for",
    "A green flag I look for",
    "A life goal of mine",
    "The best advice I’ve received",
    "My most controversial opinion",
  ];

  static const _programs = ['AA', 'NA', 'SMART', 'None', 'Other'];

  // ---------- Helpers ----------
  void _safeSnack(String msg) {
    if (_disposed || !mounted) return;
    _scaffold?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _disposed = true;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    _scrollController.dispose();
    _displayName.dispose();
    _bio.dispose();
    for (final c in _promptCtrls.values) c.dispose();
    for (final c in _answerCtrls.values) c.dispose();
    for (final f in _promptFocus.values) f.dispose();
    for (final f in _answerFocus.values) f.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _profileDoc =>
      _db.collection('profiles').doc(_auth.currentUser!.uid);

  CollectionReference<Map<String, dynamic>> get _promptsCol =>
      _profileDoc.collection('prompts');

  void _hydrateFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (_hydrated) return;
    final d = doc.data() ?? {};
    _displayName.text = (d['displayName'] ?? '') as String;
    _bio.text = (d['bio'] ?? '') as String;
    _program = (d['program'] ?? 'None') as String;
    _showStreak = (d['showStreak'] ?? false) as bool;
    _hideMode = (d['hideMode'] ?? false) as bool;
    _minAge = (d['minAge'] ?? 21) as int;
    _maxAge = (d['maxAge'] ?? 60) as int;
    _maxDistanceKm = ((d['maxDistanceKm'] ?? 100) as num).toDouble();
    _photos = List<String>.from(d['photos'] ?? const []);
    _selectedInterests
      ..clear()
      ..addAll(List<String>.from(d['interests'] ?? const []));
    _dob = d['dob'] != null ? DateTime.tryParse(d['dob']) : null;
    _soberDate = d['soberDate'] != null
        ? DateTime.tryParse(d['soberDate'])
        : null;
    _useMiles = (d['distanceUnit'] ?? 'km') == 'mi';
    _hydrated = true; // no setState here; called during build
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_minAge > _maxAge) {
      _safeSnack('Min age must be ≤ Max age');
      return;
    }

    setState(() => _busy = true);
    try {
      final data = {
        'displayName': _displayName.text.trim(),
        'bio': _bio.text.trim(),
        'program': _program,
        'showStreak': _showStreak,
        'hideMode': _hideMode,
        'minAge': _minAge,
        'maxAge': _maxAge,
        'maxDistanceKm': _maxDistanceKm, // stored in KM
        'distanceUnit': _useMiles ? 'mi' : 'km',
        'interests': _selectedInterests.take(12).toList(),
        'dob': _dob?.toIso8601String(),
        'soberDate': _soberDate?.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _profileDoc.set(data, SetOptions(merge: true));

      if (_disposed) return;
      _leaving = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          _nav?.maybePop(); // use cached navigator, not Navigator.of(context)
        }
      });
      return;
      _safeSnack('Profile saved');
    } catch (e) {
      _safeSnack('Save failed: $e');
    } finally {
      if (!_disposed && !_leaving) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
      );
      if (x == null) return;

      setState(() => _busy = true);
      final uid = _auth.currentUser!.uid;
      final ref = FirebaseStorage.instance.ref(
        'userPhotos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final task = await ref.putFile(File(x.path));
      final url = await task.ref.getDownloadURL();

      await _profileDoc.set({
        'photos': FieldValue.arrayUnion([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _safeSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(String url) async {
    setState(() => _busy = true);
    try {
      await _profileDoc.set({
        'photos': FieldValue.arrayRemove([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {
        /* ignore */
      }
    } catch (e) {
      _safeSnack('Remove failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime?> onPicked,
    DateTime? first,
    DateTime? last,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - 25, 1, 1),
      firstDate: first ?? DateTime(1900),
      lastDate: last ?? now,
    );
    if (!mounted)
      return; // important to avoid AnimationController.reverse after dispose
    onPicked(picked);
  }

  // ---------- Prompts helpers ----------
  TextEditingController _ensureCtrl(
    Map<String, TextEditingController> map,
    String id,
    String initial,
  ) => map.putIfAbsent(id, () => TextEditingController(text: initial));

  FocusNode _ensureFocus(Map<String, FocusNode> map, String id) =>
      map.putIfAbsent(id, () => FocusNode());

  Future<void> _addPrompt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_promptsBusy || docs.length >= _maxPrompts) return;
    setState(() => _promptsBusy = true);
    try {
      final nextOrder = docs.isEmpty
          ? 0
          : (docs
                    .map((d) => (d['order'] ?? 0) as int)
                    .reduce((a, b) => a > b ? a : b) +
                1);

      final newRef = await _promptsCol.add({
        'prompt': _promptSuggestions.first,
        'answer': '',
        'order': nextOrder,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _ensureCtrl(_promptCtrls, newRef.id, _promptSuggestions.first);
      _ensureCtrl(_answerCtrls, newRef.id, '');
      _ensureFocus(_answerFocus, newRef.id).requestFocus();
    } catch (e) {
      _safeSnack('Add prompt failed: $e');
    } finally {
      if (mounted) setState(() => _promptsBusy = false);
    }
  }

  Future<void> _deletePrompt(String id) async {
    if (_promptsBusy) return;
    setState(() => _promptsBusy = true);
    try {
      await _promptsCol.doc(id).delete();
      _promptCtrls.remove(id)?.dispose();
      _answerCtrls.remove(id)?.dispose();
      _promptFocus.remove(id)?.dispose();
      _answerFocus.remove(id)?.dispose();
    } catch (e) {
      _safeSnack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _promptsBusy = false);
    }
  }

  Future<void> _savePrompts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_promptsBusy) return;
    setState(() => _promptsBusy = true);
    try {
      final batch = _db.batch();
      for (var i = 0; i < docs.length; i++) {
        final id = docs[i].id;
        final prompt = _promptCtrls[id]?.text.trim() ?? '';
        final answer = _answerCtrls[id]?.text.trim() ?? '';
        batch.set(_promptsCol.doc(id), {
          'prompt': prompt,
          'answer': answer,
          'order': i,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      _safeSnack('Prompts saved');
    } catch (e) {
      _safeSnack('Save prompts failed: $e');
    } finally {
      if (mounted) setState(() => _promptsBusy = false);
    }
  }

  Future<void> _movePrompt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int from,
    int to,
  ) async {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= docs.length ||
        to >= docs.length) {
      return;
    }
    final swapped = [...docs];
    final item = swapped.removeAt(from);
    swapped.insert(to, item);
    await _savePrompts(swapped);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileDoc.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${snap.error}')));
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: Text('No profile yet')));
        }
        if (snap.data!.exists) {
          _hydrateFromDoc(snap.data!); // no setState here
        }

        // UI display value for distance in current unit
        final double displayDistance = _useMiles
            ? _kmToMiles(_maxDistanceKm)
            : _maxDistanceKm;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Edit Profile'),
            actions: [
              TextButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
          body: SafeArea(
            child: AbsorbPointer(
              absorbing: _busy,
              child: SingleChildScrollView(
                key: _scrollStorageKey,
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Photos
                      _PhotoGrid(
                        photos: _photos,
                        onAdd: _pickAndUploadPhoto,
                        onRemove: _removePhoto,
                      ),
                      const SizedBox(height: 12),

                      // Display name
                      TextFormField(
                        controller: _displayName,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 40,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),

                      // Bio
                      TextFormField(
                        controller: _bio,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          hintText: 'A sentence or two about you',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 4,
                        maxLength: 280,
                      ),
                      const SizedBox(height: 12),

                      // Program + sober date + show streak
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _program,
                              decoration: const InputDecoration(
                                labelText: 'Program',
                                border: OutlineInputBorder(),
                              ),
                              items: _programs
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _program = v ?? 'None'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateField(
                              label: 'Sobriety date',
                              value: _soberDate,
                              onTap: () => _pickDate(
                                initial: _soberDate,
                                onPicked: (d) => setState(() => _soberDate = d),
                              ),
                              onClear: () => setState(() => _soberDate = null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        title: const Text('Show streak publicly'),
                        value: _showStreak,
                        onChanged: (v) => setState(() => _showStreak = v),
                      ),
                      const SizedBox(height: 8),

                      // DOB
                      _DateField(
                        label: 'Date of birth (optional)',
                        value: _dob,
                        onTap: () => _pickDate(
                          initial: _dob,
                          onPicked: (d) => setState(() => _dob = d),
                          last: DateTime.now().subtract(
                            const Duration(days: 365 * 18),
                          ),
                        ),
                        onClear: () => setState(() => _dob = null),
                      ),
                      const SizedBox(height: 12),

                      // Interests (chips)
                      _SectionHeader(
                        'Interests  (${_selectedInterests.length}/12)',
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final label in kInterestOptions)
                            FilterChip(
                              label: Text(label),
                              selected: _selectedInterests.contains(label),
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    if (_selectedInterests.length >= 12) {
                                      _safeSnack('You can pick up to 12.');
                                      return;
                                    }
                                    _selectedInterests.add(label);
                                  } else {
                                    _selectedInterests.remove(label);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Prompts editor
                      _PromptsEditor(
                        stream: _promptsCol
                            .orderBy('order')
                            .limit(_maxPrompts)
                            .snapshots(),
                        busy: _promptsBusy,
                        ensureCtrl: _ensureCtrl,
                        ensureFocus: _ensureFocus,
                        promptCtrls: _promptCtrls,
                        answerCtrls: _answerCtrls,
                        promptFocus: _promptFocus,
                        answerFocus: _answerFocus,
                        onAdd: _addPrompt,
                        onDelete: _deletePrompt,
                        onSaveAll: _savePrompts,
                        onMove: _movePrompt,
                      ),

                      const SizedBox(height: 16),

                      // Discovery prefs
                      _SectionHeader('Discovery preferences'),

                      // Age double-bar slider (Syncfusion)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Age range: $_minAge–$_maxAge'),
                          SfRangeSlider(
                            min: 18.0,
                            max: 99.0,
                            values: SfRangeValues(
                              _minAge.toDouble(),
                              _maxAge.toDouble(),
                            ),
                            stepSize: 1, // whole years
                            showTicks: true,
                            showLabels: true,
                            enableTooltip: true,
                            onChanged: (SfRangeValues v) {
                              setState(() {
                                _minAge = (v.start as double).round();
                                _maxAge = (v.end as double).round();
                                if (_minAge > _maxAge) {
                                  final t = _minAge;
                                  _minAge = _maxAge;
                                  _maxAge = t;
                                }
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Unit toggle + distance slider (display in selected unit)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Max distance: '
                            '${_useMiles ? _kmToMiles(_maxDistanceKm).round() : _maxDistanceKm.round()} '
                            '${_useMiles ? 'mi' : 'km'}',
                          ),
                          SegmentedButton<DistanceUnit>(
                            segments: const [
                              ButtonSegment(
                                value: DistanceUnit.km,
                                label: Text('km'),
                              ),
                              ButtonSegment(
                                value: DistanceUnit.mi,
                                label: Text('mi'),
                              ),
                            ],
                            selected: {
                              _useMiles ? DistanceUnit.mi : DistanceUnit.km,
                            },
                            onSelectionChanged: (sel) {
                              final next = sel.first;
                              if ((next == DistanceUnit.mi) != _useMiles) {
                                setState(() {
                                  _useMiles = (next == DistanceUnit.mi);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      // Distance slider (Syncfusion) — UI shows selected unit, stores KM
                      SfSlider(
                        min: 1.0,
                        max: _useMiles ? 100.0 : 160.0,
                        value: _useMiles
                            ? _kmToMiles(_maxDistanceKm)
                            : _maxDistanceKm,
                        stepSize: 1,
                        showTicks: true,
                        showLabels: true,
                        enableTooltip: true,
                        onChanged: (dynamic val) {
                          final double d = (val as double);
                          setState(() {
                            // Convert UI value back to stored KM
                            _maxDistanceKm = _useMiles ? _milesToKm(d) : d;
                          });
                        },
                      ),

                      // Safety
                      _SectionHeader('Safety'),
                      SwitchListTile.adaptive(
                        title: const Text('Hide me from discovery'),
                        subtitle: const Text(
                          'You can still chat with existing matches',
                        ),
                        value: _hideMode,
                        onChanged: (v) => setState(() => _hideMode = v),
                      ),

                      const SizedBox(height: 24),
                      if (_busy) const CircularProgressIndicator(),
                      if (!_busy)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save),
                            label: const Text('Save'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Not set'
        : '${value!.year.toString().padLeft(4, '0')}-'
              '${value!.month.toString().padLeft(2, '0')}-'
              '${value!.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: value == null
              ? const Icon(Icons.date_range)
              : IconButton(onPressed: onClear, icon: const Icon(Icons.clear)),
        ),
        child: Text(text),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<String> photos;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _PhotoGrid({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ...photos.map<Widget>(
        (url) => Stack(
          fit: StackFit.expand,
          children: [
            Image.network(url, fit: BoxFit.cover),
            Positioned(
              right: 6,
              top: 6,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => onRemove(url),
                ),
              ),
            ),
          ],
        ),
      ),
      _AddTile(onTap: onAdd),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      children: items,
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: InkWell(
        onTap: onTap,
        child: const Center(child: Icon(Icons.add_a_photo_outlined, size: 28)),
      ),
    );
  }
}

// ---------- Prompts Editor ----------

class _PromptsEditor extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final bool busy;

  final TextEditingController Function(
    Map<String, TextEditingController>,
    String,
    String,
  )
  ensureCtrl;

  final FocusNode Function(Map<String, FocusNode>, String) ensureFocus;

  final Map<String, TextEditingController> promptCtrls;
  final Map<String, TextEditingController> answerCtrls;
  final Map<String, FocusNode> promptFocus;
  final Map<String, FocusNode> answerFocus;

  final Future<void> Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>)
  onAdd;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>)
  onSaveAll;
  final Future<void> Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int from,
    int to,
  )
  onMove;

  const _PromptsEditor({
    required this.stream,
    required this.busy,
    required this.ensureCtrl,
    required this.ensureFocus,
    required this.promptCtrls,
    required this.answerCtrls,
    required this.promptFocus,
    required this.answerFocus,
    required this.onAdd,
    required this.onDelete,
    required this.onSaveAll,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final docs =
            snap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Profile prompts'),
            ...[
              for (var i = 0; i < docs.length; i++)
                _PromptRow(
                  key: ValueKey('prompt_row_${docs[i].id}'),
                  id: docs[i].id,
                  initialPrompt: (docs[i]['prompt'] ?? '') as String? ?? '',
                  initialAnswer: (docs[i]['answer'] ?? '') as String? ?? '',
                  promptCtrl: ensureCtrl(
                    promptCtrls,
                    docs[i].id,
                    (docs[i]['prompt'] ?? '') as String? ?? '',
                  ),
                  answerCtrl: ensureCtrl(
                    answerCtrls,
                    docs[i].id,
                    (docs[i]['answer'] ?? '') as String? ?? '',
                  ),
                  promptFocus: ensureFocus(promptFocus, docs[i].id),
                  answerFocus: ensureFocus(answerFocus, docs[i].id),
                  onDelete: () => onDelete(docs[i].id),
                  canMoveUp: i > 0,
                  canMoveDown: i < docs.length - 1,
                  onMoveUp: () => onMove(docs, i, i - 1),
                  onMoveDown: () => onMove(docs, i, i + 1),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: busy || docs.length >= 3
                      ? null
                      : () => onAdd(docs),
                  icon: const Icon(Icons.add),
                  label: const Text('Add prompt'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: busy ? null : () => onSaveAll(docs),
                  icon: const Icon(Icons.save),
                  label: const Text('Save prompts'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose up to 3. Prompts are shown between your photos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _PromptRow extends StatelessWidget {
  final String id;
  final String initialPrompt;
  final String initialAnswer;
  final TextEditingController promptCtrl;
  final TextEditingController answerCtrl;
  final FocusNode promptFocus;
  final FocusNode answerFocus;
  final VoidCallback onDelete;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _PromptRow({
    super.key,
    required this.id,
    required this.initialPrompt,
    required this.initialAnswer,
    required this.promptCtrl,
    required this.answerCtrl,
    required this.promptFocus,
    required this.answerFocus,
    required this.onDelete,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: promptCtrl,
                    focusNode: promptFocus,
                    decoration: const InputDecoration(
                      labelText: 'Prompt',
                      hintText: 'e.g., My perfect Saturday is',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: canMoveUp ? onMoveUp : null,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: canMoveDown ? onMoveDown : null,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: answerCtrl,
              focusNode: answerFocus,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                hintText: 'Type your answer…',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
    );
  }
}
