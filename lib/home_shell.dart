import 'package:flutter/material.dart';
import 'features/swipe/swipe_screen.dart';
import 'features/profile/profile_screen.dart'; // <-- ProfileView here
import 'features/profile/edit_profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    const SwipeScreen(),
    const LikesScreen(),
    const MessagesScreen(),
    const ProfileScreen(), // <-- from profile_screen.dart
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_outlined),
            activeIcon: Icon(Icons.local_fire_department),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Likes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _index == 3
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            )
          : null,
    );
  }
}

// placeholders
class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Likes'));
}

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Chats'));
}
