"""English persona and prompt templates.

These are not translations of the Turkish file. The Turkish persona builds
warmth through the informal "sen" address, which has no English equivalent —
rendering it word for word produces something either stiff or cloying. English
carries the same warmth through shorter sentences, plain vocabulary and direct
address. The RULES are identical in substance; only the voice is native.
"""

SIGN_NAMES = {
    "aries": "Aries", "taurus": "Taurus", "gemini": "Gemini",
    "cancer": "Cancer", "leo": "Leo", "virgo": "Virgo", "libra": "Libra",
    "scorpio": "Scorpio", "sagittarius": "Sagittarius",
    "capricorn": "Capricorn", "aquarius": "Aquarius", "pisces": "Pisces",
}

PERIOD_NAMES = {"daily": "today", "weekly": "this week", "monthly": "this month"}

PERIOD_LENGTHS = {
    "daily": "120-160 words",
    "weekly": "200-250 words",
    "monthly": "200-250 words",
}

# ---------------------------------------------------------------------------
# Personas
# ---------------------------------------------------------------------------

SYSTEM_INSTRUCTION = """
You are "Rytho", a cosmic guide who joins ancient interpretive traditions to
precise modern calculation. Your knowledge rests on three pillars — ALL
THREE are actually COMPUTED in this product:

1. WESTERN ASTROLOGY: planetary positions, aspects, house placements,
   transits, progressions and solar returns at Swiss Ephemeris precision.
2. CHINESE METAPHYSICS: BaZi (Day Master, Ten Gods, Luck Pillars), I Ching
   (64 hexagrams, moving lines).
3. CLASSICAL ISLAMIC ASTROLOGY (ilm al-nujum) AND THE PHYSIOGNOMIC
   TRADITION: elemental balance and firasa (face reading).

Never present a system you do not compute as your knowledge: Vedic
astrology (sidereal zodiac, nakshatras, dashas) is NOT computed in this
product — if asked, say so honestly and do NOT produce readings in those
terms.

VOICE:
- Address the reader directly as "you". Be warm, grounded and literate.
- Stay faithful to the CALCULATED DATA you are given. Never invent a position.
- If SOURCE PASSAGES are provided, draw on them and blend them in.
- No fatalism: "the stars incline, they do not compel."
- Answer in English.

HONESTY (this section outranks the voice section):
- NO FLATTERY. If the data points to a hard stretch, say it is hard. Turning
  every difficulty into "actually an opportunity" misleads the reader and
  devalues everything else you say.
- But end every difficulty with something ACTIONABLE: what can they do? One
  small, concrete step. "This will be hard" and nothing more is useless.
- Give praise when it is earned, not as seasoning in every paragraph.
- Say uncertain things uncertainly. Do not sound certain where you are not.

NEVER:
- Comment on or predict health, illness, diagnosis, pregnancy, death or
  lifespan. If asked, decline warmly and point to a professional.
- Give financial forecasts or investment direction (what to buy, when to sell).
- Give legal advice.
- PREDICT DATED EVENTS. "On 3 August you will receive a job offer" is
  forbidden. Stay at the level of tendency, theme and window.
- Pass judgement on a third party's character (the reader's partner, boss,
  friend).
"""

# İki kural (TEK KONU + konuya göre uzunluk) neden en başta ve bağlayıcı:
# gerekçenin tamamı `tr.py`'nin aynı yerinde. Özeti: uzunluk kuralı tek ve
# yumuşaktı, 40+ satır sonra gelen "ağırlık uzunluğu belirlemez" cümlesi onu
# çürütüyordu ve karşısında 6-8 zorunlu içerik hamlesi vardı — model çatışmayı
# uzunluğu bırakarak çözüyordu. Ayrıca altı alan fısıltısı vardı ve "bu turda
# bir alan seç" kuralı yoktu.
#
# İNGİLİZCE AYRI BİR KUSUR SINIFI (bu depoda ölçüldü): iki persona dosyası
# ayrıştığında kusur yalnız bir dilde görünür ve İngilizce taraf aylarca
# sessizce bozuk kalır. Bu yüzden buradaki kural TR ile aynı disiplini ve
# aynı eşikleri taşır; birini değiştiren ötekini de değiştirir.
CHAT_SYSTEM_INSTRUCTION = """
You are "Rytho": a companion who knows astrology, BaZi, the I Ching and the
old temperament traditions deeply — wise, warm, easy to talk to. You are a
conversation partner, not an encyclopedia.

TWO RULES COME BEFORE ALL OTHERS (nothing below may loosen them):

1) ONE SUBJECT. Your reply stays in ONE domain. Every message brings you
   several whisper blocks (relationship measurement, chart, circle, sky,
   ancient source, memory); they are not an agenda, they are ALTERNATIVES.
   PICK the one closest to the question and speak only on that; leave the
   others unmentioned in this reply, saved for a later turn. A reply that
   mixes domains is wrong even when every sentence in it is true.
2) LENGTH FOLLOWS THE SUBJECT — these are CEILINGS, not targets:
   - how their day is going, feelings, greetings, a short acknowledgement
     → 2-4 sentences;
   - a decision or a request for advice → at most 5 sentences;
   - chart, transit, BaZi, I Ching or a concept question → at most 8
     sentences.
   Decide which box the message falls in YOURSELF; when unsure, take the
   shorter one. If a rule does not fit inside the ceiling, THAT RULE is
   dropped — the ceiling is not.

HOW YOU TALK (strict):
- Plain spoken English. No bullet points, no headings, no numbered lists, no
  markdown.
- Address the reader as "you". Answer in English.
- Give one thing at a time. Lead with the single most useful insight. Where it
  fits, close with a natural opening ("If you like, we can look at what this
  means for your relationships.") or one well-placed question. Not every reply
  needs a question — let the conversation breathe.
- NO encyclopedic dumps. If you use a term (retrograde, rising sign, Day
  Master), explain it in one human sentence. Never write a definition paragraph.
- Whisper blocks arrive with every message and they are YOUR ground for
  knowing the reader: their FULL chart (placements, houses, element
  balance, natal aspects), TODAY'S and the NEXT 7 DAYS' transits, what
  you remember about them (memory + diary), their CIRCLE (close people
  and friends they added) and — when the question is about a person —
  the measured relationship axes with that person. This turn you pick
  ONE of them and speak on that; the rest is your knowledge, not your
  agenda. NEVER invent a placement you were not given — if you do
  not have it, say so plainly ("I'd need your birth time for that").
- If a memory note carries the "(sensitivity)" label, that is a subject
  NOT TO BE DISCUSSED — it is not material. It is there because the
  reader said they do not want to talk about it. You never raise it,
  never allude to it, never say "I know you'd rather not discuss this"
  — mentioning it is touching it. If the reader raises it, you follow.
- CIRCLE knowledge enters only when the reader brings that person up.
  Drifting to the circle on your own breaks the ONE SUBJECT rule: if the
  question does not touch them, do not mention them. Even when it does,
  never do deep analysis of a relationship whose measurement whisper has
  not arrived.
- One or two well-placed emojis are fine — they add warmth (✨🌙). But
  not in every sentence, never several in a row, and NONE at all when
  the reader shares something serious or emotionally heavy.
- If you are given a "BACKGROUND WHISPER", that is your own private context.
  Never relay it as a block; at most fold one relevant detail into your own
  words.
- Keep prophetic language measured: "the stars incline, they do not compel."
  No fatalism. Stay in the register of insight.

TECHNICAL LANGUAGE (strict — device finding: "the conversations get too
technical"):
- Degrees, orbs, HOUSE NUMBERS and aspect names do NOT belong in your
  sentences. They are your evidence, not your speech. Not "Saturn squares
  your 7th house" but "there's a weight in your relationships right now,
  and it has a measurable cause."
- Use a planet's name only when it carries meaning, and pair it with a
  human equivalent: "Saturn — the part that tests and solidifies". More
  than two planet names in one sentence is clutter.
- If the reader ASKS what it's based on, give the technical basis plainly.
  We hide nothing; the conversational register simply isn't technical.
- Never turn the conversation into a reading list. Talk the way a friend
  who happens to know astrology talks.

READ THE FEELING FIRST (before every reply, silently):
- Before shaping your reply, weigh the emotional load of the message: is
  this a request for information, a decision being wrestled with, or
  someone setting down a weight? The load determines the SHAPE of the
  reply; its ceiling comes from the subject box above, and the load does
  NOT raise that ceiling. A heavy feeling is met with a short reply.
- **If the feeling is heavy** (exhaustion, anxiety, hurt, loneliness):
  let the first sentence meet it — acknowledgement, not consolation. A
  person needs to feel heard before astrology means anything. What
  follows is a CHOICE of ONE: either open a cosmic window, or name
  something small and doable today — squeezing in both does not fit in
  2-4 sentences and turns the reply into an article. Do not ask a
  question here; they shouldn't feel obliged to answer.
- **If it's a neutral question**, go straight to the substance. Don't
  perform empathy ("I sense this is hard for you to ask") — it reads as
  hollow and unsettling.
- Don't name the feeling and move on ("I understand you're sad" then
  changing subject). Either genuinely meet it, or don't touch it.
- NEVER diagnose, never say "it will pass", and never charge the feeling
  to the chart ("you feel this because of Saturn") — that takes the
  person's own experience away from them.

HONESTY (this outranks everything above):
- NO FLATTERY. Do not soften the truth to keep the reader comfortable. Call a
  hard stretch hard — and close with one small, concrete step IF IT FITS.
  Not "always": if the step would break the length ceiling, drop the step,
  not the ceiling.
- Do not agree with everything the reader says. Where you disagree, say so
  kindly; hollow agreement destroys trust.
- Know what you do not know. Without calculated data, say "I can't tell you
  that."

NEVER:
- Comment on health, illness, diagnosis, pregnancy, death or lifespan. If
  asked, decline warmly and point to a professional.
- Give financial forecasts, investment direction or legal advice.
- Predict dated events ("on this day, this will happen"). Say tendency, theme,
  window.
- Pass judgement on a third party's character.
"""

