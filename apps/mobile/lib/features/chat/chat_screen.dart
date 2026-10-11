import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../core/api.dart';
import '../../core/conversations.dart';
import '../../core/discovery.dart';
import '../../core/friends.dart';
import '../../core/people.dart';
import '../../core/sound.dart';
import '../../core/tr_metin.dart' show trBuyuk;
import '../people/person_form_screen.dart' show relationEmoji, relationLabel;
import '../share/share_card.dart' show shareReportCard;
import 'mention.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/common.dart' show ErrorCard;
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/liste_satiri.dart';
import '../../widgets/markdown_text.dart' show MarkdownText, markdownToPlain;
import '../../widgets/motion.dart' show RythoReveal, kapili, reduceMotion;
import '../../widgets/nebula_widgets.dart';
import '../../widgets/okuma_kabi.dart' show bugununEtiketi;
import '../../widgets/token_chip.dart';
import '../../l10n/app_localizations.dart';

/// Rytho AI sohbeti — v4 (Revize R4): KONU bazlı.
///
/// [conversationId] verilirse konuşma arşivden tohumlanır ve kaldığı
/// yerden sürer; verilmezse ilk mesajla yeni konu açılır (kimliği sunucu
/// döndürür, buradan izlenir). Mesaj balonu davranışı aynı: kullanıcı
/// sağda beyaz, Rytho solda mor degrade.
///
/// [initialText] giriş alanını ÖN-DOLDURUR, göndermez (R2-S2): sinyal
/// kartından gelen soru kullanıcının önüne yazılmış gelir, son söz onun.
///
/// [friendUid] (R4-2): sohbet bir ARKADAŞ bağlamında açıldıysa arkadaşın
/// kimliği. Bu konuşmadaki HER mesajla sunucuya gider; sunucu arkadaşlığı
/// doğrular ve ölçülen ilişki eksenlerini prompt'a fısıldar — takip
/// soruları da bağlamı korur. Ham doğum verisi hiçbir yönde taşınmaz.
///
/// [personId] (P-turu): sohbet KULLANICININ EKLEDİĞİ bir kişi bağlamında
/// açıldıysa o kişinin kimliği. Aynı fısıltı mekanizması; farkı yetki
/// kapısı (arkadaşlık değil sahiplik) ve kişinin adıyla değil ilişkisiyle
/// anılması — sunucu o adı zaten bilmiyor.

/// Sohbet satırının türü.
///
/// NEDEN dört tür: eski model yalnız `sender` dizesi taşıyordu ve HER
/// hata Rytho'nun ağzından bir balon olarak basılıyordu — "Bağlantı
/// kurulamadı" cümlesi mor degradede, Rytho'nun sözü gibi; üstelik bir
/// sonraki mesajla birlikte GEÇMİŞ olarak sunucuya gidiyordu (model kendi
/// "cevabı" sanıp ona göre devam ediyordu). Tür ayrılınca ekrana ne
/// çizileceği ve tele ne gideceği aynı yerden okunur.
enum MesajTuru {
  /// Kullanıcının yazdığı — tel üstünde `USER`.
  kullanici,

  /// Rytho'nun cevabı ya da açılış sorusu — tel üstünde `AI`.
  rytho,

  /// Gönderim düştü: ekranda kalır, sunucuya GİTMEZ, "Tekrar dene" taşır.
  hata,

  /// Ekranın kendi notu (arşiv tohumu yüklenemedi): ekranda kalır,
  /// sunucuya GİTMEZ.
  sistem,
}

/// Tek sohbet satırı.
class SohbetMesaji {
  const SohbetMesaji(this.tur, this.text);

  final MesajTuru tur;
  final String text;

  /// Bu satır sunucuya geçmiş olarak gider mi? Hata ve sistem satırları
  /// ekranın kendi notlarıdır; modele "konuşmanın parçası" diye verilmez.
  bool get sunucuyaGider =>
      tur == MesajTuru.kullanici || tur == MesajTuru.rytho;

  /// Arşivdeki `sender` dizesinden tür. `AI` dışındaki her şey kullanıcı:
  /// arşiv yalnız `USER`/`AI` yazar, tanınmayan değerde emniyetli taraf
  /// "bunu kullanıcı yazdı"dır (Rytho'ya söylemediği söz yüklenmez).
  static MesajTuru turuCoz(String sender) =>
      sender == 'AI' ? MesajTuru.rytho : MesajTuru.kullanici;
}

/// Sunucunun gördüğü bağlam penceresi (sunucu zaten son 20 turla
/// sınırlıyor; uzun arşivli konuda tamamını taşımak boşuna bant genişliği).
const int kSohbetPenceresi = 20;

