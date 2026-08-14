import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:teledart/teledart.dart';
import 'package:teledart/telegram.dart';
import 'package:teledart/model.dart';

Map<int, String> userStates = {};
Map<int, Map<String, dynamic>> usersData = {};
Map<int, bool> activeRequests = {};

final int adminId = 1913765360;
List<int> bannedUsers = [];

// 🔴 تم إضافة رابط قاعدة بياناتك هنا بنجاح 🔴
const String dbUrl = 'https://warshti-9911e-default-rtdb.firebaseio.com/';

// دالة الحفظ السريع
void saveUserToFirebase(int chatId) async {
  try {
    if (usersData.containsKey(chatId)) {
      final url = Uri.parse('${dbUrl}users/$chatId.json');
      await http.put(url, body: jsonEncode(usersData[chatId]));
    }
  } catch (e) {
    print('⚠️ خطأ في الحفظ: $e');
  }
}

void main() async {
  // -----------------------------------------------------
  // 1. الاتصال العادي والسريع بقاعدة البيانات
  // -----------------------------------------------------
  try {
    final response = await http.get(Uri.parse('${dbUrl}users.json'));
    if (response.statusCode == 200 && response.body != 'null') {
      final Map<String, dynamic> data = jsonDecode(response.body);
      data.forEach((key, value) {
        usersData[int.parse(key)] = Map<String, dynamic>.from(value);
      });
      print('👥 تم تحميل ${usersData.length} مستخدم من القاعدة بشكل دائم.');
    } else {
      print('🔥 تم الاتصال بقاعدة البيانات بنجاح! (القاعدة فارغة حالياً)');
    }
  } catch (e) {
    print('⚠️ خطأ في جلب البيانات من الإنترنت.');
  }

  // -----------------------------------------------------
  // 2. تشغيل البوت
  // -----------------------------------------------------
  const botToken = '8562183756:AAGP9bayjKdlh3sa1famoJfdKsmjJr3cz1s';
  final username = (await Telegram(botToken).getMe()).username;
  var teledart = TeleDart(botToken, Event(username!));
  teledart.start();

  print('✅ البوت شغال ومربوط بالبيانات بدون مشاكل!');

  teledart.onCommand('start').listen((message) {
    if (bannedUsers.contains(message.chat.id)) return;
    sendStartMenu(teledart, message.chat.id);
  });

  teledart.onMessage(keyword: 'القائمة الرئيسية 🏠').listen((message) {
    if (bannedUsers.contains(message.chat.id)) return;
    sendStartMenu(teledart, message.chat.id);
  });

  // -----------------------------------------------------
  // 3. الاستماع للأزرار الشفافة
  // -----------------------------------------------------
  teledart.onCallbackQuery().listen((callbackQuery) {
    teledart.answerCallbackQuery(callbackQuery.id).catchError((e) {});
    final data = callbackQuery.data!;
    final dynamic msg = callbackQuery.message;
    if (msg == null) return;

    final int chatId = msg.chat.id;
    final int messageId = msg.messageId;

    if (bannedUsers.contains(chatId)) {
      teledart.sendMessage(chatId, '⛔️ عذراً، لقد تم حظرك من استخدام المنصة.');
      return;
    }

    if (data == 'role_customer' || data == 'role_technician') {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      bool hasSavedInfo =
          usersData.containsKey(chatId) &&
          usersData[chatId]!['name'] != null &&
          usersData[chatId]!['phone'] != null;

      if (hasSavedInfo) {
        usersData[chatId]!['temp_role'] = data;
        var savedInfoMarkup = InlineKeyboardMarkup(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: 'استخدام بياناتي المحفوظة ✅',
                callbackData: 'use_saved',
              ),
            ],
            [
              InlineKeyboardButton(
                text: 'تسجيل بيانات جديدة 🔄',
                callbackData: 'new_reg',
              ),
            ],
          ],
        );
        teledart.sendMessage(
          chatId,
          'أهلاً بعودتك يا *${usersData[chatId]!['name']}*! 👋\n\nهل تريد استخدام معلوماتك المحفوظة؟',
          replyMarkup: savedInfoMarkup,
          parseMode: 'Markdown',
        );
      } else {
        String roleName = data == 'role_customer' ? 'زبون 👤' : 'فني 🛠️';
        usersData[chatId] = {'role': data};
        userStates[chatId] = 'ask_name';
        teledart.sendMessage(
          chatId,
          '✅ تم اختيار: *$roleName*\n\n📝 *الخطوة 1:* يرجى كتابة اسمك الكامل (أو اسم المحل):',
          parseMode: 'Markdown',
        );
      }
    } else if (data == 'use_saved') {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      String intendedRole = usersData[chatId]!['temp_role'] ?? 'role_customer';
      usersData[chatId]!['role'] = intendedRole;
      usersData[chatId]!.remove('temp_role');
      saveUserToFirebase(chatId);

      userStates[chatId] = 'ask_category';
      var categoriesMarkup = getCategoriesMarkup();
      teledart.sendMessage(
        chatId,
        'تم استرجاع معلوماتك بنجاح ✅\n\n🗂️ *الخطوة الأخيرة:* اختر القسم المناسب لك:',
        replyMarkup: categoriesMarkup,
        parseMode: 'Markdown',
      );
    } else if (data == 'new_reg') {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      String intendedRole = usersData[chatId]!['temp_role'] ?? 'role_customer';
      usersData[chatId] = {'role': intendedRole};
      saveUserToFirebase(chatId);

      userStates[chatId] = 'ask_name';
      String roleName = intendedRole == 'role_customer' ? 'زبون 👤' : 'فني 🛠️';
      teledart.sendMessage(
        chatId,
        '✅ تم اختيار: *$roleName*\n\n📝 *الخطوة 1:* يرجى كتابة اسمك الكامل الجديد:',
        parseMode: 'Markdown',
      );
    } else if (data.startsWith('gov_')) {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      String selectedGov = data.replaceFirst('gov_', '');
      usersData[chatId]!['gov'] = selectedGov;
      saveUserToFirebase(chatId);

      userStates[chatId] = 'ask_phone';
      teledart.sendMessage(
        chatId,
        '📍 المحافظة المختارة: *$selectedGov*\n\n📞 *الخطوة 3:* اكتب رقم هاتفك للتواصل:',
        parseMode: 'Markdown',
      );
    } else if (data.startsWith('cat_')) {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      String selectedCategory = '';
      if (data == 'cat_tech') selectedCategory = 'حاسبات وموبايل 💻';
      if (data == 'cat_elec') selectedCategory = 'كهربائيات ⚡';
      if (data == 'cat_print') selectedCategory = 'طابعات 🖨️';
      if (data == 'cat_ac') selectedCategory = 'تبريد وتكييف ❄️';
      if (data == 'cat_plumb') selectedCategory = 'سباكة وتأسيس 🚰';
      if (data == 'cat_wood') selectedCategory = 'نجارة وحدادة 🔨';
      if (data == 'cat_other') selectedCategory = 'صيانة عامة 🛠️';

      usersData[chatId]!['category'] = selectedCategory;
      saveUserToFirebase(chatId);

      if (usersData[chatId]!['role'] == 'role_customer') {
        userStates[chatId] = 'ask_problem';
        teledart.sendMessage(
          chatId,
          '🎯 القسم المختار: *$selectedCategory*\n\n✍️ *الخطوة الأخيرة:* اكتب مشكلتك أو العطل بالتفصيل:',
          parseMode: 'Markdown',
        );
      } else {
        userStates[chatId] = 'tech_ready';
        teledart.sendMessage(
          chatId,
          '🎉 *تم تسجيلك كفني بنجاح!*\n\n⏳ *أنت الآن جاهز لاستقبال الطلبات الخاصة بمحافظتك وقسمك فقط...*',
          parseMode: 'Markdown',
        );
      }
    } else if (data.startsWith('accept_')) {
      int customerId = int.parse(data.split('_')[1]);
      if (activeRequests[customerId] == true) {
        var techData = usersData[chatId]!;
        var agreeMarkup = InlineKeyboardMarkup(
          inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: 'تم الاتفاق ✅',
                callbackData: 'agree_$chatId',
              ),
            ],
            [
              InlineKeyboardButton(
                text: 'رفض الفني ❌',
                callbackData: 'decline_$chatId',
              ),
            ],
          ],
        );
        teledart.sendMessage(
          customerId,
          '🔔 *عرض صيانة جديد!*\n\n👨‍🔧 الفني: ${techData['name']}\n📞 رقم الهاتف: ${techData['phone']}\n\nيرجى التواصل معه، هل تم الاتفاق؟',
          replyMarkup: agreeMarkup,
          parseMode: 'Markdown',
        );
        teledart.sendMessage(
          chatId,
          '✅ تم إرسال موافقتك للزبون، بانتظار رده...',
        );
      } else {
        teledart.sendMessage(
          chatId,
          '⚠️ عذراً، هذا الطلب تم الاتفاق عليه مسبقاً مع فني آخر.',
        );
      }
    } else if (data.startsWith('agree_')) {
      int techId = int.parse(data.split('_')[1]);
      activeRequests[chatId] = false;
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      teledart.sendMessage(
        chatId,
        '🤝 *تم تأكيد الاتفاق!*\nتم إغلاق الطلب ولن يصل لفنيين آخرين.',
        parseMode: 'Markdown',
      );
      teledart.sendMessage(
        techId,
        '🎉 *مبروك!*\nالزبون وافق على عرضك وتم الاتفاق.',
        parseMode: 'Markdown',
      );
    } else if (data.startsWith('decline_')) {
      int techId = int.parse(data.split('_')[1]);
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      teledart.sendMessage(
        chatId,
        '❌ تم رفض الفني، طلبك لا يزال متاحاً للفنيين الآخرين.',
      );
      teledart.sendMessage(
        techId,
        'عذراً، الزبون لم يوافق على العرض. حظاً أوفر في الطلبات القادمة! 🌹',
      );
    }
  });

  // -----------------------------------------------------
  // 4. الاستماع للرسائل النصية
  // -----------------------------------------------------
  teledart.onMessage(entityType: '*').listen((message) {
    final chatId = message.chat.id;
    final text = message.text ?? '';

    if (chatId == adminId) {
      if (text.startsWith('/ban ')) {
        try {
          int targetId = int.parse(text.split(' ')[1]);
          if (!bannedUsers.contains(targetId)) {
            bannedUsers.add(targetId);
            teledart.sendMessage(
              chatId,
              '✅ تم حظر المستخدم ($targetId) بنجاح.',
            );
            teledart
                .sendMessage(
                  targetId,
                  '⛔️ لقد تم حظرك من استخدام البوت بسبب مخالفة الشروط.',
                )
                .catchError((e) {});
          }
        } catch (e) {
          teledart.sendMessage(
            chatId,
            '⚠️ خطأ في الأمر. الاستخدام الصحيح: /ban 123456',
          );
        }
        return;
      }
      if (text.startsWith('/unban ')) {
        try {
          int targetId = int.parse(text.split(' ')[1]);
          bannedUsers.remove(targetId);
          teledart.sendMessage(
            chatId,
            '✅ تم فك الحظر عن المستخدم ($targetId).',
          );
          teledart
              .sendMessage(
                targetId,
                '🎉 تم فك الحظر عنك، يمكنك استخدام البوت الآن.',
              )
              .catchError((e) {});
        } catch (e) {
          teledart.sendMessage(chatId, '⚠️ خطأ في الأمر.');
        }
        return;
      }
    }

    if (bannedUsers.contains(chatId)) return;

    if (text == 'الدعم الفني 📞') {
      teledart.sendMessage(
        chatId,
        '📞 *تواصل مع إدارة المنصة:*\n\nحساب التليجرام: @r_tk_n\nرقم الهاتف: 07807389172\n\nنحن في خدمتك لأي استفسار أو مشكلة!',
        parseMode: 'Markdown',
      );
      return;
    }

    if (text == 'حسابي 👤') {
      if (usersData.containsKey(chatId) && usersData[chatId]!['name'] != null) {
        var data = usersData[chatId]!;
        String roleStr = data['role'] == 'role_customer'
            ? 'زبون 👤'
            : 'فني 🛠️';
        teledart.sendMessage(
          chatId,
          '🪪 *معلومات حسابك:*\n\n🔹 نوع الحساب: $roleStr\n🔹 الاسم: ${data['name']}\n🔹 المحافظة: ${data['gov']}\n🔹 الهاتف: ${data['phone']}\n🔹 القسم: ${data['category'] ?? "لم يحدد"}\n\n🆔 رقمك التعريفي: $chatId',
          parseMode: 'Markdown',
        );
      } else {
        teledart.sendMessage(
          chatId,
          '⚠️ أنت لم تقم بتسجيل معلومات حسابك بالكامل بعد.\n🆔 رقمك التعريفي: $chatId',
          parseMode: 'Markdown',
        );
      }
      return;
    }

    if (text == 'تعديل حسابي ⚙️') {
      if (usersData.containsKey(chatId) && usersData[chatId]!['role'] != null) {
        userStates[chatId] = 'ask_name';
        teledart.sendMessage(
          chatId,
          '🔄 *تم تفعيل وضع تعديل الحساب*\n📝 يرجى كتابة اسمك من جديد:',
          parseMode: 'Markdown',
        );
      } else {
        teledart.sendMessage(
          chatId,
          '⚠️ أنت لم تقم بإنشاء حساب بعد لتتمكن من تعديله.',
        );
      }
      return;
    }

    if (text.startsWith('/') || text == 'القائمة الرئيسية 🏠') return;

    if (userStates[chatId] == 'ask_name') {
      usersData[chatId]!['name'] = text;
      saveUserToFirebase(chatId);
      userStates[chatId] = 'ask_gov';

      var govMarkup = InlineKeyboardMarkup(
        inlineKeyboard: [
          [
            InlineKeyboardButton(text: 'بغداد', callbackData: 'gov_بغداد'),
            InlineKeyboardButton(text: 'البصرة', callbackData: 'gov_البصرة'),
            InlineKeyboardButton(text: 'نينوى', callbackData: 'gov_نينوى'),
          ],
          [
            InlineKeyboardButton(text: 'النجف', callbackData: 'gov_النجف'),
            InlineKeyboardButton(text: 'كربلاء', callbackData: 'gov_كربلاء'),
            InlineKeyboardButton(text: 'بابل', callbackData: 'gov_بابل'),
          ],
          [
            InlineKeyboardButton(text: 'ذي قار', callbackData: 'gov_ذي قار'),
            InlineKeyboardButton(text: 'ميسان', callbackData: 'gov_ميسان'),
            InlineKeyboardButton(text: 'واسط', callbackData: 'gov_واسط'),
          ],
          [
            InlineKeyboardButton(text: 'المثنى', callbackData: 'gov_المثنى'),
            InlineKeyboardButton(
              text: 'الديوانية',
              callbackData: 'gov_الديوانية',
            ),
            InlineKeyboardButton(text: 'كركوك', callbackData: 'gov_كركوك'),
          ],
          [
            InlineKeyboardButton(text: 'الأنبار', callbackData: 'gov_الأنبار'),
            InlineKeyboardButton(text: 'ديالى', callbackData: 'gov_ديالى'),
            InlineKeyboardButton(
              text: 'صلاح الدين',
              callbackData: 'gov_صلاح الدين',
            ),
          ],
          [
            InlineKeyboardButton(text: 'أربيل', callbackData: 'gov_أربيل'),
            InlineKeyboardButton(
              text: 'السليمانية',
              callbackData: 'gov_السليمانية',
            ),
            InlineKeyboardButton(text: 'دهوك', callbackData: 'gov_دهوك'),
          ],
        ],
      );
      teledart.sendMessage(
        chatId,
        'عاشت الأسامي! ✨\n\n📍 *الخطوة 2:* اختر محافظتك من القائمة أدناه:',
        replyMarkup: govMarkup,
        parseMode: 'Markdown',
      );
    } else if (userStates[chatId] == 'ask_gov') {
      teledart.sendMessage(
        chatId,
        '⚠️ يرجى اختيار المحافظة من الأزرار الشفافة في الأعلى 👆',
      );
    } else if (userStates[chatId] == 'ask_phone') {
      usersData[chatId]!['phone'] = text;
      saveUserToFirebase(chatId);
      userStates[chatId] = 'ask_category';
      var categoriesMarkup = getCategoriesMarkup();
      teledart.sendMessage(
        chatId,
        '🗂️ *الخطوة 4:* اختر القسم المناسب لك:',
        replyMarkup: categoriesMarkup,
        parseMode: 'Markdown',
      );
    } else if (userStates[chatId] == 'ask_problem') {
      String cat = usersData[chatId]!['category'];
      String gov = usersData[chatId]!['gov'];

      activeRequests[chatId] = true;
      var acceptMarkup = InlineKeyboardMarkup(
        inlineKeyboard: [
          [
            InlineKeyboardButton(
              text: 'قبول الطلب وتقديم خدمة ✅',
              callbackData: 'accept_$chatId',
            ),
          ],
        ],
      );

      int techsFound = 0;
      usersData.forEach((techId, data) {
        if (data['role'] == 'role_technician' &&
            data['category'] == cat &&
            data['gov'] == gov) {
          techsFound++;
          teledart.sendMessage(
            techId,
            '🚨 *طلب صيانة جديد في منطقتك!* 🚨\n\n📍 المحافظة: $gov\n⚠️ *المشكلة:* $text\n\n👇 إذا كنت متاحاً، اضغط على قبول الطلب:',
            replyMarkup: acceptMarkup,
            parseMode: 'Markdown',
          );
        }
      });

      if (techsFound > 0) {
        teledart.sendMessage(
          chatId,
          '✅ *تم إرسال طلبك للفنيين بنجاح!*\n\n⏳ تم إرسال الطلب إلى ($techsFound) فني في محافظة ($gov). يرجى الانتظار...',
          parseMode: 'Markdown',
        );
        userStates[chatId] = 'done';
      } else {
        teledart.sendMessage(
          chatId,
          '⚠️ عذراً، لا يوجد فنيين مسجلين حالياً في قسم ($cat) داخل محافظة ($gov).\n\nسنقوم بحفظ طلبك، يرجى المحاولة في وقت لاحق.',
        );
        userStates[chatId] = 'done';
      }
    }
  });
}

