import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../services/app_settings.dart';

/// Lets the user pick the UI language and light/dark theme. Changes apply
/// immediately and are saved for next time.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    final settings = AppSettings.instance;
    return AlertDialog(
      title: Text(t.settingsTitle),
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.language, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'th', label: Text(t.languageThai)),
                  ButtonSegment(value: 'en', label: Text(t.languageEnglish)),
                ],
                selected: {settings.locale.languageCode},
                onSelectionChanged: (s) =>
                    settings.setLocale(Locale(s.first)),
              ),
              const SizedBox(height: 20),
              Text(t.theme, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto, size: 18),
                    label: Text(t.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode, size: 18),
                    label: Text(t.themeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode, size: 18),
                    label: Text(t.themeDark),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) => settings.setThemeMode(s.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.done),
        ),
      ],
    );
  }
}
