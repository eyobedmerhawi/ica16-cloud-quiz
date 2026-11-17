import 'dart:convert';
import 'dart:math';

import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;

class TriviaQuestion {
  final String question;
  final String correctAnswer;
  final List<String> answers;

  TriviaQuestion({
    required this.question,
    required this.correctAnswer,
    required this.answers,
  });
}

class TriviaService {
  static final HtmlUnescape _decoder = HtmlUnescape();

  static const String _url =
      'https://opentdb.com/api.php'
      '?amount=10&category=9&difficulty=easy&type=multiple';

  static DateTime? _lastRequest;

  static Future<List<TriviaQuestion>> fetchQuestions() async {
    final now = DateTime.now();

    if (_lastRequest != null && now.difference(_lastRequest!).inSeconds < 5) {
      throw Exception(
        'Please wait at least 5 seconds before requesting another quiz.',
      );
    }

    _lastRequest = now;

    final http.Response response;

    try {
      response = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw Exception(
        'Could not connect to the quiz server. Check your internet connection.',
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Quiz server returned HTTP ${response.statusCode}.');
    }

    final dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('Quiz server returned invalid JSON.');
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['response_code'] != 0 ||
        decoded['results'] is! List) {
      throw Exception('Quiz server did not return a valid quiz.');
    }

    final results = decoded['results'] as List;

    if (results.length != 10) {
      throw Exception('Expected exactly 10 questions.');
    }

    final questions = <TriviaQuestion>[];
    final random = Random();

    for (final item in results) {
      if (item is! Map<String, dynamic> ||
          item['category'] != 'General Knowledge' ||
          item['difficulty'] != 'easy' ||
          item['type'] != 'multiple' ||
          item['question'] is! String ||
          item['correct_answer'] is! String ||
          item['incorrect_answers'] is! List) {
        throw Exception('Quiz contains an invalid question.');
      }

      final incorrect = item['incorrect_answers'] as List;

      if (incorrect.length != 3 ||
          incorrect.any((answer) => answer is! String)) {
        throw Exception('Quiz contains invalid answer options.');
      }

      final question = _decoder.convert(item['question'] as String).trim();

      final correct = _decoder.convert(item['correct_answer'] as String).trim();

      final answers = <String>[
        correct,
        ...incorrect.map((answer) => _decoder.convert(answer as String).trim()),
      ];

      if (question.isEmpty ||
          answers.any((answer) => answer.isEmpty) ||
          answers.toSet().length != 4) {
        throw Exception('Quiz contains empty or duplicate answers.');
      }

      answers.shuffle(random);

      questions.add(
        TriviaQuestion(
          question: question,
          correctAnswer: correct,
          answers: List.unmodifiable(answers),
        ),
      );
    }

    return List.unmodifiable(questions);
  }
}
