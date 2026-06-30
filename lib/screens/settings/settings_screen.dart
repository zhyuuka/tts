// 做什么：设置页 —— AI 服务商、凭证、模型、生成参数、能力开关、数据。
// 为什么这样做：所有"配置入口"集中到一个滚动页，顶栏不再堆按钮；
// 分区以卡片承载，保存时一次性写回 SettingsService 并刷新当前 AI 服务。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../services/ai_service_factory.dart';
import '../../services/settings_service.dart';
import '../../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onClose;
  const SettingsScreen({super.key, required this.onClose});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _serviceId;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _modelCtrl;
  late double _temperature;
  late int _maxTokens;
  late double _topP;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsService>();
    _serviceId = s.getAiServiceId();
    final key = s.getApiKeyForService(_serviceId) ?? '';
    _apiKeyCtrl = TextEditingController(text: key);
    _modelCtrl = TextEditingController(text: s.getModel());
    _temperature = s.getTemperature();
    _maxTokens = s.getMaxTokens();
    _topP = s.getTopP();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _switchService(String id) {
    if (id == _serviceId) return;
    setState(() {
      _serviceId = id;
      final s = context.read<SettingsService>();
      _apiKeyCtrl.text = s.getApiKeyForService(id) ?? '';
      // 模型回退到该服务默认列表首项（若有），否则清空
      final info = AiServiceFactory.getServiceInfo(id);
      _modelCtrl.text = info.models.isNotEmpty ? info.models.first.id : '';
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final s = context.read<SettingsService>();
    final chat = context.read<ChatProvider>();
    try {
      // 仅在发生变化时写入，减少冗余 IO
      if (s.getAiServiceId() != _serviceId) {
        await s.setAiServiceId(_serviceId);
      }
      final key = _apiKeyCtrl.text.trim();
      final existing = s.getApiKeyForService(_serviceId) ?? '';
      if (key != existing) {
        await s.setApiKeyForService(_serviceId, key);
      }
      if (s.getModel() != _modelCtrl.text.trim()) {
        await s.setModel(_modelCtrl.text.trim());
      }
      await s.setTemperature(_temperature);
      await s.setMaxTokens(_maxTokens);
      await s.setTopP(_topP);
      // 强制刷新当前 AI 服务，使新 Key/模型立即生效
      await chat.switchAiService(_serviceId, forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存并应用')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AiServiceFactory.getAllServiceInfo();
    final currentInfo = AiServiceFactory.getServiceInfo(_serviceId);
    final searchOn = context.select<SettingsService, bool>(
      (s) => s.isSearchEnabled(),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onClose: widget.onClose),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 30,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '设置',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'AI 服务、模型与联网检索配置。所有密钥通过硬件加密安全存储。',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 26),
                          _SectionLabel(text: 'AI 服务商'),
                          _Card(
                            child: _ServiceGrid(
                              services: services,
                              selectedId: _serviceId,
                              onSelect: _switchService,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(text: '凭证与模型'),
                          _Card(
                            child: Column(
                              children: [
                                _Field(
                                  label: 'API Key',
                                  required: true,
                                  child: TextField(
                                    controller: _apiKeyCtrl,
                                    obscureText: true,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'sk-••••••••••••••••',
                                    ),
                                  ),
                                ),
                                _SelectRow(
                                  label: '模型',
                                  value: _modelCtrl.text.isEmpty
                                      ? '默认'
                                      : _modelCtrl.text,
                                  onTap: () => _pickModel(currentInfo),
                                ),
                                _SelectRow(
                                  label: '上下文长度',
                                  value: currentInfo.models.isNotEmpty
                                      ? '${_fmt(currentInfo.models.first.contextLength)} tokens'
                                      : '—',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(text: '生成参数'),
                          _Card(
                            child: Column(
                              children: [
                                _SliderRow(
                                  label: 'Temperature',
                                  value: _temperature,
                                  min: 0,
                                  max: 2,
                                  divisions: 20,
                                  display: _temperature.toStringAsFixed(1),
                                  onChanged: (v) => setState(() => _temperature = v),
                                ),
                                _SliderRow(
                                  label: 'Max Tokens',
                                  value: _maxTokens.toDouble(),
                                  min: 256,
                                  max: 8192,
                                  divisions: 31,
                                  display: '$_maxTokens',
                                  onChanged: (v) => setState(
                                    () => _maxTokens = v.round(),
                                  ),
                                ),
                                _SliderRow(
                                  label: 'Top P',
                                  value: _topP,
                                  min: 0,
                                  max: 1,
                                  divisions: 20,
                                  display: _topP.toStringAsFixed(2),
                                  onChanged: (v) => setState(() => _topP = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(text: '联网与能力'),
                          _Card(
                            child: Column(
                              children: [
                                _ToggleRow(
                                  icon: Icons.travel_explore,
                                  title: '联网搜索',
                                  desc: '回复前先检索网络，4 引擎可选',
                                  value: searchOn,
                                  onChanged: (_) => context
                                      .read<ChatProvider>()
                                      .toggleSearchEnabled(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(text: '数据'),
                          _Card(
                            child: Column(
                              children: [
                                _NavRow(
                                  icon: Icons.file_download_outlined,
                                  title: '导出备份',
                                  desc: '将所有会话与记忆导出为 JSON',
                                  onTap: () => _export(),
                                ),
                                _NavRow(
                                  icon: Icons.file_upload_outlined,
                                  title: '导入备份',
                                  desc: '从 JSON 文件恢复',
                                  onTap: () => _notImplemented(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _SaveBar(
                            saving: _saving,
                            onSave: _save,
                            onCancel: widget.onClose,
                          ),
                        ],
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

  Future<void> _pickModel(AiServiceInfo info) async {
    if (info.models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该服务商暂无预设模型，可手动填写')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in info.models)
                ListTile(
                  title: Text(m.displayName, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${_fmt(m.contextLength)} tokens',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  trailing: _modelCtrl.text == m.id
                      ? const Icon(Icons.check, size: 16, color: AppColors.accent2)
                      : null,
                  onTap: () => Navigator.pop(ctx, m.id),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _modelCtrl.text = picked);
    }
  }

  Future<void> _export() async {
    final path = await context.read<ChatProvider>().exportBackup();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(path != null ? '已导出：$path' : '导出失败')),
    );
  }

  void _notImplemented() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导入功能将在后续版本启用')),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return k == k.roundToDouble() ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
    }
    return '$n';
  }
}

// ── 头部 ──
class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            onPressed: onClose,
            tooltip: '返回对话',
          ),
          const Text(
            '设置',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

// ── 服务商网格 ──
class _ServiceGrid extends StatelessWidget {
  final List<AiServiceInfo> services;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _ServiceGrid({
    required this.services,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 520 ? 4 : (c.maxWidth > 360 ? 3 : 2);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.1,
            children: [
              for (final s in services) _ServiceCard(info: s, selectedId: selectedId, onSelect: onSelect),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final AiServiceInfo info;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const _ServiceCard({
    required this.info,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final sel = info.id == selectedId;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onSelect(info.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        decoration: BoxDecoration(
          color: sel ? AppColors.accentSoft : AppColors.surface2,
          border: Border.all(
            color: sel ? const Color(0x808B7CFF) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(
                    color: AppColors.serviceColor(info.id),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text(
                      _initial(info.name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Text(
                  info.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: sel ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (sel)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check, size: 12, color: AppColors.accent2),
              ),
          ],
        ),
      ),
    );
  }

  String _initial(String name) {
    if (name.isEmpty) return '?';
    final ch = name.characters.first;
    return ch;
  }
}

// ── 字段 ──
class _Field extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  const _Field({required this.label, required this.child, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (required)
                  const Text(' *', style: TextStyle(color: AppColors.rose)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _SelectRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13.5)),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: AppColors.accent2,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 滑块行 ──
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(
                display,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: AppColors.accent2,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── 开关行 ──
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── 导航行 ──
class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.title, required this.desc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ── 保存条 ──
class _SaveBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  const _SaveBar({
    required this.saving,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: onCancel,
            child: const Text('取消'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentOn,
                    ),
                  )
                : const Text('保存并应用'),
          ),
        ],
      ),
    );
  }
}
