import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// Экран входа — первое, что видит пользователь (КП 1.2, 1.3).
///
/// Сейчас это витрина, а не рабочий вход: ни один из пяти способов ещё не
/// подключён. Кнопки стоят намеренно — чтобы заказчик и тестировщик видели
/// состав будущего входа целиком, а не узнавали о китайских способах в конце
/// работы. Каждая пропускает внутрь и честно говорит, что она в разработке.
///
/// Показ вместо заглушки выбран сознательно: «кнопки появятся потом» —
/// договорённость, которую невозможно проверить, а нарисованная кнопка с
/// уведомлением проверяется одним нажатием.
///
/// Уведомление намеренно похоже на системное: тестировщик должен не гадать,
/// сработало ли нажатие, а видеть ответ приложения.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onSignedIn});

  /// Куда пускать после нажатия. Пока — просто в приложение.
  final VoidCallback onSignedIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

/// Способ входа: подпись, фирменные цвет и знак.
enum _SignInMethod {
  apple('Apple', FontAwesomeIcons.apple, Color(0xFF1C1C1E), Colors.white),
  google('Google', FontAwesomeIcons.google, Colors.white, Color(0xFF3C4043)),
  wechat('WeChat', FontAwesomeIcons.weixin, Color(0xFF07C160), Colors.white),
  alipay('Alipay', FontAwesomeIcons.alipay, Color(0xFF1677FF), Colors.white),
  qq('QQ', FontAwesomeIcons.qq, Color(0xFF12B7F5), Colors.white);

  const _SignInMethod(this.title, this.icon, this.background, this.foreground);

  /// Название способа — торговая марка, не переводится.
  final String title;
  final FaIconData icon;
  final Color background;
  final Color foreground;

  String label(AppLocalizations l10n) => switch (this) {
    _SignInMethod.apple => l10n.signInApple,
    _SignInMethod.google => l10n.signInGoogle,
    _SignInMethod.wechat => l10n.signInWeChat,
    _SignInMethod.alipay => l10n.signInAlipay,
    _SignInMethod.qq => l10n.signInQq,
  };
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  /// Сколько уведомление висит, прежде чем пустить внутрь. Полторы секунды —
  /// столько нужно, чтобы прочитать две строки и не заскучать.
  static const Duration _readTime = Duration(milliseconds: 1600);

  late final AnimationController _banner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  _SignInMethod? _pending;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _banner.dispose();
    super.dispose();
  }

  void _tap(_SignInMethod method) {
    // Повторное нажатие, пока идёт переход, ничего не меняет: иначе
    // `onSignedIn` вызвался бы дважды и экран ушёл бы дважды.
    if (_pending != null) return;

    setState(() => _pending = method);
    _banner.forward();
    _timer = Timer(_readTime, () {
      if (!mounted) return;
      widget.onSignedIn();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          // Мягкий переход от кремового к пудровому: фирменные свотчи 3 и 2.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, AppColors.cream, Color(0xFFF3D9D2)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(
                // `Spacer` внутри прокручиваемой области не работает:
                // высота там не ограничена, и распределять между гибкими
                // детьми нечего — всё схлопывается кверху. Поэтому колонке
                // задаём минимальную высоту в экран и растягиваем её
                // `IntrinsicHeight`: только тогда `spaceBetween` разводит
                // шапку, кнопки и подпись по своим местам, а на маленьком
                // экране остаётся прокрутка.
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 36,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 24),
                              const _Wordmark(),
                              const SizedBox(height: 14),
                              Text(
                                l10n.signInTagline,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.signInPrompt,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  letterSpacing: 0.4,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (final method in _SignInMethod.values) ...[
                                _MethodButton(
                                  method: method,
                                  label: method.label(l10n),
                                  busy: _pending == method,
                                  onTap: () => _tap(method),
                                ),
                                const SizedBox(height: 10),
                              ],
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () => _tap(_SignInMethod.apple),
                                child: Text(
                                  l10n.signInSkip,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            l10n.signInLegal,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_pending != null)
              _SoonBanner(animation: _banner, method: _pending!),
          ],
        ),
      ),
    );
  }
}

/// Название приложения в кружке — пока вместо логотипа из брендбука.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.tan.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text('🧸', style: TextStyle(fontSize: 40)),
        ),
        const SizedBox(height: 18),
        const Text(
          'TeddyTales',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Кнопка одного способа входа: фирменный цвет, знак, подпись.
class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.method,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final _SignInMethod method;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Белая кнопка Google на кремовом фоне без обводки теряется — это её
    // фирменный вид, менять цвет нельзя, поэтому обводим.
    final needsOutline = method.background.computeLuminance() > 0.8;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: method.background,
        borderRadius: BorderRadius.circular(14),
        elevation: busy ? 0 : 1.5,
        shadowColor: AppColors.tan.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: needsOutline
                  ? Border.all(color: const Color(0xFFDADCE0))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: FaIcon(
                    method.icon,
                    size: 20,
                    color: method.foreground,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: method.foreground,
                    ),
                  ),
                ),
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(method.foreground),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Уведомление «в разработке», съезжающее сверху.
///
/// Нарочно похоже на системное: тестировщик по этому баннеру понимает, что
/// нажатие обработано, а способ входа ещё не готов. Обычный SnackBar внизу
/// такой роли не играет — его читают как служебное сообщение интерфейса.
class _SoonBanner extends StatelessWidget {
  const _SoonBanner({required this.animation, required this.method});

  final Animation<double> animation;
  final _SignInMethod method;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1.4),
            end: Offset.zero,
          ).animate(curve),
          child: FadeTransition(
            opacity: animation,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                shadowColor: AppColors.textPrimary.withValues(alpha: 0.28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: method.background,
                          borderRadius: BorderRadius.circular(9),
                          border: method.background.computeLuminance() > 0.8
                              ? Border.all(color: const Color(0xFFDADCE0))
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: FaIcon(
                          method.icon,
                          size: 17,
                          color: method.foreground,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          // Без этого колонка тянется на всю доступную
                          // высоту, и карточка уведомления разворачивается
                          // во весь экран.
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.signInSoonTitle,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l10n.signInSoonBody(method.title),
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
