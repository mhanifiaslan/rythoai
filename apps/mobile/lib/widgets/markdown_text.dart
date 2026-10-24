import 'package:flutter/material.dart';

import '../theme/rytho_theme.dart';
import '../theme/rytho_tokens.dart';

/// LLM metnini Rytho tipografisiyle çizen HAFİF markdown okuyucu.
///
/// ## Neden paket değil
///
/// Cihaz turunda tam rapor ekranında ham işaretler görünüyordu: `### 1. Öz
/// Kimlik`, `**Safravî**`. Sebep basit — metin düz `Text` ile basılıyordu ve
/// modelin ürettiği yapı hiç çözülmüyordu.
///
/// Hazır bir markdown paketi kendi tipografisini getiriyor ve tema
/// token'larımızı (Sora başlık, Manrope gövde, satır yüksekliği 1.65)
/// eziyor. Bize gereken çok küçük bir alt küme: başlık, kalın, madde
/// işareti, paragraf. Otuz satırlık bir çözümleyici, bir bağımlılıktan ve
/// onun sürüm bakımından daha ucuz.
///
/// Desteklenen: `#`/`##`/`###` başlık, `**kalın**`, `*eğik*`, `- ` ve
/// `1. ` madde satırı (numara korunur), boş satırla ayrılan paragraf.
/// Desteklenmeyen her şey (tablo, bağlantı, kod bloğu) düz metin olarak
/// çizilir — asla ham işaret göstererek değil, olduğu gibi okunur biçimde.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.baseStyle});

  final String data;

  /// Gövde stili; verilmezse okuma tipografisi (`RythoType.reading`).
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final govde = baseStyle ?? RythoType.reading;
    final bloklar = parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Son blok alt dolgusuz: sohbet balonu alt dolgusunu sıfıra çekmişti
        // (D6) ve paragrafın kendi `md` dolgusu balonun altında boşluk
        // bırakıyordu — biri değişince öteki bozuluyordu, artık tek yerde.
        for (var i = 0; i < bloklar.length; i++)
          markdownBlockWidget(bloklar[i], govde, son: i == bloklar.length - 1),
      ],
    );
  }
}

/// Tek bloğun widget'ı. Ayrı ayrı çizilebilmesi gerekiyor: okuma sayfası
/// blokları kademeli belirtiyor (R12-B2), bu yüzden hepsini tek Column'a
/// gömen bir çizici yetmez.
///
/// [son]: metnin son bloğu — paragrafsa alt dolgusu yok (bkz. [MarkdownText]).
Widget markdownBlockWidget(MarkdownBlock blok, TextStyle govde,
    {bool son = false}) {
    switch (blok.type) {
      case MarkdownBlockType.heading:
        // Başlık seviyeleri: h1 19, h2 17, h3 15.5 — okuma metninden
        // ayrışacak kadar büyük, ekranı bölmeyecek kadar ölçülü.
        final boyut = switch (blok.level) { 1 => 19.0, 2 => 17.0, _ => 15.5 };
        return Padding(
          padding: EdgeInsets.only(
              top: blok.level == 1 ? RythoSpace.lg : RythoSpace.md,
              bottom: 6),
          child: Text(blok.text,
              style: RythoText.display(boyut, w: FontWeight.w700)),
        );
      case MarkdownBlockType.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (blok.numara case final numara?)
              // Numara gövdeyle aynı tipografide: aynı satır yüksekliği,
              // ilk satırla aynı taban çizgisi; nokta imi gibi elle
              // hizalanması gerekmez.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('$numara.',
                    style: govde.copyWith(
                        color: RythoColors.lilac,
                        fontWeight: FontWeight.w600)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: RythoColors.lilac,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Expanded(child: Text.rich(inlineSpan(blok.text, govde))),
          ]),
        );
      case MarkdownBlockType.paragraph:
        return Padding(
          padding: EdgeInsets.only(bottom: son ? 0 : RythoSpace.md),
          child: Text.rich(inlineSpan(blok.text, govde)),
        );
    }
}

enum MarkdownBlockType { heading, paragraph, bullet }

class MarkdownBlock {
  const MarkdownBlock(this.type, this.text, {this.level = 0, this.numara});

  final MarkdownBlockType type;
  final String text;
  final int level;

  /// Numaralı madde satırının numarası; tire/yıldız maddesinde null.
  final int? numara;
}

final _basligiBul = RegExp(r'^(#{1,6})\s+(.*)$');
final _maddeBul = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numaraliBul = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
final _kucukHarfle = RegExp(r'^\p{Ll}', unicode: true);

