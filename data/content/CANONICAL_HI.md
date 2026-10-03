# Fixed Hindi sentences (translated once, reused word for word)

Aim A4, Phase 2. These are the Hindi forms of the fixed English sentences in `docs/content/GLOSSARY_EN.md`
(STALL, PETROL, ABS, NETWORK, IDLE, BATTERY, OVERHEAT, TWO-CASE, STOP-TAIL, twin clause, throttle stuck open) plus
a few safety sentences that repeat in many entries. `build_hi.py` copies a Hindi sentence from this table whenever
the English advice uses the English sentence exactly, and `validate_hi.py` rejects any Hindi row that changed it.

The two tables below are read by the programs. Keep the three-column layout (`| ID | English | Hindi |`) and put no
pipe character inside a cell. Every sentence is 25 words or fewer and uses no idiom.

Written for riders and mechanics, so it follows the app's register: workshop loanwords for parts, ABS and ECU in
Latin script, native verbs for actions (रुकें, जाँचें, कराएँ), Latin digits, "एडेप्टर" and "फ़ॉल्ट कोड" with the nukta.

## Whole sentences

| ID | English | Hindi |
|---|---|---|
| STALL-SHORT | If it stalls more than once or will not restart, do not keep riding. | अगर इंजन एक से ज़्यादा बार अपने आप बंद हो जाए या दोबारा चालू न हो, तो आगे न चलाएँ। |
| STALL | If it stalls more than once or will not restart, do not keep riding; have it taken to a workshop. | अगर इंजन एक से ज़्यादा बार अपने आप बंद हो जाए या दोबारा चालू न हो, तो आगे न चलाएँ; बाइक को वर्कशॉप तक पहुँचवाएँ। |
| STOP-TAIL | Pull over safely, switch off and do not keep riding; have the bike taken to a workshop. | सुरक्षित जगह पर रुकें, इंजन बंद करें और आगे न चलाएँ; बाइक को वर्कशॉप तक पहुँचवाएँ। |
| TWO-CASE | If the engine runs normally, have it checked soon; if it stalls, loses power or will not start, do not keep riding. | अगर इंजन सामान्य चलता है, तो जल्द जाँच कराएँ; अगर वह अपने आप बंद हो जाए, पावर घटे या चालू न हो, तो आगे न चलाएँ। |
| NETWORK-1 | Some electronic units on the bike cannot talk to each other, so warning lights or safety features may not work. | बाइक की कुछ इलेक्ट्रॉनिक यूनिट आपस में संपर्क नहीं कर पा रही हैं, इसलिए चेतावनी लैंप या सुरक्षा फ़ीचर काम नहीं कर सकते। |
| ABS | Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking. | आपके सामान्य ब्रेक काम करते रहेंगे, लेकिन ABS बंद है, इसलिए तेज़ ब्रेक लगाने पर व्हील लॉक हो सकता है। |
| ABS-IF | If ABS is affected, your normal brakes still work, but ABS is off, so a wheel can lock in hard braking. | अगर ABS प्रभावित है, तो आपके सामान्य ब्रेक काम करते रहेंगे, लेकिन ABS बंद है, इसलिए तेज़ ब्रेक लगाने पर व्हील लॉक हो सकता है। |
| PETROL | If you smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride. | अगर इंजन या फ़्यूल टैंक के पास पेट्रोल की तेज़ गंध आए या ईंधन टपकता दिखे, तो रुकें और बाइक न चलाएँ। |
| IDLE | If it stalls once at a stop, ride gently, avoid heavy traffic and have it checked soon. | अगर रुकने पर इंजन एक बार बंद हो जाए, तो धीरे चलाएँ, भारी ट्रैफ़िक से बचें और जल्द जाँच कराएँ। |
| BATTERY-HOT | If the battery is hot or swollen, stop, switch off and do not ride on. | अगर बैटरी गर्म या फूली हुई हो, तो रुकें, इंजन बंद करें और आगे न चलाएँ। |
| BATTERY-1 | If the battery is hot, swollen or smells of rotten eggs, stop, switch off and do not ride on. | अगर बैटरी गर्म हो, फूली हुई हो या सड़े अंडे जैसी गंध आए, तो रुकें, इंजन बंद करें और आगे न चलाएँ। |
| BATTERY-2 | Do the same if the lights are very bright or bulbs keep blowing. | अगर लाइटें बहुत तेज़ जलें या बल्ब बार-बार जल जाएँ, तो भी यही करें। |
| OVERHEAT | Pull over safely, switch off and let the engine cool; do not keep riding. | सुरक्षित जगह पर रुकें, इंजन बंद करें और इंजन को ठंडा होने दें; आगे न चलाएँ। |
| THROTTLE-OPEN | If the throttle does not snap fully shut when you let go, do not ride; have it checked first. | अगर थ्रॉटल छोड़ने पर तुरंत पूरा बंद न हो, तो बाइक न चलाएँ; पहले जाँच कराएँ। |
| COOLANT-STOP | If your bike has a temperature warning and it comes on, or you see steam or smell hot coolant, stop and let the engine cool. | अगर आपकी बाइक में तापमान चेतावनी है और वह जल जाए, या भाप दिखे या गर्म कूलेंट की गंध आए, तो रुकें और इंजन को ठंडा होने दें। |
| KNOCK-STOP | If you hear heavy knocking or pinging, stop and let the engine cool. | अगर इंजन में तेज़ खटखट या पिंगिंग की आवाज़ सुनाई दे, तो रुकें और इंजन को ठंडा होने दें। |
| OIL-STOP | If your bike has an oil pressure warning lamp and it stays on, stop, switch off and do not keep riding. | अगर आपकी बाइक में ऑयल प्रेशर चेतावनी लैंप है और वह जला रहे, तो रुकें, इंजन बंद करें और आगे न चलाएँ। |
| RIDE-SHORT | Ride gently and keep the trip short; stop if it runs very rough or loses power badly. | धीरे चलाएँ और सफ़र छोटा रखें; अगर इंजन बहुत रफ़ चले या पावर बहुत घट जाए, तो रुकें। |
| RIDE-GENTLE-STOP | Ride gently, avoid hard acceleration and get it checked soon; stop if it runs very rough, backfires or loses power badly. | धीरे चलाएँ, तेज़ एक्सेलरेशन से बचें और जल्द जाँच कराएँ; अगर इंजन बहुत रफ़ चले, बैकफ़ायर करे या पावर बहुत घट जाए, तो रुकें। |
| NEXT-SERVICE | Get it checked at the next service. | अगली सर्विस पर जाँच कराएँ। |
| SOON | Get it checked soon. | जल्द जाँच कराएँ। |
| SOON-HAVE | Have it checked soon. | जल्द जाँच कराएँ। |
| NORMAL | The bike usually rides normally. | बाइक आमतौर पर सामान्य चलती है। |