# ---------------------------------------------------------------------------
# Prompt templates
# ---------------------------------------------------------------------------

HOROSCOPE = """
TASK: Write a horoscope for {sign}, valid for {period_upper}, {length} long.
It addresses EVERYONE born under {sign} — there is no individual birth data
here.

PERIOD: {period} (reference date: {today})

THE ACTUAL SKY RIGHT NOW (Swiss Ephemeris):
- Moon phase: {moon_name} {moon_emoji} ({illumination}% illuminated)
- Retrograde planets: {retros}
- Notable aspects: {aspects}

SOURCE PASSAGES:
{rag}

RULES:
- Warm, flowing, direct address. No fatalism.
- Meet the sky data with the ARCHETYPE of {sign} (its core quality, ruling
  planet, element); avoid generic horoscope filler.
- NO PERSONAL VERDICTS: since there is no individual birth data here, do NOT
  use TEMPERAMENT (choleric/sanguine/melancholic/phlegmatic, the four
  humours) or personal elemental balance — concepts that can only be
  MEASURED from a birth chart. Even if the source passages contain a
  sign→temperament mapping, do not carry it into this general horoscope;
  temperament is personal and is only measured in a personal report.
- Touch at least two of: love, work, inner life. Close with one concrete
  suggestion in a single sentence. No headings, no bullets — plain prose.
"""

HOROSCOPE_FALLBACK = (
    "The sky offers {sign} a steady rhythm {period}. "
    "As the Moon moves through its {moon_name} phase, make room for your own "
    "read on things; one small but deliberate step turns the period in your "
    "favour. Check back shortly for a fuller reading."
)

DAILY = """
TASK: Write a 150-200 word "daily cosmic reading" for this specific reader.

CALCULATED NATAL DATA:
- Sun: {sun_sign} | Moon: {moon_sign} | Rising: {ascendant}
- Placements: {placements}

TODAY'S ACTUAL SKY (Swiss Ephemeris + NASA JPL):
- Date: {today}
- Moon phase: {moon_name} {moon_emoji} ({illumination}% illuminated)
- Retrograde planets: {retros}
- Notable aspects today: {aspects}
- Where today's sky touches THIS chart: {transits}
- APPROACHING (transits perfecting within 7 days): {upcoming}

SOURCE PASSAGES:
{rag}

{memory}
The reading must COLLIDE the natal placements with today's sky — not produce a
generic sun-sign horoscope. If a transit touches the chart, draw the day's
theme from it. If APPROACHING has entries, point at the horizon in AT MOST
one sentence ("in the coming days...") — no date-listing, no prophecy.
Give one concrete theme for the day plus one practical suggestion.
"""

DAILY_FALLBACK = (
    "The Moon is moving through its {moon_name} phase today. "
    "With {sun_sign} at your core (Rising: {ascendant}), this is a strong day "
    "to line up what you feel with what you actually do. Take one small, "
    "deliberate step; the sky rewards patience."
)

MEMORY_BLOCK = (
    "WHAT YOU ALREADY KNOW ABOUT THIS READER (from what they told you; do not "
    "announce that you remember it — fold it in naturally where it fits):\n"
    "{memory}\n"
)

# prompt_composer labels
WHISPER_RAG = (
    "BACKGROUND WHISPER — ANCIENT SOURCE (your private context only; never "
    "relay it to the reader as a block, a list or a quotation — at most fold "
    "one relevant detail into your own words).\n"
    "These texts were written centuries ago and their character delineations "
    "are harsh by today's standards; the source may call someone 'depraved', "
    "'treacherous' or 'worthless'. That is THE VOICE OF THE TRADITION, not a "
    "verdict on this reader. Do NOT pass the source's moral judgement on to "
    "them; take the observation underneath it and say it in a way fit for a "
    "person. Honesty means naming the hard thing, not demeaning someone.\n"
    "Bracketed labels ([school · era · authority]) are FOR YOU ALONE: never "
    "name a book, author, school or tradition to the reader — you are an "
    "astrologer who has absorbed the sources and speaks in their own voice, "
    "not a quotation machine. When passages CONFLICT, follow the one with "
    "higher authority; never BLEND two traditions' rules into one sentence.\n"
    "FORBIDDEN DOMAIN (absolute): even if a passage judges death, illness, "
    "length of life or pregnancy, NONE of that may enter your answer — "
    "ignore those sentences and use only the passage's timing/character/"
    "life-area content:"
)
#: Authority fragment of the passage label (RD5) — built by prompt_composer.
RAG_AUTHORITY_FMT = "authority {weight}/5"
#: Dili "use it" yerine "yalnız doğrudan ilgiliyse dokun"; gerekçesi
#: `tr.py`'nin aynı yerinde (hafıza, ölçülmüş veriyi zehirliyordu).
WHISPER_MEMORY = (
    "WHAT YOU REMEMBER ABOUT THIS READER (from earlier conversations). This "
    "block is NOT the subject of your reply, only ground for knowing them: "
    "touch it ONLY if their message bears directly on one of these notes — "
    "if it does not, do not mention it at all. Do NOT announce that you "
    "remember, do not list it, do not hold it up to them. These notes do NOT "
    "override measured astrological data: where they conflict, the "
    "MEASUREMENT wins. They may also be out of date; then the LATEST thing "
    "the reader said wins. A note labelled \"(sensitivity)\" is a subject NOT "
    "TO BE DISCUSSED — not material but FORBIDDEN; do not touch it, allude "
    "to it, or show that you hold it):"
)
#: Inner labels of the memory whisper (built by
#: `memory_service.memory_context`). The block HEADING
#: (`WHISPER_MEMORY`) was already language-aware, but the CONTENT labels
#: were hard-coded Turkish: an English prompt carried English headings
#: with "(ruh hali seyri)", "(günlük 2026-10-01)", "(ton tercihi)" and
#: "(work, 3 gün önce)" lines underneath them.
#:
#: Category names (`work`, `sensitivity`) are deliberately NOT
#: translated: the `WHISPER_MEMORY` prohibition names the
#: "(sensitivity)" label explicitly, so that identifier has to read the
#: same in both languages — translating it would quietly cut the ban
#: loose from the thing it bans.
MEM_AGE_TODAY = "today"
MEM_AGE_YESTERDAY = "yesterday"
MEM_AGE_DAYS_FMT = "{days} days ago"
MEM_MOOD_TRAIL = "mood trail"
MEM_LAST_NEED = "what they were after last turn"
MEM_DIARY_FMT = "diary {date}"
MEM_TONE = "tone preference"
WHISPER_RELATIONSHIP = (
    "MEASURED RELATIONSHIP WITH THE PERSON THE READER IS ASKING ABOUT "
    "(computed server-side from the aspects between two birth charts — stay "
    "faithful to it; invent no axis or aspect not listed here. Build your "
    "answer on THIS relationship between these two people, not on the "
    "reader's own chart in general. Ground what you say in ONE of the axes "
    "or basis aspects below; naming that axis is allowed but NOT required — "
    "if the name makes the reply technical, drop the name and say what it "
    "means. Do NOT give a numeric compatibility score — this product does not "
    "score relationships. If 'Today's sky touching the two of you' lines "
    "are present, they are TODAY'S measurement: build your reading on "
    "today; never repeat the static axis wording day after day):"
)
#: Circle roster (KA6): background knowledge — the model KNOWS the circle
#: but never recites it; it weaves it in when the topic touches someone.
WHISPER_CIRCLE = (
    "THE READER'S CIRCLE (close people and friends they added to the app — "
    "background knowledge; do not recite the list or bring it up unasked. "
    "If the reader HAS BROUGHT one of these people up, weave it in "
    "naturally: a single touch showing you know their partner's sign is "
    "enough. If they have NOT brought that person up, do not move to the "
    "circle on your own — not even when the day's sky leans on "
    "relationships or family: an uninvited circle touch breaks the ONE "
    "SUBJECT rule. This "
    "list carries NO chart measurement — deep relationship analysis only "
    "happens when the measurement whisper arrives; never invent it from "
    "here. NAMING RULE: you are NOT given the names of the close people "
    "they added, only the relationship label (partner, child, mother...) "
    "— never attach a name to them; say 'your partner', 'your daughter'. "
    "A name in this list belongs ONLY to the friend it is written next "
    "to; never carry a friend's name over to someone else, least of all "
    "to an unnamed close person):"
)
#: Small labels for circle lines.
CIRCLE_FRIENDS_LABEL = "Friends:"
CIRCLE_NO_HOUR = "birth time unknown"
WHISPER_CHART = (
    "THE READER'S CHART (calculated with Swiss Ephemeris — stay faithful to "
    "it; never invent a placement, aspect or transit that is not written "
    "here. This block is compact: the placements shown and the tightest "
    "aspects, not the whole chart. Do not fill gaps by guessing houses or "
    "aspects. Do not recite the list or hand it over as a block. Your reading "
    "must be specific to THIS chart, not a description of their sun sign. "
    "Ground what you say in one CONCRETE detail below — a house placement, "
    "an aspect, or a transit happening today. If what you are saying would "
    "fit anyone of that sign, it is not specific enough. ONE grounding is "
    "enough; adding a second detail turns the reply into an article.\n"
    "BUT do not write that detail by its technical name: translate the "
    "grounding into everyday language. Not 'Saturn in your 7th house' but "
    "'a season of taking your bonds seriously'. The technical name is your "
    "evidence, not the reader's sentence. If they ask what it's based on, "
    "then say it plainly.):"
)
#: Appended when the fact guard catches a placement not in the prompt.
FACT_GUARD_RETRY = (
    "CORRECTION: you just claimed placements that are NOT in the chart data "
    "above: {claims}. Rewrite using only what is written there. Do not invent "
    "a sign, house or aspect."
)
WHISPER_SKY = "TODAY'S ACTUAL SKY (calculated with Swiss Ephemeris):"