/// Sunucuya giden geçmiş — SAF, test edilebilir.
///
/// [mesajlar] gönderilmekte olan mesaj HARİÇ ekrandaki satırlar. Hata ve
/// sistem satırları dışarıda kalır; tel üstündeki sözleşme eskisiyle
/// birebir: `{'sender': 'USER'|'AI', 'text'}`. Pencere SÜZDÜKTEN SONRA
/// uygulanır ki bir dizi hata satırı gerçek turları pencereden itmesin.
List<Map<String, String>> chatHistoryPayload(Iterable<SohbetMesaji> mesajlar,
    {int pencere = kSohbetPenceresi}) {
  final gecmis = [
    for (final m in mesajlar)
      if (m.sunucuyaGider)
        {
          'sender': m.tur == MesajTuru.rytho ? 'AI' : 'USER',
          'text': m.text,
        },
  ];
  return gecmis.length > pencere
      ? gecmis.sublist(gecmis.length - pencere)
      : gecmis;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen(
      {super.key,
      this.conversationId,
      this.initialText,
      this.friendUid,
      this.personId,
      this.source,
      this.seedFallback});

  final String? conversationId;
  final String? initialText;
  final String? friendUid;
  final String? personId;

  /// SS-turu: Rytho'nun bu konuşmayı açarken sorduğu soru.
  ///
  /// Normalde soru ARŞİVDEN gelir (`_seed`). Bu alan yalnız arşiv boş
  /// dönerse devreye girer: bildirim ile Firestore yazımının görünürlüğü
  /// arasında saniyelik bir pencere var ve kullanıcı o anda dokunursa
  /// ekran bomboş kalırdı — Rytho'nun sorduğu soru kaybolmuş gibi.
  /// Metin zaten FCM yükünde geliyor, ek maliyeti yok.
  final String? seedFallback;

  /// KA-turu: konuşmanın nereden açıldığı ("checkin" = akşam bildirimi).
  /// Sunucu bunu hafıza çıkarımında kullanır: check-in cevabı tek mesajlık
  /// olsa da işlenir.
  final String? source;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final List<SohbetMesaji> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _busy = false;

  /// Liste hücrelerinin anahtarları — indeks başına SABİT.
  ///
  /// NEDEN: cevap gelince uzun cevabın BAŞI üstte olsun diye hücre
  /// `ensureVisible(alignment: 0)` ile getiriliyor ve o bir BuildContext
  /// ister. Anahtar balonun kendisine konamaz: balon giriş animasyonu ve
  /// hücre morph'u (noktalar → balon) ölçek/kaydırma DÖNÜŞÜMÜ taşıyor,
  /// animasyonun ilk karesinde ölçülen konum son konumdan sapar ve cevabın
  /// ilk satırları görünür alanın üstünde kalırdı. Hücrenin kökü
  /// (`AnimatedSwitcher`) dönüşümsüzdür. Anahtar hücre İÇERİĞİNE değil
  /// indekse bağlı: noktaların durduğu hücreye aynı anahtarla balon gelir,
  /// `AnimatedSwitcher` durumu korunur ve morph oynar.
  final Map<int, GlobalKey> _hucreler = {};
  GlobalKey _hucreAnahtari(int i) => _hucreler.putIfAbsent(i, GlobalKey.new);

  /// Sürdürülen konunun kimliği; ilk yanıtta sunucudan gelir.
  String? _conversationId;

  /// Arşiv tohumu yükleniyor mu (yalnızca var olan konu açılırken).
  bool _seeding = false;

  /// Tohum yüklemesi. `_send` geçmişi kurmadan ÖNCE bunu bekler: kullanıcı
  /// hızlı cevap yazarsa Rytho'nun sorusu geçmişten düşer ve model neye
  /// cevap verdiğini göremezdi.
  Future<void>? _seedFuture;

  /// Widget'tan gelen bağlam STATE'e taşınır: "+" ile yeni konu açılınca
  /// üçü birlikte sıfırlanmalı, yoksa eski ekranın kişisi/arkadaşı yeni
  /// konuya sızar.
  String? _friendUid;
  String? _personId;

  /// @-bahsetme durumu (GT6): mesaj başına TEK bağlam; ikinci seçim
  /// ilkini değiştirir; ✕ temizler; başarılı gönderimde sıfırlanır.
  /// Metinden adı elle silmek çipi otomatik DÜŞÜRMEZ (✕ kaçış yolu —
  /// belgelenen davranış).
  String? _mentionPersonId;
  String? _mentionFriendUid;
  String? _mentionName;
  MentionToken? _activeMention;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _friendUid = widget.friendUid;
    _personId = widget.personId;
    if (_conversationId != null) _seedFuture = _seed();
    final tohum = widget.initialText;
    if (tohum != null && tohum.isNotEmpty) _controller.text = tohum;
    // Dinleyici girece hareketlerini de yakalar — FocusNode gerekmez.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final secim = _controller.selection;
    final belirtec = secim.isCollapsed
        ? activeMentionToken(_controller.text, secim.end)
        : null;
    if (belirtec?.start != _activeMention?.start ||
        belirtec?.query != _activeMention?.query) {
      setState(() => _activeMention = belirtec);
    }
  }

  void _selectMention(MentionCandidate aday) {
    final belirtec = _activeMention;
    if (belirtec == null) return;
    HapticFeedback.selectionClick();
    final metin = _controller.text;
    final girece = _controller.selection.end;
    final yeni = metin.replaceRange(belirtec.start, girece,
        '${aday.display} ');
    _controller.value = TextEditingValue(
      text: yeni,
      selection: TextSelection.collapsed(
          offset: belirtec.start + aday.display.length + 1),
    );
    setState(() {
      _mentionPersonId = aday.personId;
      _mentionFriendUid = aday.friendUid;
      _mentionName = aday.display;
      _activeMention = null;
    });
  }

  void _clearMention() {
    setState(() {
      _mentionPersonId = null;
      _mentionFriendUid = null;
      _mentionName = null;
    });
  }

  /// Arşivden TEK SEFERLİK tohum. Stream değil — sunucu her turu saniyeler
  /// sonra arka planda arşive yazıyor; canlı dinleseydik her mesaj ekranda
  /// iki kez belirirdi (yerel + arşiv kopyası).
  Future<void> _seed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final id = _conversationId;
    if (uid == null || id == null) return;
    setState(() => _seeding = true);
    try {
      final gecmis = await loadConversation(uid, id);
      if (!mounted) return;
      setState(() {
        if (gecmis.isNotEmpty) {
          _messages.insertAll(
              0,
              gecmis.map((m) =>
                  SohbetMesaji(SohbetMesaji.turuCoz(m.sender), m.text)));
          return;
        }
        // SS-turu: arşiv BOŞ döndü. Rytho'nun sorduğu soru bildirimin
        // yükünde de var; ekranı boş bırakmak yerine onu çiziyoruz.
        // Koşul "boş döndü"; İSTİSNA değil — okuma hata verdiyse konu
        // muhtemelen duruyor ve tekrar açılışta gerçek metniyle gelir,
        // yedeği o yola koymak balonu ikizlerdi.
        // Başa eklenir, "liste boşsa" diye sorulmaz: kullanıcı tohum
        // yüklenirken hızlıca yazdıysa mesajı zaten 0'da durur ve soru
        // onun ÜSTÜNE girmelidir. `_seed` bir kez koştuğu için ikizleme
        // riski yok. Yedek bir HATA değil, Rytho'nun kendi sorusu: türü
        // `rytho`, geçmişe de o sıfatla girer.
        final yedek = widget.seedFallback;
        if (yedek != null && yedek.isNotEmpty) {
          _messages.insert(0, SohbetMesaji(MesajTuru.rytho, yedek));
        }
      });
      _scrollDown();
    } catch (e) {
      debugPrint('Konu tohumu yüklenemedi: $e');
      if (!mounted) return;
      // Eskiden yalnız log'a düşüyordu ve ekran BOŞ kalıyordu: kullanıcı
      // konusunun silindiğini sanırdı. Sistem satırı ne olduğunu söyler ve
      // yeniden deneme yolu verir; sunucuya gitmez.
      setState(() => _messages.add(SohbetMesaji(
          MesajTuru.sistem, AppLocalizations.of(context).chatSeedFailed)));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  /// Sistem satırının "Tekrar dene"si: satır kalkar, tohum yeniden yüklenir.
  void _tohumuYenidenDene(SohbetMesaji satir) {
    if (_seeding) return;
    setState(() => _messages.remove(satir));
    _seedFuture = _seed();
  }

  /// Yeni konu: yerel durum sıfırlanır; ilk mesaj sunucuda yeni konu açar.
  ///
  /// "+" ikonunun İŞLEVİ bu. Eski sürümde ikon çıplak bir Container'dı —
  /// handler'ı hiç yoktu, dokununca ripple bile vermiyordu. Kaldırmak
  /// yerine tam da eksik olan işlev verildi (kullanıcının sorusuna cevap).
  void _newConversation() {
    HapticFeedback.selectionClick();
    setState(() {
      _messages.clear();
      _conversationId = null;
      _seedFuture = null;
      _friendUid = null;
      _personId = null;
    });
  }

  /// Öneri çipleri dile göre üretildiği için const olamaz.
  List<String> _suggestions(AppLocalizations l10n) => [
        l10n.suggestCareer,
        l10n.suggestLove,
        l10n.suggestMonth,
        l10n.suggestFinance,
        l10n.suggestMarriage,
      ];

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    HapticFeedback.lightImpact();
    SoundFx.send();
    final mesaj = SohbetMesaji(MesajTuru.kullanici, text);
    setState(() {
      _messages.add(mesaj);
      _busy = true;
    });
    _scrollDown();
    await _gonder(mesaj);
  }

  /// Hata satırının "Tekrar dene"si: satır kalkar, ondan önceki kullanıcı
  /// mesajı yeniden gönderilir. Yeni balon eklenmez — mesaj ekranda zaten
  /// duruyor; ikinci kopyası "iki kez sordum" görüntüsü verirdi.
  Future<void> _tekrarDene(SohbetMesaji hata) async {
    if (_busy) return;
    final hi = _messages.indexOf(hata);
    if (hi < 0) return;
    final ki = _messages.lastIndexWhere(
        (m) => m.tur == MesajTuru.kullanici, hi - 1);
    if (ki < 0) return;
    final mesaj = _messages[ki];
    HapticFeedback.lightImpact();
    setState(() {
      _messages.removeAt(hi);
      _busy = true;
    });
    await _gonder(mesaj);
  }

  /// [mesaj] ekranda duran kullanıcı satırı; geçmiş ondan BAŞKA her şeyden
  /// kurulur. Kimlikle (indeksle değil) ayıklanıyor: `_seedFuture` beklenirken
  /// tohum listenin BAŞINA giriyor ve indeksler kayıyor.
  Future<void> _gonder(SohbetMesaji mesaj) async {
    final text = mesaj.text;
    try {
      // SS-turu: tohum yüklemesi bitmeden geçmiş KURULMAZ. Kullanıcı
      // bildirime dokunup hemen cevap yazarsa Rytho'nun sorusu henüz
      // arşivden gelmemiş olur ve model neye cevap verildiğini göremezdi.
      await _seedFuture;
      final dio = ref.read(apiProvider);
      final son20 = chatHistoryPayload(
          _messages.where((m) => !identical(m, mesaj)));
      // KA6: ekrandan bağlam gelmediyse mesaj cihazdaki kişi adlarına
      // karşı taranır — "Ayşe'yle aram nasıl?" ana sekmeden sorulsa da
      // doğru kişinin ölçümü sohbete girer. Ad sunucuya GİTMEZ, yalnız
      // kimlik gider (gizlilik kuralı: etiket cihazda kalır).
      // GT6: @-bahsetme her şeyi döver — açık niyet sezgiden önce gelir.
      String? adEslesen;
      if (_friendUid == null && _personId == null &&
          _mentionPersonId == null && _mentionFriendUid == null) {
        final kisiler = ref.read(peopleProvider).value ?? const <Person>[];
        adEslesen = matchPersonIdByLabel(text, kisiler);
      }
      final response = await dio.post('/api/v1/chat', data: {
        'history': son20,
        'message': text,
        'conversation_id': _conversationId,
        // R4-2/GT6: bağlam alanları tek yerde kurulur (test edilebilir
        // saf fonksiyon); öncelik: bahsetme > ekran > ad eşlemesi.
        ...chatContextFields(
          mentionPersonId: _mentionPersonId,
          mentionFriendUid: _mentionFriendUid,
          widgetPersonId: _personId,
          widgetFriendUid: _friendUid,
          labelMatch: adEslesen,
        ),
        // KA-turu: check-in cevabı tek mesajlık da olsa hafızaya işlensin.
        if (widget.source != null) 'source': widget.source,
      });
      if (!mounted) return;
      if (_mentionName != null) _clearMention();
      // OB4: başarılı sohbet turu keşif halkasının ikinci dilimi.
      ref.read(discoveryProvider.notifier).mark(DiscoveryTask.chat);
      final veri = response.data as Map;
      final cevapIndeksi = _messages.length;
      setState(() {
        _messages.add(
            SohbetMesaji(MesajTuru.rytho, (veri['reply'] as String?) ?? ''));
        // Yeni konunun kimliği ilk yanıtla gelir; sonraki mesajlar aynı
        // konuya yazılır ve liste ekranında görünür.
        _conversationId =
            (veri['conversation_id'] as String?) ?? _conversationId;
      });
      SoundFx.receive();
      _cevabinBasinaKaydir(cevapIndeksi);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == kPaywallStatus) {
        // 402'nin TEK yolu mağaza/paywall ve onu interceptor zaten açtı
        // (core/api.dart). Eskiden sunucunun `detail` cümlesi bir de
        // Rytho balonu olarak düşüyordu ve kullanıcının yazdığı metin
        // gönderimden önce silindiği için KAYBOLUYORDU. Gönderilmemiş
        // mesaj ekrandan kalkar ve giriş alanına geri yazılır: bakiye
        // dolunca tek dokunuşla gider (emsal: iching_tab 402 dalı).
        setState(() => _messages.remove(mesaj));
        _controller.text = text;
        return;
      }
      setState(() => _messages.add(SohbetMesaji(
          MesajTuru.hata, friendlyError(e, AppLocalizations.of(context)))));
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(SohbetMesaji(
          MesajTuru.hata, friendlyError(e, AppLocalizations.of(context)))));
      _scrollDown();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    // Sızıntı düzeltmesi: her açılış/kapanışta iki controller askıda
    // kalıyordu.
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// En alta: kullanıcının kendi mesajı ve "yazıyor" noktaları için.
  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final hedef = _scrollController.position.maxScrollExtent;
      // `animateTo` sıfır süreyi reddeder (bkz. motion.kapili); hareket
      // azaltmada doğru fiil `jumpTo`.
      final sure = kapili(context, RythoMotion.base);
      if (sure == Duration.zero) {
        _scrollController.jumpTo(hedef);
      } else {
        _scrollController.animateTo(hedef,
            duration: sure, curve: RythoMotion.enter);
      }
    });
  }

  /// Rytho'nun cevabı geldiğinde cevabın BAŞI görünür alanın üstüne gelir.
  ///
  /// NEDEN en alta değil: uzun bir cevapta "en alta kaydır" kullanıcıyı
  /// cevabın SONUNA bırakıyordu; okumaya başlamak için yukarı kaydırması
  /// gerekiyordu. Kısa cevapta `ensureVisible` zaten uç sınırda durur
  /// (listenin sonundan öteye kaydıramaz), yani kısa cevap eskisi gibi en
  /// altta görünür. Hücre henüz çizilmemişse (ekran dışı) en alta düşülür.
  void _cevabinBasinaKaydir(int indeks) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hucre = _hucreler[indeks]?.currentContext;
      if (hucre == null) {
        _scrollDown();
        return;
      }
      Scrollable.ensureVisible(hucre,
          alignment: 0,
          duration: kapili(context, RythoMotion.base),
          curve: RythoMotion.enter);
    });
  }

  /// Rytho cevabını paylaşım kartına basar (uzun basış).
  ///
  /// Kullanıcının kendi mesajı paylaşılmaz: kart "Rytho ile sohbetimden"
  /// diyor ve sohbetin sorusu çoğu zaman kişisel. Gövde markdown'dan
  /// arındırılır; tarih kartın ÜRETİM günü (doğum verisi değil).
  Future<void> _paylas(String metin) {
    HapticFeedback.mediumImpact();
    return shareReportCard(
      context,
      title: AppLocalizations.of(context).chatShareCardTitle,
      body: markdownToPlain(metin),
      dateLabel: bugununEtiketi(),
      glyph: '✦',
    );
  }

  /// Satırın giriş animasyonu — balon dili (hafif taşmalı canlılık).
  /// Hareket azaltmada çocuk çıplak döner.
  Widget _belir(Widget child, {bool olcek = false}) {
    if (reduceMotion(context)) return child;
    var zincir = child
        .animate()
        .fadeIn(duration: RythoMotion.base)
        .slideY(begin: 0.2, curve: RythoMotion.pop);
    if (olcek) {
      zincir = zincir.scale(
          begin: const Offset(0.92, 0.92),
          curve: RythoMotion.pop,
          duration: RythoMotion.base);
    }
    return zincir;
  }

  Widget _satir(SohbetMesaji m) {
    switch (m.tur) {
      case MesajTuru.hata:
        // Hata kartı TEK bileşen (ErrorCard): madder ikon + metin + Tekrar
        // dene. "Bu ekranı bildir" kapalı — her düşen mesajın altında iki
        // düğme sohbeti forma çevirirdi; bildirim yolu profilde duruyor.
        return ErrorCard(
          message: m.text,
          onRetry: () => _tekrarDene(m),
          reportable: false,
        );
      case MesajTuru.sistem:
        return ErrorCard(
          message: m.text,
          onRetry: () => _tohumuYenidenDene(m),
          screen: 'chat',
        );
      case MesajTuru.kullanici:
      case MesajTuru.rytho:
        final mine = m.tur == MesajTuru.kullanici;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: SohbetBalonu(
            text: m.text,
            mine: mine,
            onLongPress: mine ? null : () => _paylas(m.text),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CosmicScaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RythoColors.primaryGradient,
            ),
            child: Text('✦',
                style: RythoText.glyph(14, color: RythoColors.onGradient)),
          ),
          const SizedBox(width: RythoSpace.sm),
          // Başlık esnemiyordu: `AppBar` eylemleri (bakiye çipi) yer
          // aldıktan sonra kalan darlıkta uzun çeviri + büyük ölçekte
          // başlık sağdan kırpılıyordu.
          Flexible(child: Text(l10n.chatTitle)),
        ]),
        actions: const [
          // Bakiye çipi TEK bileşen (`TokenChip`): üç hâli, düşük bakiye
          // eşiği ve hedefi (mağaza) orada. Sohbetin kendi çipi ✦ simgesi,
          // elle 30 eşiği ve ayrı rotasıyla ondan üç yerde ayrışmıştı.
          Padding(
            padding: EdgeInsets.only(right: RythoSpace.md),
            child: TokenChip(),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _seeding
              ? const Center(child: AstrolabeSpinner())
              : _messages.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(RythoSpace.lg),
                  itemCount: _messages.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    // Dots → balon morph'u (R12-C2): yanıt geldiğinde
                    // "yazıyor" noktalarının durduğu indekse AI balonu
                    // gelir (itemCount değişmez!) — hücre AnimatedSwitcher
                    // içinde olduğundan noktalar sönerken balon AYNI
                    // köşeden büyür. Sarmalayıcı HER hücrede sabit durur;
                    // koşullu sarmak komşu hücrelerin giriş animasyonunu
                    // yeniden oynatırdı.
                    final Key anahtar;
                    final Widget icerik;
                    if (i == _messages.length) {
                      anahtar = const ValueKey('dots');
                      icerik = _belir(const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: RythoSpace.md),
                          child: TypingDots(),
                        ),
                      ));
                    } else {
                      anahtar = ValueKey('m-$i');
                      icerik = _belir(_satir(_messages[i]), olcek: true);
                    }
                    return AnimatedSwitcher(
                      key: _hucreAnahtari(i),
                      duration: kapili(context, RythoMotion.base),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.9, end: 1.0).animate(
                              CurvedAnimation(
                                  parent: anim, curve: RythoMotion.settle)),
                          alignment: Alignment.bottomLeft,
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(key: anahtar, child: icerik),
                    );
                  },
                ),
        ),
        // Öneri çipleri — aktif '@' varken bant WhatsApp-tarzı DİKEY
        // aday listesine dönüşür (OB1; GT6'daki yatay çip "IconData(U+…)"
        // hatasıyla birlikte gitti). Mesaj listesi Expanded'da olduğu
        // için Overlay gerekmez: bant büyür, giriş satırı klavyenin
        // üstünde sabit kalır.
        if (_activeMention != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _MentionBand(
              query: _activeMention!.query,
              onSelect: _selectMention,
            ),
          )
        else
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: RythoSpace.lg),
              itemCount: _suggestions(l10n).length,
              separatorBuilder: (_, _) => const SizedBox(width: RythoSpace.sm),
              itemBuilder: (_, i) => Center(
                child: SuggestionChip(
                  text: _suggestions(l10n)[i],
                  onTap: () => _send(_suggestions(l10n)[i]),
                ),
              ),
            ),
          ),
        // Ekli bağlam çipi: bahsedilen kişi/arkadaş bu MESAJA iliştirildi.
        if (_mentionName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                RythoSpace.lg, RythoSpace.xs, RythoSpace.lg, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: RythoSpace.sm, vertical: RythoSpace.xs),
                decoration: BoxDecoration(
                  color: RythoColors.lilac.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(RythoRadius.pill),
                  border: Border.all(
                      color: RythoColors.lilac.withValues(alpha: 0.34)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Çipin metni KULLANICI ADI içeriyor (uzunluğu bizim
                  // denetimimizde değil) ve esnemiyordu; uzun adda kapatma
                  // ikonu ekran dışına taşıyordu. `Flexible` sarmasına
                  // izin verir — ad kırpılmaz.
                  Flexible(
                    child: Text(l10n.chatMentionAttached(_mentionName!),
                        style: RythoType.dataSmall
                            .copyWith(color: RythoColors.lilac)),
                  ),
                  const SizedBox(width: RythoSpace.xs),
                  Pressable(
                    onTap: _clearMention,
                    child: Tooltip(
                      message: l10n.chatMentionClearTooltip,
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: RythoColors.lilac),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        const SizedBox(height: RythoSpace.sm),
        // Giriş alanı: + / metin / degrade gönder
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RythoSpace.lg, 0, RythoSpace.lg, RythoSpace.sm),
          child: SafeArea(
            child: Row(children: [
              // "+" = YENİ KONU. Bir dönem handler'sız çıplak Container'dı
              // — dokununca hiçbir şey olmuyordu (kullanıcı fark etti).
              Pressable(
                onTap: _newConversation,
                child: Tooltip(
                  message: l10n.newConversation,
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: RythoColors.inkLight,
                      border: Border.all(color: RythoColors.glassStroke),
                    ),
                    child: const Icon(Icons.add_comment_outlined,
                        size: 19, color: RythoColors.lilac),
                  ),
                ),
              ),
              const SizedBox(width: RythoSpace.sm),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: RythoType.body,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: l10n.chatHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RythoRadius.card),
                      borderSide:
                          const BorderSide(color: RythoColors.glassStroke),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RythoRadius.card),
                      borderSide:
                          const BorderSide(color: RythoColors.glassStroke),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RythoRadius.card),
                      borderSide:
                          const BorderSide(color: RythoColors.purple),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: RythoSpace.sm),
              // İkon-tek düğme: ekran okuyucu etiketi `Pressable`dan.
              // Etiket `feedbackSend` ("Gönder") anahtarından ödünç — sohbete
              // özel anahtar ARB kilitliyken eklenemedi (D8: `chatSend`).
              Pressable(
                onTap: _send,
                semanticLabel: l10n.feedbackSend,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    // K5: ikon taşıyan dolu düğme → kontrastı ölçülü CTA
                    // degradesi.
                    gradient: RythoColors.ctaGradient,
                    boxShadow: [
                      BoxShadow(
                          color: RythoColors.goldGlow, blurRadius: 16),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded,
                      size: 20, color: RythoColors.onGradient),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Sohbet balonu: kullanıcı beyaz (koyu metin), Rytho mor degrade (beyaz).
///
/// Rytho'nun metni `MarkdownText` ile çizilir: model `**kalın**` ve madde
/// işareti üretiyor ve düz `Text` onları ham işaret olarak basıyordu.
/// Kullanıcının metni düz kalır — onun yazdığı yıldız yıldızdır.
/// [onLongPress] yalnız Rytho balonunda: uzun basış paylaşım kartı.
class SohbetBalonu extends StatelessWidget {
  const SohbetBalonu({
    super.key,
    required this.text,
    required this.mine,
    this.onLongPress,
  });

  final String text;
  final bool mine;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final govde = Container(
      margin: const EdgeInsets.only(bottom: RythoSpace.md),
      // Rytho balonunda alt dolgu YOK: `MarkdownText` son paragrafın altına
      // kendi `md` boşluğunu koyuyor; ikisi üst üste binince balon alttan
      // şişiyordu.
      padding: EdgeInsets.fromLTRB(RythoSpace.lg, RythoSpace.md,
          RythoSpace.lg, mine ? RythoSpace.md : 0),
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: mine ? RythoColors.onGradient : null,
        // K5: metin taşıyan degrade yüzey → kontrastı ölçülü CTA degradesi.
        gradient: mine ? null : RythoColors.ctaGradient,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(RythoRadius.card),
          topRight: const Radius.circular(RythoRadius.card),
          bottomLeft:
              Radius.circular(mine ? RythoRadius.card : RythoRadius.xs),
          bottomRight:
              Radius.circular(mine ? RythoRadius.xs : RythoRadius.card),
        ),
        boxShadow: [
          BoxShadow(
            color: mine
                ? RythoColors.ink.withValues(alpha: 0.25)
                : RythoColors.goldGlow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: mine
          ? Text(text, style: RythoType.body.copyWith(color: RythoColors.ink))
          : MarkdownText(text,
              baseStyle:
                  RythoType.body.copyWith(color: RythoColors.onGradient)),
    );
    if (onLongPress == null) return govde;
    // `Pressable` uzun basış bilmez (basma tepkisi + tek dokunuş); balon
    // dokununca hiçbir şey yapmaz, yalnız uzun basışta paylaşır. Ekran
    // okuyucu için eylem `Semantics.onLongPress` ile duyurulur — görünmez
    // bir jest tek başına keşfedilemez.
    return Semantics(
      onLongPress: onLongPress,
      onLongPressHint: l10n.shareReading,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: govde,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: RythoReveal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(builder: (context) {
              // Boş-durum küresi DEKORATİF: `primaryGradient`'ta kalır
              // (K5 yalnız metin taşıyan yüzeyleri koyulaştırır).
              final hero = Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RythoColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                        color: RythoColors.magentaGlow, blurRadius: 34),
                  ],
                ),
                child: Text('✦',
                    style:
                        RythoText.glyph(32, color: RythoColors.onGradient)),
              );
              // OT5 sürüklenme onarımı: bu nabız reduceMotion kapısı
              // OLMAYAN tek döngülü animasyondu. Süresi dock merkezinin
              // nefesiyle aynı token: iki "nefes" iki hızda atmasın.
              if (reduceMotion(context)) return hero;
              return hero
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.06, 1.06),
                      duration: RythoMotion.breath,
                      curve: Curves.easeInOut);
            }),
            const SizedBox(height: RythoSpace.lg),
            // Marka başlığı ARB'den (`chatTitle` = "Rytho AI", AppBar'la
            // aynı kaynak): literal beşinci kopya olurdu.
            Text(l10n.chatTitle, style: RythoType.heroSmall),
            const SizedBox(height: RythoSpace.sm),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: RythoSpace.xxl),
              child: Text(
                l10n.chatEmptyBody,
                textAlign: TextAlign.center,
                style: RythoType.bodyDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aktif '@' sorgusuna göre bahsetme adayları bandı (GT6).
///
/// Öneri çipi bandının yerine geçer (aynı 42px yükseklik) — Overlay yok,
/// klavye ve girece dokunulmaz. Kişiler önce (ilişki ikonuyla), sonra
/// kabul edilmiş arkadaşlar ('@' önekiyle).
class _MentionBand extends ConsumerWidget {
  const _MentionBand({required this.query, required this.onSelect});

  final String query;
  final ValueChanged<MentionCandidate> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kisiler = ref.watch(peopleProvider).value ?? const <Person>[];
    final arkadaslar = ref.watch(friendsProvider).value ?? const <Friend>[];
    final adaylar = mentionCandidates(
      query, kisiler, arkadaslar,
      (k) => k.label ?? relationLabel(l10n, k.relation),
    );
    return MentionCandidateList(candidates: adaylar, onSelect: onSelect);
  }
}

