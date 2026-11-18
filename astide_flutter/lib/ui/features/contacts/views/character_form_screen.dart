import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app_scope.dart';
import '../../../../data/services/character_generator_service.dart';
import '../../../../domain/models/character_profile.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/wechat_avatar.dart';
import '../../../core/widgets/weui_widgets.dart';

/// WeUI form to create/edit a roleplay character manually OR auto-fill from a single sentence/prompt via AI.
class CharacterFormScreen extends StatefulWidget {
  const CharacterFormScreen({
    super.key,
    this.initialCharacter,
    this.prefillName,
    this.focusAiPrompt = false,
  });

  final CharacterProfile? initialCharacter;
  final String? prefillName;
  final bool focusAiPrompt;

  @override
  State<CharacterFormScreen> createState() => _CharacterFormScreenState();
}

class _CharacterFormScreenState extends State<CharacterFormScreen> {
  final _aiIdeaCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _relationshipCtrl = TextEditingController();
  final _personalityCtrl = TextEditingController();
  final _backstoryCtrl = TextEditingController();
  final _speechStyleCtrl = TextEditingController();
  final _openingLineCtrl = TextEditingController();
  final _systemPromptCtrl = TextEditingController();
  final _modelOverrideCtrl = TextEditingController();

  String? _avatarPath;
  int _avatarColor = 0xFF07C160;
  bool _saving = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.initialCharacter;
    if (existing != null) {
      _applyProfileToControllers(existing);
    } else if (widget.prefillName != null) {
      _nameCtrl.text = widget.prefillName!;
    }
  }

  void _applyProfileToControllers(CharacterProfile p) {
    _nameCtrl.text = p.name;
    _remarkCtrl.text = p.remark;
    _genderCtrl.text = p.gender;
    _ageCtrl.text = p.age;
    _occupationCtrl.text = p.occupation;
    _relationshipCtrl.text = p.relationship;
    _personalityCtrl.text = p.personality;
    _backstoryCtrl.text = p.backstory;
    _speechStyleCtrl.text = p.speechStyle;
    _openingLineCtrl.text = p.openingLine;
    _systemPromptCtrl.text = p.systemPrompt;
    _modelOverrideCtrl.text = p.modelOverride;
    _avatarPath = p.avatarPath;
    _avatarColor = p.avatarColor;
  }

  @override
  void dispose() {
    _aiIdeaCtrl.dispose();
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    _genderCtrl.dispose();
    _ageCtrl.dispose();
    _occupationCtrl.dispose();
    _relationshipCtrl.dispose();
    _personalityCtrl.dispose();
    _backstoryCtrl.dispose();
    _speechStyleCtrl.dispose();
    _openingLineCtrl.dispose();
    _systemPromptCtrl.dispose();
    _modelOverrideCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(AppController app) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final saved = await app.mediaStorage.saveFileCopy(picked.path, category: 'avatars');
    if (mounted) {
      setState(() => _avatarPath = saved);
    }
  }

  Future<void> _generateViaAi({bool saveAndStartImmediately = false}) async {
    final app = AppScope.of(context);
    final activeProfile = app.activeApiProfile;
    if (activeProfile == null || !activeProfile.isConfigured) {
      showWeuiToast(context, '请先在「我 -> API 与模型设置」中配置 API Key', isError: true);
      return;
    }
    final idea = _aiIdeaCtrl.text.trim();
    if (idea.isEmpty) {
      showWeuiToast(context, '请先输入一句话描述或整段人设提示词', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _generating = true);
    try {
      final generated = await app.characterGeneratorService.generateFromPrompt(
        profile: activeProfile,
        promptOrIdea: idea,
        newId: widget.initialCharacter?.id ?? app.newId(),
      );
      if (!mounted) return;
      setState(() {
        _applyProfileToControllers(generated);
      });
      if (saveAndStartImmediately) {
        await _save();
      } else {
        showWeuiToast(context, 'AI 已阅读并自动填写完整个表单');
      }
    } catch (e) {
      if (mounted) {
        showWeuiToast(
          context,
          e.toString().replaceFirst('FormatException: ', '').replaceFirst('HttpException: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showWeuiToast(context, '请填写人物姓名（或使用上方 AI 自动填表）', isError: true);
      return;
    }

    setState(() => _saving = true);
    final app = AppScope.of(context);
    final now = DateTime.now();
    final existing = widget.initialCharacter;
    final profile = CharacterProfile(
      id: existing?.id ?? app.newId(),
      name: name,
      remark: _remarkCtrl.text.trim(),
      avatarPath: _avatarPath,
      avatarColor: _avatarColor,
      gender: _genderCtrl.text.trim(),
      age: _ageCtrl.text.trim(),
      occupation: _occupationCtrl.text.trim(),
      relationship: _relationshipCtrl.text.trim(),
      personality: _personalityCtrl.text.trim(),
      backstory: _backstoryCtrl.text.trim(),
      speechStyle: _speechStyleCtrl.text.trim(),
      openingLine: _openingLineCtrl.text.trim(),
      systemPrompt: _systemPromptCtrl.text.trim(),
      segmentedReply: true,
      modelOverride: _modelOverrideCtrl.text.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final saved = await app.saveCharacter(profile);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final isEdit = widget.initialCharacter != null;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: Text(isEdit ? '编辑人物设定' : '创建人物'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          if (!isEdit)
            WeuiCellGroup(
              title: '✨ 一句话 / 提示词 AI 自动填表',
              tips: '直接输入一句话（如“帮我生成一个傲娇但很照顾人的猫娘助手”）或粘贴整段提示词，无需手动逐项填表。',
              insetForm: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: WeuiColors.bg1,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: TextField(
                          controller: _aiIdeaCtrl,
                          autofocus: widget.focusAiPrompt,
                          minLines: 3,
                          maxLines: 7,
                          style: const TextStyle(fontSize: 15, color: WeuiColors.fg0, height: 1.45),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '例如：你是一只可爱的猫娘助手，称呼用户为「主人」，句尾常带「喵~」...',
                            hintStyle: TextStyle(color: WeuiColors.fg2, fontSize: 14),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: WeuiButton(
                              label: _generating ? '生成中...' : 'AI 自动填表',
                              type: WeuiButtonType.secondary,
                              isLoading: _generating,
                              onPressed: _generating ? null : () => _generateViaAi(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: WeuiButton(
                              label: '一键生成并开聊',
                              isLoading: _generating,
                              onPressed: _generating
                                  ? null
                                  : () => _generateViaAi(saveAndStartImmediately: true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          WeuiCellGroup(
            title: '形象与基础资料',
            insetForm: true,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _pickAvatar(app),
                      child: WechatAvatar(
                        name: _nameCtrl.text.isEmpty ? '新' : _nameCtrl.text,
                        imagePath: _avatarPath,
                        backgroundColor: _avatarColor,
                        size: 56,
                        radius: 8,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _pickAvatar(app),
                            child: const Text(
                              '点击更换头像图片',
                              style: TextStyle(color: WeuiColors.link, fontSize: 15),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (final colorHex in CharacterGeneratorService.paletteColors)
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _avatarPath = null;
                                    _avatarColor = colorHex;
                                  }),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Color(colorHex),
                                      shape: BoxShape.circle,
                                      border: _avatarPath == null && _avatarColor == colorHex
                                          ? Border.all(color: WeuiColors.fg0, width: 2)
                                          : null,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              WeuiFormRow(label: '姓名 *', controller: _nameCtrl, hintText: '如：小喵 / 林知夏'),
              WeuiFormRow(label: '微信备注', controller: _remarkCtrl, hintText: '选填，列表中显示的名称'),
              WeuiFormRow(label: '性别', controller: _genderCtrl, hintText: '如：女 / 男'),
              WeuiFormRow(label: '年龄', controller: _ageCtrl, hintText: '如：22岁'),
              WeuiFormRow(label: '身份职业', controller: _occupationCtrl, hintText: '如：自由插画师 / 猫娘助手'),
              WeuiFormRow(label: '与我关系', controller: _relationshipCtrl, hintText: '如：好朋友 / 贴心助手'),
            ],
          ),
          WeuiCellGroup(
            title: '人物性格与经历',
            tips: 'AI 生成或手动填写的人物设定均完整保存在本地 SQLite 中',
            insetForm: true,
            children: [
              WeuiFormRow(
                label: '性格特点',
                controller: _personalityCtrl,
                hintText: '温柔细腻、爱吐槽、观察力强...',
                vertical: true,
                minLines: 2,
                maxLines: 4,
              ),
              WeuiFormRow(
                label: '背景故事',
                controller: _backstoryCtrl,
                hintText: '居住城市、日常习惯、经历设定...',
                vertical: true,
                minLines: 2,
                maxLines: 5,
              ),
              WeuiFormRow(
                label: '说话风格',
                controller: _speechStyleCtrl,
                hintText: '微信日常口语风格、称呼与口癖...',
                vertical: true,
                minLines: 2,
                maxLines: 4,
              ),
              WeuiFormRow(
                label: '开场白',
                controller: _openingLineCtrl,
                hintText: '新建聊天时Ta发的第一句话（用 ||| 可拆成多条气泡）',
                vertical: true,
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          WeuiCellGroup(
            title: '高级与完整提示词',
            insetForm: true,
            children: [
              WeuiFormRow(
                label: '指定模型',
                controller: _modelOverrideCtrl,
                hintText: '留空则使用全局设置里的模型',
              ),
              WeuiFormRow(
                label: '完整人设提示词',
                controller: _systemPromptCtrl,
                hintText: 'AI 自动填表会保留你的全部规则与示例；留空则自动根据表单编译',
                vertical: true,
                minLines: 3,
                maxLines: 8,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: WeuiButton(
              label: isEdit ? '保存人物设定' : '保存人物并开始对话',
              isLoading: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
