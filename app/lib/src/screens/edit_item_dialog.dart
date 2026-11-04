import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/models.dart';
import '../models/validation.dart';
import '../services/api.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'item_fields.dart';

/// Edits an item's details, or hides it. Returns the updated item.
Future<Item?> showEditItemDialog(BuildContext context, {required Item item}) {
  final services = AppScope.of(context);
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
  final editor = AppScope(
    services: services,
    child: _EditItemForm(item: item),
  );
  if (wide) {
    return showDialog<Item>(
      context: context,
      animationStyle: Motion.dialog(context),
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: editor,
        ),
      ),
    );
  }
  return Navigator.of(context).push<Item>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => editor),
  );
}

class _EditItemForm extends StatefulWidget {
  const _EditItemForm({required this.item});
  final Item item;

  @override
  State<_EditItemForm> createState() => _EditItemFormState();
}

class _EditItemFormState extends State<_EditItemForm> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.item.courseCode);
  late final _title = TextEditingController(text: widget.item.title);
  late final _session = TextEditingController(text: widget.item.session);
  late final _note = TextEditingController(text: widget.item.description);
  late ItemType _type = widget.item.type;
  late Semester _semester = widget.item.semester;
  late bool _hidden = widget.item.hidden;
  bool _saving = false;
  String? _error;
  final _serverErrors = <String, String>{};

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _session.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _serverErrors.clear();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final services = AppScope.of(context);
    try {
      final updated = await services.api
          .updateItem(widget.item.shelfId, widget.item.id, {
            'courseCode': normalizeCourseCode(_code.text),
            'title': _title.text.trim(),
            'type': _type.wire,
            'semester': _semester.wire,
            'session': normalizeSession(_session.text),
            'description': _note.text.trim(),
            'hidden': _hidden,
          });
      if (mounted) Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e.field != null) {
          _serverErrors[e.field!] = e.message;
          _form.currentState!.validate();
        } else {
          _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fullscreen = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final form = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldRow(
            children: [
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Course code',
                  hintText: 'CSC 301',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    _serverErrors['courseCode'] ?? validateCourseCode(v ?? ''),
              ),
              TypePicker(
                value: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            maxLength: 120,
            validator: (v) => _serverErrors['title'] ?? validateTitle(v ?? ''),
          ),
          const SizedBox(height: Space.xs),
          FieldRow(
            children: [
              SemesterPicker(
                value: _semester,
                onChanged: (s) => setState(() => _semester = s),
              ),
              TextFormField(
                controller: _session,
                decoration: const InputDecoration(
                  labelText: 'Session',
                  hintText: '2026/2027',
                ),
                keyboardType: TextInputType.datetime,
                validator: (v) =>
                    _serverErrors['session'] ?? validateSession(v ?? ''),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Short description (optional)',
              hintText: 'For example: covers weeks 1 to 4',
            ),
            maxLength: 280,
            minLines: 2,
            maxLines: 4,
            validator: (v) =>
                _serverErrors['description'] ?? validateDescription(v ?? ''),
          ),
          const SizedBox(height: Space.xs),
          SwitchListTile(
            value: _hidden,
            onChanged: (v) => setState(() => _hidden = v),
            contentPadding: EdgeInsets.zero,
            title: Text('Hide from the shelf', style: text.titleSmall),
            subtitle: Text(
              'Students will not see it. The file stays on Walrus until its '
              'storage period ends, or until you delete it with Walrus tools.',
              style: text.bodySmall,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Notice(tone: NoticeTone.error, child: Text(_error!)),
          ],
        ],
      ),
    );

    final actions = [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save changes'),
      ),
    ];

    if (fullscreen) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit details'),
          backgroundColor: LecternColors.paper,
          surfaceTintColor: Colors.transparent,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.item.fileName, style: text.bodySmall),
              const SizedBox(height: Space.md),
              form,
              const SizedBox(height: Space.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  actions[0],
                  const SizedBox(width: Space.xs),
                  actions[1],
                ],
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit details', style: text.headlineSmall),
          const SizedBox(height: 2),
          Text(widget.item.fileName, style: text.bodySmall),
          const SizedBox(height: Space.lg),
          form,
          const SizedBox(height: Space.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              actions[0],
              const SizedBox(width: Space.xs),
              actions[1],
            ],
          ),
        ],
      ),
    );
  }
}