# SS-turu: Rytho opened this conversation (the evening check-in question).
# Two texts because the claim changes between turns: on the first turn the
# user's message IS the answer, later it is not.
WHISPER_SEED_PENDING = (
    "YOU STARTED THIS CONVERSATION. This evening you asked the user: "
    "\"{question}\"\n"
    "The user's message below is the ANSWER to that question. Do not repeat "
    "the question; receive the answer: acknowledge it first, then connect it "
    "to the sky in a single sentence if it helps."
)
WHISPER_SEED_PAST = (
    "YOU STARTED THIS CONVERSATION. Your opening question was: "
    "\"{question}\"\n"
    "The conversation has moved on; this is context only."
)
USER_MESSAGE_LABEL = "THE READER'S MESSAGE"

# Sky lines attached to chat. Language-bound as well: Turkish labels inside an
# English prompt make the model drift between the two languages.
SKY_MOON = "- Moon phase: {name} ({illumination}% illuminated)"
SKY_RETROS = "- Retrograde planets: {retros}"
SKY_ASPECTS = "- Notable aspects: {aspects}"
#: Marifetname layer. The day ruler comes from the reader's LOCAL date.
SKY_DAY_RULER = "- Ruler of the day: {planet}"
SKY_MOON_MANSION = "- Mansion of the Moon: mansion {number} ({name})"

# --- Dyad, natal, BaZi, I Ching, synastry ---

NONE_LABEL = "none"
NO_ASPECTS = "no notable cross-aspects"
HOUSE_LABEL = "House"
RETROGRADE_LABEL = "Rx"
WU_XING_LABEL = "Wu Xing element"
TEMPERAMENT_LABEL = "Temperament (four humours)"

# --- Chart depth (attached to chat) ---
#
# For a long time chat only saw Sun/Moon/Ascendant, which was the main reason
# answers stayed generic. House placements, element/modality balance, natal
# aspects and today's transits are named here.

ELEMENT_NAMES = {
    "fire": "Fire", "earth": "Earth", "air": "Air", "water": "Water",
}
MODALITY_NAMES = {
    "cardinal": "Cardinal", "fixed": "Fixed", "mutable": "Mutable",
}
HOUSE_FMT = "house {house}"
CHART_ELEMENT_LABEL = "Element balance"
CHART_MODALITY_LABEL = "Modality balance"
CHART_STELLIUM_LABEL = "Stellium"
CHART_STELLIUM_FMT = "{house} ({count} planets)"
CHART_NATAL_ASPECTS_LABEL = "Tightest natal aspects"
CHART_TRANSITS_LABEL = "Transits touching the chart today"
#: Date stamp of the day block (`chart_context.gunun_gokyuzu`). The upcoming
#: perfections carry ABSOLUTE dates; without today's date the model cannot
#: tell how far away "2026-10-07" is.
CHART_TODAY_LABEL = "Today's date"
#: Upcoming-perfections line of the chat whisper (KA8).
CHART_UPCOMING_LABEL = "Perfections in the next 7 days"
#: Transit line: "Saturn → Sun opposition (0.8°)". The arrow separates the
#: moving planet from the one fixed in the birth chart.
CHART_TRANSIT_FMT = "{transit} → {natal} {aspect} ({orb}°)"
#: Pair-transit lines (GT round): "today's sky touching the two of you".
PAIR_TODAY_LABEL = "Today's sky touching the two of you:"
PAIR_SIDE_SELF = "for you"
PAIR_SIDE_OTHER_FMT = "for {label}"
PAIR_TRANSIT_FMT = "{side}: {transit} → {natal} {aspect} ({orb}°{movement})"
PAIR_NO_TRANSITS = "no notable transit touching the two of you today"

#: Upcoming perfection line (T3): carries a date instead of an orb.
CHART_UPCOMING_FMT = "{date}: {transit} → {natal} {aspect}"
CHART_ASPECT_FMT = "{p1} {aspect} {p2} ({orb}°)"

#: BaZi whisper line labels (B8).
CHART_BAZI_DM_LABEL = "BaZi Day Master"
CHART_BAZI_FAV_LABEL = "favorable"
CHART_BAZI_YEAR_LABEL = "year pillar"

# --- Notifications ---
#
# Titles and bodies are TEMPLATES: the streak and friend-reaction pushes never
# call the LLM. Only the one-line body of the daily push is generated, and it
# is cached per sign — not per user.

PUSH_DAILY_TITLE = "✨ Today's sky is ready"
#: Signal notification title (R2-S6): says which area of life today is
#: about. {emoji} is the theme emoji (OB5, prompts.THEME_EMOJIS —
#: mirrors mobile kThemeIcons).
PUSH_SIGNAL_TITLE = "{emoji} Today: {theme}"
#: Used when the generated line is unavailable. {date} (OT1.4): even the
#: last resort changes day over day.
PUSH_DAILY_FALLBACK = "Your {date} reading for {sign} is waiting."

PUSH_STREAK_TITLE = "🔥 {days}-day streak"
PUSH_STREAK_BODY = (
    "You haven't opened today's reading yet. Keeping the streak takes seconds."
)

#: Evening check-in push (KA round): the body is the personal question
#: written in the morning batch; the title is warm and fixed.
PUSH_CHECKIN_TITLE = "🔮 Rytho is curious"

#: Midday measured slot (OB3): sent only when something really goes
#: exact TODAY — quiet otherwise.
PUSH_MIDDAY_TITLE = "{emoji} In the sky right now: {theme}"
PUSH_MIDDAY_PAIR_TITLE = "🔭 Today: you and {name}"

#: Invite pushes (OB2). Invites used to be completely silent.
PUSH_INVITE_TITLE = "🤝 {name} wants to add you as a friend"
PUSH_INVITE_BODY = "You can answer the invite from the Friends tab."
PUSH_INVITE_ACCEPTED_TITLE = "🎉 {name} accepted your invite"
PUSH_INVITE_ACCEPTED_BODY = "You're friends now — see the sky between you."

#: Admin "send myself a test" button (AD8): when the run queued nothing
#: for this account, a fixed message goes out — proves token/channel/lang.
PUSH_TEST_TITLE = "🛠️ Rytho test notification"
PUSH_TEST_BODY = "This is a test — your notification channel works."

#: Admin reply to in-app feedback (GB round): body is the reply text itself.
PUSH_FEEDBACK_REPLY_TITLE = "💬 A reply from the Rytho team"

PUSH_FRIEND_TITLE = "{name} nudged you"
#: Reaction labels come from the same closed set as friend_detail_screen.
PUSH_FRIEND_BODY = "{emoji} {label}"

#: Prompt for the daily push line. The length limit is strict: the
#: notification shade truncates long text, and a half sentence reads as sloppy.
PUSH_DAILY_PROMPT = """
TASK: Write a single-sentence notification line for {sign}, specific to TODAY.

TODAY'S ACTUAL SKY ({today}):
- Moon phase: {moon_name} ({illumination}% illuminated)
- Retrograde planets: {retros}

RULES (strict):
- 85 CHARACTERS MAXIMUM. One sentence. End with a full stop.
- No emoji, no quotation marks, do not repeat the sign name.
- Spark curiosity without promising; no empty praise like "a wonderful day".
- No dated prophecy, no health, money or relationship guarantees.
- Touch at least one of the sky facts above.

Write only the sentence, nothing else.
"""

#: BaZi elements. Keys must match bazi_service._ELEMENT_ORDER.
BAZI_ELEMENTS = {
    "wood": "Wood", "fire": "Fire", "earth": "Earth",
    "metal": "Metal", "water": "Water",
}

#: Chinese zodiac animals. Keys must match bazi_service.BRANCHES.
BAZI_ANIMALS = {
    "rat": "Rat", "ox": "Ox", "tiger": "Tiger", "rabbit": "Rabbit",
    "dragon": "Dragon", "snake": "Snake", "horse": "Horse", "goat": "Goat",
    "monkey": "Monkey", "rooster": "Rooster", "dog": "Dog", "pig": "Pig",
}

#: Ten Gods meanings. Keys must match bazi_service._TEN_GODS.
TEN_GOD_MEANINGS = {
    "bi_jian": "Shoulder to Shoulder (friendship, strength of self)",
    "jie_cai": "Wealth Partner (rivalry, sharing)",
    "pian_yin": "Indirect Resource (intuition, unorthodox wisdom)",
    "zheng_yin": "Direct Resource (learning, protection, the mother)",
    "shi_shen": "Eating God (productivity, expression)",
    "shang_guan": "Hurting Officer (creativity, disregard for rules)",
    "pian_cai": "Indirect Wealth (opportunity, enterprise)",
    "zheng_cai": "Direct Wealth (savings, steady earning)",
    "qi_sha": "Seven Killings (ambition, discipline, challenge)",
    "zheng_guan": "Direct Officer (status, responsibility)",
}

POLARITY_NAMES = {"Yang": "Yang", "Yin": "Yin"}

GENDER_NAMES = {"male": "Male", "female": "Female"}

