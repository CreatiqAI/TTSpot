import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/places_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// "Search an address or place" with live suggestions. On pick, hands back the
/// resolved place (name, address, coordinates) so the form can move the pin.
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({super.key, required this.onPicked, this.near, this.enabled = true, this.hint = 'Search a place or address'});
  final ValueChanged<PlaceDetails> onPicked;
  final (double, double)? near;
  final bool enabled;
  final String hint;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> _items = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _items = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    final my = ++_seq;
    setState(() => _loading = true);
    try {
      final r = await ref.read(placesServiceProvider).autocomplete(q, lat: widget.near?.$1, lng: widget.near?.$2);
      if (mounted && my == _seq) setState(() => _items = r);
    } catch (_) {
      if (mounted && my == _seq) setState(() => _items = const []);
    } finally {
      if (mounted && my == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _pick(PlaceSuggestion s) async {
    setState(() {
      _loading = true;
      _items = const [];
      _ctrl.text = s.main;
    });
    _focus.unfocus();
    try {
      final d = await ref.read(placesServiceProvider).details(s.placeId);
      widget.onPicked(d);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t load that place. Try another.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(AppIcons.magnifyingGlass),
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(AppIcons.x, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _items = const []);
                        },
                      ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _items.isEmpty
              ? const SizedBox.shrink()
              : Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _items.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 52),
                        ListTile(
                          dense: true,
                          leading: const Icon(AppIcons.mapPin, size: 20, color: AppColors.textSecondary),
                          title: Text(_items[i].main, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_items[i].secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          onTap: () => _pick(_items[i]),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
