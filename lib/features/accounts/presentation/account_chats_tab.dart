import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/titi.dart';
import '../../../core/widgets/empty_state.dart';
import '../../social/application/chat_providers.dart';
import '../../social/presentation/inbox_screen.dart';
import '../application/active_account.dart';

/// The Chats tab of a club or partner account. Until a member actually
/// writes, the inbox has nothing to list (a chat someone opened but never
/// wrote in doesn't count), so TiTi says what will land here instead of a
/// blank page. With a chat in it, it's the normal inbox.
class AccountChatsTab extends ConsumerWidget {
  const AccountChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(inboxProvider).value;
    final empty = list != null && !list.any((c) => c.isMeet || c.lastMessage != null);
    if (!empty) return const InboxScreen();
    final (String name, String subtitle) = switch (ref.watch(activeAccountProvider)) {
      PartnerAccount(:final vendor) => (vendor.name, 'When a member taps Message on your partner page, or joins a meet you host, the chat shows up here.'),
      ClubAccount(:final club) => (club.name, 'Members who message the club, and the group chats of its meets, show up here.'),
      _ => ('', ''),
    };
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text('$name · Chats')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(inboxProvider);
          await ref.read(inboxProvider.future);
        },
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              // Centred in what's visible above the floating tab bar.
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                child: EmptyState(titi: TitiPose.chat, title: 'No chats yet', subtitle: subtitle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
