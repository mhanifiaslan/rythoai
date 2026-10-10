// `ListeSatiri` — beş satır sınıfının tek varisi.
//
// Kopyalar bir şeyi farklı yapıyordu: `_AtlasRow` başlığı tek satıra
// kırpıp ellipsis koyuyor, `_FriendTile` da öyle; design-system §9b
// "başlıkta ASLA ellipsis" diyor — kullanıcı adı/konuyu OKUMAK ister, "…"
// tam da ayırt edici kısmı keser. Bu dosya o kuralı, kilit işaretini,
// dokunma hedefini ve ekran okuyucu düğümünü çiviler.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/theme/rytho_theme.dart';
import 'package:rytho/theme/rytho_tokens.dart';
import 'package:rytho/widgets/liste_satiri.dart';

import 'dar_ekran_test.dart' show darEkranda, tasmaYok;

Widget _sar(Widget child) => MaterialApp(
      theme: buildRythoTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

const _oncu = Text('🌙');

void main() {
  testWidgets('başlık en çok 2 satır ve ellipsis YOK', (tester) async {
    await tester.pumpWidget(_sar(ListeSatiri(
        leading: _oncu, title: 'Ayşe', subtitle: 'Boğa', onTap: () {})));
    final baslik = tester.widget<Text>(find.text('Ayşe'));
    expect(baslik.maxLines, 2, reason: 'tek satır ayırt edici kısmı keser');
    expect(baslik.overflow, isNot(TextOverflow.ellipsis),
        reason: 'design-system §9b: başlıkta asla ellipsis');
    expect(baslik.style, RythoType.cardTitle);
  });

  testWidgets('alt satır tavanı subtitleLines, ellipsis serbest',
      (tester) async {
    await tester.pumpWidget(_sar(const ListeSatiri(
        leading: _oncu, title: 'A', subtitle: 'alt', subtitleLines: 3)));
    final alt = tester.widget<Text>(find.text('alt'));
    expect(alt.maxLines, 3);
    expect(alt.overflow, TextOverflow.ellipsis,
        reason: 'alt satır tekrar eden veri; kısaltma burada serbest');
  });

  testWidgets('kilit: yalnız locked iken, ekran okuyucuya ürün adı',
      (tester) async {
    await tester.pumpWidget(
        _sar(const ListeSatiri(leading: _oncu, title: 'Yüz okuma')));
    expect(find.byIcon(Icons.lock_rounded), findsNothing);

    await tester.pumpWidget(_sar(
        const ListeSatiri(leading: _oncu, title: 'Yüz okuma', locked: true)));
    final kilit = tester.widget<Icon>(find.byIcon(Icons.lock_rounded));
    expect(kilit.color, RythoColors.goldBright);
    expect(find.bySemanticsLabel(RegExp(kPlusAdi)), findsOneWidget,
        reason: '"kilit" değil neyin kilidi olduğu duyulmalı');
  });

  testWidgets('dokunulur satır: chevron var, dokunuş çağrılır', (tester) async {
    var dokunuldu = 0;
    await tester.pumpWidget(_sar(ListeSatiri(
        leading: _oncu, title: 'Konu', onTap: () => dokunuldu++)));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.tap(find.text('Konu'));
    expect(dokunuldu, 1);
  });

  testWidgets('dokunulmaz satırda chevron YOK; trailing chevron\'un yerini alır',
      (tester) async {
    await tester.pumpWidget(
        _sar(const ListeSatiri(leading: _oncu, title: 'Konu')));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing,
        reason: 'chevron "gidilir" vaadi; gidilmeyen satır vermemeli');

    await tester.pumpWidget(_sar(ListeSatiri(
        leading: _oncu,
        title: 'Konu',
        trailing: const Text('sağ'),
        onTap: () {})));
    expect(find.text('sağ'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('ekran okuyucu TEK düğüm duyar: başlık + alt satır, düğme',
      (tester) async {
    final semantik = tester.ensureSemantics();
    await tester.pumpWidget(_sar(ListeSatiri(
        leading: _oncu, title: 'Ayşe', subtitle: 'Boğa', onTap: () {})));
    final dugum = tester.getSemantics(find.byType(ListeSatiri));
    expect(dugum, isSemantics(isButton: true, hasTapAction: true));
    // Birleşik etiket düğümün VERİSİNDE (`getSemanticsData`), `label`
    // alanında değil — ölçüldü: birleştirilen çocuklar "merged up" kalır.
    expect(dugum.getSemanticsData().label,
        allOf(contains('Ayşe'), contains('Boğa')),
        reason: 'başlık ve alt satır aynı düğümde');
    // Başlık ayrı bir düğüm olarak İKİNCİ kez duyulmaz.
    expect(find.bySemanticsLabel(RegExp('Ayşe')), findsOneWidget);
    // Gövdede kapatılır: `addTearDown` doğrulamadan sonra koşuyor.
    semantik.dispose();
  });

  testWidgets('dokunulmaz satır düğme değildir', (tester) async {
    final semantik = tester.ensureSemantics();
    await tester.pumpWidget(
        _sar(const ListeSatiri(leading: _oncu, title: 'Bilgi')));
    expect(tester.getSemantics(find.byType(ListeSatiri)),
        isSemantics(isButton: false));
    semantik.dispose();
  });

  testWidgets('alt satırsız kısa başlıkta bile dokunma hedefi ≥ 48 dp',
      (tester) async {
    await tester.pumpWidget(
        _sar(ListeSatiri(leading: _oncu, title: 'A', onTap: () {})));
    final kutu = find.descendant(
        of: find.byType(ListeSatiri), matching: find.byType(Container));
    expect(tester.getSize(kutu).height,
        greaterThanOrEqualTo(kMinInteractiveDimension));
  });

  testWidgets('320 dp × 1,3: uzun başlık + uzun alt satır taşmaz',
      (tester) async {
    await darEkranda(
        tester,
        ListeSatiri(
          leading: const Text('💼'),
          title: 'Kariyer ve meslek hayatında önümüzdeki dönem',
          subtitle: 'Satürn, natal Ay ile Kare açısını kesinleştiriyor — '
              'harcanan jeton iade edildi, tekrar deneyebilirsin',
          subtitleLines: 3,
          locked: true,
          onTap: () {},
        ));
    tasmaYok(tester);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });
}
