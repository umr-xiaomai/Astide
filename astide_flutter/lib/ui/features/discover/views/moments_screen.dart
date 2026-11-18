import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/moment_post.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';
import '../../chat_detail/views/image_viewer_screen.dart';

/// Authentic WeChat Moments ("朋友圈") feed with AI posts, likes, comments, and user publishing.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  String? _openMenuMomentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppScope.of(context).markMomentsSeen();
    });
  }

  Future<void> _onRefreshMoments(AppController app) async {
    await app.reloadMoments();
    await app.markMomentsSeen();
  }

  Future<void> _openComposer(AppController app) async {
    final created = await Navigator.of(context).push<MomentPost>(
      MaterialPageRoute(builder: (_) => const ComposeMomentScreen()),
    );
    if (created != null && mounted) {
      await app.reloadMoments();
      // Trigger autonomous AI likes & comments on the user's new Moment in background.
      unawaited(
        app.momentsAiService
            .reactToUserMoment(
              userPost: created,
              settings: app.settings,
              activeProfile: app.activeApiProfile,
            )
            .then((_) => app.reloadMoments()),
      );
    }
  }

  Future<void> _openCommentInput(
    AppController app,
    MomentPost post, {
    String replyTo = '',
  }) async {
    final ctrl = TextEditingController();
    final submitted = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WeuiColors.bg1,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 10,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: WeuiColors.bg2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: replyTo.isEmpty ? '评论' : '回复 $replyTo:',
                      hintStyle: const TextStyle(color: WeuiColors.fg2, fontSize: 15),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 36,
                child: Material(
                  color: WeuiColors.brand,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          '发送',
                          style: TextStyle(color: Colors.white, fontSize: 14.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    if (submitted == null || submitted.isEmpty) return;

    final userComment = MomentComment(
      id: app.newId(),
      momentId: post.id,
      authorId: 'user',
      authorName: app.settings.userNickname,
      replyToName: replyTo,
      content: submitted,
      createdAt: DateTime.now(),
    );
    await app.momentsRepository.addComment(userComment);
    await app.reloadMoments();

    if (!post.isByUser) {
      unawaited(
        app.momentsAiService
            .replyToUserComment(
              post: post,
              userComment: userComment,
              settings: app.settings,
              activeProfile: app.activeApiProfile,
            )
            .then((_) => app.reloadMoments()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final moments = app.moments;

    return Scaffold(
      backgroundColor: WeuiColors.bg2,
      appBar: AppBar(
        backgroundColor: WeuiColors.bg0,
        title: const Text('朋友圈'),
        actions: [
          IconButton(
            tooltip: '发朋友圈',
            icon: const Icon(Icons.camera_alt_outlined, size: 22),
            onPressed: () => _openComposer(app),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: GestureDetector(
        onTap: () {
          if (_openMenuMomentId != null) {
            setState(() => _openMenuMomentId = null);
          }
        },
        child: RefreshIndicator(
          color: WeuiColors.brand,
          onRefresh: () => _onRefreshMoments(app),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: moments.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _MomentsCoverHeader(
                  nickname: app.settings.userNickname,
                  avatarPath: app.settings.userAvatarPath,
                );
              }
              final post = moments[index - 1];
              return _MomentCard(
                key: ValueKey(post.id),
                post: post,
                myNickname: app.settings.userNickname,
                menuOpen: _openMenuMomentId == post.id,
                onToggleMenu: () {
                  setState(() {
                    _openMenuMomentId = _openMenuMomentId == post.id ? null : post.id;
                  });
                },
                onToggleLike: () async {
                  setState(() => _openMenuMomentId = null);
                  await app.momentsRepository.toggleLike(
                    momentId: post.id,
                    likerName: app.settings.userNickname,
                  );
                  await app.reloadMoments();
                },
                onComment: () {
                  setState(() => _openMenuMomentId = null);
                  _openCommentInput(app, post);
                },
                onReplyComment: (comment) {
                  setState(() => _openMenuMomentId = null);
                  _openCommentInput(
                    app,
                    post,
                    replyTo: comment.authorName == app.settings.userNickname
                        ? ''
                        : comment.authorName,
                  );
                },
                onDelete: post.isByUser
                    ? () async {
                        final ok = await WeuiDialog.confirm(
                          context,
                          title: '删除朋友圈',
                          content: '确定要删除这条朋友圈动态吗？',
                          confirmText: '删除',
                          destructive: true,
                        );
                        if (ok) {
                          await app.momentsRepository.deleteMoment(post.id);
                          await app.reloadMoments();
                        }
                      }
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MomentsCoverHeader extends StatelessWidget {
  const _MomentsCoverHeader({
    required this.nickname,
    this.avatarPath,
  });

  final String nickname;
  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 210,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1F2D3D),
                    Color(0xFF284152),
                    Color(0xFF182530),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: -18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, right: 14),
                    child: Text(
                      nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: WechatAvatar(
                      name: nickname,
                      imagePath: avatarPath,
                      backgroundColor: 0xFF576B95,
                      isUserSelf: true,
                      size: 62,
                      radius: 7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}

class _MomentCard extends StatefulWidget {
  const _MomentCard({
    super.key,
    required this.post,
    required this.myNickname,
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onToggleLike,
    required this.onComment,
    required this.onReplyComment,
    this.onDelete,
  });

  final MomentPost post;
  final String myNickname;
  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onToggleLike;
  final VoidCallback onComment;
  final ValueChanged<MomentComment> onReplyComment;
  final VoidCallback? onDelete;

  @override
  State<_MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<_MomentCard> {
  bool _expanded = false;

  String _formatMomentTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    return DateFormat('M月d日').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasLiked = post.likedByNames.contains(widget.myNickname);
    final isLong = post.content.length > 130 || '\n'.allMatches(post.content).length >= 5;

    return Container(
      decoration: const BoxDecoration(
        color: WeuiColors.bg2,
        border: Border(bottom: BorderSide(color: WeuiColors.bg0, width: 0.8)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WechatAvatar(
            name: post.authorName,
            imagePath: post.authorAvatarPath,
            backgroundColor: post.authorAvatarColor,
            isUserSelf: post.isByUser,
            size: 42,
            radius: 5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.authorName,
                  style: const TextStyle(
                    color: WeuiColors.link,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (post.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    post.content,
                    maxLines: _expanded ? null : 5,
                    overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WeuiColors.textPrimary,
                      fontSize: 15.5,
                      height: 1.45,
                    ),
                  ),
                  if (isLong)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _expanded ? '收起' : '全文',
                          style: const TextStyle(color: WeuiColors.link, fontSize: 14.5),
                        ),
                      ),
                    ),
                ],
                if (post.imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildImagesGrid(context, post.imagePaths),
                ],
                const SizedBox(height: 8),
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerRight,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatMomentTime(post.createdAt),
                          style: const TextStyle(
                            color: WeuiColors.textTimestamp,
                            fontSize: 12.5,
                          ),
                        ),
                        if (widget.onDelete != null) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: widget.onDelete,
                            child: const Text(
                              '删除',
                              style: TextStyle(color: WeuiColors.link, fontSize: 12.5),
                            ),
                          ),
                        ],
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onToggleMenu,
                          child: Container(
                            width: 34,
                            height: 22,
                            decoration: BoxDecoration(
                              color: WeuiColors.bg1,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _MomentDot(),
                                SizedBox(width: 4),
                                _MomentDot(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.menuOpen)
                      Positioned(
                        right: 42,
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: WeuiColors.bg4,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: widget.onToggleLike,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        hasLiked ? Icons.favorite : Icons.favorite_border,
                                        color: hasLiked ? WeuiColors.red : Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        hasLiked ? '取消' : '赞',
                                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 0.5, height: 18, color: const Color(0x44000000)),
                              InkWell(
                                onTap: widget.onComment,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    children: [
                                      Icon(Icons.chat_bubble_outline, color: Colors.white, size: 15),
                                      SizedBox(width: 5),
                                      Text(
                                        '评论',
                                        style: TextStyle(color: Colors.white, fontSize: 13.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (post.likedByNames.isNotEmpty || post.comments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: WeuiColors.bg1,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (post.likedByNames.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 3),
                                  child: Icon(
                                    Icons.favorite_border,
                                    size: 14,
                                    color: WeuiColors.link,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    post.likedByNames.join(', '),
                                    style: const TextStyle(
                                      color: WeuiColors.link,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (post.likedByNames.isNotEmpty && post.comments.isNotEmpty)
                          Container(height: 0.5, color: WeuiColors.fg3),
                        if (post.comments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final c in post.comments)
                                  GestureDetector(
                                    onTap: () => widget.onReplyComment(c),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: c.authorName,
                                              style: const TextStyle(
                                                color: WeuiColors.link,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (c.replyToName.isNotEmpty) ...[
                                              const TextSpan(
                                                text: ' 回复 ',
                                                style: TextStyle(color: WeuiColors.textPrimary),
                                              ),
                                              TextSpan(
                                                text: c.replyToName,
                                                style: const TextStyle(
                                                  color: WeuiColors.link,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                            TextSpan(
                                              text: '：${c.content}',
                                              style: const TextStyle(color: WeuiColors.textPrimary),
                                            ),
                                          ],
                                        ),
                                        style: const TextStyle(fontSize: 13.5, height: 1.4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagesGrid(BuildContext context, List<String> paths) {
    if (paths.length == 1) {
      final p = paths.first;
      final file = File(p);
      if (!file.existsSync()) return const SizedBox.shrink();
      final isSvg = p.toLowerCase().endsWith('.svg');
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ImageViewerScreen(imagePath: p)),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: isSvg
              ? SizedBox(
                  width: 200,
                  height: 150,
                  child: SvgPicture.file(file, fit: BoxFit.cover),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190, maxHeight: 220),
                  child: Image.file(file, fit: BoxFit.cover, cacheWidth: 550),
                ),
        ),
      );
    }

    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final p in paths.take(9))
          if (File(p).existsSync())
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ImageViewerScreen(imagePath: p)),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: p.toLowerCase().endsWith('.svg')
                    ? SizedBox(
                        width: 84,
                        height: 84,
                        child: SvgPicture.file(File(p), fit: BoxFit.cover),
                      )
                    : Image.file(
                        File(p),
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        cacheWidth: 260,
                      ),
              ),
            ),
      ],
    );
  }
}

class _MomentDot extends StatelessWidget {
  const _MomentDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4.5,
      height: 4.5,
      decoration: const BoxDecoration(
        color: WeuiColors.link,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// WeChat-style screen for the user to compose and publish a new Moment.
class ComposeMomentScreen extends StatefulWidget {
  const ComposeMomentScreen({super.key});

  @override
  State<ComposeMomentScreen> createState() => _ComposeMomentScreenState();
}

class _ComposeMomentScreenState extends State<ComposeMomentScreen> {
  final _contentCtrl = TextEditingController();
  final List<String> _imagePaths = [];
  bool _publishing = false;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages(AppController app) async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 88);
    if (picked.isEmpty) return;
    for (final x in picked.take(9 - _imagePaths.length)) {
      final saved = await app.mediaStorage.saveFileCopy(x.path, category: 'images');
      _imagePaths.add(saved);
    }
    if (mounted) setState(() {});
  }

  Future<void> _publish(AppController app) async {
    final text = _contentCtrl.text.trim();
    if (text.isEmpty && _imagePaths.isEmpty) {
      showWeuiToast(context, '写点这一刻的想法或选几张照片吧', isError: true);
      return;
    }

    setState(() => _publishing = true);
    final post = MomentPost(
      id: app.newId(),
      authorId: 'user',
      authorName: app.settings.userNickname,
      authorAvatarPath: app.settings.userAvatarPath,
      authorAvatarColor: 0xFF576B95,
      content: text,
      imagePaths: List.from(_imagePaths),
      createdAt: DateTime.now(),
    );
    await app.momentsRepository.insertMoment(post);
    if (mounted) {
      Navigator.of(context).pop(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Scaffold(
      backgroundColor: WeuiColors.bg2,
      appBar: AppBar(
        backgroundColor: WeuiColors.bg0,
        leadingWidth: 72,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(color: WeuiColors.fg0, fontSize: 16)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: Material(
              color: WeuiColors.brand,
              borderRadius: BorderRadius.circular(5),
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: _publishing ? null : () => _publish(app),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Text(
                      '发表',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _contentCtrl,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(fontSize: 16.5, color: WeuiColors.fg0, height: 1.5),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '这一刻的想法...',
              hintStyle: TextStyle(color: WeuiColors.fg2, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _imagePaths.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(_imagePaths[i]),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        cacheWidth: 280,
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() => _imagePaths.removeAt(i)),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Color(0xCC000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 13, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_imagePaths.length < 9)
                GestureDetector(
                  onTap: () => _pickImages(app),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: WeuiColors.bg1,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.add, size: 34, color: WeuiColors.fg2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