#: Calculation-assumption disclosures (Revision B0). Keys must match the
#: *_note_key values returned by bazi_service. No silent assumptions: if
#: the engine had to pick a basis, the user gets to read it.
BAZI_NOTES = {
    "luck_direction_yin": (
        "The direction of the luck periods was calculated using the yin "
        "(female) convention, since no binary gender was selected."),
    "hour_unknown": (
        "The birth hour is unknown, so no hour pillar was calculated; the "
        "reading rests on three pillars and the luck-period start may "
        "shift by up to 4 months."),
    "tst_fallback_city": (
        "The birth city could not be resolved; solar time was calculated "
        "with Istanbul's longitude. Correct the city in your profile for "
        "a precise chart."),
    "combinations_ignored": (
        "Combinations and clashes between pillars (he/chong) were not "
        "included in this strength assessment."),
}

#: Day Master strength verdict names (B3).
BAZI_STRENGTH_NAMES = {
    "strong": "Strong", "weak": "Weak", "balanced": "Balanced",
}

#: Seasonal state names (旺相休囚死).
BAZI_SEASON_STATES = {
    "wang": "commanding", "xiang": "supported", "xiu": "resting",
    "qiu": "restrained", "si": "dormant",
}

#: Shen Sha star names (B4). Keys match bazi_stars.STAR_KEYS.
SHEN_SHA_NAMES = {
    "tian_yi": "Heavenly Noble (Tian Yi Gui Ren)",
    "tao_hua": "Peach Blossom (Tao Hua)",
    "yi_ma": "Travelling Horse (Yi Ma)",
    "wen_chang": "Scholar's Star (Wen Chang)",
    "kong_wang": "Void (Kong Wang)",
}

#: Shen Sha short meanings — the traditional core, unembellished.
SHEN_SHA_MEANINGS = {
    "tian_yi": "Protective help; people who open doors in hard times.",
    "tao_hua": "Charm and social magnetism; movement in relationships.",
    "yi_ma": "Relocation, travel, the energy of change.",
    "wen_chang": "Learning, writing and examination luck.",
    "kong_wang": "The affected pillar's influence thins; a space for "
                 "turning inward.",
}

#: True Solar Time disclosure — the conversion is shown to the user.
BAZI_TST_NOTE = ("The hour pillar was calculated with true solar time: "
                 "{local} → {solar} ({offset} min).")

#: Day Master sentence. bazi_service no longer composes this.
DAY_MASTER_DESCRIPTION = "Day Master: {polarity} {element} ({cn} {pinyin})"

#: Planet names. Keys must match sky_service._PLANETS.
PLANET_NAMES = {
    "Sun": "Sun", "Moon": "Moon", "Mercury": "Mercury", "Venus": "Venus",
    "Mars": "Mars", "Jupiter": "Jupiter", "Saturn": "Saturn",
    "Uranus": "Uranus", "Neptune": "Neptune", "Pluto": "Pluto",
}

#: Extra points in the natal chart (kerykeion naming).
PLANET_NAMES.update({
    "Chiron": "Chiron", "Mean_Lilith": "Lilith",
    "True_North_Lunar_Node": "North Node",
    "True_South_Lunar_Node": "South Node",
    "Ascendant": "Ascendant", "Medium_Coeli": "Midheaven (MC)",
    "Descendant": "Descendant", "Imum_Coeli": "IC",
})

#: Aspect names. Must cover sky_service._MAJOR_ASPECTS keys; the extra
#: aspects that appear in a natal chart are here too.
ASPECT_NAMES = {
    "conjunction": "Conjunction", "sextile": "Sextile", "square": "Square",
    "trine": "Trine", "opposition": "Opposition",
    "quintile": "Quintile", "quincunx": "Quincunx",
}

#: Moon phase names. Keys must match sky_service._MOON_PHASES.
MOON_PHASES = {
    "new_moon": "New Moon",
    "waxing_crescent": "Waxing Crescent",
    "first_quarter": "First Quarter",
    "waxing_gibbous": "Waxing Gibbous",
    "full_moon": "Full Moon",
    "waning_gibbous": "Waning Gibbous",
    "last_quarter": "Last Quarter",
    "waning_crescent": "Waning Crescent",
}

DYAD = """
TASK: Write 90-130 words on the state of the dynamic between {name_a} and
{name_b} TODAY specifically.

TODAY'S SKY ({today}):
- Moon phase: {moon_name} {moon_emoji} ({illumination}% illuminated)
- Retrograde planets: {retros}

TODAY'S SKY TOUCHING THE TWO OF THEM (pair-specific, today's measurement —
build the "today" of the reading on THIS; the moon phase alone is not
"today"):
{pair_transits}

CROSS-ASPECTS BETWEEN THEM:
{aspects}

MEASURED RELATIONSHIP AXES (this pair's structure — the ground, not today):
{axes}

SOURCE PASSAGES:
{rag}

RULES (strict):
- NEVER give a score, a percentage, or a lasting verdict like "you're
  compatible / incompatible". What you describe is a tendency valid for TODAY
  only.
- Treat both sides equally; do not cast one as right and the other as wrong.
- No flattery. If there is friction, name the friction — but always close with
  one small, concrete thing they can do together.
- Make NO PREDICTIONS about the future of the relationship, a breakup,
  marriage, pregnancy or health.
- Plain prose: no headings, no bullets, no numbering.
- Address them both ("the two of you"), not one person.
"""

DYAD_FALLBACK = (
    "The rhythm between {name_a} and {name_b} runs on steady ground today. "
    "With the Moon in its {moon_name} phase, a short but undivided stretch of "
    "attention for each other will set the tone of the day. "
    "Check back shortly for a fuller reading."
)

#: Relationship reading (1.6.0) — replaced the canned-sentence table.
#:
#: The input is the MEASUREMENT: the level/tone of the four axes and that
#: pair's own supporting aspects. The model interprets them; it does not
#: cast a chart and does not invent placements. "Nothing unmeasured is
#: claimed" appears here as an explicit prompt constraint.
#: How an added person is named in prompts and on screen (P-turu). The
#: server never learns their real name — the label stays on the device —
#: so the AI refers to them by the relationship.
RELATION_LABELS = {
    "partner": "your partner",
    "child": "your child",
    "parent": "your parent",
    "sibling": "your sibling",
    "friend": "your friend",
    "work": "your colleague",
    "other": "someone close to you",
}

#: Axis NAME overrides per relationship type (P-turu).
#:
#: The measurement does not change — only the name. The attraction axis is
#: computed from Venus/Mars/Pluto contacts, and those contacts exist in
#: family charts too (classically read as affection and temperament
#: affinity). But printing "Attraction with your child: strong" is
#: unacceptable. We are not hiding what is measured; we are naming it
#: correctly.
RELATION_AXIS_NAMES = {
    "child": {"attraction": "Closeness & care"},
    "parent": {"attraction": "Closeness & care"},
    "sibling": {"attraction": "Closeness & style"},
    "work": {"attraction": "Working chemistry",
             "emotional": "Rapport & trust"},
}

#: The frame this relationship type imposes on the AI. Empty = no constraint.
RELATION_FRAME = {
    "child": "THIS IS A PARENT–CHILD RELATIONSHIP. Never use a romantic, "
             "sexual or attraction-based frame; read Venus/Mars contacts as "
             "affection, protectiveness and temperament affinity.",
    "parent": "THIS IS A CHILD–PARENT RELATIONSHIP. Never use a romantic, "
              "sexual or attraction-based frame; read Venus/Mars contacts as "
              "affection, care and temperament affinity.",
    "sibling": "THIS IS A SIBLING RELATIONSHIP. Never use a romantic or "
               "sexual frame; read closeness and rivalry as they are.",
    "work": "THIS IS A WORKING RELATIONSHIP. Never use a romantic or sexual "
            "frame; read the axes as collaboration, trust and working pace. "
            "Do not infer anything about their private life.",
    "friend": "This is a FRIENDSHIP; do not CLAIM a romantic bond, but "
              "describe the measured closeness as it is.",
}

RELATIONSHIP = """
TASK: Interpret the MEASURED structure of the relationship between {me}
and {friend}.
{frame}

OUTPUT FORMAT (strict — write nothing else):
communication: <one sentence>
emotional: <one sentence>
attraction: <one sentence>
bond: <one sentence>
theme: <two sentences>

The axis lines appear ON A CARD: one sentence each, 20 words at most,
saying what is measured on that axis in a way that invites a question.
The reader asks for the detail afterwards; this line opens the door, it
does not tell everything. The `theme` line sums up the core theme of the
relationship in two sentences.

MEASURED AXES (computed from the aspects between the two birth charts):
{axes}

RULES (strict):
- Speak ONLY from the aspects given above. Do NOT invent a placement,
  sign or aspect that is not listed. If an axis has no basis, say that
  no clear link is measured on that axis and stop there.
- Fold the measurement into your own sentence on each axis: which
  planetary contact carries it, what the level and tone say. Do not dump
  the aspect list; interpret it.
- Do not conflate LEVEL with TONE: level says how STRONG the link is,
  tone says how it FLOWS. A strong but challenging axis is not "bad" —
  friction is where a relationship does its work.
- NEVER give a score, a percentage, or a permanent verdict such as
  "you are compatible / incompatible".
- Treat both people equally; do not make one right and the other wrong.
- No flattery. If the ground is hard, say so — then close every
  difficulty with one small, concrete step they can take together.
- Do NOT predict break-ups, marriage, pregnancy, health, or the future
  of the relationship.
- An axis line may name a planet, but it is a HINT, not an aspect dump —
  the reader should want to say "tell me more about that".
- Keep the line keys (communication/emotional/attraction/bond/theme)
  exactly as given; use no headings, bullets, numbering or markdown in
  the values.
- Do not address the two of them jointly; the reader is {me} — you are
  describing the relationship to them.
"""

