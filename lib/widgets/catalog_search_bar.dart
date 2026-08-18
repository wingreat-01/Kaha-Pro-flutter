import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Search-with-autocomplete bar for locating an item by name in a
/// catalog that's already fully loaded in memory (Product or
/// Ingredient lists both work — pass in whatever names list applies).
/// No network calls: this is a pure client-side filter, so there's no
/// debounce, it just rebuilds/re-filters on every keystroke.
///
/// Two things it does:
/// 1. Calls [onQueryChanged] on every keystroke so the caller can
///    filter its own grid/list live (this widget doesn't own the
///    filtered result — the caller's `_filtered()` style method does,
///    same as it already filters by category/tab).
/// 2. Shows an autocomplete dropdown of up to [maxSuggestions] matching
///    names below the field via an Overlay (CompositedTransformTarget/
///    Follower) — tapping a suggestion fills the field and triggers
///    [onSuggestionSelected] (falls back to [onQueryChanged] with the
///    picked name if that's not provided), so the caller can jump
///    straight to that item instead of just narrowing the list.
///
/// Starts collapsed to a bare search icon (saves header width on
/// phone, where this sits next to the Edit toggle) and expands into a
/// full-width field on tap; collapses back automatically once it's
/// empty and loses focus. Pass [alwaysExpanded] true to skip the
/// collapse behavior entirely (e.g. if there's a dedicated header row
/// with room to spare, like a standalone Inventory panel toolbar).
class CatalogSearchBar extends StatefulWidget {
  final List<String> suggestions;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String>? onSuggestionSelected;
  final String hintText;
  final int maxSuggestions;
  final bool alwaysExpanded;

  const CatalogSearchBar({
    super.key,
    required this.suggestions,
    required this.onQueryChanged,
    this.onSuggestionSelected,
    this.hintText = 'Search products…',
    this.maxSuggestions = 6,
    this.alwaysExpanded = false,
  });

  @override
  State<CatalogSearchBar> createState() => _CatalogSearchBarState();
}

class _CatalogSearchBarState extends State<CatalogSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.alwaysExpanded;
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
      // Collapse back to icon-only once empty and unfocused — but not
      // if alwaysExpanded, and not while there's still text in the
      // field (a non-empty query should stay visible/filterable even
      // after the user taps elsewhere, e.g. to tap a filtered product
      // card).
      if (!widget.alwaysExpanded && _controller.text.isEmpty) {
        setState(() => _expanded = false);
      }
    } else {
      _showOverlay();
    }
  }

  void _onTextChanged() {
    widget.onQueryChanged(_controller.text);
    if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  List<String> get _matches {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final seen = <String>{};
    final results = <String>[];
    for (final name in widget.suggestions) {
      if (results.length >= widget.maxSuggestions) break;
      final lower = name.toLowerCase();
      if (lower.contains(query) && seen.add(lower)) {
        results.add(name);
      }
    }
    return results;
  }

  void _showOverlay() {
    _removeOverlay();
    final matches = _matches;
    if (matches.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 260;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 44),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.slate,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ledAmber.withOpacity(0.25)),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
              ),
              margin: const EdgeInsets.only(top: 4),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final name = matches[i];
                  return InkWell(
                    onTap: () => _selectSuggestion(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: AppTextStyles.body(size: 13, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectSuggestion(String name) {
    _controller.text = name;
    _controller.selection = TextSelection.collapsed(offset: name.length);
    _removeOverlay();
    _focusNode.unfocus();
    if (widget.onSuggestionSelected != null) {
      widget.onSuggestionSelected!(name);
    } else {
      widget.onQueryChanged(name);
    }
  }

  void _clear() {
    _controller.clear();
    widget.onQueryChanged('');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return IconButton(
        tooltip: 'Search',
        icon: Icon(Icons.search, size: 18, color: AppColors.textSecondary),
        onPressed: () {
          setState(() => _expanded = true);
          // Wait for the field to actually build before focusing it —
          // requesting focus in the same frame as the setState that
          // creates the field can no-op, same class of timing issue as
          // the AI assistant input's post-send refocus.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusNode.requestFocus();
          });
        },
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        height: 36,
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.slate),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: AppTextStyles.body(size: 13, color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hintText,
                  hintStyle: AppTextStyles.body(size: 13, color: AppColors.textMuted),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              InkWell(
                onTap: _clear,
                child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
