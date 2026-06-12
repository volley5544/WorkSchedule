import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/schedule_service.dart';

/// Admin-only screen for assigning roles to signed-in users.
class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({
    super.key,
    required this.service,
    required this.currentUser,
  });

  final ScheduleService service;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage users')),
      body: StreamBuilder<List<AppUser>>(
        stream: service.allUsers(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Failed to load users: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final user = users[i];
              final isSelf = user.uid == currentUser.uid;
              return ListTile(
                leading: CircleAvatar(
                  foregroundImage: user.photoUrl == null
                      ? null
                      : NetworkImage(user.photoUrl!),
                  child: Text(user.displayName.isEmpty
                      ? '?'
                      : user.displayName.characters.first.toUpperCase()),
                ),
                title: Text(user.displayName),
                subtitle: Text(user.email),
                trailing: SegmentedButton<UserRole>(
                  segments: [
                    for (final role in UserRole.values)
                      ButtonSegment(value: role, label: Text(role.label)),
                  ],
                  selected: {user.role},
                  // Admins cannot demote themselves: avoids locking everyone out.
                  onSelectionChanged: isSelf
                      ? null
                      : (selection) async {
                          try {
                            await service.setUserRole(
                                user.uid, selection.first);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Failed to update role: $e')),
                              );
                            }
                          }
                        },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
