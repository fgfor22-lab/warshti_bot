import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:teledart/teledart.dart';
import 'package:teledart/telegram.dart';
import 'package:teledart/model.dart';
import 'dart:io';

Map<int, String> userStates = {};
Map<int, Map<String, dynamic>> usersData = {};
Map<int, bool> activeRequests = {};

final int adminId = 1913765360; 
List<int> bannedUsers = []; 

const String dbUrl = 'https://warshti-9911e-default-rtdb.firebaseio.com/';

// 🔴 ضع مُعرّف قناتك هنا (مع علامة @) 🔴
const String myChannel = '@warshtii'; 

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

// دالة فحص الاشتراك الإجباري
Future<bool> checkUserSubscription(TeleDart teledart, int chatId, String channelUsername) async {
  try {
    // تم تصحيح الخطأ البرمجي هنا (إزالة .telegram)
    var chatMember = await teledart.getChatMember(channelUsername, chatId);
    String status = chatMember.status;
    if (status == 'member' || status == 'administrator' || status == 'creator') {
      return true;
    }
  } catch (e) {
    print('⚠️ خطأ في فحص الاشتراك: $e');
  }
  return false;
}

void main() async {
  HttpServer.bind(InternetAddress.anyIPv4, 8080).then((server) {
    server.listen((HttpRequest request) {
      request.response.write('Bot is running successfully!');
      request.response.close();
    });
  });

  try {
    final response = await http.get(Uri.parse('${dbUrl}users.json'));
    if (response.statusCode == 200 && response.body != 'null') {
      final Map<String, dynamic> data = jsonDecode(response.body);
      data.forEach((key, value) {
        usersData[int.parse(key)] = Map<String, dynamic>.from(value);
      });
    }
  } catch (e) {
    print('⚠️ خطأ في جلب البيانات.');
  }

  const botToken = '8562183756:AAGP9bayjKdlh3sa1famoJfdKsmjJr3cz1s';
  final username = (await Telegram(botToken).getMe()).username;
  var teledart = TeleDart(botToken, Event(username!));
  teledart.start();
  
  teledart.onCommand('start').listen((message) async {
    if (bannedUsers.contains(message.chat.id)) return;
    int chatId = message.chat.id;

    bool isSubscribed = await checkUserSubscription(teledart, chatId, myChannel);
    if (!isSubscribed) {
      String channelLink = 'https://t.me/${myChannel.replaceAll('@', '')}';
      var subMarkup = InlineKeyboardMarkup(inlineKeyboard: [
        [InlineKeyboardButton(text: 'اشتراك بالقناة الان 🔔', url: channelLink)],
        [InlineKeyboardButton(text: 'تحقق من الاشتراك ✅', callbackData: 'check_sub')]
      ]);
      teledart.sendMessage(chatId, '⚠️ *عذراً، يجب عليك الاشتراك في قناة البوت لتتمكن من استخدامه.*\n\nيرجى الاشتراك في قناتنا ثم اضغط على زر "تحقق من الاشتراك".', replyMarkup: subMarkup, parseMode: 'Markdown');
      return;
    }
    sendStartMenu(teledart, chatId);
  });
  
  teledart.onCallbackQuery().listen((callbackQuery) async {
    final data = callbackQuery.data!;
    final dynamic msg = callbackQuery.message;
    if (msg == null) return;
    final int chatId = msg.chat.id;
    final int messageId = msg.messageId;

    if (data == 'check_sub') {
      bool isSubscribed = await checkUserSubscription(teledart, chatId, myChannel);
      if (isSubscribed) {
        teledart.deleteMessage(chatId, messageId).catchError((e) {});
        teledart.sendMessage(chatId, '🎉 شكراً لاشتراكك بالقناة! تم تفعيل البوت بنجاح.');
        sendStartMenu(teledart, chatId);
      } else {
        teledart.answerCallbackQuery(callbackQuery.id, text: '❌ أنت لم تشترك بالقناة بعد! يرجى الاشتراك أولاً.', showAlert: true).catchError((e){});
      }
      return;
    }

    if (data == 'role_customer' || data == 'role_technician') {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      bool hasSavedInfo = usersData.containsKey(chatId) && usersData[chatId]!['name'] != null && usersData[chatId]!['phone'] != null;

      if (hasSavedInfo) {
        usersData[chatId]!['temp_role'] = data;
        var savedInfoMarkup = InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: 'استخدام بياناتي المحفوظة ✅', callbackData: 'use_saved')],
          [InlineKeyboardButton(text: 'تسجيل بيانات جديدة 🔄', callbackData: 'new_reg')]
        ]);
        teledart.sendMessage(chatId, 'أهلاً بعودتك يا *${usersData[chatId]!['name']}*! 👋\n\nهل تريد استخدام معلوماتك المحفوظة؟', replyMarkup: savedInfoMarkup, parseMode: 'Markdown');
      } else {
        usersData[chatId] = {'role': data}; 
        userStates[chatId] = 'ask_name'; 
        teledart.sendMessage(chatId, '📝 *الخطوة 1:* يرجى كتابة اسمك الكامل (أو اسم المحل):', parseMode: 'Markdown');
      }
    }
    else if (data == 'use_saved') {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      String intendedRole = usersData[chatId]!['temp_role'] ?? 'role_customer';
      usersData[chatId]!['role'] = intendedRole; 
      usersData[chatId]!.remove('temp_role'); 
      saveUserToFirebase(chatId); 
      userStates[chatId] = 'ask_category'; 
      teledart.sendMessage(chatId, 'تم استرجاع معلوماتك بنجاح ✅\n\n🗂️ *الخطوة الأخيرة:* اختر القسم:', replyMarkup: getCategoriesMarkup(), parseMode: 'Markdown');
    }
    else if (data == 'new_reg') {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      String intendedRole = usersData[chatId]!['temp_role'] ?? 'role_customer';
      usersData[chatId] = {'role': intendedRole}; 
      userStates[chatId] = 'ask_name';
      teledart.sendMessage(chatId, '📝 *الخطوة 1:* يرجى كتابة اسمك الكامل الجديد:', parseMode: 'Markdown');
    }
    else if (data.startsWith('gov_')) {
      teledart.deleteMessage(chatId, messageId).catchError((e) {});
      usersData[chatId]!['gov'] = data.replaceFirst('gov_', '');
      saveUserToFirebase(chatId); 
      userStates[chatId] = 'ask_phone';
      teledart.sendMessage(chatId, '📞 *الخطوة 3:* اكتب رقم هاتفك للتواصل:', parseMode: 'Markdown');
    }
    else if (data.startsWith('cat_')) {
      teledart.deleteMessage(chatId, messageId).catchError((e) {}); 
      String selectedCategory = data.replaceAll('cat_', '');
      usersData[chatId]!['category'] = selectedCategory;
      saveUserToFirebase(chatId); 
      if (usersData[chatId]!['role'] == 'role_customer') {
        userStates[chatId] = 'ask_problem'; 
        teledart.sendMessage(chatId, '✍️ *الخطوة الأخيرة:* اكتب مشكلتك أو العطل بالتفصيل:', parseMode: 'Markdown');
      } else {
        teledart.sendMessage(chatId, '🎉 *تم تسجيلك كفني بنجاح!*', parseMode: 'Markdown');
      }
    }
  });

  teledart.onMessage(entityType: '*').listen((message) {
    final chatId = message.chat.id;
    final text = message.text ?? '';
    
    if (bannedUsers.contains(chatId)) return;

    // --- أوامر الإدمن ---
    if (chatId == adminId) {
      if (text.startsWith('/ban ')) {
        try {
          int targetId = int.parse(text.split(' ')[1]);
          if (!bannedUsers.contains(targetId)) {
            bannedUsers.add(targetId);
            teledart.sendMessage(chatId, '✅ تم حظر المستخدم ($targetId) بنجاح.');
            teledart.sendMessage(targetId, '⛔️ لقد تم حظرك من استخدام البوت بسبب مخالفة الشروط.').catchError((e) {});
          }
        } catch (e) {
          teledart.sendMessage(chatId, '⚠️ خطأ في الأمر. الاستخدام الصحيح: /ban 123456');
        }
        return;
      }
      if (text.startsWith('/unban ')) {
        try {
          int targetId = int.parse(text.split(' ')[1]);
          bannedUsers.remove(targetId);
          teledart.sendMessage(chatId, '✅ تم فك الحظر عن المستخدم ($targetId).');
          teledart.sendMessage(targetId, '🎉 تم فك الحظر عنك، يمكنك استخدام البوت الآن.').catchError((e) {});
        } catch (e) {
          teledart.sendMessage(chatId, '⚠️ خطأ في الأمر.');
        }
        return;
      }

      // نظام الإحصائيات مع الرمز السري
      if (text == '/stats' || text == 'الاحصائيات') {
        userStates[chatId] = 'ask_stats_password';
        teledart.sendMessage(chatId, '🔒 *يرجى إدخال الرمز السري لعرض الإحصائيات:*', parseMode: 'Markdown');
        return;
      }
      
      if (userStates[chatId] == 'ask_stats_password') {
        if (text == '1242009') {
          userStates[chatId] = ''; // تصفير الحالة
          
          int techCount = 0;
          int customerCount = 0;
          int karbalaTech = 0;
          int baghdadTech = 0;
          int karbalaCustomer = 0;
          int baghdadCustomer = 0;
          
          usersData.forEach((id, data) {
            String gov = data['gov'] ?? '';
            if (data['role'] == 'role_technician') {
              techCount++;
              if (gov == 'كربلاء') karbalaTech++;
              if (gov == 'بغداد') baghdadTech++;
            }
            if (data['role'] == 'role_customer') {
              customerCount++;
              if (gov == 'كربلاء') karbalaCustomer++;
              if (gov == 'بغداد') baghdadCustomer++;
            }
          });

          teledart.sendMessage(chatId, '''
📊 *إحصائيات منصة ورشتي:*

👨‍🔧 *الفنيين (المجموع: `$techCount`):*
 🔹 كربلاء: `$karbalaTech` فني
 🔹 بغداد: `$baghdadTech` فني

👤 *الزبائن (المجموع: `$customerCount`):*
 🔹 كربلاء: `$karbalaCustomer` زبون
 🔹 بغداد: `$baghdadCustomer` زبون

👥 *المجموع الكلي للمستخدمين:* `${usersData.length}`
''', parseMode: 'Markdown');
        } else {
          userStates[chatId] = ''; // تصفير الحالة
          teledart.sendMessage(chatId, '❌ الرمز خاطئ! تم إلغاء العملية.');
        }
        return;
      }
    }
    // --- نهاية أوامر الإدمن ---

    if (text == 'الدعم الفني 📞') {
      teledart.sendMessage(chatId, '''
📞 *تواصل مع إدارة المنصة:*

🔹 حساب التليجرام: `@r_tk_n` (اضغط للنسخ)
🔹 رقم الهاتف: `07807389172` (اضغط للنسخ)

نحن في خدمتك لأي استفسار أو مشكلة!
''', parseMode: 'Markdown');
      return;
    }

    if (text == 'حسابي 👤') {
      var data = usersData[chatId];
      if (data != null && data['name'] != null) {
        String roleStr = data['role'] == 'role_customer' ? 'زبون 👤' : 'فني 🛠️';
        teledart.sendMessage(chatId, '''
🪪 *معلومات حسابك:*

🔹 نوع الحساب: $roleStr
🔹 الاسم: `${data['name']}`
🔹 المحافظة: `${data['gov']}`
🔹 الهاتف: `${data['phone']}`
🔹 القسم: `${data['category'] ?? "لم يحدد"}`

🆔 رقمك التعريفي: `${chatId}`
''', parseMode: 'Markdown');
      } else {
        teledart.sendMessage(chatId, '⚠️ أنت لم تقم بتسجيل معلومات حسابك بالكامل بعد.\n🆔 رقمك التعريفي: `${chatId}`', parseMode: 'Markdown');
      }
      return;
    }

    if (text == 'تعديل حسابي ⚙️') {
      if (usersData.containsKey(chatId) && usersData[chatId]!['role'] != null) {
        userStates[chatId] = 'ask_name';
        teledart.sendMessage(chatId, '🔄 *تم تفعيل وضع تعديل الحساب*\n📝 يرجى كتابة اسمك من جديد:', parseMode: 'Markdown');
      } else {
        teledart.sendMessage(chatId, '⚠️ أنت لم تقم بإنشاء حساب بعد لتتمكن من تعديله.');
      }
      return;
    }

    if (text.startsWith('/') || text == 'القائمة الرئيسية 🏠') return;

    if (userStates[chatId] == 'ask_name') {
      usersData[chatId]!['name'] = text;
      saveUserToFirebase(chatId); 
      userStates[chatId] = 'ask_gov';
      var govMarkup = InlineKeyboardMarkup(inlineKeyboard: [
        [InlineKeyboardButton(text: 'بغداد', callbackData: 'gov_بغداد'), InlineKeyboardButton(text: 'البصرة', callbackData: 'gov_البصرة'), InlineKeyboardButton(text: 'نينوى', callbackData: 'gov_نينوى')],
        [InlineKeyboardButton(text: 'النجف', callbackData: 'gov_النجف'), InlineKeyboardButton(text: 'كربلاء', callbackData: 'gov_كربلاء'), InlineKeyboardButton(text: 'بابل', callbackData: 'gov_بابل')],
        [InlineKeyboardButton(text: 'ذي قار', callbackData: 'gov_ذي قار'), InlineKeyboardButton(text: 'ميسان', callbackData: 'gov_ميسان'), InlineKeyboardButton(text: 'واسط', callbackData: 'gov_واسط')],
        [InlineKeyboardButton(text: 'المثنى', callbackData: 'gov_المثنى'), InlineKeyboardButton(text: 'الديوانية', callbackData: 'gov_الديوانية'), InlineKeyboardButton(text: 'كركوك', callbackData: 'gov_كركوك')],
        [InlineKeyboardButton(text: 'الأنبار', callbackData: 'gov_الأنبار'), InlineKeyboardButton(text: 'ديالى', callbackData: 'gov_ديالى'), InlineKeyboardButton(text: 'صلاح الدين', callbackData: 'gov_صلاح الدين')],
        [InlineKeyboardButton(text: 'أربيل', callbackData: 'gov_أربيل'), InlineKeyboardButton(text: 'السليمانية', callbackData: 'gov_السليمانية'), InlineKeyboardButton(text: 'دهوك', callbackData: 'gov_دهوك')],
      ]);
      teledart.sendMessage(chatId, 'عاشت الأسامي! ✨\n\n📍 *الخطوة 2:* اختر محافظتك من القائمة أدناه:', replyMarkup: govMarkup, parseMode: 'Markdown');
    }
    else if (userStates[chatId] == 'ask_gov') {
      teledart.sendMessage(chatId, '⚠️ يرجى اختيار المحافظة من الأزرار الشفافة في الأعلى 👆');
    }
    else if (userStates[chatId] == 'ask_phone') {
      usersData[chatId]!['phone'] = text;
      saveUserToFirebase(chatId); 
      userStates[chatId] = 'ask_category';
      teledart.sendMessage(chatId, '🗂️ *الخطوة 4:* اختر القسم المناسب لك:', replyMarkup: getCategoriesMarkup(), parseMode: 'Markdown');
    }
    else if (userStates[chatId] == 'ask_problem') {
      String cat = usersData[chatId]!['category'];
      String gov = usersData[chatId]!['gov']; 
      
      activeRequests[chatId] = true;
      var acceptMarkup = InlineKeyboardMarkup(inlineKeyboard: [
        [InlineKeyboardButton(text: 'قبول الطلب وتقديم خدمة ✅', callbackData: 'accept_$chatId')] 
      ]);

      int techsFound = 0;
      usersData.forEach((techId, data) {
        if (data['role'] == 'role_technician' && data['category'] == cat && data['gov'] == gov) {
          techsFound++;
          teledart.sendMessage(techId, '🚨 *طلب صيانة جديد في منطقتك!* 🚨\n\n📍 المحافظة: $gov\n⚠️ *المشكلة:* $text\n\n👇 إذا كنت متاحاً، اضغط على قبول الطلب:', replyMarkup: acceptMarkup, parseMode: 'Markdown');
        }
      });

      if (techsFound > 0) {
        teledart.sendMessage(chatId, '✅ *تم إرسال طلبك للفنيين بنجاح!*\n\n⏳ تم إرسال الطلب إلى ($techsFound) فني في محافظة ($gov). يرجى الانتظار...', parseMode: 'Markdown');
        userStates[chatId] = 'done'; 
      } else {
        teledart.sendMessage(chatId, '⚠️ عذراً، لا يوجد فنيين مسجلين حالياً في قسم ($cat) داخل محافظة ($gov).\n\nسنقوم بحفظ طلبك، يرجى المحاولة في وقت لاحق.');
        userStates[chatId] = 'done'; 
      }
    }
  });
}

