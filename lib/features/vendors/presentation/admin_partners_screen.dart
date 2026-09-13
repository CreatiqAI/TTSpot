import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_art.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/vendors_providers.dart';
import '../domain/vendor.dart';

/// Admins only: pending partner applications.
class AdminPartnersScreen extends ConsumerWidget {
  const AdminPartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(adminPartnerQueueProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Partner applications'),
        actions: [
          IconButton(tooltip: 'Commission report', icon: const Icon(AppIcons.chartBar), onPressed: () => context.push(Routes.adminCommission)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminPartnerQueueProvider);
          await ref.read(adminPartnerQueueProvider.future);
        },
        child: queue.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (list) => list.isEmpty
              ? LayoutBuilder(
                  builder: (_, c) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(height: c.maxHeight, child: const EmptyState(art: AppArt.check, title: 'No applications waiting', subtitle: 'New ones show up here.')),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 24),
                  itemBuilder: (_, i) => _Card(app: list[i]),
                ),
        ),
      ),
    );
  }
}

class _Card extends ConsumerStatefulWidget {
  const _Card({required this.app});
  final PartnerApplication app;

  @override
  ConsumerState<_Card> createState() => _CardState();
}

class _CardState extends ConsumerState<_Card> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject application'),
          content: TextField(controller: c, autofocus: true, maxLines: 2, decoration: const InputDecoration(hintText: 'Reason the applicant will see')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
          ],
        ),
      );
      if (note == null) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(vendorActionsProvider).reviewApplication(widget.app.id, approve: approve, note: note?.isEmpty ?? true ? null : note);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: a.userId == null ? null : () => context.push(Routes.profile(a.userId!)),
                child: UserAvatar(url: a.avatarUrl, name: a.username, size: 36),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${a.username ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('applied ${timeAgo(a.createdAt)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: a.logoUrl == null
                    ? Container(width: 64, height: 64, color: AppColors.surfaceGray, child: const Icon(AppIcons.storefront, color: AppColors.textSecondary))
                    : Image.network(a.logoUrl!, width: 64, height: 64, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.businessName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(businessTypeLabel(a.businessType), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    if (a.address != null) Text(a.address!, style: const TextStyle(fontSize: 13)),
                    if (a.phone != null) Text(a.phone!, style: const TextStyle(fontSize: 13)),
                    if (a.ssmNo != null) Text('SSM ${a.ssmNo}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (a.description != null) ...[
            const SizedBox(height: 8),
            Text(a.description!, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _decide(false),
                  icon: const Icon(AppIcons.xCircle, size: 18, color: AppColors.danger),
                  label: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _decide(true),
                  icon: const Icon(AppIcons.checkCircle, size: 18),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
