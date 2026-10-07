import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../application/door_providers.dart';
import '../domain/door_models.dart';

/// The preset check-in areas, in metres.
const kCheckinAreaPresets = [300, 500, 1000, 2000, 5000];

/// Host: how far from the event pin members can check in.
class CheckinAreaScreen extends ConsumerStatefulWidget {
  const CheckinAreaScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<CheckinAreaScreen> createState() => _CheckinAreaScreenState();
}

class _CheckinAreaScreenState extends ConsumerState<CheckinAreaScreen> {
  int? _picked;
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _custom(int current) async {
    final c = TextEditingController(text: '$current');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom area'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'm', helperText: '50 m to 100 km'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('OK')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (v == null) return;
    if (v < 50 || v > 100000) return _snack('Pick between 50 m and 100 km.');
    setState(() => _picked = v);
  }

  Future<void> _save(int metres) async {
    setState(() => _busy = true);
    try {
      final m = await ref.read(doorActionsProvider).setCheckinRadius(widget.eventId, metres);
      if (!mounted) return;
      setState(() => _picked = null);
      _snack('Saved. People can check in within ${formatMetres(m)}.');
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = ref.watch(checkinRadiusProvider(widget.eventId));
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;
    final current = radius.value;
    final value = _picked ?? current;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.arrowLeft), onPressed: () => context.pop()),
        title: const Text('Check-in area'),
      ),
      body: radius.hasError && current == null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(radius.error!), textAlign: TextAlign.center)))
          : current == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(AppIcons.mapPinArea, size: 22, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'People check in by scanning your QR within this distance of the event pin. Big halls and car parks need more.',
                            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surfaceGray, borderRadius: BorderRadius.circular(AppRadius.lg)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AREA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          Text(
                            formatMetres(value!),
                            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 40, height: 1.05, fontWeight: FontWeight.w700),
                          ),
                          if (_picked != null && _picked != current)
                            Text('Now ${formatMetres(current)}. Save to change.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in kCheckinAreaPresets)
                          ChoiceChip(label: Text(formatMetres(m)), selected: value == m, showCheckmark: false, onSelected: (_) => setState(() => _picked = m)),
                        if (isAdmin)
                          ChoiceChip(
                            label: const Text('Custom'),
                            selected: !kCheckinAreaPresets.contains(value),
                            showCheckmark: false,
                            onSelected: (_) => _custom(value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(label: 'Save', loading: _busy, onPressed: _picked == null || _picked == current ? null : () => _save(_picked!)),
                    const SizedBox(height: 10),
                    Text(
                      isAdmin ? 'Up to 100 km for admins.' : 'Up to 5 km. Need more? Ask TT Spot.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                    ),
                  ],
                ),
    );
  }
}
