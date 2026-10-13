import 'package:flutter/material.dart';

import '../theme.dart';
import 'messages_tab.dart';
import 'profile_screen.dart';
import 'rooms_tab.dart';
import 'search_tab.dart';
import '../main.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: [
        const RoomsTab(),
        const SearchTab(),
        MessagesTab(active: _i == 2),
        ProfileScreen(userId: myId, embedded: true),
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xE60F0A26),
          border: Border(top: BorderSide(color: C.glassBorder)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          indicatorColor: C.violet.withValues(alpha: 0.35),
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.mic_none_rounded),
                selectedIcon: Icon(Icons.mic_rounded),
                label: 'الغرف'),
            NavigationDestination(
                icon: Icon(Icons.search_rounded), label: 'بحث'),
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'الرسائل'),
            NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'حسابي'),
          ],
        ),
      ),
    );
  }
}