## Clauses (the Hindi clause must appear word for word inside any sentence that contains the English clause)

| ID | English | Hindi |
|---|---|---|
| TWIN | on a two-cylinder bike it may keep running on one cylinder, but have it checked soon | दो सिलेंडर वाली बाइक एक सिलेंडर पर चलती रह सकती है, पर जल्द जाँच कराएँ |

## Rider-action wording (the app's existing Hindi labels, `riderAction*` and `canRide*` in `app_strings.dart`)

| ID | English | Hindi |
|---|---|---|
| ACTION-STOP | Stop | रुकें |
| ACTION-SERVICE-SOON | Service soon | जल्द सर्विस कराएँ |
| ACTION-MONITOR | Monitor | नज़र रखें |
| ACTION-INFO | Info | जानकारी |
| CANRIDE-YES | Can be ridden to a workshop | वर्कशॉप तक चलाकर ले जा सकते हैं |
| CANRIDE-WITH-CARE | Can be ridden to a workshop, with care | सावधानी से वर्कशॉप तक चलाकर ले जा सकते हैं |
| CANRIDE-NO | Do not ride. Have the bike taken to a workshop. | बाइक न चलाएँ। बाइक को वर्कशॉप तक पहुँचवाएँ। |

## Hedges (the hedge stays in every language; the validator needs the Hindi hedge wherever the English has it)

| ID | English | Hindi |
|---|---|---|
| HEDGE-FITTED | if fitted | अगर लगा हो |
| HEDGE-HOSE | if hose-fed | अगर होज़ से जुड़ा हो |
| HEDGE-LESS | less common | कम आम |
| HEDGE-LIQUID | liquid-cooled | लिक्विड-कूल्ड |
| HEDGE-RARE | rare | दुर्लभ |
| HEDGE-IF-BIKE | if your bike | अगर आपकी बाइक |

## Stop and do-not-ride wording (used by validator check 9)

- Stop wording (a rider is told to stop): a word from the group **रुकें / रुक जाएँ**.
- Do-not-ride wording (a rider is told not to ride): **न चलाएँ** (always with the chandrabindu: चलाएँ).
- The engine stopping by itself is always written **बंद हो** (never "रुक"), so "रुक" in a row always means the rider.
