import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Feuille du bas à choix unique (filtres, date…) : titre, liste d'options,
/// coche orange sur l'option courante. Retourne l'option touchée, ou null
/// si la feuille est fermée sans choix. Une longue liste (15 places d'un
/// minibus) défile et s'ouvre sur l'option courante.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) =>
        _OptionSheet<T>(title: title, options: options, selected: selected),
  );
}

class _OptionSheet<T> extends StatefulWidget {
  final String title;
  final List<(T, String)> options;
  final T selected;

  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  State<_OptionSheet<T>> createState() => _OptionSheetState<T>();
}

class _OptionSheetState<T> extends State<_OptionSheet<T>> {
  static const _rowHeight = 52.0;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Deux options visibles au-dessus de l'option courante.
    final index = widget.options.indexWhere((o) => o.$1 == widget.selected);
    _scroll = ScrollController(
      initialScrollOffset: index > 2 ? (index - 2) * _rowHeight : 0,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title, style: AppTextStyles.title2),
            ),
            Flexible(
              child: ListView(
                controller: _scroll,
                shrinkWrap: true,
                children: [
                  for (final (value, label) in widget.options)
                    InkWell(
                      onTap: () => Navigator.of(context).pop(value),
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: _rowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    height: 1.2,
                                    fontWeight: value == widget.selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (value == widget.selected)
                                const Icon(Icons.check_rounded,
                                    color: AppColors.primary, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
