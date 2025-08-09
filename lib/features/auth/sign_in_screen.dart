// lib/features/auth/sign_in_screen.dart
// NOTE: For google_sign_in v7+ you must call this once in main():
//   await GoogleSignIn.instance.initialize();
/**
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:google_sign_in/google_sign_in.dart'; // v7 API (singleton)
import 'package:sign_in_with_apple/sign_in_with_apple.dart'; // optional (iOS)
import 'package:crypto/crypto.dart' as crypto; // for Apple nonce

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _ensureProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final u = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('profiles').doc(uid).set({
      'displayName': u.displayName ?? 'New User',
      'program': 'None',
      'showStreak': false,
      'hideMode': false,
      'interests': <String>[],
      'minAge': 21,
      'maxAge': 60,
      'maxDistanceKm': 100,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _afterSignIn() async {
    await _ensureProfile();
    if (!mounted) return;
    context.go('/');
  }

  // ---------------- Google (plugin v7 on mobile, popup on web) ----------------
  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        // Web uses Firebase provider popup
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Mobile: google_sign_in v7 singleton flow
        // Ensure you've called GoogleSignIn.instance.initialize() in main()
        final googleUser = await GoogleSignIn.instance.authenticate();
        if (googleUser == null) return; // user canceled

        final tokens = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken:
              tokens.idToken, // optional for Firebase, kept for completeness
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      await _afterSignIn();
    } on GoogleSignInException catch (e) {
      _snack('Google sign-in canceled/failed: ${e.code}');
    } catch (e) {
      _snack('Google sign-in error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Apple (iOS/macOS only) ----------------
  String _nonce([int len = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _signInWithApple() async {
    setState(() => _busy = true);
    try {
      final raw = _nonce();
      final hashed = crypto.sha256.convert(utf8.encode(raw)).toString();

      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashed,
      );

      final oauth = OAuthProvider(
        'apple.com',
      ).credential(idToken: apple.identityToken, rawNonce: raw);
      await FirebaseAuth.instance.signInWithCredential(oauth);

      final u = FirebaseAuth.instance.currentUser!;
      if ((u.displayName ?? '').isEmpty) {
        final parts = [
          apple.givenName,
          apple.familyName,
        ].where((s) => (s ?? '').trim().isNotEmpty).join(' ');
        if (parts.isNotEmpty) {
          await u.updateDisplayName(parts);
        }
      }

      await _afterSignIn();
    } catch (e) {
      _snack('Apple sign-in error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Dev anonymous (optional) ----------------
  Future<void> _signInAnon() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await _afterSignIn();
    } catch (e) {
      _snack('Anonymous sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool get _isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FlutterLogo(size: 72),
                  const SizedBox(height: 12),
                  Text(
                    'Unhinged',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),

                  // Google
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Continue with Google'),
                      onPressed: _busy ? null : _signInWithGoogle,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Apple (iOS/macOS only)
                  if (_isApplePlatform)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.apple),
                        label: const Text('Continue with Apple'),
                        onPressed: _busy ? null : _signInWithApple,
                      ),
                    ),

                  const SizedBox(height: 8),
                  if (kDebugMode)
                    TextButton(
                      onPressed: _busy ? null : _signInAnon,
                      child: const Text('Continue (anonymous) – dev'),
                    ),

                  const SizedBox(height: 16),
                  if (_busy) const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
*/

// lib/features/auth/sign_in_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../dev/faker_seed.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _ensureProfile() async {
    final u = FirebaseAuth.instance.currentUser!;
    final uid = u.uid;
    await FirebaseFirestore.instance.collection('profiles').doc(uid).set({
      'displayName': u.displayName ?? 'New User',
      'program': 'None',
      'showStreak': false,
      'hideMode': false,
      'interests': <String>[],
      'minAge': 21,
      'maxAge': 60,
      'maxDistanceKm': 100,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _afterSignIn() async {
    await _ensureProfile();
    if (!mounted) return;
    context.go('/');
  }

  // --- Google Sign-In (plugin v7 on mobile, popup on web) ---
  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Requires: await GoogleSignIn.instance.initialize(); in main()
        final googleUser = await GoogleSignIn.instance.authenticate();
        if (googleUser == null) return; // user cancelled

        final tokens = await googleUser.authentication;
        final cred = GoogleAuthProvider.credential(
          idToken: tokens.idToken, // accessToken not needed for Firebase
        );
        await FirebaseAuth.instance.signInWithCredential(cred);
      }
      await _afterSignIn();
    } on GoogleSignInException catch (e) {
      _snack('Google sign-in failed: ${e.code}');
    } catch (e) {
      _snack('Google sign-in error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInAnon() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
      await _afterSignIn();
    } catch (e) {
      _snack('Anonymous sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FlutterLogo(size: 72),
                  const SizedBox(height: 12),
                  Text(
                    'Unhinged',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),

                  // Google
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Continue with Google'),
                      onPressed: _busy ? null : _signInWithGoogle,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (kDebugMode)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    try {
                                      final seeded = await FakerSeed(
                                        FirebaseFirestore.instance,
                                      ).seedProfiles(40);
                                      _snack(
                                        'Seeded ${seeded.length} profiles',
                                      );
                                    } catch (e) {
                                      _snack('Seed error: $e');
                                    } finally {
                                      if (mounted)
                                        setState(() => _busy = false);
                                    }
                                  },
                            child: const Text('Seed 40 fake profiles (dev)'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    try {
                                      final n = await FakerSeed(
                                        FirebaseFirestore.instance,
                                      ).deleteFakes();
                                      _snack('Deleted $n fake profiles');
                                    } catch (e) {
                                      _snack('Delete error: $e');
                                    } finally {
                                      if (mounted)
                                        setState(() => _busy = false);
                                    }
                                  },
                            child: const Text('Delete fake profiles (dev)'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _signInAnon,
                          child: const Text('Continue (anonymous) – dev'),
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),
                  if (_busy) const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