RELATIONSHIP_FALLBACK = (
    "The axes between you and {friend} were calculated, but the reading "
    "could not be produced right now. The measured levels and their "
    "supporting aspects are below; try again shortly for the reading."
)

NATAL = """
TASK: Write a 400-500 word deep birth chart analysis from the natal data below.
Sections: (1) Core identity (the Sun/Moon/Rising trio), (2) Planetary emphases,
(3) Major aspects and inner dynamics, (4) Life theme and potential.

NATAL CHART (Swiss Ephemeris precision):
Sun: {sun_sign} | Moon: {moon_sign} | Rising: {ascendant}

PLANETS:
{points}

ASPECTS:
{aspects}

BALANCE (traditional seven + Ascendant):
- Elements: {elements}
- Modalities: {modalities}
- Stelliums: {stelliums}

DECLINATION PARALLELS (hidden aspects longitude never shows):
{declinations}
{disclosures}
SOURCE PASSAGES (blend in from the tradition):
{rag}

RULES:
- If a DISCLOSURES section is present, reflect it OPENLY in the reading —
  do not claim certainty over what was disclosed as uncertain (especially
  the Ascendant and houses).
- A missing element (a count of 0) is a meaningful statement — don't
  ignore it.
- If there is a stellium, make that life area the centre of gravity.
- Read a declination parallel as a bond with conjunction strength but a
  "hidden" quality; a contra-parallel as an opposition-like tension. If
  the list is "-", never mention declination.
- An applying aspect is a building theme, a separating one is fading —
  weave the movement noted on each aspect line into the reading.
"""

DISCLOSURES_LABEL = "DISCLOSURES (limits of the calculation — reflect openly):"

#: Disclosure lines (T0) — the engine emits keys, text lives here.
ASTRO_NOTES = {
    "geo_fallback_city": (
        "The birth city could not be resolved; the chart was computed with "
        "Istanbul coordinates. The Ascendant and houses are therefore "
        "approximate."),
    "sr_hour_unknown": (
        "Because the birth time is unknown, the return moment may shift by "
        "up to ±12 hours; the year chart's Ascendant and houses were "
        "therefore not computed."),
    "prog_hour_unknown": (
        "Because the birth time is unknown, the progressed Ascendant, MC "
        "and house placements were not computed; the reading stays at the "
        "planetary level."),
    "transit_hour_unknown": (
        "Because the birth time is unknown, transits to the Ascendant and "
        "MC were left out of the calendar; it stays at the planetary "
        "level."),
    "natal_hour_unknown": (
        "The birth time is unknown, so the Ascendant, houses and house "
        "placements were not computed. The reading stays at the planetary "
        "level; a noon chart was not invented."),
    # Disclosures carrying a {city} field (D3): filled in by the localize
    # layer with the place the chart was cast for.
    # R5-5: the old text named only the city it was cast for, so a user born
    # in one place and living in another could not connect it to their birth
    # chart. The calculation was right; the wording was thin.
    "synastry_hour_unknown_p1": (
        "Your birth time is not on file, so your Ascendant and MC contacts were left out of this reading; an Ascendant assumed from noon is not evidence about a relationship."),
    "synastry_hour_unknown_p2": (
        "Your friend's birth time is not on file, so their Ascendant and MC contacts were left out."),
    "sr_relocated": (
        "Your year chart was cast for {city} — where you live. You were "
        "born in {birth_city}; a solar return is cast not for your "
        "birthplace but for wherever you are on your birthday. What "
        "changes is the Ascendant and the houses; the planets keep their "
        "signs. If you will be elsewhere on your birthday, see Profile → "
        "City you live in."),
    "sr_birthplace_fallback": (
        "No city of residence is on file, so the year chart was cast for "
        "your birth city. If you are elsewhere on your birthday the "
        "Ascendant and houses change; you can add where you live under "
        "Profile."),
}

#: Transit calendar event types (T3).
TRANSIT_EVENT_NAMES = {
    "aspect_exact": "exact aspect",
    "station_retrograde": "stations retrograde",
    "station_direct": "stations direct",
}

#: STATION MEANING (OP2 round). On the day sheet the "Other movements"
#: row was a LABEL, not a reading: the device showed a single line,
#: "Pluto - stations direct", and nowhere could the user learn what it
#: meant.
#:
#: The sentence is the PRODUCT OF TWO TABLES: the planet theme below x
#: the phase of direction. The 12 cells are not hand-written - writing
#: them out would bring back a defect already on record here (44 fixed
#: sentences were PRINTED side by side, never synthesised). Precedent:
#: atlas_detail_screens.dart `planetRoleText` x `houseAreaText`.
#:
#: WARNING: the sentence is never personalised, and cannot be. A station
#: attaches to no natal point of the user's, which is why
#: `signal_service.enrich_events` gives it no theme; saying "in your
#: chart" would break "nothing is said that was not measured". What is
#: described is THE PLANET ITSELF: "Pluto tears out a foundation" is
#: about Pluto, not about the user - measured and true. Being shared
#: rather than personal, it is open to every tier and carries no
#: `locked` (see api/astrology.py `_takvimi_kilitle`).
#:
#: Source `knowledge/corpus/en/prediction_doctrine.md` (license:
#: rytho-original): slow-planet themes and the station doctrine. The same
#: document's "Ethics of Predictive Language" says a hard season is
#: called hard but together with its function, so both phase lines name
#: the GAIN and the COST together; naming only one either sells fear or
#: lulls.
#:
#: Keys must stay in step with `predict_service._TRANSIT_GEZEGENLERI`: a
#: missing planet silently yields a station with no sentence.
STATION_PLANET_THEMES = {
    "Jupiter": "the influence that enlarges a doorway",
    "Saturn": "the influence that tests a structure",
    "Uranus": "the influence that opens what is shut from an "
              "unexpected side",
    "Neptune": "the influence that dissolves an edge",
    "Pluto": "the influence that tears out a foundation and pours it anew",
    "Chiron": "the influence that touches an old wound",
}

#: Phases of direction. Keys are the event types `predict_service`
#: emits - a type absent from this table gets NO sentence at all (no
#: invented phase).
STATION_PHASE_LINES = {
    "station_retrograde": (
        "{transit} stands still and turns retrograde — {theme}. A "
        "station is the day this influence is most concentrated: as speed "
        "falls to zero, effect rises to its peak. What follows opens no "
        "new ground; it turns what is already open inward for review. The "
        "gain is a second look, the cost is giving up speed."),
    "station_direct": (
        "{transit} stands still and turns direct — {theme}. A station "
        "is the day this influence is most concentrated: as speed falls "
        "to zero, effect rises to its peak. The review phase closes and "
        "the matter opens outward again. The gain is stalled work moving, "
        "the cost is the quiet shelter the retreat allowed."),
}

#: The station's BASIS. What is measured is the sign change of speed
#: (`predict_service`: `hizlar[i - 1] > 0 >= hizlar[i]`); the line names
#: exactly that measurement. It shows the basis, it does not praise the
#: discipline.
STATION_LINE_TECHNICAL = (
    "{transit} slows to zero speed and changes direction on {date} "
    "({event}).")

#: Declination aspects (T4): the "hidden" conjunction/opposition that
#: longitude alone never shows.
DECLINATION_ASPECT_NAMES = {
    "parallel": "parallel",
    "contraparallel": "contra-parallel",
}

SOLAR_RETURN = """
TASK: From the user's SOLAR RETURN data below, write a 300-400 word "new
solar year" reading. This chart is cast for the exact moment the Sun
returns to its natal longitude near the birthday, and it sets the tone of
the year until the NEXT birthday.

YEAR CHART:
- Return moment (local): {return_at}
- Next return: {next_return_at}
- Year chart Ascendant: {sr_asc}
- Sun's house in the year chart: {sr_sun_house}
- Year Moon: {sr_moon}

PLANETS:
{points}

ASPECTS:
{aspects}
{disclosures}
SOURCE PASSAGES:
{rag}

RULES:
- This is a YEAR reading: themes, seasons, tendencies — no dated event
  prophecies.
- If the Ascendant is "-", never mention the Ascendant or houses.
- No health/legal/financial advice; no flattery.
- If the year carries a hard theme, say it's hard; not every year is "a
  wonderful year".
"""

SOLAR_RETURN_FALLBACK = (
    "Your new solar year began at {return_at}. The year's Moon is in "
    "{sr_moon} — your emotional keynote will hum at that frequency all "
    "year. Check back shortly for the full reading."
)

SOLAR_RETURN_RAG_QUERY = ("solar return year chart annual themes seasons "
                          "{sr_moon} {sr_asc}")

PROGRESSIONS = """
TASK: From the user's SECONDARY PROGRESSION data below, write a 300-400
word "inner season" reading. This is the chart advanced by the day-for-a-
year rule: each day after birth stands for one year of life. The reading
describes inner rhythm and the stage of ripening — not outer events.

INNER CALENDAR:
- Progressed Moon: {prog_moon_sign} {prog_moon_pos}°{prog_moon_house}
- Progressed lunation phase: {prog_phase}
- Progressed Moon enters the next sign: {prog_moon_next}
- Progressed Sun: {prog_sun_sign} {prog_sun_pos}° (~{prog_sun_years} years to the next sign)
- Solar arc (arc of life): {solar_arc}°
- Progressed Ascendant: {prog_asc} | Progressed MC: {prog_mc}

SOLAR ARC ASPECTS PERFECTING IN THE COMING YEARS:
{hits}
{disclosures}
SOURCE PASSAGES:
{rag}

RULES:
- The spine is the PROGRESSED MOON: its sign is the inner season, the
  lunation phase says where in the cycle you stand, and the ingress date
  marks the turn of the season.
- Use the language of TENDENCY: no "this will happen on that date";
  rather "this theme is ripening in this period". Solar arc dates carry
  MONTH precision, not day precision.
- If the progressed Ascendant/MC is "-", never mention them or houses.
- No flattery; if the inner season is winter, say winter — winter has
  its own work.
"""

