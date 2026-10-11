// "Rytho'ya sor" TOHUMU: gerçekten geçiyor mu, ve GÖNDERİLMİYOR mu?
// (OP5-turu, P3 paketi.)
//
// Ölçüldü: bu mekanizmanın TAMAMI bugüne kadar bekçisizdi —
// `initialText` / `signalAsk` / `ChatScreen(` çapaları için testlerde
// SIFIR eşleşme vardı. Kişi ekranındaki çağrı da bu yüzden bir tur
// boyunca BOŞ sohbet açıyordu: etiket "Rytho'ya sor" diyor, giriş alanı
// boş geliyordu.
//
// ⚠️ NEDEN WIDGET TESTİ DEĞİL (kısmen): `ChatScreen`i MONTE etmek
// `FirebaseAuth.instance`a dokunuyor (`_seed`), yani ekranı pompalamak
// Firebase başlatmayı gerektirir. Bu yüzden iddia üçe bölündü:
//   1. SÖZLEŞME gerçek nesneyle ölçülüyor — `ChatScreen` kuruluyor ve
//      alanları okunuyor (montaj yok, Firebase'e dokunulmuyor). Bu kısım
//      metin eşleştirmesi DEĞİL.
//   2. ÇAĞRI YERİ kaynaktan okunuyor (emsal: `kisi_ekrani_burc_test` —
//      panel özel, veri ağdan).
//   3. "GÖNDERİLMİYOR" iddiası `chat_screen.dart`ın `initState`inden
//      okunuyor; o dosya bu paketin SAHİPLİĞİNDE DEĞİL, yani mutasyonla
//      sınanamaz. Körlüğü başka yolla kapatıldı: ölçen şey saf bir
//      fonksiyon ve o fonksiyon aşağıda SENTETİK iyi/kötü kaynaklara
//      karşı koşuyor. Yani bekçinin kendi bekçisi var.
//
// ⚠️ Yorumlar eşleşmeden ÖNCE atılıyor. Bu şart değil, ZORUNLU: bu
// turda `person_detail_screen.dart`a yazılan gerekçe yorumu `initialText`
// sözcüğünü GEÇİYOR — yorumları atmayan bir bekçi, satır silinse bile
// yeşil kalırdı. Depo bu tuzağa iki kez düştü (build kapısı kendi
// manifest yorumuna, davet sayfası kendi HTML yorumuna).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rytho/features/chat/chat_screen.dart';

const _kKisiYolu = 'lib/features/people/person_detail_screen.dart';
const _kSohbetYolu = 'lib/features/chat/chat_screen.dart';

/// Tam satır yorumları ve `///` belgeleri atılır.
///
/// Satır SONUNDAKİ yorumlar atılmıyor ve bu bilinçli: `//` bir dize
/// literalinin içinde de geçebiliyor (URL) ve kör bir kesme kaynağı
/// bozardı. Ölçülen iddialar tam satır yorumlarıyla maskelenebilen
/// türden, satır sonu yorumuyla değil.
String _yorumsuz(String kaynak) => kaynak
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((s) => !s.trimLeft().startsWith('//'))
    .join('\n');

/// [imza]dan sonraki ilk `(`/`{` ile eşleşen kapanışa kadarki blok.
///
/// Derleyici değil, dengeli sayaç: dize literali içindeki parantezi
/// ayırt etmez. Aşağıda ölçülen iki blokta (bir yapıcı çağrısı ve bir
/// `initState` gövdesi) dengesiz parantez taşıyan dize YOK; yöntemin
/// sınırı bu ve yazılı olması şart — bir gün böyle bir dize girerse bu
/// bekçi sessizce yanlış blok okur.
String? _blok(String kaynak, String imza, {bool susluMu = false}) {
  final ac = susluMu ? '{' : '(';
  final kapa = susluMu ? '}' : ')';
  final i = kaynak.indexOf(imza);
  if (i < 0) return null;
  final bas = kaynak.indexOf(ac, i + imza.length);
  if (bas < 0) return null;
  var derinlik = 0;
  for (var j = bas; j < kaynak.length; j++) {
    final c = kaynak[j];
    if (c == ac) derinlik++;
    if (c == kapa) {
      derinlik--;
      if (derinlik == 0) return kaynak.substring(bas, j + 1);
    }
  }
  return null;
}

/// Kaynaktaki HER `ChatScreen(...)` kurulumu tohum taşıyor mu?
///
/// "Her" önemli: tek bir çağrı varken "en az biri" ile aynı şey, ama
/// ikinci bir giriş eklendiği gün bu bekçi onu da ister.
bool tohumGeciyor(String kaynak) {
  final s = _yorumsuz(kaynak);
  var bulundu = 0;
  var kalan = s;
  while (true) {
    final i = kalan.indexOf('ChatScreen(');
    if (i < 0) break;
    final blok = _blok(kalan.substring(i), 'ChatScreen');
    if (blok == null || !blok.contains('initialText:')) return false;
    bulundu++;
    kalan = kalan.substring(i + 'ChatScreen('.length);
  }
  return bulundu > 0;
}

