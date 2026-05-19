Omar Auto Icons - مشروع أداة جيلبريك مستقلة عن SnowBoard

الفكرة:
- Tweak يحقن داخل SpringBoard.
- يبدل أيقونات Day/Night بدون SnowBoard.
- التبديل حسب الوقت.
- أول تثبيت فقط يحتاج Respring حتى يتحمل التويك.
- بعد ذلك التبديل يحاول تحديث الأيقونات بدون Respring.

المسارات:
layout/Library/OmarAutoIcons/Day/
layout/Library/OmarAutoIcons/Night/
layout/Library/OmarAutoIcons/config.plist

طريقة البناء على Mac أو Linux مع Theos:
make clean package THEOS_PACKAGE_SCHEME=rootless

مهم:
هذا مشروع source جاهز للبناء. لا أقدر أضمن التوافق 100% مع كل إصدار iOS لأن أسماء كلاسّات SpringBoard تتغير بين الإصدارات.
إذا لم تتبدل الأيقونات، نعدل hook حسب إصدار iOS عندك من crash/log.