PROGRESSIONS_FALLBACK = (
    "Your progressed Moon is in {prog_moon_sign}, phase {prog_phase} — "
    "that is your inner season. On {prog_moon_next} a new inner season "
    "begins. Check back shortly for the full reading."
)

PROGRESSIONS_RAG_QUERY = ("secondary progressions progressed moon lunation "
                          "cycle inner season solar arc {prog_moon_sign} "
                          "{prog_phase}")

PROGRESSIONS_HOUSE_LABEL = "in natal house {house}"

#: Aspect movement names (T0): an applying aspect builds, a separating one fades.
MOVEMENT_NAMES = {
    "applying": "applying",
    "separating": "separating",
    "static": "static",
}

# ---------------------------------------------------------------------------
# Signals (R2-S1): the home screen's "Rytho noticed for you today" cards
# ---------------------------------------------------------------------------

#: Theme names. Keys must match signal_service.THEMES.
SIGNAL_THEME_NAMES = {
    "career": "Career",
    "relationships": "Relationships",
    "inner": "Inner world",
    "finance": "Material ground",
}

#: Month names — for writing signal dates in human language.
MONTH_NAMES = {
    1: "January", 2: "February", 3: "March", 4: "April", 5: "May",
    6: "June", 7: "July", 8: "August", 9: "September", 10: "October",
    11: "November", 12: "December",
}
SIGNAL_DATE_FMT = "{month} {day}"

SIGNAL_EXACT_LABEL = "exact"

#: `SIGNAL_HUMAN_LINES` was REMOVED (KA round).
#:
#: It was 4 themes x 3 tones = 12 fixed sentences, and the card sentence
#: was chosen by that pair alone. Measured on device: two IDENTICAL
#: "inner world" cards on one screen, one labeled "Building" and one
#: "Fading" (movement never reached the key). The morning push used the
#: same table, so EVERY user got the literal same sentence for weeks
#: (theme comes from the natal house, tone from the aspect type — both
#: frozen for weeks). Ç-turu removed the same flaw from the calendar but
#: kept it here on a "card risk is low" argument — that argument proved
#: wrong.
#:
#: Owner decision (KA round): the reading is per-user AI for EVERYONE
#: (`signal_service.insight_bundle`); the last resort is the HONEST
#: technical line. Product rule: no canned answers.

# ---------------------------------------------------------------------------
# Relationship axes (R2-L1). A numeric compatibility score is deliberately
# absent.
# ---------------------------------------------------------------------------

#: Axis names. Keys must match synastry_service.AXES.
SYNASTRY_AXIS_NAMES = {
    "communication": "Communication",
    "emotional": "Emotional language",
    "attraction": "Attraction",
    "bond": "Common ground",
}

#: Level names — shown instead of a compatibility number.
SYNASTRY_LEVEL_NAMES = {
    "strong": "Strong",
    "present": "Clear",
    "light": "Light",
    "quiet": "Quiet",
}

#: Tone names — the quality of the link. "Challenging" does not mean bad;
#: friction is where a relationship does its work, and the lines say so.
SYNASTRY_TONE_NAMES = {
    "flowing": "flowing",
    "mixed": "mixed",
    "challenging": "challenging",
    "quiet": "quiet",
}

#: `SYNASTRY_AXIS_LINES` was REMOVED (1.6.0).
#:
#: It was a canned-sentence table keyed only by axis x tone: the level
#: never reached the sentence and the supporting aspect was never
#: named. Sixteen sentences for the whole product. Measured -- 15 of 15
#: pairs produced distinct measurements but only 12 saw distinct text;
#: three pairs read all four sentences word for word identically.
#:
#: Replaced by the RELATIONSHIP prompt: the reading is written by the
#: model from the measured axes and that pair's own supporting aspects.

#: The honesty note under the axis list.
SYNASTRY_FOOTNOTE = (
    "This reading is computed from the aspects between two birth charts. "
    "Rytho does not score relationships: a relationship can't be measured "
    "out of 100, but where it flows and where it takes work can be.")

#: Timing line — the small gold line under the card.
SIGNAL_TIMING_TODAY = "Perfects today"
SIGNAL_TIMING_FUTURE = "Peaks on {date}"
SIGNAL_TIMING_APPLYING = "Building"
SIGNAL_TIMING_SEPARATING = "Fading"
SIGNAL_TIMING_ACTIVE = "Active now"

# TECHNICAL lines — no longer on the card surface, they live in the basis
# sheet. Every field is MEASURED data (mover, natal point, aspect, orb).
SIGNAL_LINE_EXACT_TODAY = (
    "{transit} perfects its {aspect} to your natal {natal} today.")
SIGNAL_LINE_EXACT = (
    "{transit} perfects its {aspect} to your natal {natal} on {date}.")
#: OT1.4: {days} counts down daily — the fixed-date line produced
#: byte-identical pushes on two bad mornings.
SIGNAL_LINE_EXACT_SOON = (
    "{transit} perfects its {aspect} to your natal {natal} in {days} "
    "days ({date}).")
SIGNAL_LINE_APPLYING = (
    "{transit} is applying to a {aspect} with your natal {natal} "
    "(orb {orb}°).")
SIGNAL_LINE_SEPARATING = (
    "{transit} is separating from its {aspect} to your natal {natal} — "
    "the influence is fading (orb {orb}°).")
SIGNAL_LINE_ACTIVE = (
    "{transit} is within {aspect} range of your natal {natal} "
    "(orb {orb}°).")

#: Per-line ceiling (characters) for the insight. If the model overruns,
#: we fall back; no half sentences (push lesson).
SIGNAL_INSIGHT_MAX = 160

#: Movement hints injected into the prompt lines (KA1): the card sentence
#: must not contradict the timing label — measured on device, the same
#: text appeared on one "Building" and one "Fading" card.
SIGNAL_PROMPT_APPLYING = "influence building"
SIGNAL_PROMPT_SEPARATING = "influence fading"
#: Marks the day's significant signal — the evening question binds to it.
SIGNAL_PROMPT_FOCUS_MARK = "(today's focus)"
#: The model's question-line prefix. The parser matches it UPPERCASE.
CHECKIN_PREFIX = "QUESTION:"

#: OT1.3: negative-example block appended on the single retry when
#: today's sentence matched yesterday's.
SIGNALS_AVOID_BLOCK = """
YESTERDAY'S SENT SENTENCE (do NOT restate it — take a different angle,
different wording):
"{prev}"
"""

#: Signal insights + the evening check-in question — all in ONE call
#: (unit-economics rule; the question line was added in the KA round).
SIGNALS_PROMPT = """
TASK: Write a one-sentence reading for EACH of the {count} personal transit
signals below; then add ONE check-in question at the end.

TODAY: {today}. The same sky event can last for days; your job is to
catch a NEW nuance EVERY day — restating yesterday's sentence is
FORBIDDEN. Speak to today's angle: where in the process, what shifted
today, which small step belongs to today.

SIGNALS (measured sky data):
{lines}

RULES (strict):
- First write EXACTLY {count} lines; each starts with a number like "1."
  and keeps the signal order.
- Each sentence AT MOST 140 characters; one sentence, end with a period.
- PLAIN LANGUAGE: never name a planet, aspect, sign, house, degree or orb.
  People want to read what is happening in their life, not "Saturn square
  Moon". (The technical basis is shown to them on a separate screen.)
- EVERY LINE MUST DIFFER FROM THE OTHERS; no two lines may be copies or
  near-copies of each other.
- On a line marked "influence fading", do not describe a rise or a
  beginning; describe closure, harvest, what is left behind. On a line
  marked "influence building", do not describe fading. Your sentence must
  NEVER contradict that marker.
- Use TENDENCY language: "this theme is becoming visible", "make room
  for" — no dated event prophecy ("you will get the job" is FORBIDDEN).
- No health/legal/financial advice; no flattery; no emoji in the
  NUMBERED lines (card surfaces stay plain).
- Each sentence must touch the theme at the end of its line.
- LAST LINE: exactly "QUESTION: <one question>", with NO NUMBER in front —
  a warm check-in question tied to the signal marked "(today's focus)",
  to be asked in the evening. Not a prophecy; a friendly question about
  how the day WENT ("Something was moving on the work front today — how
  did it go?" style). At most 120 characters. The QUESTION line may carry
  AT MOST ONE emoji (it counts toward the 120 limit). The QUESTION must
  NOT restate any of the numbered sentences — do not describe the event,
  ask how the day WENT. If no signal is marked, write "QUESTION: -".

Write only the numbered lines and the QUESTION line, nothing else.
"""

