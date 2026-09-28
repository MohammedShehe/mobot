import 'dart:convert';
import 'package:http/http.dart' as http;

class Turn {
  final String role; // user | assistant
  final String text;
  const Turn(this.role, this.text);
  Map<String, dynamic> toJson() => {'r': role, 't': text};
  factory Turn.fromJson(Map<String, dynamic> j) => Turn('${j['r']}', '${j['t']}');
}

/// Direct, stateless call to Groq's OpenAI-compatible endpoint.
class GroqService {
  static const _url = 'https://api.groq.com/openai/v1/chat/completions';

  static Future<String> ask({
    required String apiKey,
    required String model,
    required String system,
    required List<Turn> turns,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('No Groq API key. Add it in Settings → Integrations.');
    }
    final res = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'temperature': 0.6,
            'max_tokens': 700,
            'messages': [
              {'role': 'system', 'content': system},
              for (final t in turns) {'role': t.role, 'content': t.text},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      throw Exception(body['error']?['message'] ?? 'Groq error ${res.statusCode}');
    }
    return (body['choices'][0]['message']['content'] as String).trim();
  }
}
