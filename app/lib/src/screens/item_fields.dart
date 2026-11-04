import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';

/// Type and semester pickers shared by the upload desk and the edit dialog.
class TypePicker extends StatelessWidget {
  const TypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ItemType value;
  final ValueChanged<ItemType> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ItemType>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Type'),
      items: [
        for (final t in ItemType.values)
          DropdownMenuItem(value: t, child: Text(t.label)),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) onChanged(v);
            }
          : null,
    );
  }
}

class SemesterPicker extends StatelessWidget {
  const SemesterPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  final Semester? value;
  final ValueChanged<Semester> onChanged;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Semester>(
      initialValue: value,
      isExpanded: true,
      hint: const Text('Choose'),
      decoration: InputDecoration(labelText: 'Semester', errorText: errorText),
      items: [
        for (final s in Semester.values)
          DropdownMenuItem(
            value: s,
            child: Text(
              '${s.label.split(' ').first} · ${s.alsoCalled}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      selectedItemBuilder: (context) => [
        for (final s in Semester.values)
          Text(s.label, overflow: TextOverflow.ellipsis),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) onChanged(v);
            }
          : null,
    );
  }
}

/// Lays out fields two-up on wide screens and stacked on phones.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.children, this.breakpoint = 520});
  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: Space.md),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.sm),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}
