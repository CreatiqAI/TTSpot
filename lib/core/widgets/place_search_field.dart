import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/place_autocomplete.dart';
import '../places/places_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// "Search an address or place" with live suggestions. On pick, hands back the
/// resolved place (name, address, coordinates) so the form can move the pin.
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.onPicked,
    this.near,
    this.enabled = true,
    this.hint = 'Search a place or address',
    this.label,
    this.icon = AppIcons.magnifyingGlass,
    this.controller,
    this.onChanged,
    this.autofocus = false,
  });
  final ValueChanged<PlaceDetails> onPicked;
  final (double, double)? near;
  final bool enabled;
  final String hint;
  final String? label;
  final IconData icon;
  /// Pass one to read the free text back (when nothing was picked).
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  late final TextEditingController _ctrl = widget.controller ?? TextEditingController();
  final _focus = FocusNode();
  // Debounce, one session token from first keystroke to the pick, stale answers dropped.
  late final _auto = PlaceAutocomplete(
    (q, token) => ref.read(placesServiceProvider).autocomplete(q, lat: widget.near?.$1, lng: widget.near?.$2, sessionToken: token),
  )..addListener(_rebuild);
  bool _resolving = false;

  List<PlaceSuggestion> get _items => _auto.items;
  bool get _loading => _auto.loading || _resolving;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auto.dispose();
    if (widget.controller == null) _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    widget.onChanged?.call(v);
    _auto.onChanged(v);
  }

  Future<void> _pick(PlaceSuggestion s) async {
    final token = _auto.pick(); // a late keystroke would open a new session after the pick
    setState(() {
      _resolving = true;
      _ctrl.text = s.main;
    });
    _focus.unfocus();
    try {
      final d = await ref.read(placesServiceProvider).details(s.placeId, sessionToken: token);
      widget.onPicked(d);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't load that place. Try another.")));
    } finally {
      _auto.finish();
      if (mounted) setState(() => _resolving = false);
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
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.words,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon),
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(AppIcons.x, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          _auto.clear();
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
                          leading: Icon(AppIcons.mapPin, size: 20, color: AppColors.textSecondary),
                          title: Text(_items[i].main, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_items[i].secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
