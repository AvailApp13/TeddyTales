import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'sign_in_layout.dart';

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
  /// Цвет нижней кромки присланной сцены — снят с картинки.
  ///
  /// На вытянутом экране кадр не достаёт до низа: обрезать ему бока дальше
  /// нельзя. Полоса, залитая этим цветом, продолжает ковёр без шва.
  static const Color _sceneEdge = Color(signInEdgeColor);

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
      // Тот же цвет, что у полосы под кадром, — на случай щелей.
      backgroundColor: _sceneEdge,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scene = Size(constraints.maxWidth, constraints.maxHeight);
          final bottom = MediaQuery.paddingOf(context).bottom + 8;

          // Сначала кадр под самую тесную панель — он говорит, где кончаются
          // лапы, — и уже по этому месту считаются настоящие размеры кнопок.
          final frame = SignInFrame.of(
            scene,
            panelHeight: SignInMetrics.tight.height,
            bottomInset: bottom,
          );
          final metrics = SignInMetrics.of(
            scene.height - frame.bearsBottomY - bottom,
          );
          final side = (scene.width * 0.09).clamp(20.0, 44.0);

          return Stack(
            children: [
              // Ковёр ниже кадра: на вытянутом телефоне сцена не достаёт до
              // низа, потому что обрезать ей бока дальше нельзя — срежутся
              // книжки и домик. Полоса берёт цвет нижней кромки кадра, а
              // мягкий переход прячет стык.
              Positioned(
                left: 0,
                right: 0,
                top: frame.rect.bottom - 90,
                bottom: 0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00ECC9BC), _sceneEdge, _sceneEdge],
                      stops: [0, 0.62, 1],
                    ),
                  ),
                ),
              ),
              // Сама сцена: без заливок поверх неё — под кнопками должен
              // быть тот же ковёр с листьями и звёздами, что на макете.
              Positioned.fromRect(
                rect: frame.rect,
                child: const Image(
                  image: AssetImage('assets/ui/signin_scene.jpg'),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              // Подзаголовок стоит в просвете между логотипом и капюшоном —
              // единственном месте сверху, где он никого не закрывает.
              Positioned(
                left: side,
                right: side,
                top: frame.taglineCenterY - frame.taglineBand / 2,
                height: frame.taglineBand,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.signInTagline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: bottom,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: _SignInPanel(
                        metrics: metrics,
                        pending: _pending,
                        onTap: _tap,
                      ),
                    ),
                  ),
                ),
              ),
              if (_pending != null)
                _SoonBanner(animation: _banner, method: _pending!),
            ],
          );
        },
      ),
    );
  }
}

/// Нижняя половина экрана: подпись, пять кнопок входа и две служебные
/// строки. Размеры приходят готовыми — их считает [SignInMetrics] по тому,
/// сколько места осталось под мишками.
class _SignInPanel extends StatelessWidget {
  const _SignInPanel({
    required this.metrics,
    required this.pending,
    required this.onTap,
  });

  final SignInMetrics metrics;
  final _SignInMethod? pending;
  final ValueChanged<_SignInMethod> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.showPrompt) ...[
          Text(
            l10n.signInPrompt,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: metrics.promptSize,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: metrics.gap),
        ],
        for (final method in _SignInMethod.values) ...[
          _MethodButton(
            method: method,
            label: method.label(l10n),
            height: metrics.buttonHeight,
            busy: pending == method,
            onTap: () => onTap(method),
          ),
          if (method != _SignInMethod.values.last)
            SizedBox(height: metrics.gap),
        ],
        TextButton(
          onPressed: () => onTap(_SignInMethod.apple),
          style: TextButton.styleFrom(
            minimumSize: Size.fromHeight(metrics.skipHeight),
            padding: EdgeInsets.zero,
          ),
          child: Text(
            l10n.signInSkip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: metrics.promptSize + 1,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          l10n.signInLegal,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: metrics.legalSize,
            height: 1.4,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
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
    required this.height,
    required this.busy,
    required this.onTap,
  });

  final _SignInMethod method;
  final String label;
  final double height;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Белая кнопка Google на кремовом фоне без обводки теряется — это её
    // фирменный вид, менять цвет нельзя, поэтому обводим.
    final needsOutline = method.background.computeLuminance() > 0.8;
    // Скругление от высоты: на макете кнопки почти капсулы, и при сжатии
    // столбика они должны оставаться такими же на вид.
    final radius = BorderRadius.circular(height * 0.34);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: method.background,
        borderRadius: radius,
        elevation: busy ? 0 : 1.5,
        shadowColor: AppColors.tan.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: needsOutline
                  ? Border.all(color: const Color(0xFFDADCE0))
                  : null,
            ),
            // Знак слева, подпись по центру кнопки — как на макете. В ряд их
            // не поставить: подпись тогда центрируется по остатку строки и
            // на кнопках с разной шириной знака съезжает.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 30,
                    child: Center(
                      child: FaIcon(
                        method.icon,
                        size: height * 0.38,
                        color: method.foreground,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: method.foreground,
                    ),
                  ),
                ),
                if (busy)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(method.foreground),
                      ),
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
