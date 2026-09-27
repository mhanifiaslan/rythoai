import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../core/ai_consent.dart' show aiOnayiIste;
import '../../core/api.dart';
import '../../core/conversations.dart';
import '../../core/discovery.dart';
import '../../core/friends.dart';
import '../../core/people.dart';
import '../../core/sound.dart';
import '../../core/wallet.dart';
import '../people/person_form_screen.dart' show relationEmoji, relationLabel;
import 'mention.dart';
import '../../theme/rytho_theme.dart';
import '../../theme/rytho_tokens.dart';
import '../../widgets/atlas_widgets.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../../widgets/motion.dart' show reduceMotion;
import '../../widgets/nebula_widgets.dart';
import '../paywall/token_store_screen.dart';
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

/// Bakiye bu sayının altına inince çip bakır renge döner (R2-F2): aylık
/// hakkın (300) yaklaşık %10'u — "bitmek üzere" uyarısı, panik değil.
const int _kDusukBakiye = 30;

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
  final List<({String sender, String text})> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _busy = false;

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
    // U06: sohbet tamamen AI — ekran her açıldığında onay yoksa sayfa
    // gelir. "Şimdi değil" ekranı KAPATMAZ (geçmiş konuşmalar okunabilir
    // kalır); gönderim ayrıca kapılı (bkz. `_send`).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) aiOnayiIste(context, ref);
    });
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
              0, gecmis.map((m) => (sender: m.sender, text: m.text)));
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
        // riski yok.
        final yedek = widget.seedFallback;
        if (yedek != null && yedek.isNotEmpty) {
          _messages.insert(0, (sender: 'AI', text: yedek));
        }
      });
      _scrollDown();
    } catch (e) {
      debugPrint('Konu tohumu yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
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
    // U06: mesaj Gemini'ye gider — onay yoksa GÖNDERİLMEZ ve metin kutuda
    // kalır (kullanıcı yazdığını kaybetmesin). Sunucu da aynı kapıyı
    // tutuyor; bu, isteğin hiç çıkmaması için.
    if (!await aiOnayiIste(context, ref) || !mounted) return;
    _controller.clear();
    HapticFeedback.lightImpact();
    SoundFx.send();
    setState(() {
      _messages.add((sender: 'USER', text: text));
      _busy = true;
    });
    _scrollDown();

    try {
      // SS-turu: tohum yüklemesi bitmeden geçmiş KURULMAZ. Kullanıcı
      // bildirime dokunup hemen cevap yazarsa Rytho'nun sorusu henüz
      // arşivden gelmemiş olur ve model neye cevap verildiğini göremezdi.
      await _seedFuture;
      final dio = ref.read(apiProvider);
      // Bağlam penceresi: sunucu zaten son 20 turla sınırlıyor; uzun
      // arşivli konuda tamamını taşımak boşuna bant genişliği.
      final history = _messages
          .map((m) => {'sender': m.sender, 'text': m.text})
          .toList()
        ..removeLast();
      final son20 = history.length > 20
          ? history.sublist(history.length - 20)
          : history;
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
      if (_mentionName != null) _clearMention();
      // OB4: başarılı sohbet turu keşif halkasının ikinci dilimi.
      ref.read(discoveryProvider.notifier).mark(DiscoveryTask.chat);
      final veri = response.data as Map;
      setState(() {
        _messages.add((sender: 'AI', text: veri['reply'] ?? ''));
        // Yeni konunun kimliği ilk yanıtla gelir; sonraki mesajlar aynı
        // konuya yazılır ve liste ekranında görünür.
        _conversationId =
            (veri['conversation_id'] as String?) ?? _conversationId;
      });
      SoundFx.receive();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add((
            sender: 'AI',
            text: friendlyError(e, AppLocalizations.of(context))
          )));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
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

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
            child: const Text('✦',
                style: TextStyle(fontSize: 14, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          // Başlık esnemiyordu: `AppBar` eylemleri (bakiye çipi) yer
          // aldıktan sonra kalan darlıkta uzun çeviri + büyük ölçekte
          // başlık sağdan kırpılıyordu.
          Flexible(child: Text(AppLocalizations.of(context).chatTitle)),
        ]),
        actions: [
          // Bakiye çipi — "kalan hakkın" ilk kez bir yüzeye kavuşuyor.
          // Dokununca token mağazası: bakiyeyi GÖREN kullanıcı, bitmeden
          // doldurabilmeli. KT4: 0 bakiyede de GÖRÜNÜR (token_chip.dart
          // kendi kuralı) — çipin en gerekli olduğu an tam da bakiyenin
          // bittiği andır; kaybolması mağazaya giden yolu da kaybettiriyordu.
          Consumer(builder: (context, ref, _) {
            final cuzdan = ref.watch(walletProvider).value;
            if (cuzdan == null) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(right: RythoSpace.md),
              child: Pressable(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TokenStoreScreen(),
                  fullscreenDialog: true,
                )),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: RythoSpace.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: RythoColors.inkLighter,
                    borderRadius: BorderRadius.circular(RythoRadius.pill),
                    border: Border.all(color: RythoColors.glassStroke),
                  ),
                  // R2-F2: sayaç SAKİN. Bakiye görünür kalır (sürpriz yok
                  // ilkesi), ama her mesajda aşağı kayan animasyon sohbeti
                  // bir oyun ekonomisine çeviriyordu — duygusal güven
                  // isteyen bir üründe yanlış his. Vurgu yalnız bakiye
                  // AZALDIĞINDA (<%10) renkle geri geliyor.
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('✦', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: RythoSpace.xs),
                    Text(
                      AppLocalizations.of(context)
                          .tokenBalanceChip(cuzdan.total),
                      style: RythoType.dataSmall.copyWith(
                          color: cuzdan.total <= _kDusukBakiye
                              ? RythoColors.copper
                              : null),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _seeding
              ? const Center(child: AstrolabeSpinner())
              : _messages.isEmpty
              ? _EmptyState(onSuggestion: (s) => _send(s))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
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
                      icerik = const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: TypingDots(),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 220.ms)
                          .slideY(begin: 0.2, curve: Curves.easeOutBack);
                    } else {
                      final m = _messages[i];
                      final mine = m.sender != 'AI';
                      anahtar = ValueKey('m-$i');
                      icerik = Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: _Bubble(text: m.text, mine: mine)
                            .animate()
                            .fadeIn(duration: 240.ms)
                            .slideY(begin: 0.25, curve: Curves.easeOutBack)
                            .scale(
                                begin: const Offset(0.92, 0.92),
                                curve: Curves.easeOutBack,
                                duration: 300.ms),
                      );
                    }
                    return AnimatedSwitcher(
                      duration: RythoMotion.base,
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions(l10n).length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: RythoColors.lilac.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
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
                  const SizedBox(width: 6),
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
        const SizedBox(height: 8),
        // Giriş alanı: + / metin / degrade gönder
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: RythoText.body(15),
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: l10n.chatHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: RythoColors.glassStroke),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: RythoColors.glassStroke),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          const BorderSide(color: RythoColors.purple),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: _send,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RythoColors.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                          color: RythoColors.goldGlow, blurRadius: 16),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded,
                      size: 20, color: Colors.white),
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
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: mine ? Colors.white : null,
        gradient: mine ? null : RythoColors.primaryGradient,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 6),
          bottomRight: Radius.circular(mine ? 6 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: mine
                ? Colors.black.withValues(alpha: 0.25)
                : RythoColors.goldGlow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        style: RythoText.body(14.5,
            color: mine ? const Color(0xFF1D1230) : Colors.white,
            height: 1.5),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSuggestion});
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(builder: (context) {
            final hero = Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RythoColors.primaryGradient,
                boxShadow: [
                  BoxShadow(color: RythoColors.magentaGlow, blurRadius: 34),
                ],
              ),
              child: const Text('✦',
                  style: TextStyle(fontSize: 32, color: Colors.white)),
            );
            // OT5 sürüklenme onarımı: bu nabız reduceMotion kapısı OLMAYAN
            // tek döngülü animasyondu (motion_test bekçisi artık tutuyor).
            if (reduceMotion(context)) return hero;
            return hero
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.06, 1.06),
                    duration: 1400.ms,
                    curve: Curves.easeInOut);
          }),
          const SizedBox(height: 18),
          Text('Rytho AI', style: RythoText.display(24)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              l10n.chatEmptyBody,
              textAlign: TextAlign.center,
              style: RythoText.body(14, color: RythoColors.parchmentDim),
            ),
          ),
        ],
      )
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.06, curve: Curves.easeOutCubic),
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
/// Satır anatomisi `_PersonTile` çekirdeği: 34px daire (kişide ilişki
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
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (_, i) {
        final aday = candidates[i];
        final burc = localizedSignName(l10n, aday.sunSign);
        final altSatir = aday.relation != null
            ? (burc.isNotEmpty ? burc : relationLabel(l10n, aday.relation!))
            : [
                if (aday.username != null) '@${aday.username}',
                if (burc.isNotEmpty) burc,
              ].join(' · ');
        return Pressable(
          onTap: () => onSelect(aday),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: RythoColors.inkLight.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RythoColors.lilac.withValues(alpha: 0.14),
                ),
                child: aday.relation != null
                    ? Text(relationEmoji(aday.relation!),
                        style: const TextStyle(fontSize: 16))
                    : Text(
                        aday.display.isEmpty
                            ? '@'
                            : aday.display[0].toUpperCase(),
                        style: RythoText.body(14,
                            color: RythoColors.lilac,
                            w: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(aday.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RythoText.body(13.5, w: FontWeight.w600)),
                    if (altSatir.isNotEmpty)
                      Text(altSatir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RythoText.body(11,
                              color: RythoColors.parchmentDim)),
                  ],
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