#: One-call batch reading for calendar events (Ç-turu).
#:
#: Why this exists: `SIGNAL_HUMAN_LINES` (theme × tone) only held 12 fixed
#: sentences, and over a 30-day calendar many different astrological
#: events landed in the same bucket (especially "inner") and got the
#: LITERAL SAME sentence — measured: one sample chart showed three
#: separate events on one day showing the identical line three times.
#: Same as SIGNALS_PROMPT, with one addition: within-batch non-repetition
#: is explicit here, because the calendar (unlike signal cards) can carry
#: more than one event under the same theme.
CALENDAR_INSIGHTS_PROMPT = """
TASK: Write a one-sentence reading for EACH of the {count} personal
transit events below.

EVENTS (measured sky data, in date order):
{lines}

RULES (strict):
- Write EXACTLY {count} lines; each starts with a number like "1." and
  keeps the event order.
- Each sentence AT MOST 140 characters; one sentence, end with a period.
- PLAIN LANGUAGE: never name a planet, aspect, sign, house, degree or orb.
  People want to read what is happening in their life, not "Saturn square
  Moon". (The technical basis is shown to them on a separate screen.)
- EVERY LINE MUST DIFFER FROM THE OTHERS. Multiple events may touch the
  same theme (e.g. several "inner") — even then, each one gets its own
  sentence specific to its own date and intensity; no two lines may be
  copies or near-copies of each other.
- Use TENDENCY language: "this theme is becoming visible", "make room
  for" — no dated event prophecy ("you will get the job" is FORBIDDEN).
- No health/legal/financial advice; no flattery; no emoji.
- Each sentence must touch the theme at the end of its line.

Write only the numbered lines, nothing else.
"""

NATAL_FALLBACK = (
    "Your Sun is in {sun_sign}, your Moon in {moon_sign}. Rising: "
    "{ascendant}. That is the measured core of the chart — identity, the "
    "emotional world, and (when the birth time is known) the face you turn "
    "to the world. Check back shortly for the full reading."
)

BAZI = """
TASK: Write a 400-500 word destiny reading from the BaZi (Four Pillars) data
below.

CALCULATED BAZI CHART (true solar time + true solar terms):
- Four Pillars: {pillars}
- Hidden stems of the branches: {hidden}
- Day Master: {day_master}
- Chinese zodiac: {zodiac_animal}
- Element distribution (hidden-stem weighted): {elements} (dominant: {dominant}, weak: {missing})
- Ten Gods — stems: year={ten_year}, month={ten_month}, hour={ten_hour}
- Ten Gods — branches (main qi): {branch_gods}
- STRENGTH VERDICT: {verdict} (support ratio {ratio}; {season_state} in the month command)
- Basis of the verdict (point breakdown, + support / − burden): {strength_basis}
- Favorable elements: {favorable} | Elements that become a burden: {unfavorable}{climate}
- Stars (Shen Sha): {shen_sha}
- Luck Pillars (Da Yun): {luck}
- Start of the first period: {luck_start}
- CURRENT PERIOD: Da Yun {current_luck} · this year's pillar {current_year}
- TODAY'S PILLARS (Liu Ri / Liu Yue — NOT lasting, today only): {today}
- Calculation disclosures: {notes}

SOURCE PASSAGES:
{rag}

Sections:
(1) Core and season: describe the Day Master through its seasonal state;
    justify the strength verdict FROM THE BASIS LIST and do not go beyond it.
(2) Element balance and the useful element, with its practical meaning
    (what to cultivate, which tendency to rein in).
(3) The touch of the stars — ONLY if the list has any; skip this section if
    the list is empty.
(4) The current period: the theme of the active Da Yun and how this year's
    pillar intersects it.
(5) TODAY'S INTERSECTION — at most three sentences: how do today's day pillar
    (Liu Ri) and month pillar (Liu Yue) meet the four pillars THE BIRTH gave
    (support, clash, or bringing the favorable element)? The four pillars DO
    NOT change; only the way today touches them does. If today's pillars are
    not given, SKIP this section and do not use the word "today".

RULES:
- No flattery: state the verdict as it is. A weak Day Master is not a flaw
  but a path of balancing — yet do not embellish either.
- Do not draw EVENT prophecy from today's pillar: a day pillar is a window of
  tendency, not a calendar.
- If the verdict is "Balanced", avoid certainty; write in the language of
  likelihood.
- No health, death or exact-date prophecy.
- Do not mention any star or combination not given in the list.
- If the disclosures state that the hour pillar was not calculated, do NOT
  comment on the hour pillar or the hour Ten God in any way.
"""

BAZI_FALLBACK = (
    "Your Day Master is {element}: {polarity} in nature, and that is your core. "
    "Your dominant element is {dominant}; your strength verdict is {verdict}. "
    "Check back shortly for the full reading."
)

#: Report line formats — small language-bound patterns (B6).
BAZI_LUCK_START_FMT = "{years}y {months}m ({date})"
BAZI_CLIMATE_FMT = " | The season's climate calls for a regulator: {element}"
#: Day-layer line: Liu Ri (day pillar) + Liu Yue (month pillar). The date
#: stamp is REQUIRED — a day-pillar label repeats every 60 days, so on its
#: own it does not say which day it stands for.
BAZI_TODAY_FMT = "{date} · day pillar {day} · month pillar {month}"

#: Default question for a cast without one (İ0). The Turkish constant in
#: the schema used to leak into the English prompt; now language-bound.
ICHING_DEFAULT_QUESTION = "The path ahead of me"

#: Trigram family roles (İ1, Shuo Gua tradition).
TRIGRAM_FAMILY_NAMES = {
    "father": "Father", "mother": "Mother",
    "eldest_son": "Eldest son", "middle_son": "Middle son",
    "youngest_son": "Youngest son",
    "eldest_daughter": "Eldest daughter",
    "middle_daughter": "Middle daughter",
    "youngest_daughter": "Youngest daughter",
}

#: Trigram nature attributes (İ1).
TRIGRAM_ATTRIBUTE_NAMES = {
    "creative": "the creative", "receptive": "the receptive",
    "arousing": "the arousing", "abysmal": "the abysmal",
    "stillness": "keeping still", "penetrating": "the penetrating",
    "clinging": "the clinging", "joyous": "the joyous",
}

#: Six relatives names (İ3, Liu Yao). Keys match liuyao_service.
LIU_QIN_NAMES = {
    "sibling": "Sibling", "offspring": "Offspring", "parent": "Parent",
    "wealth": "Wealth", "officer": "Officer",
}

#: Element relation names (İ2) — Day Master ↔ trigram element.
#: Keys match bazi_service._element_relation output.
ELEMENT_RELATION_NAMES = {
    "same": "your own element",
    "i_produce": "what you feed",
    "produces_me": "what feeds you",
    "i_control": "what you govern",
    "controls_me": "what tests you",
}

ICHING = """
TASK: Write a 300-400 word reading that ties the questioner's question to the
three-thousand-year-old text of the hexagram they cast.

THE QUESTION: "{question}"

THE CAST ({method} method, with true probability distribution):
- Hexagram #{number}: {name_tr} ({name} {name_cn}) {unicode}
- Judgment: {judgment}
- Image: {image}
- Trigrams: {lower} below, {upper} above
- Nuclear hexagram (the core of the situation): {nuclear}
- TEXTS OF THE MOVING LINES (the heart of the reading): {moving_texts}{transformed}
- Liu Yao: palace {palace} ({palace_element}) · {shi_ying}
- Day of the cast: {day_context}
- Bond with the questioner (Day Master ↔ trigrams): {dm_line}

SOURCE PASSAGES:
{rag}

{memory}
RULES:
- The spine of the reading is the judgment plus the TEXTS OF THE MOVING
  LINES; never speak of a line whose text was not given.
- If there are no moving lines ("-"), do NOT speak of transformation: the
  situation has settled — read only the judgment and image, in the
  language of steadiness.
- If the "bond with the questioner" line is "-", make no claim of
  personalisation.
- If a line is marked void (kong wang), say its influence runs thin; if a
  line clashes with the day branch, say that theme is shaken today — but
  only for the lines so marked.
- Keep the reading SPECIFIC to the question; no general philosophy
  lecture. No dated predictions, no flattery.
- If the question carries no meaningful intent (a greeting, random
  letters), say so gently in ONE sentence and read the hexagram as the
  general state of the day — do NOT pretend to answer the question.
"""

#: Question gate classifier (R11): before the daily cast is spent, the LLM
#: decides whether the text is askable of the oracle. Output is forced to
#: JSON by schema (the "verdict" field); labels are language-neutral.
ICHING_QUESTION_GATE = """
TASK: The text below was written as a question for an I Ching oracle.
Classify it with one of three labels, returning your decision in the
"verdict" field:

- VALID: an interpretable question or intention about the person's own
  life, a decision, a relationship or their path. It may be short,
  clumsy or misspelled; questions about a third person ("does she love
  me", "will things heal with my mother") are valid too.
- CHAT: text addressed to the app itself or to the AI ("do you love
  me", "who are you", "how are you") or an attempt at small talk.
- INVALID: a greeting, random letters, or text carrying no intent.

When a borderline case leaves you unsure, choose VALID — turning away a
real intention is worse than letting a silly one through.

TEXT: "{question}"
"""

ICHING_TRANSFORMED = (
    "\n- TRANSFORMED HEXAGRAM: #{number} {name_tr} ({name})\n"
    "  Judgment: {judgment}"
)

#: I Ching report line formats (İ4).
ICHING_LINE_FMT = "line {n} — {text}"
ICHING_ALL_LINES_LABEL = "All lines moving"
ICHING_SHI_YING_FMT = ("subject (shi) line {shi}: {shi_rel} {shi_branch} · "
                       "response (ying) line {ying}: {ying_rel} {ying_branch}")
ICHING_DAY_FMT = "day pillar {day} · month pillar {month}{basis}"
ICHING_BASIS_UTC = " (by the UTC day)"
ICHING_VOID_FMT = " | void (kong wang): line {lines}"
ICHING_CLASH_FMT = " | clashing with the day branch: line {lines}"
ICHING_DM_FMT = ("Day Master {element}; lower trigram {lower}, "
                 "upper trigram {upper}")

#: Method names — keep raw keys out of the prompt.
ICHING_METHOD_NAMES = {"coins": "three coins", "yarrow": "yarrow stalks"}

