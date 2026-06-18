import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Reusable Notes & Tasks section widget for any resource (machine or domain).
class NotesAndTasksSection extends ConsumerStatefulWidget {
  final String resourceType;
  final String resourceId;

  const NotesAndTasksSection({
    super.key,
    required this.resourceType,
    required this.resourceId,
  });

  @override
  ConsumerState<NotesAndTasksSection> createState() => _NotesAndTasksSectionState();
}

class _NotesAndTasksSectionState extends ConsumerState<NotesAndTasksSection> {
  final _noteController = TextEditingController();
  final _taskController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  void _addNote() {
    final content = _noteController.text.trim();
    if (content.isEmpty) return;
    final db = ref.read(databaseProvider);
    db.notesDao.addNote(widget.resourceType, widget.resourceId, content);
    _noteController.clear();
    ref.invalidate(notesProvider((widget.resourceType, widget.resourceId)));
  }

  void _deleteNote(String id) {
    final db = ref.read(databaseProvider);
    db.notesDao.deleteNote(id);
    ref.invalidate(notesProvider((widget.resourceType, widget.resourceId)));
  }

  void _addTask() {
    final title = _taskController.text.trim();
    if (title.isEmpty) return;
    final db = ref.read(databaseProvider);
    db.notesDao.addTask(widget.resourceType, widget.resourceId, title);
    _taskController.clear();
    ref.invalidate(tasksProvider((widget.resourceType, widget.resourceId)));
  }

  void _toggleTask(String id, bool done) {
    final db = ref.read(databaseProvider);
    db.notesDao.toggleTask(id, done);
    ref.invalidate(tasksProvider((widget.resourceType, widget.resourceId)));
  }

  void _deleteTask(String id) {
    final db = ref.read(databaseProvider);
    db.notesDao.deleteTask(id);
    ref.invalidate(tasksProvider((widget.resourceType, widget.resourceId)));
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider((widget.resourceType, widget.resourceId)));
    final tasksAsync = ref.watch(tasksProvider((widget.resourceType, widget.resourceId)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('NOTES & TASKS', style: AppTheme.labelStyle),
              ],
            ),
            const SizedBox(height: 16),

            // ── Tasks ──
            const Text('TASKS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: AppTheme.displayFont, color: AppColors.secondary)),
            const SizedBox(height: 8),
            tasksAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const Text('Could not load tasks', style: TextStyle(color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
              data: (tasks) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('No tasks yet', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                      ),
                    ...tasks.map((task) => _TaskRow(
                      task: task,
                      onToggle: (done) => _toggleTask(task.id, done),
                      onDelete: () => _deleteTask(task.id),
                    )),
                    const SizedBox(height: 8),
                    _AddRow(
                      controller: _taskController,
                      hintText: 'Add a task...',
                      onSubmitted: _addTask,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // ── Notes ──
            const Text('NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: AppTheme.displayFont, color: AppColors.secondary)),
            const SizedBox(height: 8),
            notesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const Text('Could not load notes', style: TextStyle(color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
              data: (notes) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('No notes yet', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                      ),
                    ...notes.map((note) => _NoteCard(
                      note: note,
                      onDelete: () => _deleteNote(note.id),
                    )),
                    const SizedBox(height: 8),
                    _AddRow(
                      controller: _noteController,
                      hintText: 'Add a note...',
                      onSubmitted: _addNote,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _TaskRow({required this.task, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: task.done,
              onChanged: (v) => onToggle(v ?? false),
              activeColor: AppColors.tertiary,
              side: const BorderSide(color: AppColors.outline),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppTheme.bodyFont,
                color: task.done ? AppColors.secondary.withValues(alpha: 0.5) : AppColors.primary,
                decoration: task.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 14, color: AppColors.outline),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onDelete;

  const _NoteCard({required this.note, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final ts = note.createdAt;
    final dateStr = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.content, style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, color: AppColors.primary)),
                const SizedBox(height: 4),
                Text(dateStr, style: TextStyle(fontSize: 10, fontFamily: AppTheme.bodyFont, color: AppColors.secondary.withValues(alpha: 0.5))),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 14, color: AppColors.outline),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSubmitted;

  const _AddRow({required this.controller, required this.hintText, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => onSubmitted(),
            style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, color: AppColors.primary),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, color: AppColors.secondary.withValues(alpha: 0.4)),
              filled: true,
              fillColor: AppColors.neutral,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.tertiary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onSubmitted,
          icon: const Icon(Icons.add, size: 18, color: AppColors.tertiary),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.tertiary.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }
}