/// Türkçede sıra sayısı rakam + noktayla yazılır ("4. ev" = dördüncü ev)
/// ve ardından gelen ad küçük harfle başlar. Model "4. evdeki Güneş…" diye
/// bir CÜMLE yazınca satır başındaki sıra sayısı Markdown sıralı listesine
/// benziyor; liste sanılırsa cümle madde gibi çiziliyor (mağaza çekimi
/// 2026-10-24, tam rapor: eski desen sayıyı da atıyordu).
///
/// Ayrım: küçük harfle süren numaralı satır cümledir — İSTİSNA, bir
/// listenin açılışı (1) ya da bir önceki maddenin ardılı (n-1 → n); o
/// durumda küçük harfli gerçek bir listedir ("1. sabah yürüyüşü"). Büyük
/// harf, `**` ya da başka bir işaretle süren satır her zaman maddedir.
/// İki hâlde de sayı ekranda kalır.
bool _siraSayisiCumlesi(int numara, String govde, MarkdownBlock? onceki) {
  if (!_kucukHarfle.hasMatch(govde)) return false;
  if (numara == 1) return false;
  final ardil = onceki != null &&
      onceki.type == MarkdownBlockType.bullet &&
      onceki.numara == numara - 1;
  return !ardil;
}

/// Metni bloklara ayırır. Saf fonksiyon — test edilebilir.
List<MarkdownBlock> parseBlocks(String data) {
  final bloklar = <MarkdownBlock>[];
  final paragraf = <String>[];

  void paragrafiKapat() {
    if (paragraf.isEmpty) return;
    bloklar.add(MarkdownBlock(
        MarkdownBlockType.paragraph, paragraf.join(' ').trim()));
    paragraf.clear();
  }

  for (final ham in data.split('\n')) {
    final satir = ham.trimRight();
    if (satir.trim().isEmpty) {
      paragrafiKapat();
      continue;
    }

    final baslik = _basligiBul.firstMatch(satir.trimLeft());
    if (baslik != null) {
      paragrafiKapat();
      bloklar.add(MarkdownBlock(
        MarkdownBlockType.heading,
        // Başlık metninde kalan `**` işaretleri de temizlenir.
        _isaretleriSoy(baslik.group(2)!.trim()),
        level: baslik.group(1)!.length,
      ));
      continue;
    }

    final madde = _maddeBul.firstMatch(satir);
    if (madde != null) {
      paragrafiKapat();
      bloklar.add(
          MarkdownBlock(MarkdownBlockType.bullet, madde.group(1)!.trim()));
      continue;
    }

    final numarali = _numaraliBul.firstMatch(satir);
    if (numarali != null) {
      final numara = int.parse(numarali.group(1)!);
      final govde = numarali.group(2)!.trim();
      // Açık paragraf varken önceki blok paragraf sayılır: cümle onun
      // devamıdır, listenin ardılı değil.
      final onceki =
          paragraf.isEmpty && bloklar.isNotEmpty ? bloklar.last : null;
      if (!_siraSayisiCumlesi(numara, govde, onceki)) {
        paragrafiKapat();
        bloklar.add(MarkdownBlock(MarkdownBlockType.bullet, govde,
            numara: numara));
        continue;
      }
    }

    paragraf.add(satir.trim());
  }
  paragrafiKapat();
  return bloklar;
}

/// `**kalın**` ve `*eğik*` işaretlerini gerçek stile çevirir.
InlineSpan inlineSpan(String text, TextStyle base) {
  final parcalar = <InlineSpan>[];
  final desen = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_');
  var son = 0;

  for (final e in desen.allMatches(text)) {
    if (e.start > son) {
      parcalar.add(TextSpan(text: text.substring(son, e.start), style: base));
    }
    final kalin = e.group(1) ?? e.group(2);
    final egik = e.group(3) ?? e.group(4);
    if (kalin != null) {
      parcalar.add(TextSpan(
          text: kalin,
          style: base.copyWith(
              fontWeight: FontWeight.w700, color: RythoColors.parchment)));
    } else if (egik != null) {
      parcalar.add(TextSpan(
          text: egik, style: base.copyWith(fontStyle: FontStyle.italic)));
    }
    son = e.end;
  }
  if (son < text.length) {
    parcalar.add(TextSpan(text: text.substring(son), style: base));
  }
  return TextSpan(children: parcalar, style: base);
}

/// Paylaşım kartı ve önizleme gibi DÜZ metin isteyen yerler için: markdown
/// işaretlerini söker, yapıyı korur.
String markdownToPlain(String data) {
  final satirlar = <String>[];
  for (final blok in parseBlocks(data)) {
    switch (blok.type) {
      case MarkdownBlockType.heading:
        satirlar.add(blok.text);
      case MarkdownBlockType.bullet:
        final im = blok.numara == null ? '•' : '${blok.numara}.';
        satirlar.add('$im ${_isaretleriSoy(blok.text)}');
      case MarkdownBlockType.paragraph:
        satirlar.add(_isaretleriSoy(blok.text));
    }
  }
  return satirlar.join('\n\n');
}

// `replaceAll` geri başvuru (`$1`) DESTEKLEMEZ — düz metin yazar. Grup
// almanın tek yolu `replaceAllMapped`.
String _isaretleriSoy(String s) => s
    .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1)!)
    .replaceAll('`', '')
    .trim();
