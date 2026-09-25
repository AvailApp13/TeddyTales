import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import 'legal_screen.dart';
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
  const SignInScreen({super.key, required this.onSignedIn, this.onEmail});

  /// Пустить без регистрации: «Пропустить» и способы, которые ещё не
  /// подключены (Apple, Google — ждут App Store и Google Play).
  final VoidCallback onSignedIn;

  /// Открыть регистрацию и вход по почте. `null` — кнопки почты нет.
  final void Function(BuildContext context)? onEmail;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

/// Способ входа: подпись, фирменные цвет и знак.
enum _SignInMethod {
  apple('Apple', FontAwesomeIcons.apple, Color(0xFF1C1C1E), Colors.white),
  google('Google', FontAwesomeIcons.google, Colors.white, Color(0xFF3C4043)),
  wechat('WeChat', FontAwesomeIcons.weixin, Color(0xFF07C160), Colors.white),
  alipay('Alipay', FontAwesomeIcons.alipay, Color(0xFF1677FF), Colors.white),
  qq('QQ', FontAwesomeIcons.qq, Color(0xFF12B7F5), Colors.white),
  email(
    'E-mail',
    FontAwesomeIcons.solidEnvelope,
    AppColors.sageDark,
    Colors.white,
  );

  /// Что показываем сейчас. Заказчик 24.09: «спрячь Alipay, QQ и WeChat;
  /// Apple, Google, ниже регистрация по почте». Китайские способы в
  /// перечислении остаются — вернуть их значит дописать сюда.
  static const List<_SignInMethod> shown = [apple, google, email];

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
    _SignInMethod.email => l10n.signInEmail,
  };
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  /// Цвет нижней кромки присланной сцены — снят с картинки.
  ///
  /// На вытянутом экране кадр не достаёт до низа: обрезать ему бока дальше
  /// нельзя. Полоса, залитая этим цветом, продолжает ковёр без шва.
  static const Color _sceneEdge = Color(signInEdgeColor);

  /// Сколько уведомление висит. Две с половиной секунды — прочитать две
  /// строки и не заскучать.
  static const Duration _readTime = Duration(milliseconds: 2600);

  // Создаётся сразу, а не по первому обращению: уйти со страницы можно и
  // не тронув баннер (через почту), и тогда ленивое поле рождалось бы в
  // dispose — на уже снятом с дерева экране.
  late final AnimationController _banner;

  _SignInMethod? _pending;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _banner = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _banner.dispose();
    super.dispose();
  }

  void _tap(_SignInMethod method) {
    // Почта работает по-настоящему: свой экран, без баннера «в разработке».
    final email = widget.onEmail;
    if (method == _SignInMethod.email && email != null) {
      email(context);
      return;
    }
    // Apple и Google ждут App Store и Google Play. Заказчик 24.09: «при
    // нажатии сверху уведомление, что функция ещё в разработке; вход у нас
    // только по почте» — поэтому никуда не пускаем, только сообщаем.
    // Повторное нажатие показывает уведомление заново и продлевает его.
    _timer?.cancel();
    setState(() => _pending = method);
    _banner.forward();
    _timer = Timer(_readTime, () async {
      if (!mounted) return;
      await _banner.reverse();
      if (mounted) setState(() => _pending = null);
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
          final fitted = SignInFrame.of(
            scene,
            panelHeight: SignInMetrics.tight.height,
            bottomInset: bottom,
          );
          final metrics = SignInMetrics.of(
            scene.height - fitted.bearsBottomY - bottom,
          );
          // Пустоту под лапами делим: сцена чуть ниже, кнопки чуть выше
          // (заказчик 24.09).
          final (:frame, :panelTop) = fitted.settle(
            scene: scene,
            panelHeight: metrics.height,
            bottomInset: bottom,
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
              // Над опущенным кадром — его верхний ряд, растянутый вниз:
              // размытые шторы и стена продолжаются без шва.
              if (frame.rect.top > 0)
                Positioned(
                  left: frame.rect.left,
                  width: frame.rect.width,
                  top: 0,
                  height: frame.rect.top + 1,
                  child: const Image(
                    image: AssetImage('assets/ui/signin_top_edge.png'),
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
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
                top: panelTop,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: _SignInPanel(
                        methods: [
                          for (final method in _SignInMethod.shown)
                            if (method != _SignInMethod.email ||
                                widget.onEmail != null)
                              method,
                        ],
                        metrics: metrics,
                        onTap: _tap,
                        onSkip: widget.onSignedIn,
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
class _SignInPanel extends StatefulWidget {
  const _SignInPanel({
    required this.methods,
    required this.metrics,
    required this.onTap,
    required this.onSkip,
  });

  final List<_SignInMethod> methods;
  final SignInMetrics metrics;
  final ValueChanged<_SignInMethod> onTap;

  /// «Пропустить и посмотреть приложение» — без регистрации.
  final VoidCallback onSkip;

  @override
  State<_SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<_SignInPanel> {
  // Ссылки в строке «Продолжая, вы принимаете…» — распознаватели живут
  // с панелью и гасятся вместе с ней.
  late final _terms = TapGestureRecognizer()
    ..onTap = () => LegalScreen.open(context, LegalDoc.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => LegalScreen.open(context, LegalDoc.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final methods = widget.methods;
    final metrics = widget.metrics;
    final onTap = widget.onTap;
    final onSkip = widget.onSkip;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.showPrompt) ...[
          // Просвет между лапами и подписью: без него панель начиналась ровно
          // по линию лап и подпись ложилась на них.
          SizedBox(height: metrics.pawGap),
          Text(
            l10n.signInPrompt,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Тёмным, как подзаголовок наверху: под подписью не плашка, а
            // ковёр со звёздами и листьями, и блёклый серый на нём тонет.
            style: TextStyle(
              fontSize: metrics.promptSize,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: metrics.gap),
        ],
        for (final method in methods) ...[
          _MethodButton(
            method: method,
            label: method.label(l10n),
            height: metrics.buttonHeight,
            onTap: () => onTap(method),
          ),
          if (method != methods.last) SizedBox(height: metrics.gap),
        ],
        TextButton(
          onPressed: onSkip,
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
        // Оба документа открываются касанием по своему названию (КП 14.2).
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: metrics.legalSize,
              height: 1.4,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
            children: [
              TextSpan(text: l10n.signInLegalPrefix),
              _legalLink(l10n.signInLegalTermsLink, _terms),
              TextSpan(text: l10n.signInLegalAnd),
              _legalLink(l10n.signInLegalPrivacyLink, _privacy),
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  TextSpan _legalLink(String text, TapGestureRecognizer tap) => TextSpan(
    text: text,
    recognizer: tap,
    style: const TextStyle(
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// Кнопка одного способа входа: фирменный цвет, знак, подпись.
class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.method,
    required this.label,
    required this.height,
    required this.onTap,
  });

  final _SignInMethod method;
  final String label;
  final double height;
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
        elevation: 1.5,
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