InlineKeyboardMarkup getCategoriesMarkup() {
  return InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: '💻 حاسبات وموبايل', callbackData: 'cat_tech'), InlineKeyboardButton(text: '⚡ كهربائيات', callbackData: 'cat_elec')],
    [InlineKeyboardButton(text: '🖨️ طابعات واستنساخ', callbackData: 'cat_print'), InlineKeyboardButton(text: '❄️ تبريد وتكييف', callbackData: 'cat_ac')],
    [InlineKeyboardButton(text: '🚰 سباكة وتأسيس', callbackData: 'cat_plumb'), InlineKeyboardButton(text: '🔨 نجارة وحدادة', callbackData: 'cat_wood')],
    [InlineKeyboardButton(text: '🛠️ صيانة عامة / أخرى', callbackData: 'cat_other')]
  ]);
}

void sendStartMenu(TeleDart teledart, int chatId) {
  userStates[chatId] = 'start';
  var bottomKeyboard = ReplyKeyboardMarkup(
    keyboard: [
      [KeyboardButton(text: 'القائمة الرئيسية 🏠')],
      [KeyboardButton(text: 'حسابي 👤'), KeyboardButton(text: 'تعديل حسابي ⚙️')],
      [KeyboardButton(text: 'الدعم الفني 📞')]
    ],
    resizeKeyboard: true,
    isPersistent: true,
  );
  var startMarkup = InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: 'أنا محتاج صيانة (زبون) 👤', callbackData: 'role_customer')],
    [InlineKeyboardButton(text: 'أنا فني (أقدم خدمة) 🛠️', callbackData: 'role_technician')]
  ]);
  teledart.sendMessage(chatId, 'تم تفعيل أزرار القائمة السفلية 👇', replyMarkup: bottomKeyboard);
  teledart.sendMessage(chatId, '🌟 *أهلاً بك في منصة ورشتي* 🌟\n\nالمنصة الأولى لربط الزبائن بأفضل الفنيين 🇮🇶\nـــــــــــــــــــــــــــــــــــــــــــــــــ\n👇 يرجى تحديد نوع حسابك للبدء:', replyMarkup: startMarkup, parseMode: 'Markdown');
}
