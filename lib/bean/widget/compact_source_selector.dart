import 'package:flutter/material.dart';

/// A single option shown in [CompactSourceSelector].
class CompactSelectorOption<T> {
  const CompactSelectorOption({
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final String title;
  final String subtitle;
}

/// A compact `MenuAnchor`-based selector shared by the source sheet and the
/// playback episode panel. It shows a label, the current value and an optional
/// subtitle while collapsed, and a list of titled options when open.
class CompactSourceSelector<T> extends StatelessWidget {
  const CompactSourceSelector({
    super.key,
    required this.label,
    required this.valueLabel,
    this.valueSubtitle,
    required this.selectedValue,
    required this.enabled,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String valueLabel;
  final String? valueSubtitle;
  final T? selectedValue;
  final bool enabled;
  final List<CompactSelectorOption<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MenuAnchor(
          crossAxisUnconstrained: false,
          consumeOutsideTap: true,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            alignment: AlignmentDirectional.topStart,
            backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(3),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(width, MediaQuery.sizeOf(context).height * 0.65),
            ),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Text(
                '选择$label',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            for (final option in options)
              MenuItemButton(
                onPressed: () => onSelected(option.value),
                style: ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(width - 12, 48)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: WidgetStatePropertyAll(
                    option.value == selectedValue
                        ? colors.secondaryContainer
                        : colors.surfaceContainerLow,
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    option.value == selectedValue
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            option.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: option.value == selectedValue
                                  ? colors.onSecondaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (option.value == selectedValue)
                      Icon(
                        Icons.check_rounded,
                        color: colors.primary,
                        size: 18,
                      ),
                  ],
                ),
              ),
          ],
          builder: (context, controller, child) {
            final open = controller.isOpen;
            final foreground = enabled
                ? open
                      ? colors.onSecondaryContainer
                      : colors.onSurface
                : colors.onSurfaceVariant;
            return Semantics(
              button: enabled,
              expanded: enabled ? open : null,
              label: enabled ? '切换$label' : valueLabel,
              child: Material(
                color: open
                    ? colors.secondaryContainer
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(open ? 14 : 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled
                      ? () => controller.isOpen
                            ? controller.close()
                            : controller.open()
                      : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: foreground,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  valueLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: foreground,
                                  ),
                                ),
                                if (valueSubtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    valueSubtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: foreground.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
