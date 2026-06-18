import 'package:drift/drift.dart';
import '../database.dart';
import '../tables.dart';

part 'notes_dao.g.dart';

/// DAO for Notes and Tasks tables.
@DriftAccessor(tables: [Notes, Tasks])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  // ── Notes ──

  /// Get all notes for a resource.
  Future<List<Note>> getNotes(String resourceType, String resourceId) {
    return (select(notes)
          ..where((n) => n.resourceType.equals(resourceType) & n.resourceId.equals(resourceId))
          ..orderBy([(n) => OrderingTerm.asc(n.createdAt)]))
        .get();
  }

  /// Add a note.
  Future<void> addNote(String resourceType, String resourceId, String content) {
    final id = 'note-${DateTime.now().millisecondsSinceEpoch}';
    return into(notes).insert(NotesCompanion.insert(
      id: id,
      resourceType: resourceType,
      resourceId: resourceId,
      content: content,
    ));
  }

  /// Update a note.
  Future<void> updateNote(String id, String content) {
    return (update(notes)..where((n) => n.id.equals(id)))
        .write(NotesCompanion(content: Value(content), updatedAt: Value(DateTime.now())));
  }

  /// Delete a note.
  Future<void> deleteNote(String id) {
    return (delete(notes)..where((n) => n.id.equals(id))).go();
  }

  // ── Tasks ──

  /// Get all tasks for a resource.
  Future<List<Task>> getTasks(String resourceType, String resourceId) {
    return (select(tasks)
          ..where((t) => t.resourceType.equals(resourceType) & t.resourceId.equals(resourceId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Add a task.
  Future<void> addTask(String resourceType, String resourceId, String title, {int sortOrder = 0}) {
    final id = 'task-${DateTime.now().millisecondsSinceEpoch}';
    return into(tasks).insert(TasksCompanion.insert(
      id: id,
      resourceType: resourceType,
      resourceId: resourceId,
      title: title,
      sortOrder: Value(sortOrder),
    ));
  }

  /// Toggle a task's done status.
  Future<void> toggleTask(String id, bool done) {
    return (update(tasks)..where((t) => t.id.equals(id)))
        .write(TasksCompanion(done: Value(done), updatedAt: Value(DateTime.now())));
  }

  /// Update a task title.
  Future<void> updateTaskTitle(String id, String title) {
    return (update(tasks)..where((t) => t.id.equals(id)))
        .write(TasksCompanion(title: Value(title), updatedAt: Value(DateTime.now())));
  }

  /// Delete a task.
  Future<void> deleteTask(String id) {
    return (delete(tasks)..where((t) => t.id.equals(id))).go();
  }
}