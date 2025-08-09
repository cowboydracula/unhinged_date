// lib/features/auth/auth_gate.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../profile/onboarding_flow.dart';
import '../swipe/swipe_screen.dart';
import 'sign_in_screen.dart';

/// Decides: Sign-in → Onboarding → Swipe
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;

    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Busy();
        }
        if (user == null) {
          return const SignInScreen();
        }

        // Watch my profile and route based on completion
        final doc = FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .snapshots();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: doc,
          builder: (context, profSnap) {
            if (!profSnap.hasData) return const _Busy();

            final data = profSnap.data!.data() ?? {};
            final completed = (data['onboardingCompleted'] ?? false) as bool;

            // Minimal required fields we’ll enforce before discovery:
            final hasName = (data['displayName'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
            final hasDob = (data['dob'] ?? '').toString().trim().isNotEmpty;
            final hasPhoto =
                (data['photos'] is List) && (data['photos'] as List).isNotEmpty;

            final ready = completed && hasName && hasDob && hasPhoto;

            if (!ready) {
              return const OnboardingFlow();
            }
            return const SwipeScreen();
          },
        );
      },
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
