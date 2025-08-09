// lib/features/profile/edit_profile_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _interests = TextEditingController(); // comma-separated

  DateTime? _dob;
  DateTime? _soberDate;
  String _program = 'None';
  bool _showStreak = false;
  bool _hideMode = false;
  int _minAge = 21;
  int _maxAge = 60;
  double _maxDistanceKm = 100;

  List<String> _photos = [];
  bool _busy = false;

  static const _programs = ['AA', 'NA', 'SMART', 'None', 'Other'];

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _interests.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _profileDoc =>
      _db.collection('profiles').doc(_auth.currentUser!.uid);

  Future<void> _loadOnce(DocumentSnapshot<Map<String, dynamic>> doc) async {
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
    _interests.text = (d['interests'] is List)
        ? (d['interests'] as List).cast<String>().join(', ')
        : (d['interests'] ?? '') as String;
    _dob = d['dob'] != null ? DateTime.tryParse(d['dob']) : null;
    _soberDate = d['soberDate'] != null
        ? DateTime.tryParse(d['soberDate'])
        : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_minAge > _maxAge) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Min age must be ≤ Max age')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final interests = _interests.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final data = {
        'displayName': _displayName.text.trim(),
        'bio': _bio.text.trim(),
        'program': _program,
        'showStreak': _showStreak,
        'hideMode': _hideMode,
        'minAge': _minAge,
        'maxAge': _maxAge,
        'maxDistanceKm': _maxDistanceKm.round(),
        'interests': interests,
        'dob': _dob?.toIso8601String(),
        'soberDate': _soberDate?.toIso8601String(),
        // don't write photos here; handled by upload/remove actions
        'updatedAt': FieldValue.serverTimestamp(),
        // ensure createdAt exists
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _profileDoc.set(data, SetOptions(merge: true));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
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
      await _profileDoc.set({
        'photos': FieldValue.arrayRemove([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Best-effort delete from Storage (ignore if not our bucket/path)
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {
        // ignore
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
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
    onPicked(picked);
  }

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
        // Initialize controllers from snapshot once
        if (snap.hasData && snap.data!.exists && _displayName.text.isEmpty) {
          _loadOnce(snap.data!);
        }

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
                padding: const EdgeInsets.all(16),
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

                      // Interests
                      TextFormField(
                        controller: _interests,
                        decoration: const InputDecoration(
                          labelText: 'Interests (comma-separated)',
                          hintText: 'hiking, sci-fi, board games',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Discovery prefs
                      _SectionHeader('Discovery preferences'),
                      Row(
                        children: [
                          Expanded(
                            child: _NumberField(
                              label: 'Min age',
                              value: _minAge,
                              onChanged: (v) => setState(() => _minAge = v),
                              min: 18,
                              max: 99,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NumberField(
                              label: 'Max age',
                              value: _maxAge,
                              onChanged: (v) => setState(() => _maxAge = v),
                              min: 18,
                              max: 99,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Max distance: ${_maxDistanceKm.round()} km'),
                          Slider(
                            value: _maxDistanceKm,
                            min: 5,
                            max: 250,
                            divisions: 49,
                            label: '${_maxDistanceKm.round()} km',
                            onChanged: (v) =>
                                setState(() => _maxDistanceKm = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

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

class _NumberField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value.toString());
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      onSubmitted: (v) {
        final n = int.tryParse(v) ?? value;
        onChanged(n.clamp(min, max));
      },
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
        : '${value!.year.toString().padLeft(4, '0')}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}';

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
