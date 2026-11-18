import 'package:flutter/material.dart';

import '../../../../app_scope.dart';
import '../../../../domain/models/api_profile.dart';
import '../../../core/theme/wechat_theme.dart';
import '../../../core/widgets/weui_widgets.dart';

/// WeUI settings screen for OpenAI-compatible API profiles, models, Vision, and default persona prompt.
class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _defaultPromptCtrl = TextEditingController();

  String? _editingProfileId;
  bool _supportsVision = false;
  bool _supportsReasoning = false;
  bool _streamEnabled = true;
  double _temperature = 0.8;
  bool _obscureKey = true;
  bool _testing = false;
  bool _saving = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final app = AppScope.of(context);
      _defaultPromptCtrl.text = app.settings.defaultAssistantPrompt;
      final active = app.activeApiProfile;
      if (active != null) {
        _loadProfileIntoForm(active);
      }
    }
  }

  void _loadProfileIntoForm(ApiProfile p) {
    _editingProfileId = p.id;
    _nameCtrl.text = p.name;
    _baseUrlCtrl.text = p.baseUrl;
    _apiKeyCtrl.text = p.apiKey;
    _modelCtrl.text = p.model;
    _supportsVision = p.supportsVision;
    _supportsReasoning = p.supportsReasoning;
    _streamEnabled = p.streamEnabled;
    _temperature = p.temperature;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _defaultPromptCtrl.dispose();
    super.dispose();
  }

  ApiProfile _buildProfileFromForm(AppController app) {
    final now = DateTime.now();
    return ApiProfile(
      id: _editingProfileId ?? app.newId(),
      name: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : '自定义模型',
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      supportsVision: _supportsVision,
      supportsReasoning: _supportsReasoning,
      streamEnabled: _streamEnabled,
      temperature: _temperature,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _testConnection() async {
    final app = AppScope.of(context);
    final profile = _buildProfileFromForm(app);
    setState(() => _testing = true);
    try {
      final msg = await app.openAiChatService.testConnection(profile);
      if (mounted) showWeuiToast(context, msg);
    } catch (e) {
      if (mounted) {
        showWeuiToast(
          context,
          e.toString().replaceFirst('HttpException: ', '').replaceFirst('FormatException: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _fetchAndPickModel() async {
    final app = AppScope.of(context);
    final profile = _buildProfileFromForm(app);
    try {
      showWeuiToast(context, '正在从 /models 拉取可用模型...');
      final models = await app.openAiChatService.fetchAvailableModels(profile);
      if (!mounted) return;
      if (models.isEmpty) {
        showWeuiToast(context, '未返回模型列表', isError: true);
        return;
      }
      await WeuiActionSheet.show(
        context,
        title: '选择可用模型',
        actions: [
          for (final id in models)
            WeuiSheetAction(
              label: id,
              onTap: () {
                setState(() {
                  _modelCtrl.text = id;
                  if (id == 'deepseek-flash') {
                    _supportsVision = true;
                  } else if (id == 'deepseek-v4-pro') {
                    _supportsVision = false;
                  }
                });
              },
            ),
        ],
      );
    } catch (e) {
      if (mounted) {
        showWeuiToast(
          context,
          e.toString().replaceFirst('HttpException: ', '').replaceFirst('FormatException: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    final baseUrl = _baseUrlCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      showWeuiToast(context, '请填写 API 地址与模型名称', isError: true);
      return;
    }

    setState(() => _saving = true);
    final profile = _buildProfileFromForm(app);
    await app.saveApiProfile(profile);
    await app.updateSettings(
      app.settings.copyWith(
        defaultAssistantPrompt: _defaultPromptCtrl.text.trim().isNotEmpty
            ? _defaultPromptCtrl.text.trim()
            : app.settings.defaultAssistantPrompt,
      ),
    );
    if (mounted) {
      setState(() => _saving = false);
      showWeuiToast(context, 'API 与模型设置已保存到本地 SQLite');
    }
  }

  void _applyQuickPreset({
    required String name,
    required String baseUrl,
    required String model,
    required bool vision,
    required bool reasoning,
  }) {
    final app = AppScope.of(context);
    setState(() {
      _editingProfileId = app.newId();
      _nameCtrl.text = name;
      _baseUrlCtrl.text = baseUrl;
      _modelCtrl.text = model;
      _supportsVision = vision;
      _supportsReasoning = reasoning;
      // Preserve currently typed key so switching presets doesn't wipe a user's key if same provider.
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final profiles = app.apiProfiles;

    return Scaffold(
      backgroundColor: WeuiColors.bg0,
      appBar: AppBar(
        title: const Text('API 与模型设置'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: WeuiColors.fg3),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          if (profiles.isNotEmpty)
            WeuiCellGroup(
              title: '已保存配置（点击切换当前激活）',
              insetForm: true,
              children: [
                for (final p in profiles)
                  WeuiCell(
                    title: p.name,
                    subtitle: '${p.model} · ${p.apiKey.isEmpty ? "未填 Key" : "已配置 Key"}',
                    leading: Icon(
                      p.isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: p.isActive ? WeuiColors.brand : WeuiColors.fg2,
                    ),
                    trailing: profiles.length > 1
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: WeuiColors.fg2),
                            onPressed: () async {
                              await app.deleteApiProfile(p.id);
                              final nextActive = app.activeApiProfile;
                              if (nextActive != null && mounted) {
                                setState(() => _loadProfileIntoForm(nextActive));
                              }
                            },
                          )
                        : null,
                    onTap: () async {
                      await app.setActiveApiProfile(p.id);
                      setState(() => _loadProfileIntoForm(p));
                    },
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PresetChip(
                  label: '+ DeepSeek Flash',
                  onTap: () => _applyQuickPreset(
                    name: 'DeepSeek Flash (V4.1)',
                    baseUrl: 'https://api.deepseek.com',
                    model: 'deepseek-flash',
                    vision: true,
                    reasoning: false,
                  ),
                ),
                _PresetChip(
                  label: '+ DeepSeek Flash (思考)',
                  onTap: () => _applyQuickPreset(
                    name: 'DeepSeek Flash (思考模式)',
                    baseUrl: 'https://api.deepseek.com',
                    model: 'deepseek-flash',
                    vision: true,
                    reasoning: true,
                  ),
                ),
                _PresetChip(
                  label: '+ OpenAI / Vision',
                  onTap: () => _applyQuickPreset(
                    name: 'OpenAI GPT-4o',
                    baseUrl: 'https://api.openai.com/v1',
                    model: 'gpt-4o-mini',
                    vision: true,
                    reasoning: false,
                  ),
                ),
              ],
            ),
          ),
          WeuiCellGroup(
            title: '当前配置参数',
            tips: '默认使用 DeepSeek 官方 deepseek-flash（支持图像理解与思考切换），兼容所有 OpenAI 格式接口地址。',
            insetForm: true,
            children: [
              WeuiFormRow(label: '配置名称', controller: _nameCtrl, hintText: '如：DeepSeek Flash'),
              WeuiFormRow(
                label: 'API 地址',
                controller: _baseUrlCtrl,
                hintText: 'https://api.deepseek.com',
                keyboardType: TextInputType.url,
              ),
              WeuiFormRow(
                label: 'API Key',
                controller: _apiKeyCtrl,
                hintText: 'sk-...',
                obscureText: _obscureKey,
                trailing: GestureDetector(
                  onTap: () => setState(() => _obscureKey = !_obscureKey),
                  child: Icon(
                    _obscureKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: WeuiColors.fg1,
                  ),
                ),
              ),
              WeuiFormRow(
                label: '模型名称',
                controller: _modelCtrl,
                hintText: 'deepseek-flash',
                trailing: GestureDetector(
                  onTap: _fetchAndPickModel,
                  child: const Text(
                    '拉取模型',
                    style: TextStyle(color: WeuiColors.link, fontSize: 13.5),
                  ),
                ),
              ),
            ],
          ),
          WeuiCellGroup(
            title: '能力开关与参数',
            insetForm: true,
            children: [
              WeuiCell(
                title: '流式响应 (Stream)',
                subtitle: '实时逐字显示回复，开启后交互更流畅',
                trailing: WeuiSwitch(
                  value: _streamEnabled,
                  onChanged: (v) => setState(() => _streamEnabled = v),
                ),
              ),
              WeuiCell(
                title: '支持视觉识图 (Vision)',
                subtitle: '发送图片时附带 image_url（纯文本模型请保持关闭）',
                trailing: WeuiSwitch(
                  value: _supportsVision,
                  onChanged: (v) => setState(() => _supportsVision = v),
                ),
              ),
              WeuiCell(
                title: '支持深度思考过程',
                subtitle: '显示 reasoning_content 折叠思考过程',
                trailing: WeuiSwitch(
                  value: _supportsReasoning,
                  onChanged: (v) => setState(() => _supportsReasoning = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('温度 (Temperature)',
                            style: TextStyle(fontSize: 16, color: WeuiColors.fg0)),
                        Text(_temperature.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 15, color: WeuiColors.brand)),
                      ],
                    ),
                    Slider(
                      value: _temperature,
                      min: 0.0,
                      max: 1.5,
                      divisions: 15,
                      activeColor: WeuiColors.brand,
                      onChanged: (v) => setState(() => _temperature = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          WeuiCellGroup(
            title: '默认“星汐 Astide”人设提示词',
            tips: '默认对话时，星汐会以真实人类身份和你聊天而不自称AI',
            insetForm: true,
            children: [
              WeuiFormRow(
                label: '系统提示词',
                controller: _defaultPromptCtrl,
                vertical: true,
                minLines: 3,
                maxLines: 6,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: Column(
              children: [
                WeuiButton(
                  label: '保存配置',
                  isLoading: _saving,
                  onPressed: _save,
                ),
                const SizedBox(height: 12),
                WeuiButton(
                  label: '测试连接',
                  type: WeuiButtonType.secondary,
                  isLoading: _testing,
                  onPressed: _testConnection,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: WeuiColors.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WeuiColors.fg3, width: 0.8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: WeuiColors.link, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