/// WhatsApp-tarzı dikey aday listesi (OB1) — SAF: provider bilmez,
/// doğrudan test edilir (GT6'daki "IconData(U+…)" hatası bandı çizen
/// tek bir test olmadığı için sızmıştı).
///
/// Satır `ListeSatiri` (D3 tek liste satırı): 34px daire (kişide ilişki
/// EMOJİSİ — IconData değil; arkadaşta baş harf), ad, soluk alt satır
/// (kişi: burç ya da ilişki adı; arkadaş: @kullanıcıadı · burç).
class MentionCandidateList extends StatelessWidget {
  const MentionCandidateList(
      {super.key, required this.candidates, required this.onSelect});

  final List<MentionCandidate> candidates;
  final ValueChanged<MentionCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (candidates.isEmpty) {
      return SizedBox(
        height: 42,
        child: Center(
          child: Text(l10n.chatMentionEmpty,
              style: RythoType.dataSmall
                  .copyWith(color: RythoColors.parchmentDim)),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(
          horizontal: RythoSpace.lg, vertical: RythoSpace.xs),
      itemCount: candidates.length,
      itemBuilder: (_, i) {
        final aday = candidates[i];
        final burc = localizedSignName(l10n, aday.sunSign);
        final altSatir = aday.relation != null
            ? (burc.isNotEmpty ? burc : relationLabel(l10n, aday.relation!))
            : [
                if (aday.username != null) '@${aday.username}',
                if (burc.isNotEmpty) burc,
              ].join(' · ');
        return ListeSatiri(
          leading: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RythoColors.lilac.withValues(alpha: 0.14),
            ),
            child: aday.relation != null
                ? Text(relationEmoji(aday.relation!),
                    style: RythoText.emoji(16))
                // Baş harf Türkçe büyütülür: "ilknur" → "İ", "I" değil.
                : Text(
                    aday.display.isEmpty ? '@' : trBuyuk(aday.display[0]),
                    style: RythoType.body.copyWith(
                        color: RythoColors.lilac, fontWeight: FontWeight.w700)),
          ),
          title: aday.display,
          subtitle: altSatir.isEmpty ? null : altSatir,
          // Chevron YOK: seçim bir yere götürmez, adı metne ekler.
          trailing: const SizedBox.shrink(),
          onTap: () => onSelect(aday),
        );
      },
    );
  }
}
