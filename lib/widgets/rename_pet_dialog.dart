import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/pet_name.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

/// Как зовут малыша (КП 2.3).
///
/// Единственное место в игре, куда человек пишет свой текст, — и потому
/// единственное, где нужен фильтр.
///
/// Ошибка формы показывается, пока он печатает: «коротко», «слишком длинно»
/// — это видно сразу, без отправки. Запрещённые слова ловит сервер, и его
/// ответ приходит после нажатия. Разделение не техническое: первое человек
/// правит на ходу, второе всё равно требует запроса, а держать список брани
/// в приложении нельзя — он правится модератором (КП 15.6).
///
/// Возвращает новое имя, если его приняли, и `null`, если отменили.
Future<String?> showRenamePetDialog({
  required BuildContext context,
  required String current,

  /// Отправить имя на сервер. Возвращает причину отказа или `null`, если
  /// приняли. Диалог сам ничего не знает ни про сеть, ни про хранилище, а
  /// причину получает кодом и переводит сам: язык интерфейса есть у него.
  required Future<PetNameError?> Function(String name) onSubmit,

  /// Первый запуск: имени ещё не давали (КП 2.3). Окно само приходит после
  /// рождения, поэтому говорит «Назвать» и «Позже», а не «Сохранить» и
  /// «Отмена», и объясняет, что имя можно поменять.
  bool firstRun = false,
}) {
  // Заказчик 26.09: окно из матового стекла в стиле главного экрана.
  return showGlassPanel<String>(
    context: context,
    center: const Offset(0.5, 0.4),
    width: 330,
    dismissible: false,
    builder: (context) =>
        _RenameDialog(current: current, onSubmit: onSubmit, firstRun: firstRun),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.current,
    required this.onSubmit,
    required this.firstRun,
  });

  final String current;
  final bool firstRun;
  final Future<PetNameError?> Function(String name) onSubmit;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current,
  );

  /// Ошибка формы — считается на лету, пока человек печатает.
  PetNameError? _localError;

  /// Ответ сервера. Живёт до следующей правки поля: человек изменил имя —
  /// прежний отказ к нему уже не относится.
  PetNameError? _serverError;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _localError = checkPetName(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _localError = checkPetName(value);
      _serverError = null;
    });
  }

  Future<void> _submit() async {
    final name = normalizePetName(_controller.text);
    if (_localError != null || _sending) return;

    setState(() => _sending = true);
    final error = await widget.onSubmit(name);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _sending = false;
        _serverError = error;
      });
      return;
    }

    Navigator.of(context).pop(name);
  }

  String? _errorText(AppLocalizations l10n) {
    return switch (_serverError ?? _localError) {
      null => null,
      PetNameError.empty => l10n.nameErrorEmpty,
      PetNameError.tooShort => l10n.nameErrorShort(petNameMinLength),
      PetNameError.tooLong => l10n.nameErrorLong(petNameMaxLength),
      PetNameError.badCharacters => l10n.nameErrorCharacters,
      PetNameError.blocked || PetNameError.rejected => l10n.nameErrorBlocked,
      PetNameError.network => l10n.nameErrorNetwork,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _errorText(l10n);
    // Пустое поле — не ошибка, а начало ввода: подчёркивать его красным,
    // пока человек ещё ничего не напечатал, значит ругаться авансом.
    final showError = error != null && _controller.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassTitle(
          l10n.nameDialogTitle,
          close: false,
          leading: const _PawBadge(),
        ),
        const SizedBox(height: 10),
        if (widget.firstRun) ...[
          Text(
            l10n.nameFirstLead,
            style: glassText(14, 600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_sending,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          // Ограничение вводом, а не только проверкой: подсчёт знаков
          // человеку виден, и лишнее просто не печатается. Предел с
          // запасом — нормализация всё равно срежет пробелы по краям.
          inputFormatters: [
            LengthLimitingTextInputFormatter(petNameMaxLength + 2),
          ],
          style: glassText(18, 800, color: AppColors.textPrimary),
          decoration: glassField(
            hint: l10n.nameDialogHint,
            error: showError ? error : null,
            counter:
                '${normalizePetName(_controller.text).runes.length}'
                '/$petNameMaxLength',
          ),
          onChanged: _onChanged,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.nameDialogNote(petNameMinLength, petNameMaxLength),
          style: glassText(12, 600, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                key: const ValueKey('name-later'),
                label: widget.firstRun
                    ? l10n.nameFirstLater
                    : l10n.commonCancel,
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton(
                key: const ValueKey('name-save'),
                primary: true,
                label: _sending
                    ? '…'
                    : widget.firstRun
                    ? l10n.nameFirstSave
                    : l10n.nameDialogSave,
                onPressed: _localError != null || _sending ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Лапка в белом кружке у заголовка — как кнопка профиля в шапке.
class _PawBadge extends StatelessWidget {
  const _PawBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.tan, width: 3),
      ),
      child: const Icon(Icons.pets, size: 17, color: AppColors.tan),
    );
  }
}
