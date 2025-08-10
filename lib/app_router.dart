// lib/app_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_shell.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/profile/onboarding_flow.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_screen.dart';

/// Listenable that tracks:
/// - auth state
/// - the user's onboarding completion flag in /profiles/{uid}
class _GateListenable extends ChangeNotifier {
  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  /// null = unknown (still loading profile),
  /// true = onboarded, false = not onboarded
  bool? onboarded;

  _GateListenable() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Reset profile state whenever auth changes
      onboarded = null;
      _profileSub?.cancel();

      if (user != null) {
        final docRef = FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid);
        _profileSub = docRef.snapshots().listen((doc) {
          final done = (doc.data()?['onboardingCompleted'] as bool?) ?? false;
          onboarded = doc.exists && done;
          notifyListeners();
        });
      }

      // Notify for the auth change itself
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}

class AppRouter {
  static final _gate = _GateListenable();

  static final GoRouter router = GoRouter(
    debugLogDiagnostics: true,
    refreshListenable: _gate,
    initialLocation: '/',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isAtSignIn = state.matchedLocation == '/signin';
      final isAtOnboarding = state.matchedLocation == '/onboarding';

      // Not signed in -> must be at /signin
      if (user == null) {
        return isAtSignIn ? null : '/signin';
      }

      // Signed in, but we don't yet know onboarding status -> don't redirect
      final onboarded = _gate.onboarded;
      if (onboarded == null) return null;

      // Needs onboarding
      if (onboarded == false && !isAtOnboarding) return '/onboarding';

      // Already onboarded; keep them out of /signin and /onboarding
      if (onboarded == true && (isAtSignIn || isAtOnboarding)) return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingFlow()),
      GoRoute(path: '/', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/edit-profile',
        builder: (_, __) => const EditProfileScreen(),
      ),
      GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) => ChatScreen(
          matchId: state.pathParameters['id']!,
          peerUid: (state.extra as Map?)?['peerUid'] as String?,
        ),
      ),
    ],
  );
}
