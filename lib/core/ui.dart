import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Өнгө — web-ийн base.css-ийн токенууд ────────────────────────────────────
class AppColors {
  static const brand = Color(0xFF126B4B); // theme-color, admin-green
  static const background = Color(0xFFF5F7FB);
  static const surface = Colors.white;
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFD8E1EF);
  static const success = Color(0xFF1F8F4F);
  static const warning = Color(0xFFB7791F);
  static const warningSoft = Color(0xFFFFF4DB);
  static const danger = Color(0xFFB83232);
  static const dangerSoft = Color(0xFFFDECEC);
  static const successSoft = Color(0xFFE6F4EC);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}

// ── Мессеж ──────────────────────────────────────────────────────────────────
enum MessageKind { info, success, warning, error }

class AppMessage {
  final String text;
  final MessageKind kind;
  const AppMessage(this.text, [this.kind = MessageKind.info]);
  const AppMessage.error(this.text) : kind = MessageKind.error;
  const AppMessage.success(this.text) : kind = MessageKind.success;
  const AppMessage.warning(this.text) : kind = MessageKind.warning;
}

class MessageBanner extends StatelessWidget {
  final AppMessage? message;
  final VoidCallback? onClose;
  const MessageBanner(this.message, {super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m == null || m.text.isEmpty) return const SizedBox.shrink();
    final (bg, fg, icon) = switch (m.kind) {
      MessageKind.error => (AppColors.dangerSoft, AppColors.danger, Icons.error_outline),
      MessageKind.success => (AppColors.successSoft, AppColors.success, Icons.check_circle_outline),
      MessageKind.warning => (AppColors.warningSoft, AppColors.warning, Icons.warning_amber_outlined),
      MessageKind.info => (const Color(0xFFEFF4FF), AppColors.text, Icons.info_outline),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(m.text, style: TextStyle(color: fg, height: 1.35)),
          ),
          if (onClose != null)
            InkResponse(
              onTap: onClose,
              radius: 18,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: fg),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Карт / хэсэг ────────────────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsets padding;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  final Color? accent;
  const KpiTile({super.key, required this.label, required this.value, this.caption, this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent ?? AppColors.text,
              ),
            ),
            if (caption != null)
              Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted), maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.muted),
    ),
  );
}

class LoadingState extends StatelessWidget {
  final String text;
  const LoadingState(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(text, style: const TextStyle(color: AppColors.muted)),
        ),
      ],
    ),
  );
}

// Жижиг «чип» шошго (өдөр, бүс, төлөв).
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  const Tag(this.text, {super.key, this.color = AppColors.muted, this.background = const Color(0xFFF1F4F9)});

  const Tag.warning(this.text, {super.key}) : color = AppColors.warning, background = AppColors.warningSoft;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

// ── Dialog ──────────────────────────────────────────────────────────────────
class PromptField {
  final String name;
  final String label;
  final bool number;
  final bool required;
  final String? initial;
  final String? hint;

  const PromptField(this.name, this.label, {this.number = false, this.required = false, this.initial, this.hint});
}

/// web-ийн AppDialog.prompt. Цуцалбал null.
Future<Map<String, String>?> showPromptDialog(
  BuildContext context, {
  required String title,
  required List<PromptField> fields,
  String? message,
  String confirmLabel = 'Хадгалах',
}) {
  final controllers = {for (final f in fields) f.name: TextEditingController(text: f.initial ?? '')};
  final formKey = GlobalKey<FormState>();
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                Text(message, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
              ],
              for (final (i, f) in fields.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                TextFormField(
                  controller: controllers[f.name],
                  autofocus: i == 0,
                  decoration: InputDecoration(labelText: f.label, hintText: f.hint),
                  keyboardType: f.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  inputFormatters: f.number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (f.required && t.isEmpty) return 'Заавал бөглөнө';
                    // ⚠ «1,500» нь 1.5 үү, 1500 үү — тодорхойгүй тул хүлээж авахгүй.
                    if (f.number && (RegExp(r'[.,].*[.,]').hasMatch(t) || RegExp(r'^\d+,\d{3}$').hasMatch(t))) {
                      return 'Мянгатын таслал бичихгүй; бутархайг 1.5 гэж бичнэ';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Болих')),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.of(dialogContext).pop({
              for (final f in fields)
                f.name: f.number
                    ? controllers[f.name]!.text.trim().replaceAll(',', '.')
                    : controllers[f.name]!.text.trim(),
            });
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  ).whenComplete(() {
    for (final c in controllers.values) {
      c.dispose();
    }
  });
}

Future<void> showInfoDialog(BuildContext context, {required String title, required Widget content}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: [FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Хаах'))],
    ),
  );
}

/// Тийм/Болих баталгаажуулалт (борлуулагч, үйлдвэр хоёул хэрэглэнэ).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Тийм',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Болих')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