/// `initState` tohumu giriş alanına YAZIYOR ve GÖNDERMİYOR mu?
bool onDoldurulurGonderilmez(String kaynak) {
  final govde = _blok(_yorumsuz(kaynak), 'void initState()', susluMu: true);
  if (govde == null) return false;
  if (!govde.contains('widget.initialText')) return false;
  if (!govde.contains('_controller.text')) return false;
  // Gönderim çağrısı AÇILIŞTA olmamalı: "son söz onun".
  return !govde.contains('_send(');
}

// ---------------------------------------------------------------------
// Sentetik kaynaklar: bekçinin kör OLMADIĞININ kanıtı.
// ---------------------------------------------------------------------
const _kKisiIyi = '''
ChatScreen(
    personId: person.id,
    initialText: l10n.chartAskPrefillNatal(ad))
''';

const _kKisiTohumsuz = '''
ChatScreen(personId: person.id)
''';

/// En sinsi kötü hâl: tohum YALNIZ yorumda geçiyor.
const _kKisiYalnizYorumda = '''
// initialText gecmeli; bu CTA aksi halde bos sohbet acar
ChatScreen(personId: person.id)
''';

const _kSohbetIyi = '''
void initState() {
  super.initState();
  final tohum = widget.initialText;
  if (tohum != null && tohum.isNotEmpty) _controller.text = tohum;
}
''';

const _kSohbetGonderen = '''
void initState() {
  super.initState();
  final tohum = widget.initialText;
  if (tohum != null && tohum.isNotEmpty) _send(tohum);
}
''';

const _kSohbetYutan = '''
void initState() {
  super.initState();
}
''';

void main() {
  group('bekçinin kendi bekçisi', () {
    test('tohumGeciyor sentetik kaynakları doğru ayırıyor', () {
      expect(tohumGeciyor(_kKisiIyi), isTrue);
      expect(tohumGeciyor(_kKisiTohumsuz), isFalse);
      expect(tohumGeciyor(_kKisiYalnizYorumda), isFalse,
          reason: 'yorumda gecen tohum sayildi — bekci kor');
    });

    test('onDoldurulurGonderilmez sentetik kaynakları doğru ayırıyor', () {
      expect(onDoldurulurGonderilmez(_kSohbetIyi), isTrue);
      expect(onDoldurulurGonderilmez(_kSohbetGonderen), isFalse,
          reason: 'acilista gonderen govde gecti');
      expect(onDoldurulurGonderilmez(_kSohbetYutan), isFalse,
          reason: 'tohumu hic okumayan govde gecti');
    });
  });

  group('ChatScreen sözleşmesi', () {
    test('tohum ve kişi kimliği alanlara GERÇEKTEN iniyor', () {
      // Metin eşleştirmesi değil: nesne kuruluyor, alanları okunuyor.
      const ekran = ChatScreen(personId: 'kisi-1', initialText: 'soru');
      expect(ekran.initialText, equals('soru'));
      expect(ekran.personId, equals('kisi-1'));
      // Varsayılan hâl BOŞ: tohum opsiyonel, yani ekranı tohumsuz açan
      // yüzeyler (ör. yoklama) bozulmuyor.
      expect(const ChatScreen().initialText, isNull);
    });
  });

  group('kişi ekranındaki çağrı', () {
    test('sohbet TOHUMLU açılıyor', () {
      expect(tohumGeciyor(File(_kKisiYolu).readAsStringSync()), isTrue,
          reason: '$_kKisiYolu: "Rytho\'ya sor" bos sohbet aciyor');
    });

    test('tohum ekranın KENDİ konusundan geliyor', () {
      // Bu ekranın gövdesi kişinin NATAL çarkı; tohum da natal kipin
      // kendi anahtarından gelir (D6: kip başına anahtar — eski tek
      // `chartAskPrefill(title)` "Şu an {title} çarkını" kalıbı her kipte
      // aynı cümleyi üretiyordu). Kişinin tam ekran çarkı aynı kipte
      // aynı anahtarı kullanır.
      final s = _yorumsuz(File(_kKisiYolu).readAsStringSync());
      expect(s, contains('initialText: l10n.chartAskPrefillNatal(ad)'));
      expect(s, isNot(contains('chartAskPrefill(ad)')),
          reason: 'kipsiz eski anahtar geri geldi');
    });

    test('kişi kimliği tohumla birlikte KALIYOR', () {
      // Yetki kapısı ve bağlam fısıltısı tohumdan bağımsız; tohum
      // eklenirken düşmüş olmasın.
      final blok = _blok(
          _yorumsuz(File(_kKisiYolu).readAsStringSync()), 'ChatScreen');
      expect(blok, isNotNull);
      expect(blok, contains('personId: person.id'));
    });
  });

  group('tohum GÖNDERİLMEZ', () {
    test('initState giriş alanını doldurur, göndermez', () {
      expect(
          onDoldurulurGonderilmez(File(_kSohbetYolu).readAsStringSync()),
          isTrue,
          reason: '$_kSohbetYolu: tohum ya hic okunmuyor ya da '
              'acilista gonderiliyor — "son soz onun" ilkesi kirik');
    });
  });
}
