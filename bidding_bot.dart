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
const String myChannel = '@warshti_iq'; 

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
    var chatMember = await teledart.telegram.getChatMember(channelUsername, chatId);
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
        teledart.sendMessage(chatId, '''
🪪 *معلومات حسابك:*

🔹 الاسم: `${data['name']}`
🔹 المحافظة: `${data['gov']}`
🔹 الهاتف: `${data['phone']}`
🔹 القسم: `${data['category']}`

🆔 رقمك التعريفي: `${chatId}`
''', parseMode: 'Markdown');
      } else {
        teledart.sendMessage(chatId, '⚠️ لم تكمل تسجيل معلوماتك.\n🆔 رقمك التعريفي: `${chatId}`', parseMode: 'Markdown');
      }
      return;
    }

    if (userStates[chatId] == 'ask_name') {
      usersData[chatId]!['name'] = text;
      userStates[chatId] = 'ask_gov';
      teledart.sendMessage(chatId, '📍 *الخطوة 2:* اختر محافظتك:', replyMarkup: getGovMarkup(), parseMode: 'Markdown');
    }
    else if (userStates[chatId] == 'ask_phone') {
      usersData[chatId]!['phone'] = text;
      saveUserToFirebase(chatId); 
      userStates[chatId] = 'ask_category';
      teledart.sendMessage(chatId, '🗂️ *الخطوة 4:* اختر القسم المناسب:', replyMarkup: getCategoriesMarkup(), parseMode: 'Markdown');
    }
  });
}

InlineKeyboardMarkup getCategoriesMarkup() {
  return InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: '💻 حاسبات', callbackData: 'cat_tech'), InlineKeyboardButton(text: '⚡ كهربائيات', callbackData: 'cat_elec')],
    [InlineKeyboardButton(text: '🖨️ طابعات', callbackData: 'cat_print'), InlineKeyboardButton(text: '❄️ تبريد', callbackData: 'cat_ac')],
  ]);
}

InlineKeyboardMarkup getGovMarkup() {
  return InlineKeyboardMarkup(inlineKeyboard: [
    [InlineKeyboardButton(text: 'بغداد', callbackData: 'gov_بغداد'), InlineKeyboardButton(text: 'كربلاء', callbackData: 'gov_كربلاء')],
  ]);
}

void sendStartMenu(TeleDart teledart, int chatId) {
  var bottomKeyboard = ReplyKeyboardMarkup(keyboard: [[KeyboardButton(text: 'القائمة الرئيسية 🏠')], [KeyboardButton(text: 'حسابي 👤')], [KeyboardButton(text: 'الدعم الفني 📞')]], resizeKeyboard: true, isPersistent: true);
  var startMarkup = InlineKeyboardMarkup(inlineKeyboard: [[InlineKeyboardButton(text: 'زبون 👤', callbackData: 'role_customer'), InlineKeyboardButton(text: 'فني 🛠️', callbackData: 'role_technician')]]);
  teledart.sendMessage(chatId, '🌟 *أهلاً بك في منصة ورشتي* 🌟', replyMarkup: bottomKeyboard);
  teledart.sendMessage(chatId, 'اختر نوع حسابك للبدء:', replyMarkup: startMarkup, parseMode: 'Markdown');
}
