# Omar Theme Switcher

أداة خفيفة لتبديل ثيم SnowBoard بين وضع نهاري ووضع ليلي.

## الفكرة

- لا يوجد محرك أيقونات جديد.
- لا يتم لمس أسماء التطبيقات أو صورها مباشرة.
- الأداة تستخدم `snowboardutil` الرسمي الموجود مع SnowBoard.
- تختار ثيم للنهار وثيم لليل من الإعدادات.
- عند تغيّر وضع الجهاز، الأداة تفعل الثيم المطلوب وتطفي الثيم الآخر.

## المسارات

الأداة تبحث عن الثيمات في:

- `/var/jb/Library/Themes`
- `/Library/Themes`

وعند إرسال الأمر إلى SnowBoard تستخدم صيغة:

- `/Library/Themes/ThemeName.theme`

لأن SnowBoard نفسه يستخدم هذا المسار داخلياً.

## الأمان

هذه النسخة لا تعمل hook على الأيقونات ولا تستبدل `UIImageView`.
هي فقط تستدعي:

- `snowboardutil -q`
- `snowboardutil -t`
- `snowboardutil -r`

## الإعدادات

تظهر في Settings باسم:

`Omar Theme Switcher`

وتحتوي على:

- Day Theme
- Night Theme
- Enabled
- Use System Appearance
- Day Starts
- Night Starts
- Apply Now
- Open SnowBoard
- Respring