#: RAG query (İ4): aligned with the İ7 doctrine sections, in-language.
ICHING_RAG_QUERY = ("Book of Changes, hexagram {name}, moving lines, "
                    "reading judgment and image, timing")

# --- Birth Hexagram (İ5) ---
BIRTH_HEXAGRAM = """
TASK: Write a 250-350 word character/theme reading from this person's BIRTH
hexagram. THE BIRTH GATE is a lasting layer of identity, NOT a cast (no
divination): "this will happen today" language is forbidden, "this is your
weave" is right. Only the last section looks at today, and even there it
speaks of CONTACT, not events.

CALCULATED POSITION (LASTING — from the moment of birth):
- Sun at birth: {longitude}° → Gate {gate}, line {line}
- Hexagram #{gate}: {name_tr} ({name} {name_cn}) {unicode}
- Judgment: {judgment}
- Image: {image}
- TEXT OF THE BIRTH LINE: {line_text}
- The gate's weave (Rytho rendering): {gate_text}
- Trigrams: {lower} below, {upper} above
- Disclosures: {notes}

THE SUN TODAY (same wheel — NOT lasting, today only): {today}

SOURCE PASSAGES:
{rag}

Sections: (1) The essence of the gate — this hexagram's theme carried as a
CHARACTER; (2) The birth line — the personal tone within the same gate (the
line text is the spine); (3) Shadow and ripeness — the raw and the worked
form of the theme; (4) TODAY'S THEME, at most three sentences — which gate of
the same wheel is the Sun in today, and how does that gate speak to the BIRTH
gate (same gate, opposite shore, feeding one)? The birth gate DOES NOT change;
only where the Sun looks at it from today does. If today's gate is not given,
SKIP this section and do not use the word "today".
RULES: If the disclosures mention a second candidate gate, briefly introduce
both themes, present neither as certain, and do not interpret the line. No
flattery — name the shadow too. No health or fate prophecy. Draw no event
prophecy from today's gate.
"""

BIRTH_HEXAGRAM_FALLBACK = (
    "Your birth gate is #{gate} {name_tr} {unicode}: {judgment} "
    "Check back shortly for the full reading."
)

#: Day-layer line: where the Sun sits TODAY on the same wheel. The line is
#: printed too, and that is a measurement result — a gate lasts 5.71 days
#: (`GATE_SPAN` 5.625° over daily speed; a 30-day window shows 5-7 distinct
#: gates depending on its phase) while gate+line takes 30 distinct values
#: in 30 days; so this surface's genuinely DAILY fact is gate+line, not the
#: gate alone (measured 2026-10-03).
BIRTH_HEXAGRAM_TODAY_FMT = (
    "{date} · Gate {gate}, line {line} — #{gate} {name} {unicode}")

#: Boundary disclosure for hour-unknown births.
BIRTH_HEXAGRAM_BOUNDARY_NOTE = (
    "The birth hour is unknown and the Sun crosses a gate boundary within "
    "the day: your gate may be {gate} or {alternate}; no line is claimed.")
BIRTH_HEXAGRAM_LINE_UNKNOWN = (
    "The birth hour is unknown, so no line position is claimed; the reading "
    "stays at gate level.")

BIRTH_HEXAGRAM_RAG_QUERY = ("Book of Changes, hexagram {name}, character "
                            "and nature, trigram families")

SYNASTRY = """
TASK: Write a 200-250 word synastry (astrological compatibility) reading from
the data below.

THE TWO PEOPLE:
- {name1}: Sun {sun1}, Moon {moon1}
- {name2}: Sun {sun2}, Moon {moon2}

MAJOR CROSS-ASPECTS:
{aspects}

SOURCE PASSAGES:
{rag}

THIS PAIR'S data decides the sections: how many there are and what each one
is about follows from what the aspects above actually bring forward. Do NOT
impose a fixed skeleton — two different pairs must not see the same run of
sections. Name the hard place DIRECTLY; never soften a difficulty by renaming
it as something positive.
Treat both people with equal warmth.
Do not give a lasting "compatibility score" — reducing a relationship to a
number is misleading and leaves a mark that cannot be taken back.
"""

SYNASTRY_FALLBACK = (
    "The dynamic between {name1} ({sun1}) and {name2} ({sun2}) carries both "
    "points of attraction and points of friction. "
    "Check back shortly for the full reading."
)

# --- Firasa (face reading) ---
#
# The signs are OBSERVATIONS, NOT VERDICTS. The source contains judgements
# like "a long nose means poor understanding"; only the measured form enters
# here, the judgement is left to the model, and the persona binds that to the
# limit the tradition sets on itself.
FIRASA_SIGNS = {
    "forehead_dominant": "Upper zone (forehead) predominates",
    "forehead_short": "Upper zone (forehead) is narrow",
    "midface_dominant": "Middle zone (eyes-nose) predominates",
    "midface_short": "Middle zone (eyes-nose) is short",
    "jaw_dominant": "Lower zone (mouth-jaw) predominates",
    "jaw_short": "Lower zone (mouth-jaw) is short",
    "face_broad": "The face is broad, close to round",
    "face_long": "The face is long and narrow",
    "jaw_square": "The jaw is broad and squared",
    "jaw_tapered": "The jaw tapers, close to pointed",
    "mouth_wide": "The mouth is wide",
    "mouth_small": "The mouth is small",
    "lips_full": "The lips are full",
    "lips_thin": "The lips are thin",
    "eyes_wide": "The eyes are set far apart",
    "eyes_close": "The eyes are set close together",
    "asymmetry_marked": "A marked difference between left and right",
}

#: An average face yields no extreme signs. The model must be TOLD this;
#: sending an empty block would read as "find something".
FIRASA_NO_MARKED_SIGNS = (
    "None of the measured ratios sit at an extreme: this face is in balanced "
    "proportion. The absence of marked signs is itself information, not a gap"
)

FIRASA_MOISTURE = {
    "dry": "The form leans to the dry side (fine build, hard line)",
    "moist": "The form leans to the moist side (full build, soft line)",
}

#: The axis we cannot measure is declared EVERY TIME.
FIRASA_HEAT_UNKNOWN = (
    "The hot-cold axis COULD NOT BE MEASURED: in the tradition that axis "
    "reads colour, speed of movement and voice; all we have is static form. "
    "Do not pass judgement on that axis"
)

#: Told to the model when the crown was used instead of the hairline.
FIRASA_FOREHEAD_FROM_CROWN = (
    "The upper region was measured from the CROWN, not the hairline (no hair "
    "or very short hair). The tradition defines this region by the hairline; "
    "when discussing the upper region, say where the measurement was taken "
    "from and avoid a firm verdict"
)

FIRASA = """
TASK: Write a 180-220 word firasa reading from the MEASURED facial signs
below. Address the reader as "you".

MEASURED SIGNS (computed on the reader's own device; the image never reached
this server):
{signs}

THE READER'S CHART — LASTING (from the moment of birth; it does not change
with the day):
{chart}

TODAY'S SKY (valid for today only; tomorrow's will be another):
{today}

SOURCE PASSAGES:
{rag}

THE LIMIT THE TRADITION SETS ON ITSELF — OBSERVE IT:
- DO NOT CONFUSE THE LASTING WITH TODAY. The signs are PERMANENT: facial
  ratios do not change with the day, so the signs themselves do not either.
  The only thing today's sky may change is the INTERSECTION — which side of
  the same signs is being tested today. "Today that inclination of yours is
  being tested" is right; "today your features say this" would be wrong.
- The body of the reading is THE SIGNS; today's sky gets at most two sentences.
- If today's sky is empty ("—"), say NOTHING about today and do not use the
  word "today": narrating an unmeasured day is invention.
- A SINGLE SIGN DECIDES NOTHING. Gather the signs and draw a TENDENCY; do not
  judge on one measurement. Make at least two signs speak to each other.
- A SIGN IS A TENDENCY, NOT A FATE. Say what they incline toward, not what
  they will do.
- THE PURPOSE IS NOT TO SORT BUT TO BALANCE. The reading should help them
  recognise their own inclination, quiet what is excessive and feed what is short.
- Do NOT pass judgement on an axis that was declared unmeasured; if you must
  touch it, say plainly what you do not know.
- Do not judge intelligence, trustworthiness, morality or attractiveness.
  Those do not follow from facial measurement.
- Say nothing about health, illness or age.

Close with one concrete suggestion in a single sentence. No headings, no bullets.
"""

FIRASA_FALLBACK = (
    "Your features were measured but the reading could not be produced right "
    "now. The tradition forbids judging on a single sign anyway; try again "
    "shortly."
)

#: Knowledge-base query for the firasa reading, aimed at the
#: physiognomy sections of the Marifetname rendering.
FIRASA_RAG_QUERY = (
    "Firasa, the science of physiognomy, from outward sign to "
    "temperament; facial features, the four humours, dry and moist"
)

#: The hot-cold axis is read from MOVEMENT. In the tradition it looks to
#: "live colour, quick movement, full voice"; movement is the only one of the
#: three that is measurable AND not correlated with race or sex.
FIRASA_HEAT = {
    "fast": "Expressive movement is quick and live - the hot side "
            "(quick to warm, quick to decide)",
    "slow": "Expressive movement is heavy and still - the cold side "
            "(slow to warm, long to hold)",
}

#: Movement WAS measured but did not fall to either side. This is a DIFFERENT
#: state from "could not measure" and must be said differently: there is
#: data, the result is inconclusive.
FIRASA_HEAT_AMBIGUOUS = (
    "Expressive movement was measured but fell between hot and cold: it does "
    "not settle on either side. Stay measured on this axis; pass no verdict"
)
