import 'package:astide_flutter/data/repositories/moments_repository.dart';
import 'package:astide_flutter/data/services/database_service.dart';
import 'package:astide_flutter/domain/models/moment_post.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late DatabaseService dbService;
  late MomentsRepository momentsRepo;

  setUp(() {
    dbService = DatabaseService(
      factoryOverride: databaseFactoryFfiNoIsolate,
      pathOverride: inMemoryDatabasePath,
    );
    momentsRepo = MomentsRepository(databaseService: dbService);
  });

  tearDown(() async {
    await dbService.close();
  });

  test('seeds initial Moment, toggles likes, and persists comments', () async {
    await momentsRepo.ensureInitialMoments();
    final initial = await momentsRepo.listMoments();
    expect(initial.length, equals(1));
    expect(initial.first.authorName, equals('星汐 Astide'));

    final liked = await momentsRepo.toggleLike(
      momentId: initial.first.id,
      likerName: '我',
    );
    expect(liked?.likedByNames, contains('我'));

    final unliked = await momentsRepo.toggleLike(
      momentId: initial.first.id,
      likerName: '我',
    );
    expect(unliked?.likedByNames, isNot(contains('我')));

    await momentsRepo.addComment(MomentComment(
      id: 'c-1',
      momentId: initial.first.id,
      authorId: 'user',
      authorName: '我',
      content: '今晚的风确实很舒服',
      createdAt: DateTime.now(),
    ));

    final reloaded = await momentsRepo.getMoment(initial.first.id);
    expect(reloaded?.comments.length, equals(1));
    expect(reloaded?.comments.first.content, equals('今晚的风确实很舒服'));

    final contextSnippet = await momentsRepo.buildMomentsContextSnippet();
    expect(contextSnippet, contains('热乌龙茶'));
    expect(contextSnippet, contains('今晚的风确实很舒服'));
  });
}