InlineKeyboardMarkup getCategoriesMarkup() {
  return InlineKeyboardMarkup(
    inlineKeyboard: [
      [
        InlineKeyboardButton(
          text: '💻 حاسبات وموبايل',
          callbackData: 'cat_tech',
        ),
        InlineKeyboardButton(text: '⚡ كهربائيات', callbackData: 'cat_elec'),
      ],
      [
        InlineKeyboardButton(
          text: '🖨️ طابعات واستنساخ',
          callbackData: 'cat_print',
        ),
        InlineKeyboardButton(text: '❄️ تبريد وتكييف', callbackData: 'cat_ac'),
      ],
      [
        InlineKeyboardButton(
          text: '🚰 سباكة وتأسيس',
          callbackData: 'cat_plumb',
        ),
        InlineKeyboardButton(text: '🔨 نجارة وحدادة', callbackData: 'cat_wood'),
      ],
      [
        InlineKeyboardButton(
          text: '🛠️ صيانة عامة / أخرى',
          callbackData: 'cat_other',
        ),
      ],
    ],
  );
}

void sendStartMenu(TeleDart teledart, int chatId) {
  userStates[chatId] = 'start';
  var bottomKeyboard = ReplyKeyboardMarkup(
    keyboard: [
      [KeyboardButton(text: 'القائمة الرئيسية 🏠')],
      [
        KeyboardButton(text: 'حسابي 👤'),
        KeyboardButton(text: 'تعديل حسابي ⚙️'),
      ],
      [KeyboardButton(text: 'الدعم الفني 📞')],
    ],
    resizeKeyboard: true,
    isPersistent: true,
  );
  var startMarkup = InlineKeyboardMarkup(
    inlineKeyboard: [
      [
        InlineKeyboardButton(
          text: 'أنا محتاج صيانة (زبون) 👤',
          callbackData: 'role_customer',
        ),
      ],
      [
        InlineKeyboardButton(
          text: 'أنا فني (أقدم خدمة) 🛠️',
          callbackData: 'role_technician',
        ),
      ],
    ],
  );
  teledart.sendMessage(
    chatId,
    'تم تفعيل أزرار القائمة السفلية 👇',
    replyMarkup: bottomKeyboard,
  );
  teledart.sendMessage(
    chatId,
    '🌟 *أهلاً بك في منصة ورشتي* 🌟\n\nالمنصة الأولى لربط الزبائن بأفضل الفنيين 🇮🇶\nـــــــــــــــــــــــــــــــــــــــــــــــــ\n👇 يرجى تحديد نوع حسابك للبدء:',
    replyMarkup: startMarkup,
    parseMode: 'Markdown',
  );
}
